-- 살목지(Dead Lake) 클라이언트 진입점: 입력, HUD, 연출, 관전
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local root = ReplicatedStorage:WaitForChild("DeadLake")
local Config = require(root:WaitForChild("Shared"):WaitForChild("Config"))
local remotes = root:WaitForChild("Remotes")
local toServer = remotes:WaitForChild("ToServer") :: RemoteEvent
local toClient = remotes:WaitForChild("ToClient") :: RemoteEvent
local gs = root:WaitForChild("GameState")

local HUD = require(script.Parent.HUD)
local Effects = require(script.Parent.Effects)
local Spectate = require(script.Parent.Spectate)
local Ambience = require(script.Parent.Ambience)
local WraithAnimator = require(script.Parent.WraithAnimator)

local player = Players.LocalPlayer
local grabbed = false

HUD.init()
Effects.init()
Spectate.init(HUD.setSpectate)
Ambience.init()
WraithAnimator.init()

local function send(kind: string, data: any?)
	toServer:FireServer(kind, data)
end

---------------------------------------------------------------- 게임 상태
local lastPhase = ""
local function refreshState()
	local phase = (gs:GetAttribute("Phase") :: string?) or "Waiting"
	if phase ~= lastPhase then
		lastPhase = phase
		if phase ~= "Playing" then
			Ambience.setHunted(false)
		end
		if phase == "Ended" and gs:GetAttribute("Result") == "Win" then
			Ambience.play(Config.Sounds.Win, 0.7, 1)
		end
	end
	HUD.setPhase(phase)
	HUD.setTimer((gs:GetAttribute("TimeLeft") :: number?) or 0)
	HUD.setBuckets((gs:GetAttribute("Buckets") :: number?) or 0, (gs:GetAttribute("Target") :: number?) or 0)
	if phase == "Ended" then
		local result = gs:GetAttribute("Result")
		if result == "Win" or result == "Lose" then
			HUD.showResult(result == "Win", (gs:GetAttribute("Reason") :: string?) or "")
		end
	end
	local status = (player:GetAttribute("Status") :: string?) or "Lobby"
	local spectating = (phase == "Playing" or phase == "Sealing" or phase == "Escape") and (status == "Dead" or status == "Escaped")
	Spectate.setActive(spectating)
end
for _, name in { "Phase", "TimeLeft", "Buckets", "Target", "Result" } do
	gs:GetAttributeChangedSignal(name):Connect(refreshState)
end
player:GetAttributeChangedSignal("Status"):Connect(refreshState)
refreshState()

---------------------------------------------------------------- 물뜨기 게이지 / 위협
local function refreshGauge()
	local filling = player:GetAttribute("Filling") == true
	local fill = (player:GetAttribute("Fill") :: number?) or 0
	local show = filling or fill > 0.01
	local paused = false
	if filling then
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		paused = hum ~= nil and hrp ~= nil and hum.MoveDirection.Magnitude > 0.1
	end
	HUD.setGauge(show, fill, paused)
end
player:GetAttributeChangedSignal("Fill"):Connect(refreshGauge)
player:GetAttributeChangedSignal("Filling"):Connect(refreshGauge)
player:GetAttributeChangedSignal("Threat"):Connect(function()
	local t = (player:GetAttribute("Threat") :: number?) or 0
	Effects.setThreat(t)
	Ambience.setThreat(t)
end)
player:GetAttributeChangedSignal("Awareness"):Connect(function()
	HUD.setAwareness((player:GetAttribute("Awareness") :: number?) or 0)
end)
player:GetAttributeChangedSignal("Stamina"):Connect(function()
	HUD.setStamina((player:GetAttribute("Stamina") :: number?) or 1)
end)
player:GetAttributeChangedSignal("LanternOn"):Connect(function()
	local on = player:GetAttribute("LanternOn") == true
	HUD.setLantern(on)
	Effects.setLantern(on)
end)
local function refreshLives()
	HUD.setLives((player:GetAttribute("Lives") :: number?) or Config.Ghost.Lives, Config.Ghost.Lives)
end
player:GetAttributeChangedSignal("Lives"):Connect(refreshLives)
refreshLives()
player:GetAttributeChangedSignal("Carrying"):Connect(function()
	HUD.setCarrying(player:GetAttribute("Carrying") == true)
end)
HUD.setLantern(player:GetAttribute("LanternOn") == true)
Effects.setLantern(player:GetAttribute("LanternOn") == true)
player:GetAttributeChangedSignal("Admin"):Connect(function()
	local on = player:GetAttribute("Admin") == true
	Effects.setAdminBright(on)
	HUD.setAdmin(on)
end)

---------------------------------------------------------------- 서버 메시지
local playUi = Ambience.play

