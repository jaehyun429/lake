-- 귀신(Meshy 리그 메시) 달리기 애니메이션을 내 화면에서 직접 재생.
-- Studio 애니메이션 임포트는 뼈 축이 어긋나 귀신이 누워서 달려서, tools/mesh/bake_anim.py 가 구운
-- "뼈가 기본 자세에서 움직인 양"(Shared.WraithAnim)을 게임 안 뼈 위치에 맞춰 변환해 Bone.Transform 에 넣는다.
-- 축·크기는 엉덩이·머리·양팔 뼈 위치를 보고 스스로 맞춘다. 파트로 만든 귀신이면 아무것도 안 함.
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
}

local rig: Rig? = nil
local lastPos: Vector3? = nil
local lastMoved = 0
local weight = 0
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
	return { Ghost = ghost, Bones = bones, Frames = frames }
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
	if weight <= 0 and before <= 0 then
		return
	end

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

function WraithAnimator.init()
	RunService.RenderStepped:Connect(step)
end

return WraithAnimator
