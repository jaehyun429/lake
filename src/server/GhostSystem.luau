-- 귀신(사냥꾼): 발각(Awareness) → 호수에서 나와 추격 → 발목 잡기 → 뿌리치기/구조 또는 끌려감. 제단이 차면 봉인.
-- 상태: Lurking(물속 대기) | Hunting | Searching | Returning | Stunned | Sealed
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.DeadLake.Shared.Config)
local Util = require(script.Parent.Util)
local Net = require(script.Parent.Net)
local PlayerState = require(script.Parent.PlayerState)
local GhostBuilder = require(script.Parent.GhostBuilder)

local G = Config.Ghost
local A = Config.Awareness
local M = Config.Map
local FEET = GhostBuilder.FEET -- 몸통 중심에서 발까지

type PState = {
	Awareness: number,
	Immune: number,
	Phase: string, -- Idle | Grabbed | Dragging
	Timer: number,
	Mash: number,
	LastMash: number,
	RescuePrompt: ProximityPrompt?,
}

local GhostSystem = {}
local map: any
local ctx: {
	isPlaying: () -> boolean,
	isFilling: (Player) -> boolean,
	isSprinting: (Player) -> boolean,
	isLanternOn: (Player) -> boolean,
	dropBucket: (Player, boolean?) -> (),
	onPlayerDragged: (Player) -> (),
}
local states: { [Player]: PState } = {}
local body: Model
local rng = Random.new()

-- 귀신 상태
local gState = "Lurking"
local gPos: Vector3 -- 발 위치
local gLook: Vector3 = Vector3.new(0, 0, 1)
local gTarget: Player? = nil
local gLastKnown: Vector3? = nil
local gTimer = 0
local gWander = 0
local gGiveUp = 0
local sinkAmount = 0 -- 0 수면, 1 완전 잠수
local bodyTime = 0
local nextSubmerge = 0
local sealed = false

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function hdist(a: Vector3, b: Vector3): number
	return (flat(a) - flat(b)).Magnitude
end

local function getState(player: Player): PState
	local s = states[player]
	if not s then
		s = { Awareness = 0, Immune = 0, Phase = "Idle", Timer = 0, Mash = 0, LastMash = 0 }
		states[player] = s
	end
	return s
end

local function idleFeet(): Vector3
	local p = map.GhostIdleCFrame.Position
	return Vector3.new(p.X, M.WaterLevel - 6, p.Z)
end

---------------------------------------------------------------- 지면
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function groundY(x: number, z: number): number
	local exclude = { body }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	local traps = map.Folder:FindFirstChild("Traps")
	if traps then
		table.insert(exclude, traps)
	end
	rayParams.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(Vector3.new(x, 60, z), Vector3.new(0, -140, 0), rayParams)
	local y = if hit then hit.Position.Y else 0
	if hdist(Vector3.new(x, 0, z), M.LakeCenter) < M.LakeRadius + 2 then
		y = math.max(y, M.WaterLevel - 6)
	end
	return y
end

local function placeBody()
	local torso = gPos + Vector3.new(0, FEET - sinkAmount * 12, 0)
	local bob = math.sin(bodyTime * 0.9) * 0.2
	local lookAt = torso + gLook
	body:PivotTo(CFrame.lookAt(torso + Vector3.new(0, bob, 0), Vector3.new(lookAt.X, torso.Y + bob, lookAt.Z)))
end

local function moveToward(targetPos: Vector3, speed: number, dt: number): number
	local to = flat(targetPos) - flat(gPos)
	local d = to.Magnitude
	if d > 0.05 then
		local step = math.min(d, speed * dt)
		local dir = to.Unit
		gLook = gLook:Lerp(dir, math.min(1, dt * 6))
		local nx, nz = gPos.X + dir.X * step, gPos.Z + dir.Z * step
		gPos = Vector3.new(nx, groundY(nx, nz), nz)
	end
	return d
end

