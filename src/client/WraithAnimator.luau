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
}

local rig: Rig? = nil
local lastPos: Vector3? = nil
local lastMoved = 0
local weight = 0
local holdWeight = 0 -- 붙잡는 자세 (양팔을 뻗음)
local clock = 0
local nextSearch = 0

local function key(name: string): string
	return string.lower(string.match(name, "[^:]+$") or name)
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
	return { Ghost = ghost, Bones = bones, Frames = frames, Arms = arms }
end

local function findGhost(): Model?
	local map = workspace:FindFirstChild("DeadLake")
	local ghost = map and map:FindFirstChild("Ghost")
	return if ghost and ghost:IsA("Model") then ghost else nil
end

local function step(dt: number)
	if Config.Assets.WraithAnimation ~= "Baked" then
		return
	end
	local now = os.clock()
	if rig and (not rig.Ghost:IsDescendantOf(workspace) or not rig.Bones[1]:IsDescendantOf(rig.Ghost)) then
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
		if not rig then
			return
		end
	end
	local r = rig :: Rig

	-- 서버가 귀신을 옮기고 있으면(수평 이동) 달리는 중
	local pos = r.Ghost:GetPivot().Position
	if lastPos then
		local moved = Vector3.new(pos.X - lastPos.X, 0, pos.Z - lastPos.Z).Magnitude
		if moved > 0.03 then
			lastMoved = now
		end
	end
	lastPos = pos
	local moving = now - lastMoved < 0.3
	local goal = if moving then 1 else 0
	local before = weight
	weight += math.clamp(goal - weight, -dt * 4, dt * 4)
	if weight > 0 or before > 0 then
		clock += dt * Data.Fps * Config.Assets.WraithRunSpeed
		local n = #r.Frames
		local t = clock % n
		local a = math.floor(t)
		local alpha = t - a
		local fa = r.Frames[a + 1]
		local fb = r.Frames[(a + 1) % n + 1]
		for k, bone in r.Bones do
			local pose = fa[k]:Lerp(fb[k], alpha)
			bone.Transform = if weight >= 1 then pose else CFrame.identity:Lerp(pose, weight)
		end
	end

	-- 누군가 붙잡혀 있으면 양팔을 그 사람 몸 쪽으로 뻗음 (어깨에서 통째로 돌림)
	local heldRoot: BasePart? = nil
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Status") == "Grabbed" then
			local char = p.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") and (hrp.Position - pos).Magnitude < 30 then
				heldRoot = hrp
				break
			end
		end
	end
	local holdBefore = holdWeight
	holdWeight += math.clamp((if heldRoot then 1 else 0) - holdWeight, -dt * 5, dt * 5)
	if holdWeight > 0 or holdBefore > 0 then
		local right = r.Ghost:GetPivot().RightVector
		for _, arm in r.Arms do
			local restCf = arm.Arm.WorldCFrame
			local shoulder = restCf.Position
			local reach = arm.Hand.WorldPosition - shoulder
			local turn = CFrame.identity
			if heldRoot and reach.Magnitude > 0.01 then
				-- 왼손은 몸 왼쪽, 오른손은 몸 오른쪽을 잡음
				local sideSign = if reach:Dot(right) >= 0 then 1 else -1
				local to = heldRoot.Position + right * sideSign * 0.9 - shoulder
				local axis = reach:Cross(to)
				if to.Magnitude > 0.01 and axis.Magnitude > 1e-4 then
					local angle = math.acos(math.clamp(reach.Unit:Dot(to.Unit), -1, 1))
					local swing = CFrame.new(shoulder) * CFrame.fromAxisAngle(axis.Unit, angle * holdWeight) * CFrame.new(-shoulder)
					turn = restCf:Inverse() * swing * restCf
				end
			end
			arm.Arm.Transform = turn
		end
	end
end

function WraithAnimator.init()
	RunService.RenderStepped:Connect(step)
end

return WraithAnimator
