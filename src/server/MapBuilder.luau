-- 살목지 맵 생성기. 서버 시작 시 지형·호수·검은 버드나무·캠프·물가 3곳·출구를 코드로 만듭니다.
-- Studio 편집 모드에서 미리 보고 싶으면 명령줄에서:
--   require(game.ServerScriptService.DeadLake.MapBuilder).build()
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.DeadLake.Shared.Config)
local Util = require(script.Parent.Util)
local Assets = require(script.Parent.Assets)

local M = Config.Map
local MapBuilder = {}

local COL = {
	Bark = Color3.fromRGB(26, 24, 22),
	Leaf = Color3.fromRGB(18, 24, 18),
	Wood = Color3.fromRGB(72, 54, 38),
	OldWood = Color3.fromRGB(56, 48, 40),
	Dirt = Color3.fromRGB(44, 37, 30),
	Rock = Color3.fromRGB(20, 20, 24),
	Canvas = Color3.fromRGB(58, 60, 54),
	Metal = Color3.fromRGB(50, 53, 58),
	Lantern = Color3.fromRGB(255, 170, 95),
	Reed = Color3.fromRGB(74, 78, 46),
	Vine = Color3.fromRGB(14, 14, 16),
}

export type Station = {
	Index: number,
	Name: string,
	Def: any,
	Point: Vector3,
	Prompt: ProximityPrompt,
	Marker: BasePart,
}

export type MapInfo = {
	Folder: Folder,
	Stations: { Station },
	Altar: BasePart,
	AltarPrompt: ProximityPrompt,
	AltarLabel: TextLabel,
	AltarWater: BasePart,
	AltarWaterMinY: number,
	AltarWaterMaxY: number,
	AltarCandles: { PointLight },
	PathSegments: { { Vector3 } }, -- {a, b} 덫 배치용 길 중심선
	GatePanel: BasePart,
	ExitZone: BasePart,
	Spawns: { Vector3 },
	GhostIdleCFrame: CFrame,
}

local rng = Random.new(20251104)

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- 호수 중심에서 r 만큼 떨어진 곳의 지면 높이. 땅은 전부 0 으로 평평하고,
-- 물가만 BeachWidth 폭으로 완만하게 내려가 수면(-2) 아래로 이어짐 (단차 없음).
local function groundAt(r: number): number
	local R = M.LakeRadius
	local W = M.BeachWidth
	if r >= R + W then
		return 0
	elseif r >= R then
		return (M.WaterLevel - 0) * (R + W - r) / W
	elseif r >= R - 16 then
		return M.WaterLevel - (R - r) * 0.2
	else
		return math.max(-13, M.WaterLevel - 3.2 - (R - 16 - r) * 0.35)
	end
end
MapBuilder.groundAt = groundAt

---------------------------------------------------------------- 지형
local function buildTerrain()
	local terrain = Workspace.Terrain
	local c = M.LakeCenter
	local region = Vector3.new(760, 90, 760)
	-- 작업 영역만 비우고 다시 채움 (다른 지형은 건드리지 않음)
	terrain:FillBlock(CFrame.new(c + Vector3.new(0, 0, 60)), region, Enum.Material.Air)
	-- 땅: 복셀 격자(4)에 맞춘 평평한 블록 (-16 ~ 0). 격자에 맞아야 울퉁불퉁한 단차가 안 생김
	terrain:FillBlock(CFrame.new(c + Vector3.new(0, -8, 60)), Vector3.new(760, 16, 760), Enum.Material.Grass)
	terrain:FillCylinder(CFrame.new(c + Vector3.new(0, -2, 0)), 4, M.LakeRadius + M.BeachWidth + 4, Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(c + Vector3.new(0, -10, 0)), 12, M.LakeRadius + 4, Enum.Material.Mud)
	-- 물가 경사 + 호수 바닥: 바깥에서 안쪽으로 조금씩 더 깊게 깎아 완만한 그릇 모양을 만듦
	local R = M.LakeRadius
	local r = R + M.BeachWidth
	while r > 2 do
		local h = groundAt(r)
		if h >= M.WaterLevel - 0.01 then
			-- 수면 위 모래 경사: 공기로 깎음
			terrain:FillCylinder(CFrame.new(c + Vector3.new(0, (h + 8) / 2, 0)), 8 - h, r, Enum.Material.Air)
		else
			-- 수면 아래: 물로 깎음 (수면 높이는 그대로)
			terrain:FillCylinder(CFrame.new(c + Vector3.new(0, (h + M.WaterLevel) / 2, 0)), M.WaterLevel - h, r, Enum.Material.Water)
		end
		r -= if r > R then 1 else 2
	end
	-- 가운데 작은 섬 (고목 자리): 안쪽으로 갈수록 높아지는 진흙 더미
	for ir = 10, 2, -2 do
		local h = -6 + (10 - ir) / 8 * 6.8
		terrain:FillCylinder(CFrame.new(c + Vector3.new(0, (h - 16) / 2, 0)), h + 16, ir, Enum.Material.Mud)
	end
	-- 물 외형: 어두운 밤에도 수면이 보이게 밝은 회청색 + 반사
	terrain.WaterColor = Color3.fromRGB(62, 92, 108)
	terrain.WaterReflectance = 1
	terrain.WaterTransparency = 0.7
	terrain.WaterWaveSize = 0.18
	terrain.WaterWaveSpeed = 12