---------------------------------------------------------------- 지각
local function perceives(player: Player, root: BasePart, hum: Humanoid): boolean
	local d = hdist(gPos, root.Position)
	if ctx.isLanternOn(player) and d < G.SeeRange then
		return true
	end
	if d < G.HearRange then
		return true
	end
	if ctx.isSprinting(player) and hum.MoveDirection.Magnitude > 0.1 and d < A.SprintRange then
		return true
	end
	local swimming = hum:GetState() == Enum.HumanoidStateType.Swimming or root.Position.Y < M.WaterLevel + 1.5
	if swimming and d < A.SwimRange then
		return true
	end
	return false
end

local function inSafe(pos: Vector3): boolean
	return hdist(pos, M.CampCenter) <= M.SafeRadius
end

---------------------------------------------------------------- 사냥 상태 전환
local function emergeEffects()
	local wp = Vector3.new(gPos.X, M.WaterLevel, gPos.Z)
	GhostBuilder.ripple(wp, map.Folder, 1.6)
	GhostBuilder.splash(wp, map.Folder)
	Util.playAt(wp + Vector3.new(0, 4, 0), Config.Sounds.Scream, 1, 0.45)
end

local function startHunt(player: Player, pos: Vector3)
	if sealed then
		return
	end
	local wasLurking = gState == "Lurking"
	gState = "Hunting"
	gTarget = player
	gLastKnown = pos
	gGiveUp = 0
	if wasLurking then
		sinkAmount = 0
		emergeEffects()
		Net.notifyAll("호수가 요동친다... 귀신이 물 밖으로 나왔다.", 4)
	end
	Net.broadcast("Hunt", { State = "Hunting", Target = player.Name })
end

local function startSearch(pos: Vector3)
	gState = "Searching"
	gTarget = nil
	gLastKnown = pos
	gTimer = G.SearchTime
	gWander = 0
	Net.broadcast("Hunt", { State = "Searching" })
end

local function startReturn()
	gState = "Returning"
	gTarget = nil
	gLastKnown = nil
	Net.broadcast("Hunt", { State = "Returning" })
end

-- 덫 등 외부 경보
function GhostSystem.alert(player: Player, pos: Vector3)
	if sealed or not ctx.isPlaying() then
		return
	end
	getState(player).Awareness = 1
	if gState == "Stunned" then
		gLastKnown = pos
		return
	end
	if gState == "Hunting" and gTarget and gTarget ~= player then
		local troot = PlayerState.getRoot(gTarget)
		if troot and hdist(gPos, troot.Position) < hdist(gPos, pos) then
			return -- 이미 더 가까운 사냥감을 쫓는 중
		end
	end
	startHunt(player, pos)
end

---------------------------------------------------------------- 잡기 / 끌려감
local function freeCharacter(player: Player)
	local char = player.Character
	if not char then
		return
	end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if root then
		root.Anchored = false
	end
	if hum then
		hum.PlatformStand = false
	end
end

local function release(player: Player, s: PState, reason: string, rescuer: Player?)
	if s.Phase ~= "Grabbed" then
		return
	end
	s.Phase = "Idle"
	s.Awareness = 0
	s.Immune = G.ImmunityAfterEscape
	if s.RescuePrompt then
		s.RescuePrompt:Destroy()
		s.RescuePrompt = nil
	end
	freeCharacter(player)
	PlayerState.setStatus(player, "Alive")
	Net.send(player, "Released", { Reason = reason })
	if reason == "Rescued" and rescuer then
		Net.notifyAll(string.format("%s님이 %s님을 구조했습니다!", rescuer.DisplayName, player.DisplayName), 3)
	elseif reason == "Escaped" then
		Net.notify(player, "뿌리쳤다! 랜턴을 끄고 도망치세요.", 3)
	end
	if reason ~= "Reset" and not sealed then
		gState = "Stunned"
		gTimer = G.StunTime
		gTarget = nil
		local root = PlayerState.getRoot(player)
		gLastKnown = if root then root.Position else gPos
		Net.broadcast("Hunt", { State = "Stunned" })
	end
end

