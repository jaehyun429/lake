-- 외부 메시 에셋 연결 모듈 (Meshy 등에서 가져온 모델).
-- Studio 에서 Import 3D 로 넣은 모델을 ReplicatedStorage.DeadLake.Assets 아래에 두면 자동으로 사용합니다.
-- 이름은 DeadTree / Wraith / Bucket / Jar 가 포함되기만 하면 됩니다. 없으면 파트로 만든 기본 외형을 씁니다.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local Assets = {}

local ALIASES: { [string]: { string } } = {
	DeadTree = { "deadtree", "dead_tree", "dead tree", "tree" },
	Wraith = { "wraith", "ghost" },
	Bucket = { "bucket" },
	Jar = { "jar" },
}

export type SpawnOpts = {
	Height: number?, -- 바운딩박스 높이를 이 값(스터드)으로 맞춤
	Width: number?, -- Height 가 없을 때 가로폭 기준
	Anchored: boolean?, -- 기본 true
	CanCollide: boolean?, -- 기본 false
	CanQuery: boolean?, -- 기본 true (false 면 레이캐스트에 안 잡힘)
	Massless: boolean?,
}

local function matches(name: string, key: string): boolean
	local n = string.lower(name)
	if n == string.lower(key) then
		return true
	end
	for _, alias in ALIASES[key] or {} do
		if string.find(n, alias, 1, true) then
			return true
		end
	end
	return false
end

local function isAsset(inst: Instance): boolean
	return inst:IsA("Model") or inst:IsA("BasePart")
end

-- Assets 폴더 → ReplicatedStorage/ServerStorage 전체 순으로 찾음
function Assets.find(key: string): Instance?
	local dl = ReplicatedStorage:FindFirstChild("DeadLake")
	local folder = dl and dl:FindFirstChild("Assets")
	if folder then
		for _, child in folder:GetChildren() do
			if isAsset(child) and matches(child.Name, key) then
				return child
			end
		end
	end
	for _, container in { ReplicatedStorage, ServerStorage } do
		for _, d in container:GetDescendants() do
			if isAsset(d) and matches(d.Name, key) then
				return d
			end
		end
	end
	return nil
end

function Assets.has(key: string): boolean
	return Assets.find(key) ~= nil
end

-- 복제해서 크기를 맞추고 parent 에 넣음. 에셋이 없으면 nil.
function Assets.spawn(key: string, parent: Instance, opts: SpawnOpts?): Model?
	local src = Assets.find(key)
	if not src then
		return nil
	end
	local o: SpawnOpts = opts or {}
	local clone = src:Clone()
	local model: Model
	if clone:IsA("Model") then
		model = clone
	else
		model = Instance.new("Model")
		clone.Parent = model
	end
	model.Name = key

	local largest: BasePart? = nil
	local largestVol = -1
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = o.Anchored ~= false
			d.CanCollide = o.CanCollide == true
			d.CanQuery = o.CanQuery ~= false
			d.CanTouch = false
			d.Massless = o.Massless == true
			d.CastShadow = true
			local vol = d.Size.X * d.Size.Y * d.Size.Z
			if vol > largestVol then
				largest, largestVol = d, vol
			end
		elseif d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	if not largest then
		model:Destroy()
		return nil
	end
	if not model.PrimaryPart then
		model.PrimaryPart = largest
	end

	local _, size = model:GetBoundingBox()
	local factor = 1
	if o.Height and size.Y > 0.01 then
		factor = o.Height / size.Y
	elseif o.Width then
		local w = math.max(size.X, size.Z)
		if w > 0.01 then
			factor = o.Width / w
		end
	end
	if math.abs(factor - 1) > 1e-3 then
		model:ScaleTo(model:GetScale() * factor)
	end
	model.Parent = parent
	return model
end

-- 바운딩박스 바닥 중심을 groundPos 에 맞춤. yaw(라디안)만큼 Y축 회전.
function Assets.placeOnGround(model: Model, groundPos: Vector3, yaw: number?)
	if yaw and yaw ~= 0 then
		local pivot = model:GetPivot()
		model:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, yaw, 0) * (pivot - pivot.Position))
	end
	local cf, size = model:GetBoundingBox()
	local bottom = cf.Position - Vector3.new(0, size.Y / 2, 0)
	model:PivotTo(model:GetPivot() + (groundPos - bottom))
end

-- 바운딩박스 중심이 cf 위치·방향에 오도록 배치
function Assets.placeCenter(model: Model, cf: CFrame)
	local bcf = model:GetBoundingBox()
	local offset = model:GetPivot():ToObjectSpace(bcf)
	model:PivotTo(cf * offset:Inverse())
end

-- 모델의 모든 파트를 holder 에 용접 (들고 다니는 소품용)
function Assets.weldTo(model: Model, holder: BasePart)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local w = Instance.new("WeldConstraint")
			w.Part0 = holder
			w.Part1 = d
			w.Parent = d
		end
	end
end

-- 애니메이션: Config 의 ID 가 있으면 그것을, 없으면 모델 안의 KeyframeSequence(Import 3D 가 넣어줌)를 임시 등록해서 사용
function Assets.loadAnimation(model: Model, animationId: string?): AnimationTrack?
	local id = animationId
	if not id or id == "" then
		local ks = model:FindFirstChildWhichIsA("KeyframeSequence", true)
		if not ks then
			return nil
		end
		local ok, result = pcall(function()
			return KeyframeSequenceProvider:RegisterKeyframeSequence(ks)
		end)
		if not ok then
			warn("[DeadLake] KeyframeSequence 등록 실패:", result)
			return nil
		end
		id = result
	end
	local controller: Instance = model:FindFirstChildWhichIsA("Humanoid")
		or model:FindFirstChildWhichIsA("AnimationController")
		or Instance.new("AnimationController")
	controller.Parent = model
	local animator: Animator = controller:FindFirstChildWhichIsA("Animator") or Instance.new("Animator")
	animator.Parent = controller
	local anim = Instance.new("Animation")
	anim.AnimationId = id :: string
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not ok then
		warn("[DeadLake] 애니메이션 로드 실패:", track)
		return nil
	end
	return track
end

return Assets
