-- 위험 연출: 화면 가장자리 어두워짐, 심장박동, 경고 플래시, 끌려갈 때 화면 흔들림
-- + 랜턴 빛: 카메라를 따라가는 원뿔 빛(앞쪽 동그라미만 밝음)과 가장자리 비네트
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.DeadLake.Shared.Config)

local Effects = {}
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local gui: ScreenGui
local vignette: { Frame } = {}
local redFlash: Frame
local threat = 0
local warning = false
local heartbeat: Sound
local blackout: Frame
local blackoutText: TextLabel
local grabShot = false -- 붙잡힘 장면 카메라
local grabShotStart = 0
local faceLightPart: BasePart
local faceLight: PointLight
local baseFov = 70
local shakeUntil = 0
local shakeStrength = 0
local lanternOn = false
local adminBright = false -- 관리자 모드: 비네트 끔
local lanternAlpha = 0 -- 0~1, 켜고 끌 때 부드럽게
local beamPart: BasePart
local beam: SpotLight
local L = Config.Lantern

local function edge(parent: Instance, pos: UDim2, size: UDim2, rotation: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	f.BorderSizePixel = 0
	f.Position = pos
	f.Size = size
	f.BackgroundTransparency = 1
	f.Parent = parent
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
	return f
end

function Effects.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "DeadLakeFX"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	vignette = {
		edge(gui, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.35), 90), -- top
		edge(gui, UDim2.fromScale(0, 0.65), UDim2.fromScale(1, 0.35), -90), -- bottom
		edge(gui, UDim2.fromScale(0, 0), UDim2.fromScale(0.3, 1), 0), -- left
		edge(gui, UDim2.fromScale(0.7, 0), UDim2.fromScale(0.3, 1), 180), -- right
	}
	redFlash = Instance.new("Frame")
	redFlash.BackgroundColor3 = Color3.fromRGB(120, 0, 0)
	redFlash.BackgroundTransparency = 1
	redFlash.BorderSizePixel = 0
	redFlash.Size = UDim2.fromScale(1, 1)
	redFlash.Parent = gui

	-- 끌려갈 때 암전
	blackout = Instance.new("Frame")
	blackout.BackgroundColor3 = Color3.fromRGB(2, 6, 10)
	blackout.BackgroundTransparency = 1
	blackout.BorderSizePixel = 0
	blackout.Size = UDim2.fromScale(1, 1)
	blackout.ZIndex = 5
	blackout.Parent = gui
	blackoutText = Instance.new("TextLabel")
	blackoutText.BackgroundTransparency = 1
	blackoutText.Size = UDim2.fromScale(1, 1)
	blackoutText.Font = Enum.Font.GothamMedium
	blackoutText.TextSize = 30
	blackoutText.TextColor3 = Color3.fromRGB(190, 200, 210)
	blackoutText.TextTransparency = 1
	blackoutText.Text = ""
	blackoutText.ZIndex = 6
	blackoutText.Parent = blackout
	baseFov = (workspace.CurrentCamera or camera).FieldOfView

	-- 붙잡힘 장면에서 귀신 얼굴을 비추는 빛 (내 화면에만)
	faceLightPart = Instance.new("Part")
	faceLightPart.Name = "GhostFaceLight"
	faceLightPart.Size = Vector3.new(0.2, 0.2, 0.2)
	faceLightPart.Transparency = 1
	faceLightPart.Anchored = true
	faceLightPart.CanCollide = false
	faceLightPart.CanQuery = false
	faceLightPart.CanTouch = false
	faceLight = Instance.new("PointLight")
	faceLight.Color = Color3.fromRGB(150, 185, 215)
	faceLight.Range = 14
	faceLight.Brightness = 0
	faceLight.Shadows = false
	faceLight.Enabled = false
	faceLight.Parent = faceLightPart
	faceLightPart.Parent = workspace

	-- 심장박동 루프 (위협이 높을수록 빠르고 큼)
	heartbeat = Instance.new("Sound")
	heartbeat.Name = "Heartbeat"
	heartbeat.SoundId = Config.Sounds.Heartbeat
	heartbeat.Volume = 0
	heartbeat.Looped = true
	heartbeat.Parent = SoundService
	heartbeat:Play()

	-- 본인 화면용 원뿔 빛: 카메라 아래의 파트는 복제되지 않음(다른 사람은 머리의 빛을 봄)
	beamPart = Instance.new("Part")
	beamPart.Name = "LanternBeamCarrier"
	beamPart.Size = Vector3.new(0.2, 0.2, 0.2)
	beamPart.Transparency = 1
	beamPart.Anchored = true
	beamPart.CanCollide = false
	beamPart.CanQuery = false
	beamPart.CanTouch = false
	beamPart.CastShadow = false
	beam = Instance.new("SpotLight")
	beam.Face = Enum.NormalId.Front
	beam.Color = Color3.fromRGB(255, 190, 120)
	beam.Angle = L.Angle
	beam.Range = L.Range
	beam.Brightness = 0
	beam.Shadows = true
	beam.Parent = beamPart
	beamPart.Parent = workspace -- 클라이언트가 만든 파트는 서버로 복제되지 않음

	-- 내 머리에 붙은(다른 사람용) 빛은 내 화면에서는 끈다. 카메라 빛과 겹치면 두 배로 밝아짐
	local function hideOwnHeadBeam(char: Model)
		local head = char:WaitForChild("Head", 10)
		if not head then
			return
		end
		local function hide(inst: Instance)
			if inst.Name == "LanternBeam" and inst:IsA("SpotLight") then
				inst.Enabled = false
			end
		end
		for _, c in head:GetChildren() do
			hide(c)
		end
		head.ChildAdded:Connect(hide)
	end
	player.CharacterAdded:Connect(hideOwnHeadBeam)
	if player.Character then
		task.spawn(hideOwnHeadBeam, player.Character)
	end

	RunService:BindToRenderStep("DeadLakeFX", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		-- 랜턴 빛은 카메라를 따라감 (살짝 오른쪽 아래, 손에 든 느낌)
		local cam = workspace.CurrentCamera or camera
		local target = if lanternOn then 1 else 0
		lanternAlpha += math.clamp(target - lanternAlpha, -dt * 8, dt * 8)
		beamPart.CFrame = cam.CFrame * CFrame.new(0.35, -0.4, 0.2)
		-- 귀신이 가까우면 랜턴이 깜빡임
		local flickerAmount = math.clamp((threat - Config.Scare.FlickerThreat) / (1 - Config.Scare.FlickerThreat), 0, 1)
		local flicker = 1
		if flickerAmount > 0 and not adminBright then
			local n = math.noise(os.clock() * 9, 3.7) + math.noise(os.clock() * 31, 9.1) * 0.6
			flicker = 1 - flickerAmount * math.clamp(n * 1.6 + 0.35, 0, 0.92)
		end
		beam.Brightness = L.Brightness * lanternAlpha * flicker
		beam.Enabled = lanternAlpha > 0.01

		local level = math.max(threat, if warning then 1 else 0)
		local alpha = math.clamp((level - 0.2) / 0.8, 0, 1)
		local beat = math.clamp((level - 0.25) / 0.75, 0, 1)
		heartbeat.Volume += (beat * Config.Audio.HeartbeatVolume - heartbeat.Volume) * math.min(1, dt * 3)
		heartbeat.PlaybackSpeed = 0.85 + beat * 0.6
		local pulse = if level > 0.6 then (math.sin(os.clock() * 6) * 0.5 + 0.5) * 0.15 else 0
		local dark = math.min(1, alpha * 0.75 + pulse + L.ScreenVignette * lanternAlpha)
		if adminBright then
			dark = 0
		end
		for _, f in vignette do
			f.BackgroundTransparency = 1 - dark
		end
		-- 붙잡힘 장면: 내 어깨 너머로 귀신 얼굴 클로즈업, 들려 있는 내 몸이 앞에 보임
		if grabShot then
			local S = Config.Scare
			local t = os.clock() - grabShotStart
			local map = workspace:FindFirstChild("DeadLake")
			local ghost = map and map:FindFirstChild("Ghost")
			local pivot = ghost and ghost:IsA("Model") and ghost.PrimaryPart
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if t > 0.6 and player:GetAttribute("Status") ~= "Grabbed" then
				Effects.setGrabShot(false)
			elseif pivot and char and hrp and hrp:IsA("BasePart") then
				local away = hrp.Position - pivot.Position
				away = Vector3.new(away.X, 0, away.Z)
				away = if away.Magnitude > 0.1 then away.Unit else -pivot.CFrame.LookVector
				local side = away:Cross(Vector3.yAxis)
				local face = pivot.Position + Vector3.new(0, S.GrabFaceHeight, 0)
				local push = math.min(1, t / 4) * S.ShotPushIn
				local camPos = hrp.Position + away * (S.ShotBack - push) + side * S.ShotSide + Vector3.new(0, S.ShotUp, 0)
				cam.CFrame = CFrame.lookAt(camPos, face:Lerp(hrp.Position, 0.2))
				cam.FieldOfView = baseFov - S.GrabZoom * math.min(1, t / 0.15)
				faceLightPart.Position = face + away * 2.5 + Vector3.new(0, 0.5, 0)
				faceLight.Brightness = S.FaceLight
				faceLight.Enabled = S.FaceLight > 0
				-- 1인칭에서는 내 몸이 투명하므로 이 장면 동안만 보이게
				for _, d in char:GetDescendants() do
					if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
						d.LocalTransparencyModifier = 0
					end
				end
			end
		end
		if os.clock() < shakeUntil then
			local s = shakeStrength
			camera.CFrame = camera.CFrame
				* CFrame.Angles(math.rad((math.random() - 0.5) * s), math.rad((math.random() - 0.5) * s), math.rad((math.random() - 0.5) * s * 0.5))
		end
	end)
