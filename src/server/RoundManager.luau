-- 진행 관리: 라운드·대기·제한시간 없음.
-- 플레이어가 들어오면 바로 캠프에서 시작 → 호수 주변 항아리 3개를 채우면 귀신 봉인 → 문 열림 → 탈출.
-- 탈출 성공 또는 전원 사망이면 결과 화면 뒤 맵을 되돌리고 전원 캠프에서 다시 시작.
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

-- Waiting(아무도 없음) → Playing → Sealing → Escape → Ended → Playing ...
local phase = "Waiting"
local timeLeft = 0
local filledCount = 0
local jarFill: { [number]: number } = {} -- 사당 인덱스 → 부은 양동이 수
local spawnIndex = 0

local function setPhase(p: string)
	phase = p
	gs:SetAttribute("Phase", p)
end

local function setTime(t: number)
	timeLeft = t
	gs:SetAttribute("TimeLeft", math.max(0, math.ceil(t)))
end

local function target(): number
	return #map.Shrines
end

local function isFull(shrine: any): boolean
	return (jarFill[shrine.Index] or 0) >= R.BucketsPerJar
end

local function refreshShrine(shrine: any, animate: boolean)
	local n = jarFill[shrine.Index] or 0
	local ratio = math.clamp(n / R.BucketsPerJar, 0, 1)
	local water = shrine.Water :: BasePart
	local c = shrine.Center :: Vector3
	local y = shrine.WaterMinY + ratio * (shrine.WaterMaxY - shrine.WaterMinY)
	if R.BucketsPerJar > 1 then
		shrine.Label.Text = string.format("%s  %d / %d", shrine.Name, n, R.BucketsPerJar)
	else
		shrine.Label.Text = if ratio >= 1 then shrine.Name .. " - 채워짐" else shrine.Name .. " - 비어 있음"
	end
	shrine.Label.TextColor3 = if ratio >= 1 then Color3.fromRGB(170, 215, 255) else Color3.fromRGB(150, 185, 230)
	if animate then
		Util.tween(water, 1.2, { Position = Vector3.new(c.X, y, c.Z) }, Enum.EasingStyle.Sine)
		for _, light in shrine.Candles do
			Util.tween(light, 1.2, { Brightness = ratio * 1.8 }, Enum.EasingStyle.Sine)
		end
	else
		water.Position = Vector3.new(c.X, y, c.Z)
		water.Color = Color3.fromRGB(40, 90, 120)
		water.Transparency = 0.25
		for _, light in shrine.Candles do
			light.Brightness = ratio * 1.8
			light.Range = 6
		end
	end
end

local function publishProgress()
	gs:SetAttribute("Buckets", filledCount)
	gs:SetAttribute("Target", target())
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

local function endRun(win: boolean, reason: string)
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
		if alive == 0 then
			endRun(false, "모두 살목지에 삼켜졌습니다.")
		end
	elseif phase == "Sealing" then
		if alive == 0 then
			endRun(false, "봉인은 됐지만 아무도 남지 않았습니다.")
		end
	elseif phase == "Escape" then
		local timeUp = R.EscapeTime > 0 and timeLeft <= 0
		if alive == 0 or timeUp then
			if escaped > 0 then
				endRun(true, string.format("%d명이 살아서 돌아왔습니다.", escaped))
			else
				endRun(false, "아무도 출구를 넘지 못했습니다.")
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
	Net.notifyAll("항아리가 모두 찼다... 호수가 울부짖는다!", 4)
	Net.broadcast("Sfx", "Seal")
	for _, shrine in map.Shrines do
		for _, light in shrine.Candles do
			Util.tween(light, 0.5, { Brightness = 6, Range = 14 }, Enum.EasingStyle.Quad)
		end
		Util.tween(shrine.Water, 1.5, { Color = Color3.fromRGB(120, 180, 255), Transparency = 0 })
	end
	task.delay(3.5, function()
		if phase == "Sealing" then
			beginEscape()
		end
	end)
end

-- 물을 부었을 때. 이미 가득 찬 항아리면 false (양동이는 그대로)
function RoundManager.onDelivered(player: Player, shrine: any): boolean
	if phase ~= "Playing" or isFull(shrine) then
		return false
	end
	jarFill[shrine.Index] = (jarFill[shrine.Index] or 0) + 1
	refreshShrine(shrine, true)
	if isFull(shrine) then
		filledCount += 1
		publishProgress()
		Net.notifyAll(string.format("%s님이 %s을(를) 채웠습니다. (%d / %d)", player.DisplayName, shrine.Name, filledCount, target()), 3)
		if filledCount >= target() then
			sealGhost()
		end
	else
		Net.notify(player, string.format("%s  %d / %d", shrine.Name, jarFill[shrine.Index], R.BucketsPerJar), 2)
	end
	return true
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

-- 맵을 처음 상태로 되돌리고 모든 플레이어를 캠프에 세움
local function startRun()
	filledCount = 0
	table.clear(jarFill)
	gs:SetAttribute("Result", "")
	gs:SetAttribute("Reason", "")
	for _, shrine in map.Shrines do
		refreshShrine(shrine, false)
	end
	publishProgress()
	setGate(false)
	Ghost.resetAll()
	Water.resetAll()
	TrapSystem.clear()
	local players = Players:GetPlayers()
	TrapSystem.spawn(Config.Traps.Base + Config.Traps.PerPlayer * #players)
	spawnIndex = 0
	for _, p in players do
		PlayerState.setStatus(p, "Alive")
		task.spawn(spawnPlayer, p)
	end
	setTime(0)
	setPhase("Playing")
	Net.notifyAll(
		string.format(
			"호수에서 물을 길어 주변 항아리 %d개를 채우세요. 랜턴(F)을 켜면 덫이 보이지만 귀신에게 발각됩니다.",
			target()
		),
		8
	)
end

-- 진행 중 들어온 플레이어: 기다리지 않고 바로 캠프에서 합류
local function joinRun(player: Player)
	PlayerState.setStatus(player, "Alive")
	task.spawn(spawnPlayer, player)
	Net.notify(player, "밤이 이미 시작됐습니다. 캠프에서 합류합니다.", 4)
end

function RoundManager.start()
	task.spawn(function()
		while true do
			while #Players:GetPlayers() < R.MinPlayers do
				setPhase("Waiting")
				task.wait(1)
			end
			startRun()
			local last = os.clock()
			while RoundManager.isPlaying() do
				task.wait(0.2)
				local now = os.clock()
				local dt = now - last
				last = now
				if phase == "Escape" and R.EscapeTime > 0 then
					setTime(timeLeft - dt)
				end
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
	gs:SetAttribute("Target", target())
	gs:SetAttribute("Result", "")
	gs:SetAttribute("Reason", "")

	local function onPlayer(player: Player)
		PlayerState.setStatus(player, "Lobby")
		player:SetAttribute("Threat", 0)
		player:SetAttribute("Fill", 0)
		if RoundManager.isPlaying() then
			joinRun(player)
		elseif phase == "Ended" then
			Net.notify(player, "밤이 끝나는 중입니다. 잠시 뒤 캠프에서 시작합니다.", 4)
		end
		-- Waiting 이면 루프가 곧 startRun 으로 스폰시킴
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
