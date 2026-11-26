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
	Legs: { Bone },
	HipRestHeight: number,
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
		Legs = { byName.leftupleg, byName.rightupleg },
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

-- 엎드려 기는 자세. w = 0(서 있음) ~ 1(완전히 엎드림)
local function crawl(r: Rig, w: number, now: number, pivotCf: CFrame, ankles: Vector3?)
	local right, look, up = pivotCf.RightVector, pivotCf.LookVector, Vector3.yAxis
	local phase = clock * math.pi * 2
	if Gait.StepFps > 0 then
		phase = math.floor(clock * Gait.StepFps / Gait.CrawlSpeed) / (Gait.StepFps / Gait.CrawlSpeed) * math.pi * 2
	end

	-- 엉덩이: 몸 전체를 앞으로 눕히고 땅까지 내림. 좌우로 뒤틀리며 기어감
	local restCf = r.Hips.WorldCFrame
	local p = restCf.Position
	local bodyRot = CFrame.fromAxisAngle(look, math.sin(phase) * math.rad(Gait.Slither) * w)
		* CFrame.fromAxisAngle(up, math.cos(phase) * math.rad(Gait.Slither) * 0.6 * w)
		* CFrame.fromAxisAngle(right, -math.rad(Gait.Pitch) * w)
	local offset = (-up * (r.HipRestHeight - Gait.HipHeight) - look * Gait.BodyBack) * w
	r.Hips.Transform = restCf:Inverse() * (CFrame.new(p + offset) * bodyRot * CFrame.new(-p)) * restCf

	-- 가슴을 들어 올림
	local chestRot = bodyRot
	if r.Spine then
		local arch = CFrame.fromAxisAngle(right, math.rad(Gait.Arch) * w)
		r.Spine.Transform = localTurn(r.Spine, bodyRot:Inverse() * arch * bodyRot)
		chestRot = arch * bodyRot
	end
	local toRest = chestRot:Inverse()

	-- 고개를 들어 앞을 보고, 목은 옆으로 꺾임
	if r.Head then
		local turn = CFrame.fromAxisAngle(look, headTilt(now) * w) * CFrame.fromAxisAngle(right, math.rad(Gait.HeadUp) * w)
		r.Head.Transform = localTurn(r.Head, toRest * turn * chestRot)
	end

	-- 양팔: 번갈아 앞으로 뻗었다가 땅을 긁으며 당김. 붙잡았으면 발목을 쥠
	for index, arm in r.Arms do
		local restReach = arm.Hand.WorldPosition - arm.Arm.WorldPosition
		local sideSign = if restReach:Dot(right) >= 0 then 1 else -1
		local to: Vector3
		if ankles then
			to = ankles + right * sideSign * 0.5 - arm.Arm.TransformedWorldCFrame.Position
		else
			local armPhase = phase + (if index == 1 then 0 else math.pi)
			local stroke = math.sin(armPhase) -- 1 = 앞으로 쭉 뻗음, -1 = 옆으로 당겨짐
			local angle = math.rad(45 - stroke * 32)
			local lift = math.max(0, math.cos(armPhase)) * 0.4 -- 앞으로 내밀 때는 손을 듦
			to = look * math.cos(angle) + right * sideSign * math.sin(angle) + up * (-0.3 + lift)
		end
		aimArm(arm, toRest * to, w)
	end

	-- 다리는 뒤로 끌려오며 좌우로 흔들림
	for index, leg in r.Legs do
		local sway = math.sin(phase + index * 2.4) * math.rad(Gait.LegSway) * w
		leg.Transform = localTurn(leg, bodyRot:Inverse() * CFrame.fromAxisAngle(up, sway) * bodyRot)
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
	end
	lastPos = pos
	local moving = now - lastMoved < 0.3
	local ankles = heldAnkles(pos)
	local crawling = Gait.Style == "Crawl"

	local holdBefore = holdWeight
	holdWeight += math.clamp((if ankles then 1 else 0) - holdWeight, -dt * 5, dt * 5)
	-- 기는 자세는 발목을 잡고 있는 동안에도 유지
	local goal = if moving or (crawling and ankles ~= nil) then 1 else 0
	local before = weight
	weight += math.clamp(goal - weight, -dt * 3, dt * 3)
	if weight <= 0 and before <= 0 and holdWeight <= 0 and holdBefore <= 0 then
		return
	end

	if crawling then
		-- 붙잡고 있을 때는 천천히 꿈틀거림
		clock += dt * Gait.CrawlSpeed * (if moving then 1 else 0.2)
		crawl(r, weight, now, pivotCf, ankles)
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