end

function Effects.setThreat(value: number)
	threat = value
end

function Effects.setLantern(on: boolean)
	lanternOn = on
end

-- 관리자 모드: 덫에 빨간 Highlight (클라이언트에서만 만들어 나에게만 보임)
local trapHighlightConn: RBXScriptConnection? = nil
local trapHighlights: { Highlight } = {}
local function highlightTrap(trap: Instance)
	if not trap:IsA("Model") then
		return
	end
	local h = Instance.new("Highlight")
	h.Name = "AdminTrapHighlight"
	h.FillColor = Color3.fromRGB(255, 60, 40)
	h.FillTransparency = 0.5
	h.OutlineColor = Color3.fromRGB(255, 120, 90)
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Adornee = trap
	h.Parent = trap
	table.insert(trapHighlights, h)
end
local function setTrapHighlights(on: boolean)
	if trapHighlightConn then
		trapHighlightConn:Disconnect()
		trapHighlightConn = nil
	end
	for _, h in trapHighlights do
		h:Destroy()
	end
	table.clear(trapHighlights)
	if not on then
		return
	end
	task.spawn(function()
		local map = workspace:WaitForChild("DeadLake", 30)
		if not map then
			return
		end
		local traps = map:FindFirstChild("Traps") or map:WaitForChild("Traps", 30)
		if not traps or not adminBright then
			return
		end
		for _, t in traps:GetChildren() do
			highlightTrap(t)
		end
		trapHighlightConn = traps.ChildAdded:Connect(highlightTrap)
		-- 라운드가 새로 시작되면 Traps 폴더가 다시 만들어짐
		map.ChildAdded:Connect(function(child)
			if child.Name == "Traps" and adminBright then
				if trapHighlightConn then
					trapHighlightConn:Disconnect()
				end
				trapHighlightConn = child.ChildAdded:Connect(highlightTrap)
				for _, t in child:GetChildren() do
					highlightTrap(t)
				end
			end
		end)
	end)