end

-- 물가 경계선: 수면 가장자리를 따라 희미한 물거품 띠 (어디까지가 물인지 보이게)
local function buildShoreline(folder: Folder)
	local m = Instance.new("Model")
	m.Name = "Shoreline"
	m.Parent = folder
	local c = M.LakeCenter
	local n = 64
	local segLen = 2 * math.pi * M.LakeRadius / n + 0.6
	for i = 1, n do
		local a = i / n * math.pi * 2
		local pos = c + Vector3.new(math.cos(a) * M.LakeRadius, M.WaterLevel + 0.08, math.sin(a) * M.LakeRadius)
		local foam = Util.part({
			Name = "Foam",
			Size = Vector3.new(segLen, 0.08, 0.7),
			CFrame = CFrame.new(pos) * CFrame.Angles(0, -a + math.pi / 2, 0),
			Color = Color3.fromRGB(150, 172, 190),
			Material = Enum.Material.Neon,
			Transparency = 0.6,
			CanCollide = false,
			CanQuery = false,
			Parent = m,
		})
		foam.CastShadow = false
	end
end

---------------------------------------------------------------- 검은 버드나무
local function buildWillow(folder: Folder)
	local c = M.LakeCenter
	local g = Instance.new("Model")
	g.Name = "BlackWillow"
	g.Parent = folder

	-- 희미한 달빛 반사 (나무 아래가 완전히 안 보이지 않게)
	local glow = Util.part({
		Name = "WillowGlow",
		Size = Vector3.one,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Position = c + Vector3.new(0, 6, 0),
		Parent = g,
	})
	Util.pointLight(glow, Color3.fromRGB(120, 150, 200), 40, 0.35)

	-- 메시 고목이 있으면 그것으로 대체
	local mesh = Assets.spawn("DeadTree", g, { Height = Config.Assets.TreeHeight, CanCollide = false, CanQuery = false })
	if mesh then
		Assets.placeOnGround(mesh, c + Vector3.new(0, -0.6, 0), math.rad(Config.Assets.TreeYaw))
		return
	end

	local top = c + Vector3.new(0, 24, 0)
	Util.part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(26, 5.5, 5.5),
		CFrame = CFrame.new(c + Vector3.new(0, 12, 0)) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, 0, math.rad(3)),
		Color = COL.Bark,
		Material = Enum.Material.Wood,
		Parent = g,
	})
	-- 뿌리
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		local d = Vector3.new(math.cos(a), 0, math.sin(a))
		Util.segment(c + Vector3.new(0, 2.5, 0), c + d * 6 + Vector3.new(0, 0.3, 0), 1.4, { Color = COL.Bark, Material = Enum.Material.Wood, Parent = g })
	end
	-- 가지 + 늘어진 덩굴
	local branchCount = 14
	for i = 1, branchCount do
		local a = i / branchCount * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local d = Vector3.new(math.cos(a), 0, math.sin(a))
		local p1 = top + d * rng:NextNumber(7, 10) + Vector3.new(0, rng:NextNumber(2, 4), 0)
		local p2 = p1 + d * rng:NextNumber(6, 9) - Vector3.new(0, rng:NextNumber(5, 8), 0)
		Util.segment(top - Vector3.new(0, 1, 0), p1, 1.3, { Color = COL.Bark, Material = Enum.Material.Wood, Parent = g })
		Util.segment(p1, p2, 0.8, { Color = COL.Bark, Material = Enum.Material.Wood, Parent = g })
		for v = 1, 4 do
			local t = rng:NextNumber(0.15, 1)
			local start = p1:Lerp(p2, t) + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
			local len = rng:NextNumber(9, 19)
			local sway = Vector3.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5))
			local finish = start - Vector3.new(0, len, 0) + sway
			if finish.Y < M.WaterLevel - 0.5 then
				finish = Vector3.new(finish.X, M.WaterLevel - 0.5, finish.Z)
			end
			Util.segment(start, finish, 0.25, { Color = COL.Vine, Material = Enum.Material.Fabric, CanCollide = false, Parent = g })
		end
	end