local function drag(player: Player, s: PState)
	s.Phase = "Dragging"
	if s.RescuePrompt then
		s.RescuePrompt:Destroy()
		s.RescuePrompt = nil
	end
	local root, hum = PlayerState.getRoot(player)
	Net.send(player, "Dragged", { Time = G.DragTime })
	Net.notifyAll(string.format("%s님이 호수로 끌려갔습니다...", player.DisplayName), 4)
	local finish = function()
		s.Phase = "Idle"
		s.Awareness = 0
		PlayerState.setStatus(player, "Dead")
		ctx.onPlayerDragged(player)
		if not sealed then
			startReturn()
		end
	end
	if root and hum then
		local dirToLake = flat(M.LakeCenter - root.Position)
		if dirToLake.Magnitude < 1 then
			dirToLake = Vector3.new(0, 0, -1)
		end
		dirToLake = dirToLake.Unit
		local shore = M.LakeCenter - dirToLake * (M.LakeRadius - 12)
		local target = Vector3.new(shore.X, M.WaterLevel - 9, shore.Z)
		Util.playAt(root.Position, Config.Sounds.Grab, 1, 0.8)
		root.Anchored = true
		hum.PlatformStand = true
		local goal = CFrame.lookAt(target, target + dirToLake) * CFrame.Angles(math.rad(-70), 0, 0)
		local tw = Util.tween(root, G.DragTime, { CFrame = goal }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local char = player.Character
		task.delay(G.DragTime * 0.8, function()
			GhostBuilder.splash(Vector3.new(shore.X, M.WaterLevel, shore.Z), map.Folder)
		end)
		tw.Completed:Connect(function()
			hum.Health = 0
			task.delay(0.6, function()
				if player.Character == char and char then
					char:Destroy()
				end
			end)
			finish()
		end)
	else
		finish()
	end
end

local function grab(player: Player, s: PState, root: BasePart, hum: Humanoid)
	s.Phase = "Grabbed"
	s.Timer = G.GrabEscapeTime
	s.Mash = 0
	PlayerState.setStatus(player, "Grabbed")
	ctx.dropBucket(player, true)
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, select(2, root.CFrame:ToOrientation()), 0)
	root.Anchored = true
	hum.PlatformStand = true
	Util.playAt(root.Position, Config.Sounds.Grab, 1, 0.6)
	Util.playAt(root.Position, Config.Sounds.Scream, 0.8, 0.6)
	-- 귀신은 플레이어 바로 뒤에 서서 붙잡음
	gLook = flat(root.CFrame.LookVector)
	local behind = root.Position - flat(root.CFrame.LookVector).Unit * 2.5
	gPos = Vector3.new(behind.X, groundY(behind.X, behind.Z), behind.Z)
	gTarget = player

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "구조하기"
	prompt.ObjectText = player.DisplayName
	prompt.HoldDuration = G.RescueHoldTime
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(rescuer: Player)
		if rescuer ~= player and PlayerState.isAlive(rescuer) then
			release(player, s, "Rescued", rescuer)
		end
	end)
	s.RescuePrompt = prompt
	Net.send(player, "Grabbed", { Time = G.GrabEscapeTime, Mash = G.MashRequired })
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Net.notify(other, string.format("%s님이 붙잡혔습니다! 가까이 가서 구조하세요.", player.DisplayName), 4)
		end
	end
end

---------------------------------------------------------------- 봉인
function GhostSystem.seal()
	sealed = true
	gState = "Sealed"
	gTarget = nil
	for player, s in states do
		if s.Phase == "Grabbed" then
			release(player, s, "Reset")
			Net.notify(player, "귀신의 손아귀가 풀렸다!", 3)
		end
	end
	Util.playAt(gPos + Vector3.new(0, 5, 0), Config.Sounds.Scream, 1, 0.35)
	Net.broadcast("Hunt", { State = "Sealed" })
end

function GhostSystem.resetAll()
	for player, s in states do
		if s.Phase == "Grabbed" then
			release(player, s, "Reset")
		end
		s.Awareness = 0
		s.Phase = "Idle"
		player:SetAttribute("Awareness", 0)
		player:SetAttribute("Threat", 0)
	end
	sealed = false
	gState = "Lurking"
	gTarget = nil
	gLastKnown = nil
	sinkAmount = 0
	gPos = idleFeet()
	gLook = flat(map.GhostIdleCFrame.LookVector)
	nextSubmerge = bodyTime + rng:NextNumber(G.SubmergeMin, G.SubmergeMax)
end

