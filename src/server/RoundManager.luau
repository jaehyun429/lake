-- 라운드 루프: 대기 → 라운드(물 긷기) → 탈출 → 결과
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.DeadLake.Shared.Config)
local Util = require(script.Parent.Util)
local Net = require(script.Parent.Net)
local PlayerState = require(script.Parent.PlayerState)
local LanternSystem = require(script.Parent.LanternSystem)
local TrapSystem = require(script.Parent.TrapSystem)
local StaminaSystem = require(script.Parent.StaminaSystem)

local R = Config.Round
local gs = ReplicatedStorage.DeadLake.GameState

local RoundManager = {}
local map: any
local Water: any
local Ghost: any

local phase = "Waiting"
local timeLeft = 0
local roundElapsed = 0
local delivered = 0
local target = 0
local spawnIndex = 0

local function setPhase(p: string)
	phase = p
	gs:SetAttribute("Phase", p)
end

local function setTime(t: number)
	timeLeft = t
	gs:SetAttribute("TimeLeft", math.max(0, math.ceil(t)))
end

local function setBuckets()
	gs:SetAttribute("Buckets", delivered)
	gs:SetAttribute("Target", target)
	map.AltarLabel.Text = string.format("제단 %d / %d", delivered, target)
	local ratio = if target > 0 then delivered / target else 0
	local water = map.AltarWater :: BasePart
	local c = Config.Map.AltarCenter
	local y = map.AltarWaterMinY + ratio * (map.AltarWaterMaxY - map.AltarWaterMinY)
	Util.tween(water, 1.2, { Position = Vector3.new(c.X, y, c.Z) }, Enum.EasingStyle.Sine)
	for _, light in map.AltarCandles do
		Util.tween(light, 1.2, { Brightness = ratio * 1.8 }, Enum.EasingStyle.Sine)
	end
end

function RoundManager.isPlaying(): boolean
	return phase == "Playing" or phase == "Sealing" or phase == "Escape"
end

