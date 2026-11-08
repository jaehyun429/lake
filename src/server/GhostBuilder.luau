-- 귀신 외형 생성기: 긴 팔다리, 검게 파인 눈, 마른 몸, 곧은 목. 파문·물보라 효과 포함.
-- 파트로만 만들어져 있어 나중에 메시/리그로 교체하기 쉽습니다.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.DeadLake.Shared.Config)
local Util = require(script.Parent.Util)
local Assets = require(script.Parent.Assets)

local GhostBuilder = {}
GhostBuilder.FEET = 6.8 -- 몸통 중심(피벗)에서 발까지

local tracks: { [Model]: AnimationTrack } = {}

local SKIN = Color3.fromRGB(172, 176, 166)
local DARK = Color3.fromRGB(8, 8, 10)

local function limb(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3?, material: Enum.Material?): Part
	return Util.part({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color or SKIN,
		Material = material or Enum.Material.Slate,
		CanCollide = false,
		CanQuery = false,
		Parent = model,
	})
end

-- 본체. 원점 = 몸통 중심, 정면 = -Z. 전체 키 약 12 스터드.
function GhostBuilder.buildBody(parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = "Ghost"

	-- Wraith 메시가 있으면 그것을 몸으로 사용. 보이지 않는 Torso 가 피벗(몸통 중심) 역할.
	local A = Config.Assets
	local wraith = Assets.spawn("Wraith", m, { Height = A.WraithHeight, CanCollide = false, CanQuery = false })
	if wraith then
		local pivot = limb(m, "Torso", Vector3.new(1.6, 3.2, 0.9), CFrame.new(0, 0, 0))
		pivot.Transparency = 1
		Assets.placeOnGround(wraith, Vector3.new(0, -GhostBuilder.FEET, 0), math.rad(A.WraithFacing))
		m.PrimaryPart = pivot
		m.WorldPivot = pivot.CFrame
		local track = Assets.loadAnimation(wraith, A.WraithRunAnimationId)
		if track then
			track.Looped = true
			tracks[m] = track
		end
		m.Parent = parent
		return m
	end

	local torso = limb(m, "Torso", Vector3.new(1.6, 3.2, 0.9), CFrame.new(0, 0, 0))
	limb(m, "Neck", Vector3.new(0.65, 1.5, 0.65), CFrame.new(0, 2.35, 0))
	local headY = 1.6 + 1.5 + 1.15
	limb(m, "Head", Vector3.new(1.7, 2.3, 1.7), CFrame.new(0, headY, 0))
	-- 검게 파인 눈 (움푹 들어간 구멍처럼 보이도록 검은 구를 얼굴 안쪽에)
	for _, x in { -0.42, 0.42 } do
		limb(m, "EyeSocket", Vector3.new(0.6, 0.7, 0.6), CFrame.new(x, headY + 0.35, -0.55), Color3.fromRGB(60, 58, 56), Enum.Material.SmoothPlastic)
		local eye = limb(m, "Eye", Vector3.new(0.5, 0.5, 0.5), CFrame.new(x, headY + 0.35, -0.65), DARK, Enum.Material.SmoothPlastic)
		eye.Shape = Enum.PartType.Ball
	end
	-- 벌어진 입
	limb(m, "Mouth", Vector3.new(0.7, 0.35, 0.3), CFrame.new(0, headY - 0.55, -0.78), DARK, Enum.Material.SmoothPlastic)
	-- 젖은 검은 머리카락
	limb(m, "Hair", Vector3.new(1.9, 1.1, 1.9), CFrame.new(0, headY + 0.85, 0.05), DARK, Enum.Material.Fabric)
	limb(m, "HairBack", Vector3.new(1.9, 4.2, 0.5), CFrame.new(0, headY - 1.0, 0.95), DARK, Enum.Material.Fabric)
	for _, x in { -0.85, 0.85 } do
		limb(m, "HairSide", Vector3.new(0.35, 3.0, 1.2), CFrame.new(x, headY - 0.6, 0.2), DARK, Enum.Material.Fabric)
	end
	-- 긴 팔 (어깨에서 무릎 아래까지)
	for _, s in { -1, 1 } do
		local armLen = 6.8
		limb(m, "Arm", Vector3.new(0.5, armLen, 0.5), CFrame.new(s * 1.1, 1.6 - armLen / 2 + 0.1, 0) * CFrame.Angles(0, 0, math.rad(s * 3)))
		local handY = 1.6 - armLen + 0.1 - 0.7
		limb(m, "Hand", Vector3.new(0.55, 1.4, 0.3), CFrame.new(s * 1.3, handY, 0))
		for f = -1, 1 do
			limb(m, "Finger", Vector3.new(0.14, 1.1, 0.14), CFrame.new(s * 1.3 + f * 0.17, handY - 1.2, 0))
		end
	end
	-- 다리
	for _, s in { -1, 1 } do
		limb(m, "Leg", Vector3.new(0.6, 5.2, 0.6), CFrame.new(s * 0.45, -1.6 - 2.6, 0))
	end
	-- 낡은 흰 천 (옷)
	limb(m, "Cloth", Vector3.new(1.9, 3.6, 1.1), CFrame.new(0, -0.3, 0), Color3.fromRGB(120, 118, 110), Enum.Material.Fabric).Transparency = 0.15

	m.PrimaryPart = torso
	m.WorldPivot = torso.CFrame
	m.Parent = parent
	return m
end

-- 메시 귀신의 달리기 애니메이션 재생/정지 (파트 귀신이면 아무것도 안 함)
function GhostBuilder.setMoving(model: Model, moving: boolean)
	local track = tracks[model]
	if not track then
		return
	end
	if moving and not track.IsPlaying then
		track:Play(0.2)
	elseif not moving and track.IsPlaying then
		track:Stop(0.3)
	end
end

-- 파문: 수면에 번지는 어두운 고리
function GhostBuilder.ripple(position: Vector3, parent: Instance, scale: number?)
	local s = scale or 1
	for i = 1, 2 do
		local ring = Util.part({
			Name = "Ripple",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.15, 2, 2),
			CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(10, 14, 20),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.35,
			CanCollide = false,
			CanQuery = false,
			Parent = parent,
		})
		local size = 14 * s + (i - 1) * 6
		task.delay((i - 1) * 0.45, function()
			Util.tween(ring, 1.6, { Size = Vector3.new(0.15, size, size), Transparency = 1 })
		end)
		Debris:AddItem(ring, 2.6)
	end
end

-- 손 그림자: 수면 바로 아래 어두운 형체
function GhostBuilder.shadow(position: Vector3, parent: Instance, lifetime: number): BasePart
	local disk = Util.part({
		Name = "HandShadow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 3, 3),
		CFrame = CFrame.new(position - Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(0, 0, 0),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.45,
		CanCollide = false,
		CanQuery = false,
		Parent = parent,
	})
	Util.tween(disk, 1.0, { Size = Vector3.new(0.3, 7, 7) })
	Debris:AddItem(disk, lifetime)
	return disk
end

function GhostBuilder.splash(position: Vector3, parent: Instance)
	local p = Util.part({ Name = "Splash", Size = Vector3.one, Transparency = 1, CanCollide = false, CanQuery = false, Position = position, Parent = parent })
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(Color3.fromRGB(150, 170, 190))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.1) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(8, 16)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Acceleration = Vector3.new(0, -40, 0)
	e.Rate = 0
	e.Parent = p
	e:Emit(40)
	Util.playAt(position, Config.Sounds.Splash, 1, 0.9)
	Debris:AddItem(p, 2)
end

return GhostBuilder
