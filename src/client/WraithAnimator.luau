-- 귀신(Meshy 리그 메시) 달리기 애니메이션을 내 화면에서 직접 재생.
-- Studio 애니메이션 임포트는 뼈 축이 어긋나 귀신이 누워서 달려서, tools/mesh/bake_anim.py 가 구운
-- "뼈가 기본 자세에서 움직인 양"(Shared.WraithAnim)을 게임 안 뼈 위치에 맞춰 변환해 Bone.Transform 에 넣는다.
-- 축·크기는 엉덩이·머리·양팔 뼈 위치를 보고 스스로 맞춘다. 파트로 만든 귀신이면 아무것도 안 함.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local shared = ReplicatedStorage:WaitForChild("DeadLake"):WaitForChild("Shared")
local Config = require(shared:WaitForChild("Config"))
local Data = require(shared:WaitForChild("WraithAnim"))

local WraithAnimator = {}

type Rig = {
	Ghost: Model,
	Bones: { Bone },
	Frames: { { CFrame } }, -- Frames[f][k] = Bones[k] 의 Transform
	Arms: { { Arm: Bone, Hand: Bone } }, -- 붙잡을 때 뻗는 양팔
	Spine: Bone?,
	Head: Bone?,
	Hips: Bone,
	HipRestHeight: number,
	Limbs: { Limb }, -- 왼손, 오른손, 왼발, 오른발
	RestLocal: { [Bone]: CFrame }, -- 기본 자세의 뼈 CFrame (귀신 피벗 기준)
}

-- 땅을 짚는 팔·다리 하나 (어깨→팔꿈치→손 / 골반→무릎→발)
type Limb = {
	Upper: Bone,
	Lower: Bone,
	End: Bone,
	IsArm: boolean,
	Side: number, -- 오른쪽 1, 왼쪽 -1
	Plant: Vector3?, -- 지금 짚고 있는 땅 위치
	Stepping: boolean,
	StepStart: number,
	From: Vector3,
}

local rig: Rig? = nil
local lastPos: Vector3? = nil
local lastMoved = 0
local weight = 0
local holdWeight = 0 -- 붙잡는 자세 (양팔을 뻗음)
local Gait = Config.Gait
local rng = Random.new()
local nextTwitch = 0
local twitchUntil = 0
local twitchAngle = -1
local velocity = Vector3.zero -- 귀신의 수평 이동 속도 (부드럽게 추정)
local lastState = ""
local stunStart = 0 -- 쓰러진 시각
local clock = 0
local nextSearch = 0

local function key(name: string): string
	return string.lower(string.match(name, "[^:]+$") or name)
end

-- 월드 기준 회전을 그 뼈의 로컬 회전으로 바꿈 (기본 자세 기준)
local function localTurn(bone: Bone, worldRotation: CFrame): CFrame
	local restRot = bone.WorldCFrame.Rotation
	return restRot:Inverse() * worldRotation * restRot
end

local function frameOf(origin: Vector3, up: Vector3, side: Vector3): CFrame
	local x = side.Unit
	local y = (up - x * up:Dot(x)).Unit
	return CFrame.fromMatrix(origin, x, y)
end