end

---------------------------------------------------------------- 등불 기둥
local function lanternPost(folder: Instance, pos: Vector3, bright: number?)
	local post = Util.part({
		Name = "LanternPost",
		Size = Vector3.new(0.5, 7, 0.5),
		Position = pos + Vector3.new(0, 3.5, 0),
		Color = COL.Bark,
		Material = Enum.Material.Wood,
		Parent = folder,
	})
	Util.part({
		Name = "Arm",
		Size = Vector3.new(0.3, 0.3, 1.6),
		CFrame = CFrame.new(pos + Vector3.new(0, 6.7, 0.7)),
		Color = COL.Bark,
		Material = Enum.Material.Wood,
		Parent = folder,
	})
	local lamp = Util.part({
		Name = "Lamp",
		Size = Vector3.new(0.8, 1.1, 0.8),
		Position = pos + Vector3.new(0, 5.9, 1.4),
		Color = COL.Lantern,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = folder,
	})
	Util.pointLight(lamp, COL.Lantern, 22, bright or 0.9)
	return post
end

---------------------------------------------------------------- 길
local pathSegments: { { Vector3 } } = {}
local function buildPath(folder: Instance, from: Vector3, to: Vector3, record: boolean)
	local a, b = flat(from), flat(to)
	local len = (b - a).Magnitude
	local p = Util.part({
		Name = "Path",
		Size = Vector3.new(7, 0.3, len),
		CFrame = CFrame.lookAt((a + b) / 2 + Vector3.new(0, 0.1, 0), b + Vector3.new(0, 0.1, 0)),
		Color = COL.Dirt,
		Material = Enum.Material.Ground,
		CanCollide = false,
		Parent = folder,
	})
	p.CastShadow = false
	if record then
		table.insert(pathSegments, { a, b })
	end
end