local function spawnPlayer(player: Player)
	if not player.Parent then
		return
	end
	player:LoadCharacter()
	StaminaSystem.reset(player)
	local char = player.Character or player.CharacterAdded:Wait()
	local root = char:WaitForChild("HumanoidRootPart", 5)
	spawnIndex += 1
	local pos = map.Spawns[(spawnIndex - 1) % #map.Spawns + 1]
	if root then
		char:PivotTo(CFrame.lookAt(pos, Vector3.new(Config.Map.CampCenter.X, pos.Y, Config.Map.CampCenter.Z)))
	end
	LanternSystem.give(player, char)
	player:SetAttribute("Carrying", false)
	player:SetAttribute("Sprinting", false)
	PlayerState.applySpeed(player)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Died:Connect(function()
			if RoundManager.isPlaying() and PlayerState.getStatus(player) == "Alive" then
				PlayerState.setStatus(player, "Dead")
				Water.resetPlayer(player)
				Net.notifyAll(string.format("%s님이 쓰러졌습니다.", player.DisplayName), 3)
			end
		end)
	end
end

local function countStatus(...: string): number
	local wanted = { ... }
	local n = 0
	for _, p in Players:GetPlayers() do
		local st = PlayerState.getStatus(p)
		for _, w in wanted do
			if st == w then
				n += 1
				break
			end
		end
	end
	return n
end

local function setGate(open: boolean)
	local panel = map.GatePanel :: BasePart
	local base = Config.Map.GatePosition + Vector3.new(0, 4.75, 0)
	local goal = if open then base + Vector3.new(0, 9.2, 0) else base
	Util.tween(panel, if open then 2.5 else 0.1, { Position = goal }, Enum.EasingStyle.Sine)
	for _, bar in panel:GetChildren() do
		if bar:IsA("BasePart") then
			Util.tween(bar, if open then 2.5 else 0.1, { Position = goal + (bar.Position - panel.Position) }, Enum.EasingStyle.Sine)
		end
	end
	panel.CanCollide = not open
	if open then
		Util.playAt(base, Config.Sounds.Gate, 1, 0.5)
	end
end

local function endRound(win: boolean, reason: string)
	if phase == "Ended" then
		return
	end
	setPhase("Ended")
	gs:SetAttribute("Result", if win then "Win" else "Lose")
	gs:SetAttribute("Reason", reason)
	Ghost.resetAll()
	Water.resetAll()
	Net.notifyAll(if win then "탈출 성공! " .. reason else "실패... " .. reason, R.EndingTime)
end

local function checkEnd()
	local alive = countStatus("Alive", "Grabbed")
	local escaped = countStatus("Escaped")
	if phase == "Playing" then
		if timeLeft <= 0 then
			endRound(false, "새벽이 오기 전에 제단을 채우지 못했습니다.")
		elseif alive == 0 then
			endRound(false, "모두 살목지에 삼켜졌습니다.")
		end
	elseif phase == "Sealing" then
		if alive == 0 then
			endRound(false, "봉인은 됐지만 아무도 남지 않았습니다.")
		end
	elseif phase == "Escape" then
		if alive == 0 or timeLeft <= 0 then
			if escaped > 0 then
				endRound(true, string.format("%d명이 살아서 돌아왔습니다.", escaped))
			else
				endRound(false, "아무도 출구를 넘지 못했습니다.")
			end
		end
	end
end

local function beginEscape()
	setPhase("Escape")
	setTime(R.EscapeTime)
	setGate(true)
	Net.notifyAll("귀신이 봉인됐습니다! 출구 문이 열립니다. 캠프의 문으로 탈출하세요!", 6)
	Net.broadcast("Sfx", "Gate")
end

local function sealGhost()
	setPhase("Sealing")
	Ghost.seal()
	Net.notifyAll("제단이 가득 찼다... 호수가 울부짖는다!", 4)
	Net.broadcast("Sfx", "Seal")
	-- 촛불이 강하게 타오름
	for _, light in map.AltarCandles do
		Util.tween(light, 0.5, { Brightness = 6, Range = 14 }, Enum.EasingStyle.Quad)
	end
	Util.tween(map.AltarWater, 1.5, { Color = Color3.fromRGB(120, 180, 255), Transparency = 0 })
	task.delay(3.5, function()
		if phase == "Sealing" then
			beginEscape()
		end
	end)
end

function RoundManager.onDelivered(player: Player)
	if phase ~= "Playing" then
		return
	end
	delivered += 1
	setBuckets()
	Net.notifyAll(string.format("%s님이 제단에 물을 부었습니다. (%d / %d)", player.DisplayName, delivered, target), 3)
	if delivered >= target then
		sealGhost()
	end
end

function RoundManager.onPlayerDied(_player: Player)
	-- 상태는 GhostSystem 에서 이미 Dead 로 바꿈. 종료 조건은 루프에서 확인.
end

local function onEscaped(player: Player)
	if phase ~= "Escape" or PlayerState.getStatus(player) ~= "Alive" then
		return
	end
	PlayerState.setStatus(player, "Escaped")
	Water.resetPlayer(player)
	Net.notify(player, "탈출했습니다! 남은 팀원을 기다리는 중...", 4)
	Net.notifyAll(string.format("%s님이 탈출했습니다!", player.DisplayName), 3)
	local char = player.Character
	task.delay(0.3, function()
		if char and char.Parent then
			char:Destroy()
		end
	end)
end

local function startRound()
	delivered = 0
	roundElapsed = 0
	local players = Players:GetPlayers()
	target = math.clamp(R.BucketTargetBase + R.BucketTargetPerPlayer * #players, R.BucketTargetMin, R.BucketTargetMax)
	gs:SetAttribute("Result", "")
	gs:SetAttribute("Reason", "")
	setBuckets()
	setGate(false)
	Ghost.resetAll()
	Water.resetAll()
	TrapSystem.spawn(Config.Traps.Base + Config.Traps.PerPlayer * #players)
	spawnIndex = 0
	for _, p in players do
		PlayerState.setStatus(p, "Alive")
		task.spawn(spawnPlayer, p)
	end
	setTime(R.RoundTime)
	setPhase("Playing")
	Net.notifyAll(
		string.format(
			"호수에서 물을 길어 반대편 제단을 채우세요. 목표: 양동이 %d개. 랜턴(F)을 켜면 덫이 보이지만 귀신에게 발각됩니다.",
			target
		),
		8
	)
end

local function intermission()
	setPhase("Intermission")
	gs:SetAttribute("Result", "")
	Ghost.resetAll()
	Water.resetAll()
	TrapSystem.clear()
	map.AltarWater.Color = Color3.fromRGB(40, 90, 120)
	map.AltarWater.Transparency = 0.25
	for _, light in map.AltarCandles do
		light.Brightness = 0
		light.Range = 6
	end
	for _, p in Players:GetPlayers() do
		PlayerState.setStatus(p, "Lobby")
		if not p.Character or not p.Character.Parent then
			task.spawn(spawnPlayer, p)
		end
	end
	local t = R.IntermissionTime
	setTime(t)
	while t > 0 do
		task.wait(1)
		t -= 1
		setTime(t)
	end
end

function RoundManager.start()
	task.spawn(function()
		while true do
			while #Players:GetPlayers() < R.MinPlayers do
				setPhase("Waiting")
				task.wait(1)
			end
			intermission()
			if #Players:GetPlayers() < R.MinPlayers then
				continue
			end
			startRound()
			local last = os.clock()
			while RoundManager.isPlaying() do
				task.wait(0.2)
				local now = os.clock()
				local dt = now - last
				last = now
				roundElapsed += dt
				setTime(timeLeft - dt)
				checkEnd()
			end
			task.wait(R.EndingTime)
		end
	end)
end

function RoundManager.init(mapInfo: any, water: any, ghost: any)
	map = mapInfo
	Water = water
	Ghost = ghost
	Players.CharacterAutoLoads = false
	setPhase("Waiting")
	gs:SetAttribute("TimeLeft", 0)
	gs:SetAttribute("Buckets", 0)
	gs:SetAttribute("Target", 0)
	gs:SetAttribute("Result", "")
	gs:SetAttribute("Reason", "")

	local function onPlayer(player: Player)
		PlayerState.setStatus(player, "Lobby")
		player:SetAttribute("Threat", 0)
		player:SetAttribute("Fill", 0)
		if not RoundManager.isPlaying() then
			task.spawn(spawnPlayer, player)
		else
			Net.notify(player, "라운드가 진행 중입니다. 다음 판까지 관전합니다.", 5)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayer, p)
	end

	Net.on("Sprint", function(player, on)
		player:SetAttribute("Sprinting", on == true and StaminaSystem.canSprint(player))
		PlayerState.applySpeed(player)
	end)

	map.ExitZone.Touched:Connect(function(hit: BasePart)
		local char = hit.Parent
		local player = char and Players:GetPlayerFromCharacter(char)
		if player then
			onEscaped(player)
		end
	end)
end

return RoundManager