---------------------------------------------------------------- 메인 업데이트
local function updateLurking(dt: number)
	if bodyTime >= nextSubmerge then
		local goDown = sinkAmount < 0.5
		nextSubmerge = bodyTime + (if goDown then rng:NextNumber(8, 16) else rng:NextNumber(G.SubmergeMin, G.SubmergeMax))
		local v = Instance.new("NumberValue")
		v.Value = sinkAmount
		v.Changed:Connect(function(x)
			if gState == "Lurking" then
				sinkAmount = x
			end
		end)
		local tw = TweenService:Create(
			v,
			TweenInfo.new(if goDown then 4 else 2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Value = if goDown then 1 else 0 }
		)
		tw:Play()
		tw.Completed:Connect(function()
			v:Destroy()
		end)
		if goDown then
			GhostBuilder.ripple(Vector3.new(gPos.X, M.WaterLevel, gPos.Z), map.Folder, 1.4)
		end
	end
	gPos = idleFeet()
	gLook = gLook:Lerp(flat(map.GhostIdleCFrame.LookVector), dt)
end

function GhostSystem.update(dt: number)
	bodyTime += dt
	local playing = ctx.isPlaying()

	-- 플레이어별 발각/잡힘 처리
	local perceived: { [Player]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local s = getState(player)
		local root, hum = PlayerState.getRoot(player)
		local status = PlayerState.getStatus(player)

		if s.Phase == "Dragging" then
			if root then
				local behind = root.Position - gLook * 2.5
				gPos = Vector3.new(behind.X, behind.Y - FEET + 2, behind.Z)
			end
			continue
		end
		if s.Phase == "Grabbed" then
			if not root or status ~= "Grabbed" or not playing then
				release(player, s, "Reset")
			else
				s.Timer -= dt
				if s.Timer <= 0 then
					drag(player, s)
				end
			end
			continue
		end
		if not root or not hum or status ~= "Alive" or not playing or sealed then
			s.Awareness = 0
			player:SetAttribute("Awareness", 0)
			player:SetAttribute("Threat", 0)
			continue
		end
		if s.Immune > 0 then
			s.Immune -= dt
		end

		local d = hdist(gPos, root.Position)
		local rate = 0
		if not inSafe(root.Position) then
			if ctx.isLanternOn(player) then
				local vis = math.clamp(1 - (d - A.LanternNear) / (A.LanternFar - A.LanternNear), 0, 1)
				rate += A.LanternRate * vis
			end
			if ctx.isSprinting(player) and hum.MoveDirection.Magnitude > 0.1 and d < A.SprintRange then
				rate += A.SprintRate
			end
			if ctx.isFilling(player) and d < A.FillRange then
				rate += A.FillRate
			end
			local swimming = hum:GetState() == Enum.HumanoidStateType.Swimming or root.Position.Y < M.WaterLevel + 1.5
			if swimming and d < A.SwimRange then
				rate += A.SwimRate
			end
		end
		if rate > 0 then
			s.Awareness = math.min(1, s.Awareness + rate * dt)
		else
			s.Awareness = math.max(0, s.Awareness - A.DecayPerSecond * dt)
		end
		perceived[player] = perceives(player, root, hum) and not inSafe(root.Position)

		-- 사냥 시작
		if s.Awareness >= 1 and s.Immune <= 0 and (gState == "Lurking" or gState == "Returning" or gState == "Searching") then
			startHunt(player, root.Position)
		end

		-- 심장박동용 위협값
		local prox = if gState == "Hunting" or gState == "Searching" then math.clamp(1 - d / 90, 0, 1) else 0
		if gTarget == player then
			prox = math.max(prox, 0.45)
		end
		player:SetAttribute("Awareness", s.Awareness)
		player:SetAttribute("Threat", math.max(prox, s.Awareness * 0.5))
	end

	-- 귀신 상태 머신
	if gState == "Lurking" or gState == "Sealed" then
		if gState == "Sealed" then
			local d = moveToward(M.LakeCenter, 30, dt)
			if d < 4 then
				sinkAmount = math.min(1, sinkAmount + dt * 0.5)
			end
		else
			updateLurking(dt)
		end
	elseif gState == "Stunned" then
		gTimer -= dt
		if gTimer <= 0 then
			startSearch(gLastKnown or gPos)
		end
	elseif gState == "Hunting" then
		local target = gTarget
		local troot = target and PlayerState.getRoot(target)
		if not target or not troot or PlayerState.getStatus(target) ~= "Alive" then
			startSearch(gLastKnown or gPos)
		else
			local s = getState(target)
			if perceived[target] then
				gLastKnown = troot.Position
			end
			-- 더 가까운 다른 먹잇감
			for other, seen in perceived do
				if seen and other ~= target then
					local oroot = PlayerState.getRoot(other)
					if oroot and getState(other).Immune <= 0 and hdist(gPos, oroot.Position) + 6 < hdist(gPos, gLastKnown or troot.Position) then
						gTarget = other
						gLastKnown = oroot.Position
						target = other
						troot = oroot
						s = getState(other)
						Net.broadcast("Hunt", { State = "Hunting", Target = other.Name })
						break
					end
				end
			end
			local dest = gLastKnown or troot.Position
			if inSafe(dest) then
				-- 안전지대 경계에서 서성이다 포기
				local edge = M.CampCenter + flat(dest - M.CampCenter).Unit * (M.SafeRadius + 3)
				moveToward(edge, G.HuntSpeed, dt)
				gGiveUp += dt
				if gGiveUp >= G.GiveUpTime then
					startReturn()
				end
			else
				gGiveUp = 0
				local d = moveToward(dest, G.HuntSpeed, dt)
				local _, thum = PlayerState.getRoot(target)
				if thum and hdist(gPos, troot.Position) <= G.CatchRange and s.Immune <= 0 and s.Phase == "Idle" and not inSafe(troot.Position) then
					grab(target, s, troot, thum)
				elseif d < 3 and not perceived[target] then
					startSearch(dest)
				end
			end
		end
	elseif gState == "Searching" then
		gTimer -= dt
		gWander -= dt
		if gWander <= 0 then
			gWander = 1.5
			local base = gLastKnown or gPos
			gLastKnown = base + Vector3.new(rng:NextNumber(-7, 7), 0, rng:NextNumber(-7, 7))
		end
		moveToward(gLastKnown or gPos, G.HuntSpeed * 0.5, dt)
		local bestP: Player? = nil
		local bestD = math.huge
		for player, seen in perceived do
			if seen and getState(player).Immune <= 0 then
				local r = PlayerState.getRoot(player)
				if r then
					local d = hdist(gPos, r.Position)
					if d < bestD then
						bestD = d
						bestP = player
					end
				end
			end
		end
		if bestP then
			local r = PlayerState.getRoot(bestP)
			if r then
				startHunt(bestP, r.Position)
			end
		elseif gTimer <= 0 then
			startReturn()
		end
	elseif gState == "Returning" then
		local d = moveToward(idleFeet(), G.ReturnSpeed, dt)
		if d < 3 then
			gState = "Lurking"
			nextSubmerge = bodyTime + rng:NextNumber(G.SubmergeMin, G.SubmergeMax)
			Net.broadcast("Hunt", { State = "Lurking" })
		end
	end

	GhostBuilder.setMoving(body, gState == "Hunting" or gState == "Returning" or gState == "Searching")
	placeBody()
end

function GhostSystem.getState(): string
	return gState
end

function GhostSystem.init(mapInfo: any, context: typeof(ctx))
	map = mapInfo
	ctx = context
	body = GhostBuilder.buildBody(map.Folder)
	gPos = idleFeet()
	gLook = flat(map.GhostIdleCFrame.LookVector)
	nextSubmerge = rng:NextNumber(G.SubmergeMin, G.SubmergeMax)
	placeBody()

	Net.on("Mash", function(player)
		local s = states[player]
		if not s or s.Phase ~= "Grabbed" then
			return
		end
		local now = os.clock()
		if now - s.LastMash < 0.06 then
			return
		end
		s.LastMash = now
		s.Mash += 1
		Net.send(player, "MashProgress", { Count = s.Mash, Required = G.MashRequired })
		if s.Mash >= G.MashRequired then
			release(player, s, "Escaped")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local s = states[player]
		if s and s.RescuePrompt then
			s.RescuePrompt:Destroy()
		end
		states[player] = nil
		if gTarget == player then
			startSearch(gLastKnown or gPos)
		end
	end)
end

return GhostSystem