---------------------------------------------------------------- 캠프 (안전지대 / 납품)
local function buildCamp(folder: Folder, info: MapInfo)
	local c = M.CampCenter
	local camp = Instance.new("Model")
	camp.Name = "Camp"
	camp.Parent = folder

	-- 모닥불
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		Util.part({
			Name = "Stone",
			Size = Vector3.new(1.4, 1, 1.2),
			CFrame = CFrame.new(c + Vector3.new(math.cos(a) * 2.6, 0.5, math.sin(a) * 2.6)) * CFrame.Angles(0, -a, 0),
			Color = COL.Rock,
			Material = Enum.Material.Slate,
			Parent = camp,
		})
	end
	for i = 1, 3 do
		local a = i / 3 * math.pi
		Util.part({
			Name = "Log",
			Size = Vector3.new(0.7, 0.7, 3.4),
			CFrame = CFrame.new(c + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, a, math.rad(20)),
			Color = COL.Wood,
			Material = Enum.Material.Wood,
			Parent = camp,
		})
	end
	local fireCore = Util.part({
		Name = "FireCore",
		Size = Vector3.new(1.5, 0.5, 1.5),
		Position = c + Vector3.new(0, 1, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = camp,
	})
	local fire = Instance.new("Fire")
	fire.Size = 6
	fire.Heat = 12
	fire.Color = Color3.fromRGB(255, 150, 70)
	fire.SecondaryColor = Color3.fromRGB(180, 60, 20)
	fire.Parent = fireCore
	Util.pointLight(fireCore, Color3.fromRGB(255, 160, 90), 34, 1.2)

	-- 통나무 의자
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		Util.part({
			Name = "Seat",
			Size = Vector3.new(1.2, 1.2, 4.5),
			CFrame = CFrame.new(c + Vector3.new(math.cos(a) * 6, 0.6, math.sin(a) * 6)) * CFrame.Angles(0, -a + math.pi / 2, 0),
			Color = COL.Wood,
			Material = Enum.Material.Wood,
			Parent = camp,
		})
	end

	-- 텐트 3개
	for i, off in { Vector3.new(-16, 0, 6), Vector3.new(15, 0, 10), Vector3.new(-6, 0, 18) } do
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.Size = Vector3.new(8, 5, 6)
		w.CFrame = CFrame.new(c + off + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, math.rad(40 * i), 0)
		w.Color = COL.Canvas
		w.Material = Enum.Material.Fabric
		w.Name = "Tent"
		w.Parent = camp
		local w2 = w:Clone()
		w2.CFrame = w.CFrame * CFrame.Angles(0, math.pi, 0)
		w2.Parent = camp
	end

	lanternPost(camp, c + Vector3.new(-12, 0, -10), 0.6)

	-- 스폰 지점 (모닥불 주변)
	info.Spawns = {}
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		table.insert(info.Spawns, c + Vector3.new(math.cos(a) * 11, 3, math.sin(a) * 11))
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = c + Vector3.new(0, -0.6, 10)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = camp

	-- 안전지대 표식: 땅에 희미한 돌 원
	for i = 1, 24 do
		local a = i / 24 * math.pi * 2
		Util.part({
			Name = "SafeStone",
			Size = Vector3.new(1.6, 0.5, 0.9),
			CFrame = CFrame.new(c + Vector3.new(math.cos(a) * M.SafeRadius, 0.2, math.sin(a) * M.SafeRadius)) * CFrame.Angles(0, -a, 0),
			Color = Color3.fromRGB(70, 70, 72),
			Material = Enum.Material.Slate,
			Parent = camp,
		})
	end
end

---------------------------------------------------------------- 제단 (납품·봉인 지점)
local function buildAltar(folder: Folder, info: MapInfo)
	local c = M.AltarCenter
	local altar = Instance.new("Model")
	altar.Name = "Altar"
	altar.Parent = folder

	-- 돌 단 2층
	Util.part({
		Name = "Base1",
		Size = Vector3.new(22, 1.2, 22),
		Position = c + Vector3.new(0, 0.6, 0),
		Color = Color3.fromRGB(48, 48, 52),
		Material = Enum.Material.Slate,
		Parent = altar,
	})
	Util.part({
		Name = "Base2",
		Size = Vector3.new(14, 1.2, 14),
		Position = c + Vector3.new(0, 1.8, 0),
		Color = Color3.fromRGB(42, 42, 46),
		Material = Enum.Material.Slate,
		Parent = altar,
	})
	-- 물그릇: Jar 메시가 있으면 항아리, 없으면 돌 수반
	local vessel: BasePart
	local waterMinY: number
	local waterMaxY: number
	local waterDiameter: number
	local jar = Assets.spawn("Jar", altar, { Height = Config.Assets.JarHeight, CanCollide = false })
	if jar then
		Assets.placeOnGround(jar, c + Vector3.new(0, 2.4, 0))
		local _, size = jar:GetBoundingBox()
		vessel = jar.PrimaryPart :: BasePart
		waterMinY = c.Y + 2.4 + size.Y * 0.3
		waterMaxY = c.Y + 2.4 + size.Y + 0.05
		waterDiameter = math.max(1, math.min(size.X, size.Z) * 0.5)
	else
		vessel = Util.part({
			Name = "Basin",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3, 7, 7),
			CFrame = CFrame.new(c + Vector3.new(0, 3.9, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(30, 30, 34),
			Material = Enum.Material.Slate,
			Parent = altar,
		})
		waterMinY = c.Y + 2.6
		waterMaxY = c.Y + 4.8
		waterDiameter = 6
	end
	local water = Util.part({
		Name = "AltarWater",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, waterDiameter, waterDiameter),
		CFrame = CFrame.new(Vector3.new(c.X, waterMinY, c.Z)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(40, 90, 120),
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		Reflectance = 0.35,
		CanCollide = false,
		Parent = altar,
	})
	-- 비석 + 돌기둥 원
	Util.part({
		Name = "Stele",
		Size = Vector3.new(4, 7, 1),
		Position = c + Vector3.new(0, 5.9, 4.5),
		Color = Color3.fromRGB(36, 36, 40),
		Material = Enum.Material.Slate,
		Parent = altar,
	})
	local candles = {}
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		local pos = c + Vector3.new(math.cos(a) * 16, 0, math.sin(a) * 16)
		Util.part({
			Name = "Pillar",
			Size = Vector3.new(2, rng:NextNumber(5, 9), 2),
			Position = pos + Vector3.new(0, 3.5, 0),
			Color = Color3.fromRGB(40, 40, 44),
			Material = Enum.Material.Slate,
			Parent = altar,
		})
		local candle = Util.part({
			Name = "Candle",
			Size = Vector3.new(0.4, 0.8, 0.4),
			Position = c + Vector3.new(math.cos(a) * 6, 2.8, math.sin(a) * 6),
			Color = Color3.fromRGB(200, 190, 160),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = altar,
		})
		local light = Util.pointLight(candle, Color3.fromRGB(120, 170, 255), 6, 0.0)
		table.insert(candles, light)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "물 붓기"
	prompt.ObjectText = "제단"
	prompt.HoldDuration = 0.8
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = vessel
	local label = Util.billboard(vessel, "제단 0 / 0", 5, UDim2.fromOffset(220, 46))
	label.TextColor3 = Color3.fromRGB(150, 185, 230)

	info.Altar = vessel
	info.AltarWaterMinY = waterMinY
	info.AltarWaterMaxY = waterMaxY
	info.AltarPrompt = prompt
	info.AltarLabel = label
	info.AltarWater = water
	info.AltarCandles = candles
end

---------------------------------------------------------------- 출구 문 + 울타리
local function buildGate(folder: Folder, info: MapInfo)
	local g = M.GatePosition
	local gate = Instance.new("Model")
	gate.Name = "Gate"
	gate.Parent = folder

	-- 울타리 (x -70 ~ 70, 가운데 ±6 비움)
	for x = -70, 70, 10 do
		if math.abs(x) > 6 then
			Util.part({
				Name = "FencePost",
				Size = Vector3.new(0.8, 6, 0.8),
				Position = g + Vector3.new(x, 3, 0),
				Color = COL.OldWood,
				Material = Enum.Material.Wood,
				Parent = gate,
			})
		end
	end
	for _, sideSign in { -1, 1 } do
		for _, y in { 2, 4.5 } do
			Util.part({
				Name = "Rail",
				Size = Vector3.new(64, 0.4, 0.4),
				Position = g + Vector3.new(sideSign * 38, y, 0),
				Color = COL.OldWood,
				Material = Enum.Material.Wood,
				Parent = gate,
			})
		end
	end
	-- 보이지 않는 벽 (울타리 너머 못 가게)
	for _, sideSign in { -1, 1 } do
		Util.part({ Name = "Wall", Size = Vector3.new(64, 20, 1), Position = g + Vector3.new(sideSign * 38, 10, 0), Transparency = 1, Parent = gate })
	end
	-- 문 기둥, 상인방, 표지
	for _, sideSign in { -1, 1 } do
		Util.part({
			Name = "GatePost",
			Size = Vector3.new(1.4, 11, 1.4),
			Position = g + Vector3.new(sideSign * 6.5, 5.5, 0),
			Color = COL.Bark,
			Material = Enum.Material.Wood,
			Parent = gate,
		})
		lanternPost(gate, g + Vector3.new(sideSign * 9, 0, -2), 1.0)
	end
	local lintel = Util.part({
		Name = "Lintel",
		Size = Vector3.new(15, 1.4, 1.6),
		Position = g + Vector3.new(0, 11, 0),
		Color = COL.Bark,
		Material = Enum.Material.Wood,
		Parent = gate,
	})
	local sign = Instance.new("SurfaceGui")
	sign.Face = Enum.NormalId.Front
	sign.CanvasSize = Vector2.new(600, 60)
	sign.Parent = lintel
	local signText = Instance.new("TextLabel")
	signText.Size = UDim2.fromScale(1, 1)
	signText.BackgroundTransparency = 1
	signText.Text = "출  구"
	signText.TextColor3 = Color3.fromRGB(200, 60, 50)
	signText.TextScaled = true
	signText.Font = Enum.Font.Antique
	signText.Parent = sign

	local panel = Util.part({
		Name = "GatePanel",
		Size = Vector3.new(12, 9.5, 0.6),
		Position = g + Vector3.new(0, 4.75, 0),
		Color = COL.Metal,
		Material = Enum.Material.DiamondPlate,
		Parent = gate,
	})
	for i = -2, 2 do
		Util.part({
			Name = "Bar",
			Size = Vector3.new(0.5, 9.5, 0.9),
			Position = g + Vector3.new(i * 2.4, 4.75, 0),
			Color = COL.Rock,
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = gate,
		}).Parent =
			panel
	end
	local exitZone = Util.part({
		Name = "ExitZone",
		Size = Vector3.new(14, 14, 10),
		Position = g + Vector3.new(0, 7, 9),
		Transparency = 1,
		CanCollide = false,
		Parent = gate,
	})
	-- 문 너머 길
	buildPath(gate, g + Vector3.new(0, 0, 1), g + Vector3.new(0, 0, 60), false)

	info.GatePanel = panel
	info.ExitZone = exitZone
end

---------------------------------------------------------------- 물가 3곳
local function buildStations(folder: Folder, info: MapInfo)
	local c = M.LakeCenter
	local R = M.LakeRadius
	info.Stations = {}
	for i, def in M.Stations do
		local dir = (def.Direction :: Vector3).Unit
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local m = Instance.new("Model")
		m.Name = "Station_" .. def.Kind
		m.Parent = folder
		local point: Vector3
		local markerPos: Vector3

		if def.Kind == "Pier" then
			-- 평지(물가 경사 시작점)에서 바로 이어지는 낮은 데크 (턱 0.3)
			local startP = c + dir * (R + M.BeachWidth + 2)
			local endP = c + dir * 66
			Util.part({
				Name = "Deck",
				Size = Vector3.new(6, 0.6, (endP - startP).Magnitude),
				CFrame = CFrame.lookAt((startP + endP) / 2 + Vector3.new(0, 0, 0), endP),
				Color = COL.OldWood,
				Material = Enum.Material.WoodPlanks,
				Parent = m,
			})
			local len = (endP - startP).Magnitude
			local d = 4
			while d <= len do
				for _, s in { -1, 1 } do
					local base = startP + dir * d + side * 2.6
					Util.part({
						Name = "Post",
						Size = Vector3.new(0.7, 14, 0.7),
						Position = base * Vector3.new(1, 0, 1) + Vector3.new(0, -6, 0) + side * (s - 1) * 2.6,
						Color = COL.Bark,
						Material = Enum.Material.Wood,
						Parent = m,
					})
				end
				d += 8
			end
			-- 끝 난간 & 희미한 등
			Util.segment(
				endP + side * 3 + Vector3.new(0, 1.5, 0),
				endP + side * 3 + Vector3.new(0, 4, 0),
				0.4,
				{ Color = COL.Bark, Material = Enum.Material.Wood, Parent = m }
			)
			local lamp = Util.part({
				Name = "PierLamp",
				Size = Vector3.new(0.7, 0.9, 0.7),
				Position = endP + side * 3 + Vector3.new(0, 4.4, 0),
				Color = Color3.fromRGB(200, 150, 90),
				Material = Enum.Material.Neon,
				CanCollide = false,
				Parent = m,
			})
			Util.pointLight(lamp, Color3.fromRGB(220, 160, 90), 12, 0.3)
			point = endP + Vector3.new(0, 0.45, 0)
			markerPos = endP - dir * 1 + Vector3.new(0, 0.45, 0)
		elseif def.Kind == "Reeds" then
			for _ = 1, 70 do
				local a = math.atan2(dir.Z, dir.X) + rng:NextNumber(-0.32, 0.32)
				local r = rng:NextNumber(R - 3, R + 10)
				local pos = c + Vector3.new(math.cos(a) * r, groundAt(r), math.sin(a) * r)
				local h = rng:NextNumber(4, 7.5)
				local reed = Util.part({
					Name = "Reed",
					Size = Vector3.new(0.25, h, 0.25),
					CFrame = CFrame.new(pos + Vector3.new(0, h / 2 - 0.5, 0))
						* CFrame.Angles(math.rad(rng:NextNumber(-10, 10)), rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(-10, 10))),
					Color = COL.Reed,
					Material = Enum.Material.Grass,
					CanCollide = false,
					Parent = m,
				})
				reed.CastShadow = false
			end
			-- 물가의 낡은 널빤지
			point = c + dir * (R + 1.5) + Vector3.new(0, groundAt(R + 1.5) + 0.45, 0)
			Util.part({
				Name = "Plank",
				Size = Vector3.new(4, 0.4, 6),
				CFrame = CFrame.lookAt(point - Vector3.new(0, 0.25, 0) - dir * 1, point - Vector3.new(0, 0.25, 0) + dir),
				Color = COL.OldWood,
				Material = Enum.Material.WoodPlanks,
				Parent = m,
			})
			markerPos = point
		else -- Rocks
			local slabPos = c + dir * (R + 2) + Vector3.new(0, groundAt(R + 2), 0)
			Util.part({
				Name = "Slab",
				Size = Vector3.new(10, 1.0, 12),
				CFrame = CFrame.lookAt(slabPos + Vector3.new(0, 0.1, 0), slabPos + dir + Vector3.new(0, 0.1, 0)) * CFrame.Angles(math.rad(-4), 0, 0),
				Color = COL.Rock,
				Material = Enum.Material.Slate,
				Parent = m,
			})
			for _ = 1, 14 do
				local a = math.atan2(dir.Z, dir.X) + rng:NextNumber(-0.3, 0.3)
				local r = rng:NextNumber(R - 2, R + 14)
				local pos = c + Vector3.new(math.cos(a) * r, groundAt(r), math.sin(a) * r)
				local s = rng:NextNumber(2, 6)
				Util.part({
					Name = "Rock",
					Size = Vector3.new(s, s * rng:NextNumber(0.6, 1.2), s * rng:NextNumber(0.7, 1.3)),
					CFrame = CFrame.new(pos + Vector3.new(0, s * 0.25, 0))
						* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6.28), rng:NextNumber(-0.4, 0.4)),
					Color = COL.Rock,
					Material = Enum.Material.Slate,
					Parent = m,
				})
			end
			point = c + dir * (R + 1) + Vector3.new(0, groundAt(R + 1) + 0.85, 0)
			markerPos = point
		end

		-- 상호작용 마커 + 프롬프트 + 이름표
		local marker = Util.part({
			Name = "Marker",
			Size = Vector3.new(1.6, 0.3, 1.6),
			Position = markerPos,
			Color = Color3.fromRGB(90, 130, 160),
			Material = Enum.Material.Neon,
			Transparency = 0.6,
			CanCollide = false,
			Parent = m,
		})
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "물 긷기 / 중단"
		prompt.ObjectText = def.Name
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = Config.Fill.Range
		prompt.RequiresLineOfSight = false
		prompt.Parent = marker
		Util.billboard(marker, def.Name, 4, UDim2.fromOffset(180, 34)).TextColor3 = Color3.fromRGB(150, 185, 210)
		Util.pointLight(marker, Color3.fromRGB(90, 140, 190), 9, 0.2)
		-- 물가에 놓인 낡은 양동이 (Bucket 메시가 있을 때만)
		local prop = Assets.spawn("Bucket", m, { Height = Config.Assets.BucketHeight, CanCollide = false })
		if prop then
			Assets.placeOnGround(prop, markerPos + side * 1.8 - Vector3.new(0, 0.15, 0), rng:NextNumber(0, math.pi * 2))
		end

		table.insert(info.Stations, {
			Index = i,
			Name = def.Name,
			Def = def,
			Point = point,
			Prompt = prompt,
			Marker = marker,
		})
	end