local function setup(ghost: Model): Rig?
	local byName: { [string]: Bone } = {}
	for _, d in ghost:GetDescendants() do
		if d:IsA("Bone") then
			byName[key(d.Name)] = d
		end
	end
	local index: { [string]: number } = {}
	for i, name in Data.Bones do
		index[key(name)] = i
	end
	local iHips, iHead, iLeft, iRight = index.hips, index.head, index.leftarm, index.rightarm
	local hips, head, left, right = byName.hips, byName.head, byName.leftarm, byName.rightarm
	if not (iHips and iHead and iLeft and iRight and hips and head and left and right) then
		return nil
	end
	local function rest(i: number): Vector3
		local p = Data.Rest[i]
		return Vector3.new(p[1], p[2], p[3])
	end
	local blUp = rest(iHead) - rest(iHips)
	local up = head.WorldPosition - hips.WorldPosition
	if blUp.Magnitude < 1e-4 or up.Magnitude < 1e-4 then
		return nil
	end
	-- Blender 좌표 → 지금 게임 안 좌표 (크기 s, 회전·위치 toGame)
	local s = up.Magnitude / blUp.Magnitude
	local toGame = frameOf(hips.WorldPosition, up, right.WorldPosition - left.WorldPosition)
		* frameOf(rest(iHips) * s, blUp, rest(iRight) - rest(iLeft)):Inverse()
	local toBlender = toGame:Inverse()

	local bones: { Bone } = {}
	local dataIndex: { number } = {}
	for i, name in Data.Bones do
		local bone = byName[key(name)]
		if bone then
			table.insert(bones, bone)
			table.insert(dataIndex, i)
		end
	end
	local frames: { { CFrame } } = {}
	for f, row in Data.Frames do
		local want: { [Bone]: CFrame } = {}
		local out: { CFrame } = table.create(#bones)
		for k, bone in bones do
			local d = row[dataIndex[k]]
			local delta = toGame * CFrame.new(d[1] * s, d[2] * s, d[3] * s, d[4], d[5], d[6], d[7]) * toBlender
			local target = delta * bone.WorldCFrame
			want[bone] = target
			local parent = bone.Parent
			local base = bone.WorldCFrame
			if parent and parent:IsA("Bone") then
				base = (want[parent] or parent.WorldCFrame) * bone.CFrame
			end
			out[k] = base:Inverse() * target
		end
		frames[f] = out
	end
	-- 기는 동작용: 기본 자세의 뼈 위치를 피벗 기준으로 기억해 둠 (지금은 아무 뼈도 움직이지 않은 상태)
	local pivotInv = ghost:GetPivot():Inverse()
	local restLocal: { [Bone]: CFrame } = {}
	for _, bone in byName do
		restLocal[bone] = pivotInv * bone.WorldCFrame
	end
	local limbs: { Limb } = {}
	for _, spec in
		{
			{ "leftarm", "leftforearm", "lefthand", true },
			{ "rightarm", "rightforearm", "righthand", true },
			{ "leftupleg", "leftleg", "leftfoot", false },
			{ "rightupleg", "rightleg", "rightfoot", false },
		}
	do
		local upper, lower, tip = byName[spec[1] :: string], byName[spec[2] :: string], byName[spec[3] :: string]
		if upper and lower and tip then
			table.insert(limbs, {
				Upper = upper,
				Lower = lower,
				End = tip,
				IsArm = spec[4] :: boolean,
				Side = if restLocal[tip].Position.X >= 0 then 1 else -1,
				Plant = nil,
				Stepping = false,
				StepStart = 0,
				From = Vector3.zero,
			})
		end
	end
	local arms = {}
	for _, sideName in { "left", "right" } do
		local arm, hand = byName[sideName .. "arm"], byName[sideName .. "hand"]
		if arm and hand then
			table.insert(arms, { Arm = arm, Hand = hand })
		end
	end
	return {
		Ghost = ghost,
		Bones = bones,
		Frames = frames,
		Arms = arms,
		Spine = byName.spine,
		Head = byName.head,
		Hips = hips,
		Limbs = limbs,
		RestLocal = restLocal,
		-- 서 있을 때 엉덩이가 땅에서 얼마나 높은지 (발 뼈는 발목 높이라 조금 더함)
		HipRestHeight = hips.WorldPosition.Y - math.min(
			if byName.leftfoot then byName.leftfoot.WorldPosition.Y else math.huge,
			if byName.rightfoot then byName.rightfoot.WorldPosition.Y else math.huge,
			hips.WorldPosition.Y - 6
		) + 0.9,
	}
end

local function findGhost(): Model?
	local map = workspace:FindFirstChild("DeadLake")
	local ghost = map and map:FindFirstChild("Ghost")
	return if ghost and ghost:IsA("Model") then ghost else nil
end

-- 목: 옆으로 꺾인 각도 (가끔 반대쪽으로 홱 꺾이는 경련 포함)
local function headTilt(now: number): number
	if now >= nextTwitch then
		nextTwitch = now + rng:NextNumber(Gait.TwitchInterval[1], Gait.TwitchInterval[2])
		twitchUntil = now + rng:NextNumber(0.08, 0.22)
		twitchAngle = rng:NextNumber(-1.4, -0.5)
	end
	return math.rad(Gait.HeadTilt) * (if now < twitchUntil then twitchAngle else 1)
end

-- 팔을 어깨에서 통째로 돌려 손이 toRest 방향(기본 자세 기준)을 향하게 함
local function aimArm(arm: { Arm: Bone, Hand: Bone }, toRest: Vector3, amount: number)
	local restCf = arm.Arm.WorldCFrame
	local shoulder = restCf.Position
	local reach = arm.Hand.WorldPosition - shoulder
	local turn = CFrame.identity
	if amount > 0 and reach.Magnitude > 0.01 and toRest.Magnitude > 0.01 then
		local axis = reach:Cross(toRest)
		if axis.Magnitude > 1e-4 then
			local angle = math.acos(math.clamp(reach.Unit:Dot(toRest.Unit), -1, 1))
			local swing = CFrame.new(shoulder) * CFrame.fromAxisAngle(axis.Unit, angle * amount) * CFrame.new(-shoulder)
			turn = restCf:Inverse() * swing * restCf
		end
	end
	arm.Arm.Transform = turn
end

-- 붙잡힌 사람의 발목 위치 (없으면 nil)
local function heldAnkles(ghostPos: Vector3): Vector3?
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Status") == "Grabbed" then
			local char = p.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") and (hrp.Position - ghostPos).Magnitude < 30 then
				return hrp.Position - hrp.CFrame.UpVector * 2.7
			end
		end
	end
	return nil
end

-- u 방향을 v 방향으로 돌리는 가장 짧은 회전
local function rotBetween(u: Vector3, v: Vector3): CFrame
	if u.Magnitude < 1e-4 or v.Magnitude < 1e-4 then
		return CFrame.identity
	end
	local axis = u:Cross(v)
	if axis.Magnitude < 1e-5 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(u.Unit:Dot(v.Unit), -1, 1)))