toClient.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "Notify" then
		HUD.banner(data.Text, data.Time or 3)
	elseif kind == "Danger" then
		Effects.setWarning(data.Level == 1)
	elseif kind == "Grabbed" then
		grabbed = data.CanMash ~= false
		HUD.showMash(true, data.CanMash ~= false)
		Effects.setWarning(true)
		Effects.setGrabShot(true)
		Effects.shake(0.9, 5)
		Effects.flash(0.4, 0.5)
	elseif kind == "MashProgress" then
		HUD.setMash(data.Count, data.Required)
	elseif kind == "Released" then
		grabbed = false
		HUD.showMash(false)
		Effects.setWarning(false)
		Effects.setGrabShot(false)
	elseif kind == "Dragged" then
		grabbed = false
		HUD.showMash(false)
		Effects.setWarning(false)
		Effects.setGrabShot(false)
		Effects.shake(data.Time or 2.5, 10)
		Effects.flash(0.2, data.Time or 2.5)
		Effects.dragBlackout(data.Time or 2.5)
	elseif kind == "Lantern" then
		playUi(Config.Sounds.Click, 0.5, if data.On then 1.1 else 0.95)
	elseif kind == "Trapped" then
		Effects.shake(0.5, 8)
		Effects.flash(0.5, 0.6)
		playUi(Config.Sounds.TrapSnap, 0.6, 1)
	elseif kind == "Hunt" then
		HUD.setGhost(data.State, data.Target == player.Name)
		Ambience.setHunted(data.State == "Hunting" and data.Target == player.Name)
		if data.State == "Hunting" and data.Target == player.Name then
			playUi(Config.Sounds.Stinger, Config.Audio.StingerVolume, 0.95)
			Effects.setWarning(true)
			HUD.banner("귀신이 당신을 발견했다! 랜턴을 끄고 도망쳐라!", 3)
			task.delay(1.2, function()
				Effects.setWarning(false)
			end)
		elseif data.State == "Hunting" and player:GetAttribute("Status") == "Alive" then
			-- 팀원이 발견됐을 때: 흐느낌이 작게 들림
			playUi(Config.Sounds.Stinger, Config.Audio.StingerTeamVolume, 0.95)
		elseif data.State == "Sealed" then
			Effects.setWarning(false)
		end
	elseif kind == "Sfx" then
		if data == "Fill" then
			playUi(Config.Sounds.Fill, 0.6, 1)
		elseif data == "Pour" then
			playUi(Config.Sounds.Pour, 0.5, 1)
		elseif data == "Gate" then
			playUi(Config.Sounds.Gate, 0.5, 0.9)
		elseif data == "Seal" then
			playUi(Config.Sounds.Bell, 1, 0.8)
			playUi(Config.Sounds.Rumble, 0.8, 1, 6)
			Effects.shake(2.5, 4)
		end
	end
end)

---------------------------------------------------------------- 입력
ContextActionService:BindAction("DeadLakeSprint", function(_, state)
	if state == Enum.UserInputState.Begin then
		send("Sprint", true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		send("Sprint", false)
	end
	return Enum.ContextActionResult.Pass
end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)
ContextActionService:SetTitle("DeadLakeSprint", "달리기")
ContextActionService:SetPosition("DeadLakeSprint", UDim2.new(0.72, 0, 0.35, 0))

-- 관리자(테스트) 모드: P. 서버가 허용된 사람인지 확인한 뒤 Admin 속성을 바꿈
ContextActionService:BindAction("DeadLakeAdmin", function(_, state)
	if state == Enum.UserInputState.Begin then
		send("Admin")
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.P)

ContextActionService:BindAction("DeadLakeLantern", function(_, state)
	if state == Enum.UserInputState.Begin then
		send("Lantern")
	end
	return Enum.ContextActionResult.Sink
end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
ContextActionService:SetTitle("DeadLakeLantern", "랜턴")
ContextActionService:SetPosition("DeadLakeLantern", UDim2.new(0.72, 0, 0.2, 0))

ContextActionService:BindAction("DeadLakeDrop", function(_, state)
	if state == Enum.UserInputState.Begin and player:GetAttribute("Carrying") == true then
		send("DropBucket")
	end
	return Enum.ContextActionResult.Pass
end, true, Enum.KeyCode.G, Enum.KeyCode.ButtonX)
ContextActionService:SetTitle("DeadLakeDrop", "버리기")
ContextActionService:SetPosition("DeadLakeDrop", UDim2.new(0.6, 0, 0.2, 0))

ContextActionService:BindAction("DeadLakeMash", function(_, state)
	if state == Enum.UserInputState.Begin and grabbed then
		send("Mash")
		Effects.shake(0.1, 2)
	end
	return Enum.ContextActionResult.Pass
end, true, Enum.KeyCode.E, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
ContextActionService:SetTitle("DeadLakeMash", "뿌리치기")
ContextActionService:SetPosition("DeadLakeMash", UDim2.new(0.6, 0, 0.5, 0))

print("[DeadLake] 클라이언트 준비 완료")