end

-- 관리자 모드: 내 화면의 Lighting 만 대낮처럼. 끌 때 원래 값으로 복원 (서버 값은 건드리지 않음)
local savedLighting: { [string]: any }? = nil
function Effects.setAdminBright(on: boolean)
	adminBright = on
	setTrapHighlights(on)
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if on then
		if not savedLighting then
			savedLighting = {
				Brightness = Lighting.Brightness,
				Ambient = Lighting.Ambient,
				OutdoorAmbient = Lighting.OutdoorAmbient,
				ClockTime = Lighting.ClockTime,
				FogStart = Lighting.FogStart,
				FogEnd = Lighting.FogEnd,
				ExposureCompensation = Lighting.ExposureCompensation,
				AtmoDensity = if atmo then atmo.Density else nil,
				CcEnabled = if cc then cc.Enabled else nil,
			}
		end
		Lighting.Brightness = 2.5
		Lighting.Ambient = Color3.fromRGB(170, 170, 175)
		Lighting.OutdoorAmbient = Color3.fromRGB(190, 190, 200)
		Lighting.ClockTime = 14
		Lighting.FogStart = 100000
		Lighting.FogEnd = 200000
		Lighting.ExposureCompensation = 0.4
		if atmo then
			atmo.Density = 0
		end
		if cc then
			cc.Enabled = false
		end
	elseif savedLighting then
		local s = savedLighting
		Lighting.Brightness = s.Brightness
		Lighting.Ambient = s.Ambient
		Lighting.OutdoorAmbient = s.OutdoorAmbient
		Lighting.ClockTime = s.ClockTime
		Lighting.FogStart = s.FogStart
		Lighting.FogEnd = s.FogEnd
		Lighting.ExposureCompensation = s.ExposureCompensation
		if atmo and s.AtmoDensity ~= nil then
			atmo.Density = s.AtmoDensity
		end
		if cc and s.CcEnabled ~= nil then
			cc.Enabled = s.CcEnabled
		end
		savedLighting = nil
	end