end

-- 관절 두 개짜리 팔·다리를 꺾어서 끝(손·발)이 target 에 닿게 함.
-- body = 이 팔·다리가 붙은 몸통이 기본 자세에서 움직인 양, pole = 팔꿈치·무릎이 향할 방향
local function reachLimb(limb: Limb, rest: (Bone) -> CFrame, body: CFrame, target: Vector3, pole: Vector3, w: number)
	local ru, rl = rest(limb.Upper), rest(limb.Lower)
	local a0, b0, c0 = ru.Position, rl.Position, rest(limb.End).Position
	local l1, l2 = (b0 - a0).Magnitude, (c0 - b0).Magnitude
	local a = body * a0
	local toTarget = target - a
	if toTarget.Magnitude < 1e-3 or l1 < 1e-3 or l2 < 1e-3 then
		return
	end
	local d = math.clamp(toTarget.Magnitude, math.abs(l1 - l2) + 0.05, l1 + l2 - 0.02)
	local dir = toTarget.Unit
	local along = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
	local out = math.sqrt(math.max(0, l1 * l1 - along * along))
	local bend = pole - dir * pole:Dot(dir)
	bend = if bend.Magnitude > 1e-3 then bend.Unit else Vector3.yAxis
	local b = a + dir * along + bend * out
	local c = a + dir * d
	local bodyRot = body.Rotation
	local upperRot = rotBetween(bodyRot * (b0 - a0), b - a) * bodyRot
	local lowerRot = rotBetween(upperRot * (c0 - b0), c - b) * upperRot
	local tu = ru.Rotation:Inverse() * bodyRot:Inverse() * upperRot * ru.Rotation
	local tl = rl.Rotation:Inverse() * upperRot:Inverse() * lowerRot * rl.Rotation
	limb.Upper.Transform = CFrame.identity:Lerp(tu, w)
	limb.Lower.Transform = CFrame.identity:Lerp(tl, w)
end