end

---------------------------------------------------------------- 숲
local function buildForest(folder: Folder)
	local forest = Instance.new("Model")
	forest.Name = "Forest"
	forest.Parent = folder
	local c = M.LakeCenter
	local camp = M.CampCenter
	local placed = 0
	local tries = 0
	local useMesh = Assets.has("DeadTree")
	while placed < 120 and tries < 1000 do
		tries += 1
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(M.LakeRadius + 28, 330)
		local pos = c + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local ok = (flat(pos) - flat(camp)).Magnitude > 48 and (flat(pos) - flat(M.AltarCenter)).Magnitude > 34
		if ok and pos.Z > M.GatePosition.Z - 8 and math.abs(pos.X) < 14 then
			ok = false -- 문 뒤의 길 비워둠
		end
		if ok then
			for _, seg in pathSegments do
				local a2, b2 = seg[1], seg[2]
				local ab = b2 - a2
				local t = math.clamp((flat(pos) - a2):Dot(ab) / ab:Dot(ab), 0, 1)
				if (flat(pos) - (a2 + ab * t)).Magnitude < 10 then
					ok = false
				end
			end
		end
		if ok and useMesh and rng:NextNumber() < Config.Assets.ForestMeshRatio then
			placed += 1
			local fh = rng:NextNumber(Config.Assets.ForestTreeHeight[1], Config.Assets.ForestTreeHeight[2])
			local tree = Assets.spawn("DeadTree", forest, { Height = fh, CanCollide = false, CanQuery = false })
			if tree then
				Assets.placeOnGround(tree, pos - Vector3.new(0, 0.8, 0), rng:NextNumber(0, math.pi * 2))
			end
		elseif ok then
			placed += 1
			local h = rng:NextNumber(14, 24)
			local th = rng:NextNumber(1.4, 2.6)
			Util.part({
				Name = "Trunk",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(h, th, th),
				CFrame = CFrame.new(pos + Vector3.new(0, h / 2 - 1, 0))
					* CFrame.Angles(0, 0, math.rad(90))
					* CFrame.Angles(0, 0, math.rad(rng:NextNumber(-4, 4))),
				Color = COL.Bark,
				Material = Enum.Material.Wood,
				Parent = forest,
			})
			for k = 1, 2 do
				local s = rng:NextNumber(8, 13)
				local off = Vector3.new(rng:NextNumber(-3, 3), h - 2 + (k - 1) * 4, rng:NextNumber(-3, 3))
				local ball = Util.part({
					Name = "Canopy",
					Shape = Enum.PartType.Ball,
					Size = Vector3.new(s, s, s),
					Position = pos + off,
					Color = COL.Leaf,
					Material = Enum.Material.Grass,
					CanCollide = false,
					Parent = forest,
				})
				ball.CastShadow = true
			end
		end
	end
	-- 외곽 경계벽
	for _, w in
		{
			{ Vector3.new(0, 20, 360), Vector3.new(760, 40, 2) },
			{ Vector3.new(0, 20, -340), Vector3.new(760, 40, 2) },
			{ Vector3.new(360, 20, 0), Vector3.new(2, 40, 760) },
			{ Vector3.new(-360, 20, 0), Vector3.new(2, 40, 760) },
		}
	do
		Util.part({ Name = "Boundary", Position = c + w[1], Size = w[2], Transparency = 1, Parent = forest })
	end