end

function Effects.setWarning(on: boolean)
	warning = on
	if on then
		redFlash.BackgroundTransparency = 0.55
		TweenService:Create(redFlash, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	end
end

-- 붙잡힌 동안: 어깨 너머 카메라로 전환 / 풀리면 1인칭으로 복귀
function Effects.setGrabShot(on: boolean)
	if on == grabShot then
		return
	end
	grabShot = on
	grabShotStart = os.clock()
	if not on then
		faceLight.Enabled = false
		local cam = workspace.CurrentCamera or camera
		cam.FieldOfView = baseFov
	end
end

-- 호수로 끌려감: fadeIn 초 동안 어두워지고, 글씨가 떴다가 걷힘
function Effects.dragBlackout(fadeIn: number)
	blackout.BackgroundTransparency = 1
	blackoutText.TextTransparency = 1
	blackoutText.Text = Config.Scare.DeathText
	TweenService:Create(blackout, TweenInfo.new(fadeIn, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 0 }):Play()
	task.delay(fadeIn, function()
		TweenService:Create(blackoutText, TweenInfo.new(0.8), { TextTransparency = 0 }):Play()
		task.wait(Config.Scare.DeathHold)
		TweenService:Create(blackoutText, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
		TweenService:Create(blackout, TweenInfo.new(1.5), { BackgroundTransparency = 1 }):Play()
	end)
end

function Effects.shake(seconds: number, strength: number)
	shakeUntil = os.clock() + seconds
	shakeStrength = strength
end

function Effects.flash(transparency: number, seconds: number)
	redFlash.BackgroundTransparency = transparency
	TweenService:Create(redFlash, TweenInfo.new(seconds), { BackgroundTransparency = 1 }):Play()
end

return Effects