-- 네 발로 기는 자세: 손과 발을 땅의 한 지점에 짚어 두고, 몸이 지나가면 다음 지점으로 옮겨 짚음.
-- w = 0(서 있음) ~ 1(완전히 엎드림)
-- stun = 뿌리쳐져 쓰러진 뒤 지난 시간(초). 쓰러져 있지 않으면 nil
local function crawl(r: Rig, w: number, now: number, pivotCf: CFrame, ankles: Vector3?, stun: number?)
	local right, look, up = pivotCf.RightVector, pivotCf.LookVector, Vector3.yAxis
	local function rest(bone: Bone): CFrame
		return pivotCf * r.RestLocal[bone]
	end

	-- 몸통: 앞으로 눕히고 땅 가까이 내림. 기어가며 좌우로 뒤틀림
	local hipsRest = rest(r.Hips)
	local p = hipsRest.Position
	local ground = p.Y - r.HipRestHeight
	local phase = clock * math.pi * 2
	-- 쓰러짐: collapse 0(기는 자세) ~ 1(옆으로 쓰러져 늘어짐), twist = 다시 일어나기 직전의 뒤틀림
	local collapse, twistRoll, twistSpine, twistHead = 0, 0, 0, 0
	if stun then
		local twistStart = Config.Ghost.StunTime - Gait.TwistTime
		if stun < twistStart then
			collapse = math.min(1, stun / 0.25)
		else
			-- 뚝뚝 끊기는 경련과 함께 몸을 뒤틀며 일어남
			local q = math.floor(stun * Gait.TwistFps) / Gait.TwistFps
			local u = math.clamp((q - twistStart) / Gait.TwistTime, 0, 1)
			collapse = 1 - u
			local jerk = math.noise(q * 7.3, 1.7) * 2
			local jerk2 = math.noise(q * 5.1, 8.2) * 2
			local amount = math.sin(u * math.pi) -- 중간에 가장 심하게
			twistRoll = jerk * math.rad(Gait.TwistAngle) * amount
			twistSpine = -(jerk + jerk2 * 0.5) * math.rad(Gait.TwistAngle) * 1.3 * amount
			twistHead = (if jerk2 > 0 then 1 else -1) * math.rad(80) * amount
		end
	end
	local hipHeight = Gait.HipHeight + (Gait.CollapseHeight - Gait.HipHeight) * collapse
	local pitch = Gait.Pitch + (90 - Gait.Pitch) * collapse
	local bodyRot = CFrame.fromAxisAngle(look, (math.sin(phase) * math.rad(Gait.Slither) + math.rad(Gait.CollapseRoll) * collapse + twistRoll) * w)
		* CFrame.fromAxisAngle(up, math.cos(phase) * math.rad(Gait.Slither) * 0.6 * w)
		* CFrame.fromAxisAngle(right, -math.rad(pitch) * w)
	local offset = (-up * (r.HipRestHeight - hipHeight) - look * Gait.BodyBack) * w
	local hipsMove = CFrame.new(p + offset) * bodyRot * CFrame.new(-p)
	r.Hips.Transform = hipsRest:Inverse() * hipsMove * hipsRest

	-- 가슴을 살짝 들어 올림
	local chestMove = hipsMove
	if r.Spine then
		local spineRest = rest(r.Spine)
		-- 평소엔 가슴을 살짝 들고, 뒤틀 때는 몸통 축으로 엉덩이와 반대로 꼬임
		local arch = bodyRot:Inverse()
			* CFrame.fromAxisAngle(look, twistSpine * w)
			* CFrame.fromAxisAngle(right, math.rad(Gait.Arch) * (1 - collapse) * w)
			* bodyRot
		r.Spine.Transform = spineRest.Rotation:Inverse() * arch * spineRest.Rotation
		chestMove = hipsMove * CFrame.new(spineRest.Position) * arch * CFrame.new(-spineRest.Position)
	end
	local chestRot = chestMove.Rotation

	-- 고개를 들어 앞을 보고, 목은 옆으로 꺾임
	if r.Head then
		local headRest = rest(r.Head).Rotation
		-- 쓰러져 있을 때는 고개를 떨구고, 뒤틀 때는 목이 홱 돌아감
		local tilt = if stun then twistHead else headTilt(now)
		local turn = CFrame.fromAxisAngle(look, tilt * w) * CFrame.fromAxisAngle(right, math.rad(Gait.HeadUp) * (1 - collapse) * w)
		r.Head.Transform = headRest:Inverse() * chestRot:Inverse() * turn * chestRot * headRest
	end

	-- 손발 짚기
	local speed = velocity.Magnitude
	local lead = if speed > 1 then velocity.Unit * math.min(1, speed / 8) * Gait.StepDistance * 0.8 else Vector3.zero
	for index, limb in r.Limbs do
		local body = if limb.IsArm then chestMove else hipsMove
		local joint = body * rest(limb.Upper).Position
		local home = Vector3.new(joint.X, ground, joint.Z)
			+ right * limb.Side * (if limb.IsArm then Gait.HandSide else Gait.FootSide)
			+ look * (if limb.IsArm then Gait.HandForward else -Gait.FootBack)
		local target: Vector3
		if limb.IsArm and ankles then
			-- 붙잡은 발목을 쥠
			target = ankles + right * limb.Side * 0.5
			limb.Plant = nil
			limb.Stepping = false
		else
			local plant = limb.Plant
			if not plant or (plant - home).Magnitude > 14 then
				plant = home
				limb.Stepping = false
			end
			if limb.Stepping then
				local t = (now - limb.StepStart) / Gait.StepTime
				if t >= 1 then
					limb.Stepping = false
					plant = home + lead
					target = plant
				else
					-- 손발을 들어 다음 자리로 옮김
					target = limb.From:Lerp(home + lead, t) + up * math.sin(t * math.pi) * Gait.StepLift
				end
			else
				target = plant
				-- 대각선 짝(왼손+오른발, 오른손+왼발)끼리 같이 움직임: 다른 짝이 발을 떼고 있으면 기다림
				local otherPairMoving = false
				for j, other in r.Limbs do
					local samePair = (index == j) or (index + j == 5)
					if other.Stepping and not samePair then
						otherPairMoving = true
					end
				end
				-- 쓰러져 있는 동안은 손발을 옮기지 않고 늘어뜨림
				if (plant - home).Magnitude > Gait.StepDistance and not otherPairMoving and not stun then
					limb.Stepping = true
					limb.StepStart = now
					limb.From = plant
				end
			end
			limb.Plant = plant
		end
		-- 팔꿈치·무릎은 위·바깥으로 꺾임 (거미처럼)
		local pole = up + right * limb.Side * (if limb.IsArm then 0.7 else 0.9) + look * (if limb.IsArm then -0.3 else 0.3)
		reachLimb(limb, rest, body, target, pole, w)
	end
