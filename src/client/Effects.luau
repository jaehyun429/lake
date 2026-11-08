-- 위험 연출: 화면 가장자리 어두워짐, 심장박동, 경고 플래시, 끌려갈 때 화면 흔들림
local Players = game:GetService("Players")
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
local heartbeat2: Sound
local shakeUntil = 0
local shakeStrength = 0

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

	heartbeat = Instance.new("Sound")
	heartbeat.SoundId = Config.Sounds.Heartbeat
	heartbeat.Volume = 0
	heartbeat.PlaybackSpeed = 0.35
	heartbeat.Parent = SoundService
	heartbeat2 = heartbeat:Clone()
	heartbeat2.PlaybackSpeed = 0.3
	heartbeat2.Parent = SoundService

	-- 심장박동 루프 (위협이 높을수록 빠르고 큼)
	task.spawn(function()
		while true do
			local level = math.max(threat, if warning then 1 else 0)
			if level > 0.25 then
				local vol = (level - 0.25) / 0.75
				heartbeat.Volume = 0.25 + vol * 0.6
				heartbeat2.Volume = heartbeat.Volume * 0.8
				heartbeat:Play()
				task.wait(0.16)
				heartbeat2:Play()
				task.wait(math.max(0.25, 1.1 - level * 0.75))
			else
				task.wait(0.2)
			end
		end
	end)

	RunService:BindToRenderStep("DeadLakeFX", Enum.RenderPriority.Camera.Value + 1, function()
		local level = math.max(threat, if warning then 1 else 0)
		local alpha = math.clamp((level - 0.2) / 0.8, 0, 1)
		local pulse = if level > 0.6 then (math.sin(os.clock() * 6) * 0.5 + 0.5) * 0.15 else 0
		for _, f in vignette do
			f.BackgroundTransparency = 1 - (alpha * 0.75 + pulse)
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

function Effects.setWarning(on: boolean)
	warning = on
	if on then
		redFlash.BackgroundTransparency = 0.55
		TweenService:Create(redFlash, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	end
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