end

---------------------------------------------------------------- 빌드
function MapBuilder.build(): MapInfo
	local old = Workspace:FindFirstChild("DeadLake")
	if old then
		old:Destroy()
	end
	for _, name in { "Baseplate", "SpawnLocation" } do
		local inst = Workspace:FindFirstChild(name)
		if inst then
			inst:Destroy()
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = "DeadLake"

	local info = {} :: MapInfo
	info.Folder = folder

	buildTerrain()
	buildShoreline(folder)
	buildWillow(folder)
	buildCamp(folder, info)
	buildAltar(folder, info)
	buildGate(folder, info)
	buildStations(folder, info)

	-- 길: 캠프 → 각 물가, 각 물가 → 제단, 캠프 → 출구. (숲보다 먼저 만들어 나무가 길을 피하게)
	table.clear(pathSegments)
	local pathFolder = Instance.new("Folder")
	pathFolder.Name = "Paths"
	pathFolder.Parent = folder
	for _, st in info.Stations do
		local dir = (st.Def.Direction :: Vector3).Unit
		local shore = M.LakeCenter + dir * (M.LakeRadius + M.BeachWidth + 1)
		buildPath(pathFolder, M.CampCenter, shore, true)
		buildPath(pathFolder, shore, M.AltarCenter, true)
	end
	buildPath(pathFolder, M.CampCenter, M.GatePosition, false)
	info.PathSegments = pathSegments
	buildForest(folder)

	-- 귀신 본체 대기 위치: 버드나무 옆 물속, 캠프 쪽을 바라봄 (머리·곧은 목·어깨만 수면 위)
	local idlePos = M.LakeCenter + Vector3.new(2, -4.2, 11)
	info.GhostIdleCFrame = CFrame.lookAt(idlePos, Vector3.new(M.CampCenter.X, idlePos.Y, M.CampCenter.Z))

	folder.Parent = Workspace
	return info
end

return MapBuilder