end

-- 서서 달리는 자세 (구운 달리기 동작 + 꺾인 상체·목·뻗은 팔)
local function run(r: Rig, w: number, now: number, pivotCf: CFrame, ankles: Vector3?, holdW: number)
	local right, look = pivotCf.RightVector, pivotCf.LookVector
	local n = #r.Frames
	local t = clock % n
	if Gait.StepFps > 0 then
		local hold = Data.Fps / Gait.StepFps
		t = (math.floor(clock / hold) * hold) % n
	end
	local a = math.floor(t)
	local alpha = if Gait.StepFps > 0 then 0 else t - a
	local fa = r.Frames[a + 1]
	local fb = r.Frames[(a + 1) % n + 1]
	for k, bone in r.Bones do
		bone.Transform = CFrame.identity:Lerp(fa[k]:Lerp(fb[k], alpha), w)
	end
	if r.Spine then
		r.Spine.Transform = localTurn(r.Spine, CFrame.fromAxisAngle(right, -math.rad(Gait.Lean) * w)) * r.Spine.Transform
	end
	if r.Head then
		local nod = math.rad(Gait.Lean * 0.6) * w
		r.Head.Transform = localTurn(r.Head, CFrame.fromAxisAngle(look, headTilt(now) * w) * CFrame.fromAxisAngle(right, nod))
	end
	for index, arm in r.Arms do
		local restReach = arm.Hand.WorldPosition - arm.Arm.WorldPosition
		local sideSign = if restReach:Dot(right) >= 0 then 1 else -1
		if ankles then
			aimArm(arm, ankles + right * sideSign * 0.5 - arm.Arm.WorldPosition, holdW)
		else
			local sway = math.sin(now * 2.3 + index * 2.1) * 0.12
			local to = look + Vector3.yAxis * ((if index == 1 then -0.05 else -0.45) + sway) + right * sideSign * 0.12
			aimArm(arm, to, math.max(holdW, w * Gait.ArmsReach))
		end
	end
end

local function step(dt: number)
	if Config.Assets.WraithAnimation ~= "Baked" then
		return
	end
	local now = os.clock()
	if rig and (not rig.Ghost:IsDescendantOf(workspace) or not rig.Hips:IsDescendantOf(rig.Ghost)) then
		rig = nil
	end
	if not rig then
		if now < nextSearch then
			return
		end
		nextSearch = now + 2
		local ghost = findGhost()
		rig = if ghost then setup(ghost) else nil
		lastPos = nil
		weight = 0
		holdWeight = 0
		if not rig then
			return
		end
	end
	local r = rig :: Rig

	-- 서버가 귀신을 옮기고 있으면(수평 이동) 움직이는 중
	local pivotCf = r.Ghost:GetPivot()
	local pos = pivotCf.Position
	if lastPos then
		local moved = Vector3.new(pos.X - lastPos.X, 0, pos.Z - lastPos.Z).Magnitude
		if moved > 0.03 then
			lastMoved = now
		end
		-- 서버 위치는 띄엄띄엄 오므로 속도는 부드럽게 추정
		if dt > 0 then
			local v = Vector3.new(pos.X - lastPos.X, 0, pos.Z - lastPos.Z) / dt
			velocity = velocity:Lerp(v, math.min(1, dt * 6))
		end
		if Gait.Style == "Crawl" then
			clock += moved / Gait.SlitherLength
		end
	end
	lastPos = pos
	local moving = now - lastMoved < 0.3
	local ankles = heldAnkles(pos)
	local crawling = Gait.Style == "Crawl"

	local holdBefore = holdWeight
	holdWeight += math.clamp((if ankles then 1 else 0) - holdWeight, -dt * 5, dt * 5)
	-- 서버가 알려준 귀신 상태. 뿌리쳐지면(Stunned) 쓰러짐
	local state = (r.Ghost:GetAttribute("State") :: string?) or ""
	if state ~= lastState then
		lastState = state
		if state == "Stunned" then
			stunStart = now
		end
	end
	local stun = if crawling and state == "Stunned" then now - stunStart else nil
	-- 기는 자세: 호수에 잠겨 있을 때(Lurking)와 봉인될 때만 서 있고, 물 밖에서는 멈춰 있어도 엎드려 있음
	local goal: number
	if crawling and state ~= "" then
		goal = if state == "Lurking" or state == "Sealed" then 0 else 1
	else
		goal = if moving or (crawling and ankles ~= nil) then 1 else 0
	end
	local before = weight
	weight += math.clamp(goal - weight, -dt * 3, dt * 3)
	if weight <= 0 and before <= 0 and holdWeight <= 0 and holdBefore <= 0 then
		return
	end

	if crawling then
		crawl(r, weight, now, pivotCf, ankles, stun)
	else
		clock += dt * Data.Fps * Gait.RunSpeed
		run(r, weight, now, pivotCf, ankles, holdWeight)
	end
end

-- 귀신 얼굴의 현재 위치 (리그가 없으면 nil). 붙잡힘 장면 카메라가 사용
function WraithAnimator.facePosition(): Vector3?
	local r = rig
	if r and r.Head and r.Head:IsDescendantOf(workspace) then
		return r.Head.TransformedWorldCFrame.Position
	end
	return nil
end

function WraithAnimator.init()
	RunService.RenderStepped:Connect(step)
end

return WraithAnimator
