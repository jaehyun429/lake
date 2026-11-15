-- 항아리 사당 3종의 외형을 파트로 만든다 (제단 / 돌탑 / 무너진 사당).
-- MapBuilder.buildShrine 이 바닥·항아리·물·프롬프트를 만든 뒤 여기서 꾸민다.
-- 돌려주는 PointLight 목록은 항아리가 차면 밝아지는 "촛불" 역할 (RoundManager 가 Brightness 를 조절).
--
-- 좌표계: 사당 중심 c 에서 호수 반대쪽을 "뒤(+z)", 호수 쪽을 "앞(-z)" 으로 두는 로컬 좌표를 쓴다.
-- 길이 들어오는 방향(approach)에는 걸리는 큰 구조물을 세우지 않는다. 땅 높이 장식은 전부 CanCollide=false.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.DeadLake.Shared.Config)
local Util = require(script.Parent.Util)
local Assets = require(script.Parent.Assets)

local ShrineBuilder = {}

export type Ctx = {
	Model: Model,
	Center: Vector3,
	Top: number, -- 바닥 윗면 높이 (지면 기준)
	Frame: CFrame, -- 로컬 → 월드
	Rng: Random,
	Approach: { Vector3 }, -- 길이 들어오는 수평 단위 벡터들 (월드)
	Lights: { PointLight },
}

local STONE = {
	Color3.fromRGB(44, 44, 48),
	Color3.fromRGB(52, 50, 52),
	Color3.fromRGB(38, 40, 42),
	Color3.fromRGB(58, 56, 54),
	Color3.fromRGB(47, 49, 46),
}
local OLD_WOOD = Color3.fromRGB(58, 46, 36)
local DARK_WOOD = Color3.fromRGB(40, 32, 26)
local PAPER = Color3.fromRGB(214, 206, 188)
local STRAW = Color3.fromRGB(128, 108, 66)

-- 로컬 좌표(x 오른쪽, y 위, z 뒤) → 월드 CFrame
local function L(ctx: Ctx, x: number, y: number, z: number): CFrame
	return ctx.Frame * CFrame.new(x, y, -z)
end

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

-- 월드 수평 방향 dir 이 길이 들어오는 방향과 가까운가 (그 자리엔 장애물을 안 세움)
local function blocksApproach(ctx: Ctx, worldPos: Vector3, halfAngleDeg: number): boolean
	local d = (worldPos - ctx.Center) * Vector3.new(1, 0, 1)
	if d.Magnitude < 0.1 then
		return false
	end
	d = d.Unit
	local cosLimit = math.cos(math.rad(halfAngleDeg))
	for _, a in ctx.Approach do
		if d:Dot(a) > cosLimit then
			return true
		end
	end
	return false
end

local function part(ctx: Ctx, props: { [string]: any }): Part
	props.Parent = ctx.Model
	if props.Material == nil then
		props.Material = Enum.Material.Slate
	end
	return Util.part(props)
end

local function wedge(ctx: Ctx, props: { [string]: any }): WedgePart
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.CanCollide = false
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Material = Enum.Material.Slate
	for k, v in props do
		if k ~= "Parent" then
			(w :: any)[k] = v
		end
	end
	w.Parent = ctx.Model
	return w
end

-- 초/등불: 보이는 작은 파트 + PointLight(처음엔 꺼짐). 항아리가 차면 켜진다
local function candle(ctx: Ctx, cf: CFrame, size: Vector3, color: Color3, lightColor: Color3, range: number)
	local p = part(ctx, {
		Name = "Candle",
		Size = size,
		CFrame = cf,
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	local flame = part(ctx, {
		Name = "Flame",
		Size = Vector3.new(0.18, 0.28, 0.18),
		CFrame = cf * CFrame.new(0, size.Y / 2 + 0.14, 0),
		Color = Color3.fromRGB(255, 190, 110),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
	})
	flame.CastShadow = false
	table.insert(ctx.Lights, Util.pointLight(p, lightColor, range, 0))
end

-- 돌 하나 (무작위 색·살짝 기울임)
local function stone(ctx: Ctx, cf: CFrame, size: Vector3, collide: boolean?): Part
	local rng = ctx.Rng
	return part(ctx, {
		Name = "Stone",
		Size = size,
		CFrame = cf * CFrame.Angles(math.rad(rng:NextNumber(-4, 4)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-4, 4))),
		Color = pick(rng, STONE),
		Material = if rng:NextNumber() < 0.5 then Enum.Material.Slate else Enum.Material.Rock,
		CanCollide = collide == true,
	})
end

-- 바닥에 흩어진 잔돌
local function rubble(ctx: Ctx, count: number, rMin: number, rMax: number)
	local rng = ctx.Rng
	for _ = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(rMin, rMax)
		local s = rng:NextNumber(0.3, 0.9)
		stone(ctx, L(ctx, math.cos(a) * r, ctx.Top + s * 0.3, math.sin(a) * r), Vector3.new(s, s * 0.6, s * rng:NextNumber(0.7, 1.3)), false)
	end
end

---------------------------------------------------------------- 1) 제단: 돌 제단상 + 비석 + 금줄 두른 돌기둥 + 석등
local function buildAltar(ctx: Ctx)
	local rng = ctx.Rng
	local top = ctx.Top

	-- 제단상 (항아리 뒤): 두 다리 위 널돌
	for _, x in { -2.2, 2.2 } do
		part(ctx, { Name = "AltarLeg", Size = Vector3.new(1.3, 2.3, 2.2), CFrame = L(ctx, x, top + 1.15, 4.6), Color = STONE[1] })
	end
	part(ctx, {
		Name = "AltarSlab",
		Size = Vector3.new(7.4, 0.7, 3.2),
		CFrame = L(ctx, 0, top + 2.65, 4.6) * CFrame.Angles(0, 0, math.rad(0.8)),
		Color = STONE[4],
	})
	-- 상 위: 놋그릇 3개, 초 2개
	for i, x in { -1.9, 0, 1.9 } do
		part(ctx, {
			Name = "Bowl",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.35, 1.1 - (i - 2) ^ 2 * 0.15, 1.1 - (i - 2) ^ 2 * 0.15),
			CFrame = L(ctx, x, top + 3.18, 4.9) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(96, 78, 44),
			Material = Enum.Material.CorrodedMetal,
			CanCollide = false,
		})
	end
	for _, x in { -3.0, 3.0 } do
		candle(ctx, L(ctx, x, top + 3.0 + 0.45, 4.2), Vector3.new(0.35, 0.9, 0.35), Color3.fromRGB(205, 195, 165), Color3.fromRGB(255, 180, 110), 9)
	end

	-- 비석: 글자 새김 (앞면 SurfaceGui)
	local stele = part(ctx, {
		Name = "Stele",
		Size = Vector3.new(3.6, 7.5, 0.9),
		CFrame = L(ctx, 0, top + 3.75, 7.6) * CFrame.Angles(math.rad(-2), 0, math.rad(1.5)),
		Color = Color3.fromRGB(34, 34, 38),
	})
	part(ctx, { Name = "SteleCap", Size = Vector3.new(4.2, 0.6, 1.3), CFrame = L(ctx, 0, top + 7.7, 7.6), Color = STONE[3] })
	part(ctx, { Name = "SteleBase", Size = Vector3.new(4.6, 0.5, 1.8), CFrame = L(ctx, 0, top + 0.25, 7.6), Color = STONE[2], CanCollide = false })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	gui.Parent = stele
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 0.82)
	text.Position = UDim2.fromScale(0, 0.08)
	text.BackgroundTransparency = 1
	text.Text = "殺\n木\n池"
	text.TextColor3 = Color3.fromRGB(18, 18, 20)
	text.TextStrokeTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.Antique
	text.Parent = gui

	-- 돌기둥 8개 + 금줄(새끼줄) + 한지 조각. 길이 들어오는 방향은 기둥을 비움
	local tops: { Vector3? } = {}
	for i = 1, 8 do
		local a = (i - 0.5) / 8 * math.pi * 2
		local cf = L(ctx, math.cos(a) * 15, 0, math.sin(a) * 15)
		if blocksApproach(ctx, cf.Position, 16) then
			tops[i] = nil
			continue
		end
		local h = rng:NextNumber(5.5, 8.5)
		part(ctx, {
			Name = "Pillar",
			Size = Vector3.new(1.8, h, 1.8),
			CFrame = cf
				* CFrame.new(0, h / 2 - 0.4, 0)
				* CFrame.Angles(math.rad(rng:NextNumber(-3, 3)), math.rad(rng:NextNumber(0, 90)), math.rad(rng:NextNumber(-3, 3))),
			Color = pick(rng, STONE),
			Material = Enum.Material.Slate,
		})
		part(ctx, { Name = "PillarCap", Size = Vector3.new(2.3, 0.4, 2.3), CFrame = cf * CFrame.new(0, h - 0.4, 0), Color = STONE[3], CanCollide = false })
		tops[i] = (cf * CFrame.new(0, h - 0.6, 0)).Position
	end
	for i = 1, 8 do
		local a, b = tops[i], tops[i % 8 + 1]
		if a and b then
			local sag = Vector3.new(0, -0.6, 0)
			local mid = (a + b) / 2 + sag
			for _, seg in { { a, mid }, { mid, b } } do
				Util.segment(
					seg[1],
					seg[2],
					0.16,
					{ Name = "Rope", Color = STRAW, Material = Enum.Material.Fabric, CanCollide = false, CanQuery = false, Parent = ctx.Model }
				)
			end
			-- 한지 조각 3장
			for k = 1, 3 do
				local t = k / 4
				local p = (a:Lerp(mid, math.min(1, t * 2)))
				if t > 0.5 then
					p = mid:Lerp(b, (t - 0.5) * 2)
				end
				local paper = part(ctx, {
					Name = "Paper",
					Size = Vector3.new(0.45, 1.3, 0.04),
					CFrame = CFrame.lookAt(p, p + (b - a) * Vector3.new(1, 0, 1))
						* CFrame.new(0, -0.75, 0)
						* CFrame.Angles(math.rad(rng:NextNumber(-10, 10)), math.rad(90), math.rad(rng:NextNumber(-25, 25))),
					Color = PAPER,
					Material = Enum.Material.SmoothPlastic,
					Transparency = 0.08,
					CanCollide = false,
					CanQuery = false,
				})
				paper.CastShadow = false
			end
		end
	end

	-- 석등 2기 (앞쪽 좌우). 불은 항아리가 차면 켜짐
	for _, x in { -5.5, 5.5 } do
		local base = L(ctx, x, 0, -4.5)
		part(ctx, {
			Name = "LanternBase",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 2.4, 2.4),
			CFrame = base * CFrame.new(0, top + 0.25, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = STONE[2],
			CanCollide = false,
		})
		part(ctx, { Name = "LanternPost", Size = Vector3.new(0.7, 2.4, 0.7), CFrame = base * CFrame.new(0, top + 1.7, 0), Color = STONE[1] })
		part(
			ctx,
			{ Name = "LanternTray", Size = Vector3.new(1.7, 0.3, 1.7), CFrame = base * CFrame.new(0, top + 3.05, 0), Color = STONE[3], CanCollide = false }
		)
		-- 불집: 네 기둥 + 지붕
		for _, o in { Vector2.new(-0.6, -0.6), Vector2.new(0.6, -0.6), Vector2.new(-0.6, 0.6), Vector2.new(0.6, 0.6) } do
			part(ctx, {
				Name = "LanternPillar",
				Size = Vector3.new(0.25, 1.3, 0.25),
				CFrame = base * CFrame.new(o.X, top + 3.85, o.Y),
				Color = STONE[1],
				CanCollide = false,
			})
		end
		part(
			ctx,
			{ Name = "LanternRoof", Size = Vector3.new(2.2, 0.35, 2.2), CFrame = base * CFrame.new(0, top + 4.65, 0), Color = STONE[3], CanCollide = false }
		)
		part(
			ctx,
			{ Name = "LanternRoof2", Size = Vector3.new(1.3, 0.35, 1.3), CFrame = base * CFrame.new(0, top + 5.0, 0), Color = STONE[3], CanCollide = false }
		)
		part(ctx, {
			Name = "LanternFinial",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.5, 0.5, 0.5),
			CFrame = base * CFrame.new(0, top + 5.4, 0),
			Color = STONE[1],
			CanCollide = false,
		})
		candle(ctx, base * CFrame.new(0, top + 3.6, 0), Vector3.new(0.5, 0.6, 0.5), Color3.fromRGB(70, 60, 40), Color3.fromRGB(255, 170, 100), 12)
	end

	-- 바닥에 흩어진 잔돌
	rubble(ctx, 14, 8, 13)
end

---------------------------------------------------------------- 2) 돌탑: 큰 돌탑 + 작은 돌탑 여러 개 + 색 바랜 천 장대
local function cairn(ctx: Ctx, baseCF: CFrame, count: number, baseWidth: number, collide: boolean)
	local rng = ctx.Rng
	local y = 0
	local drift = Vector2.new(0, 0)
	for i = 1, count do
		local t = (i - 1) / math.max(1, count - 1)
		local w = baseWidth * (1 - t * 0.68) * rng:NextNumber(0.9, 1.1)
		local h = math.clamp(w * rng:NextNumber(0.18, 0.32), 0.18, 0.7)
		drift += Vector2.new(rng:NextNumber(-0.08, 0.08), rng:NextNumber(-0.08, 0.08)) * baseWidth
		local cf = baseCF * CFrame.new(drift.X, y + h / 2, drift.Y) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
		part(ctx, {
			Name = "CairnStone",
			Size = Vector3.new(w, h, w * rng:NextNumber(0.75, 1.0)),
			CFrame = cf * CFrame.Angles(math.rad(rng:NextNumber(-3, 3)), 0, math.rad(rng:NextNumber(-3, 3))),
			Color = pick(rng, STONE),
			Material = if i % 3 == 0 then Enum.Material.Rock else Enum.Material.Slate,
			CanCollide = collide and i <= 3, -- 아래쪽만 충돌 (위는 머리 안 부딪히게)
		})
		y += h * 0.96
	end
	-- 꼭대기 뾰족돌
	part(ctx, {
		Name = "CairnTip",
		Size = Vector3.new(0.35, 0.6, 0.35),
		CFrame = baseCF * CFrame.new(drift.X, y + 0.3, drift.Y) * CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), 0, math.rad(rng:NextNumber(-8, 8))),
		Color = STONE[3],
		CanCollide = false,
	})
	return y
end

local function buildCairn(ctx: Ctx)
	local rng = ctx.Rng
	local top = ctx.Top

	-- 큰 돌탑 (항아리 뒤)
	cairn(ctx, L(ctx, 0, top, 4.6), 18, 4.2, true)
	-- 양옆 중간 돌탑
	cairn(ctx, L(ctx, -4.6, top, 2.8), 13, 2.7, true)
	cairn(ctx, L(ctx, 4.8, top, 3.2), 14, 2.4, true)

	-- 둘레 작은 돌탑들 (길 들어오는 방향은 비움)
	local n = 0
	local tries = 0
	while n < 9 and tries < 40 do
		tries += 1
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(6.5, 11)
		local cf = L(ctx, math.cos(a) * r, top, math.sin(a) * r)
		if blocksApproach(ctx, cf.Position, 14) then
			continue
		end
		n += 1
		local h = cairn(ctx, cf, rng:NextInteger(5, 9), rng:NextNumber(1.0, 1.9), false)
		-- 몇 개 위엔 소원초
		if n % 3 == 0 then
			candle(ctx, cf * CFrame.new(0, h + 0.75, 0), Vector3.new(0.25, 0.5, 0.25), Color3.fromRGB(205, 195, 165), Color3.fromRGB(255, 180, 110), 7)
		end
	end

	-- 무너진 돌탑: 돌이 바닥에 흩어짐
	do
		local a = rng:NextNumber(0, math.pi * 2)
		local cf = L(ctx, math.cos(a) * 7.5, top, math.sin(a) * 7.5)
		for i = 1, 6 do
			local w = rng:NextNumber(0.6, 1.4)
			stone(ctx, cf * CFrame.new(rng:NextNumber(-2.5, 2.5), w * 0.15, rng:NextNumber(-2.5, 2.5)), Vector3.new(w, w * 0.3, w * 0.9), false)
		end
	end

	-- 색 바랜 천 장대 (서낭당 느낌)
	local pole = L(ctx, 3.2, 0, 6.8)
	part(ctx, {
		Name = "Pole",
		Size = Vector3.new(0.28, 7, 0.28),
		CFrame = pole * CFrame.new(0, top + 3.5, 0) * CFrame.Angles(math.rad(3), 0, math.rad(-4)),
		Color = DARK_WOOD,
		Material = Enum.Material.Wood,
	})
	local cloth = {
		Color3.fromRGB(120, 48, 44),
		Color3.fromRGB(50, 62, 96),
		Color3.fromRGB(150, 130, 70),
		Color3.fromRGB(190, 186, 170),
		Color3.fromRGB(40, 40, 44),
	}
	for i, col in cloth do
		local strip = part(ctx, {
			Name = "Cloth",
			Size = Vector3.new(0.5, rng:NextNumber(2.2, 3.4), 0.05),
			CFrame = pole * CFrame.new(0, top + 6.6, 0) * CFrame.Angles(0, math.rad(i * 72), 0) * CFrame.new(0.35, -1.5, 0) * CFrame.Angles(
				math.rad(rng:NextNumber(-14, 14)),
				0,
				math.rad(rng:NextNumber(4, 12))
			),
			Color = col,
			Material = Enum.Material.Fabric,
			Transparency = 0.1,
			CanCollide = false,
			CanQuery = false,
		})
		strip.CastShadow = false
	end
	-- 항아리 둘레 작은 돌 동그라미
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2
		local s = rng:NextNumber(0.4, 0.7)
		stone(ctx, L(ctx, math.cos(a) * 2.8, top + s * 0.25, math.sin(a) * 2.8), Vector3.new(s, s * 0.5, s * 0.8), false)
	end
	rubble(ctx, 18, 5, 12)
end

---------------------------------------------------------------- 3) 무너진 사당
-- Meshy 사당 메시(Assets 의 "Shrine")가 있으면 그걸 세우고 앞에 초·등·잔해만 놓는다
local function buildRuinMesh(ctx: Ctx): boolean
	local A = Config.Assets
	local mesh = Assets.spawn("Shrine", ctx.Model, { Height = A.ShrineHeight, CanCollide = false, CanQuery = true })
	if not mesh then
		return false
	end
	local top = ctx.Top
	-- 모델 앞(-Z)이 호수를 보게. Frame 의 LookVector 가 '뒤'이므로 그 반대를 보도록 yaw 계산
	local back = ctx.Frame.LookVector
	local yaw = math.atan2(back.X, back.Z) + math.rad(A.ShrineYaw)
	Assets.placeOnGround(mesh, L(ctx, 0, top, A.ShrineOffset).Position, yaw)
	-- 항아리 양옆 초, 왼쪽 앞에 붉은 등, 잔해
	for _, x in { -2.6, 2.6 } do
		candle(ctx, L(ctx, x, top + 0.4, -1.2), Vector3.new(0.3, 0.8, 0.3), Color3.fromRGB(205, 195, 165), Color3.fromRGB(255, 180, 110), 9)
	end
	local poleCF = L(ctx, -4.5, 0, -2.5)
	part(ctx, {
		Name = "LanternPole",
		Size = Vector3.new(0.25, 5.5, 0.25),
		CFrame = poleCF * CFrame.new(0, top + 2.75, 0) * CFrame.Angles(0, 0, math.rad(-3)),
		Color = DARK_WOOD,
		Material = Enum.Material.Wood,
	})
	part(ctx, {
		Name = "LanternArm",
		Size = Vector3.new(1.4, 0.15, 0.15),
		CFrame = poleCF * CFrame.new(0.6, top + 5.3, 0),
		Color = DARK_WOOD,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	local lantern = part(ctx, {
		Name = "PaperLantern",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.0, 1.0, 1.0),
		CFrame = poleCF * CFrame.new(1.2, top + 4.5, 0),
		Color = Color3.fromRGB(130, 36, 30),
		Material = Enum.Material.Neon,
		Transparency = 0.45,
		CanCollide = false,
		CanQuery = false,
	})
	table.insert(ctx.Lights, Util.pointLight(lantern, Color3.fromRGB(255, 90, 70), 11, 0))
	rubble(ctx, 10, 4, 9)
	return true
end

local function buildRuin(ctx: Ctx)
	if buildRuinMesh(ctx) then
		return
	end
	local rng = ctx.Rng
	local top = ctx.Top
	local W, D, H = 11, 9, 6 -- 건물 폭(x), 깊이(z), 기둥 높이

	-- 마루: 나무 바닥 (돌바닥 위에 얇게)
	part(ctx, {
		Name = "WoodFloor",
		Size = Vector3.new(W + 1, 0.12, D + 1),
		CFrame = L(ctx, 0, top + 0.06, 1.5),
		Color = OLD_WOOD,
		Material = Enum.Material.WoodPlanks,
		CanCollide = false,
	})

	-- 기둥 4개: 앞오른쪽은 부러짐, 앞왼쪽은 기울어짐
	local corners = {
		{ x = -W / 2, z = D / 2 + 1.5, kind = "ok" },
		{ x = W / 2, z = D / 2 + 1.5, kind = "ok" },
		{ x = -W / 2, z = -D / 2 + 1.5, kind = "lean" },
		{ x = W / 2, z = -D / 2 + 1.5, kind = "broken" },
	}
	for _, cn in corners do
		if cn.kind == "broken" then
			local bh = 2.3
			part(ctx, {
				Name = "PostBroken",
				Size = Vector3.new(0.9, bh, 0.9),
				CFrame = L(ctx, cn.x, top + bh / 2, cn.z) * CFrame.Angles(0, 0, math.rad(2)),
				Color = DARK_WOOD,
				Material = Enum.Material.Wood,
			})
			wedge(ctx, {
				Name = "Splinter",
				Size = Vector3.new(0.9, 1.1, 0.9),
				CFrame = L(ctx, cn.x, top + bh + 0.55, cn.z) * CFrame.Angles(0, math.rad(40), 0),
				Color = OLD_WOOD,
				Material = Enum.Material.Wood,
			})
			-- 떨어진 윗동강
			part(ctx, {
				Name = "PostFallen",
				Size = Vector3.new(0.9, 3.2, 0.9),
				CFrame = L(ctx, cn.x + 1.2, top + 0.5, cn.z - 2.2) * CFrame.Angles(math.rad(78), math.rad(20), 0),
				Color = DARK_WOOD,
				Material = Enum.Material.Wood,
				CanCollide = false,
			})
		else
			local lean = if cn.kind == "lean" then math.rad(7) else 0
			part(ctx, {
				Name = "Post",
				Size = Vector3.new(0.9, H, 0.9),
				CFrame = L(ctx, cn.x, top + H / 2, cn.z) * CFrame.Angles(0, 0, lean),
				Color = DARK_WOOD,
				Material = Enum.Material.Wood,
			})
		end
	end

	-- 대들보 (뒤쪽은 온전, 앞쪽은 한쪽이 내려앉음)
	part(ctx, {
		Name = "BeamBack",
		Size = Vector3.new(W + 1.6, 0.6, 0.7),
		CFrame = L(ctx, 0, top + H + 0.3, D / 2 + 1.5),
		Color = DARK_WOOD,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	part(ctx, {
		Name = "BeamLeft",
		Size = Vector3.new(0.7, 0.6, D + 1.6),
		CFrame = L(ctx, -W / 2, top + H + 0.3, 1.5),
		Color = DARK_WOOD,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	part(ctx, {
		Name = "BeamFront",
		Size = Vector3.new(W + 1.6, 0.6, 0.7),
		CFrame = L(ctx, 0.6, top + H - 1.4, -D / 2 + 1.5) * CFrame.Angles(0, 0, math.rad(-17)),
		Color = DARK_WOOD,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	part(ctx, {
		Name = "Ridge",
		Size = Vector3.new(W + 2.4, 0.5, 0.5),
		CFrame = L(ctx, 0, top + H + 3.2, 1.5),
		Color = DARK_WOOD,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})

	-- 지붕: 뒤쪽 경사면은 온전, 앞쪽 경사면은 반이 떨어져 나감
	local slopeD = D / 2 + 1.4
	local roofH = 3.0
	local tile = Color3.fromRGB(28, 30, 34)
	-- WedgePart 는 파트 +Z 쪽이 높고 -Z 쪽으로 내려감. L() 의 기본 방향은 파트 +Z 가 호수(앞) 쪽이므로
	-- 뒤 경사(용마루가 앞, 처마가 뒤)는 그대로, 앞 경사는 180° 돌린다.
	wedge(ctx, {
		Name = "RoofBack",
		Size = Vector3.new(W + 3, roofH, slopeD),
		CFrame = L(ctx, 0, top + H + 0.6 + roofH / 2, 1.5 + slopeD / 2),
		Color = tile,
		Material = Enum.Material.Slate,
	})
	-- 앞 경사 왼쪽 절반 (붙어 있음)
	wedge(ctx, {
		Name = "RoofFrontLeft",
		Size = Vector3.new((W + 3) / 2, roofH, slopeD),
		CFrame = L(ctx, -(W + 3) / 4, top + H + 0.6 + roofH / 2, 1.5 - slopeD / 2) * CFrame.Angles(0, math.rad(180), 0),
		Color = tile,
		Material = Enum.Material.Slate,
	})
	-- 앞 경사 오른쪽 절반: 부러진 기둥 쪽으로 미끄러져 내려앉음
	wedge(ctx, {
		Name = "RoofFrontRightFallen",
		Size = Vector3.new((W + 3) / 2, roofH, slopeD),
		CFrame = L(ctx, (W + 3) / 4 + 0.8, top + 2.4, 1.5 - slopeD / 2 - 1.6)
			* CFrame.Angles(0, math.rad(180), 0)
			* CFrame.Angles(math.rad(38), math.rad(6), math.rad(8)),
		Color = tile,
		Material = Enum.Material.Slate,
	})
	-- 처마 끝 기와선
	part(ctx, {
		Name = "EaveBack",
		Size = Vector3.new(W + 3.2, 0.3, 0.5),
		CFrame = L(ctx, 0, top + H + 0.55, 1.5 + slopeD),
		Color = Color3.fromRGB(40, 42, 46),
		CanCollide = false,
	})
	part(ctx, {
		Name = "EaveFrontLeft",
		Size = Vector3.new((W + 3) / 2 + 0.2, 0.3, 0.5),
		CFrame = L(ctx, -(W + 3) / 4, top + H + 0.55, 1.5 - slopeD),
		Color = Color3.fromRGB(40, 42, 46),
		CanCollide = false,
	})

	-- 벽: 뒷벽(흙벽, 금 감), 왼쪽 옆벽 일부
	part(ctx, {
		Name = "WallBack",
		Size = Vector3.new(W, H - 0.6, 0.4),
		CFrame = L(ctx, 0, top + (H - 0.6) / 2, D / 2 + 1.3),
		Color = Color3.fromRGB(82, 74, 60),
		Material = Enum.Material.Concrete,
	})
	part(ctx, {
		Name = "WallCrack",
		Size = Vector3.new(0.25, H - 1.6, 0.45),
		CFrame = L(ctx, 1.8, top + (H - 1.6) / 2 + 0.4, D / 2 + 1.3) * CFrame.Angles(0, 0, math.rad(9)),
		Color = Color3.fromRGB(16, 15, 14),
		CanCollide = false,
	})
	part(ctx, {
		Name = "WallLeft",
		Size = Vector3.new(0.4, H - 0.6, D * 0.55),
		CFrame = L(ctx, -W / 2 + 0.2, top + (H - 0.6) / 2, 1.5 + D * 0.22),
		Color = Color3.fromRGB(82, 74, 60),
		Material = Enum.Material.Concrete,
	})
	-- 오른쪽 옆벽은 무너져 아래 토막만
	part(ctx, {
		Name = "WallRightStub",
		Size = Vector3.new(0.4, 1.4, D * 0.5),
		CFrame = L(ctx, W / 2 - 0.2, top + 0.7, 1.5 + D * 0.25),
		Color = Color3.fromRGB(82, 74, 60),
		Material = Enum.Material.Concrete,
		CanCollide = false,
	})

	-- 찢어진 문짝 (앞 왼쪽, 비스듬히 기대어 있음)
	local door = L(ctx, -W / 2 + 2.6, top + 2.4, -D / 2 + 1.0) * CFrame.Angles(math.rad(-8), math.rad(18), 0)
	part(ctx, { Name = "DoorFrame", Size = Vector3.new(2.4, 4.8, 0.15), CFrame = door, Color = DARK_WOOD, Material = Enum.Material.Wood, CanCollide = false })
	local paper = part(ctx, {
		Name = "DoorPaper",
		Size = Vector3.new(2.0, 2.6, 0.05),
		CFrame = door * CFrame.new(0, 0.9, -0.08),
		Color = PAPER,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.15,
		CanCollide = false,
		CanQuery = false,
	})
	paper.CastShadow = false
	for i = 1, 3 do
		part(ctx, {
			Name = "Lattice",
			Size = Vector3.new(0.08, 4.6, 0.08),
			CFrame = door * CFrame.new(-0.8 + i * 0.4 + 0.2, 0, -0.1),
			Color = DARK_WOOD,
			Material = Enum.Material.Wood,
			CanCollide = false,
			CanQuery = false,
		})
	end
	for i = 1, 5 do
		part(ctx, {
			Name = "Lattice",
			Size = Vector3.new(2.3, 0.08, 0.08),
			CFrame = door * CFrame.new(0, -2.0 + i * 0.75, -0.1),
			Color = DARK_WOOD,
			Material = Enum.Material.Wood,
			CanCollide = false,
			CanQuery = false,
		})
	end

	-- 안쪽 제사상: 뒷벽 앞 낮은 상 + 초 + 빛바랜 초상(액자)
	part(ctx, {
		Name = "Table",
		Size = Vector3.new(4.6, 0.25, 1.4),
		CFrame = L(ctx, 0, top + 1.55, D / 2 + 0.3),
		Color = DARK_WOOD,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	for _, x in { -1.6, 1.6 } do
		part(ctx, {
			Name = "TableLeg",
			Size = Vector3.new(0.3, 1.45, 1.1),
			CFrame = L(ctx, x, top + 0.72, D / 2 + 0.3),
			Color = DARK_WOOD,
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
	end
	for _, x in { -1.5, 1.5 } do
		candle(ctx, L(ctx, x, top + 1.68 + 0.4, D / 2 + 0.3), Vector3.new(0.3, 0.8, 0.3), Color3.fromRGB(205, 195, 165), Color3.fromRGB(255, 180, 110), 9)
	end
	part(ctx, {
		Name = "Frame",
		Size = Vector3.new(1.6, 2.0, 0.12),
		CFrame = L(ctx, 0, top + 3.6, D / 2 + 1.05) * CFrame.Angles(0, 0, math.rad(-4)),
		Color = Color3.fromRGB(26, 22, 20),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	part(ctx, {
		Name = "Portrait",
		Size = Vector3.new(1.3, 1.7, 0.06),
		CFrame = L(ctx, 0, top + 3.6, D / 2 + 0.96) * CFrame.Angles(0, 0, math.rad(-4)),
		Color = Color3.fromRGB(150, 140, 120),
		Material = Enum.Material.Fabric,
		CanCollide = false,
		CanQuery = false,
	})
	part(ctx, {
		Name = "PortraitFace",
		Size = Vector3.new(0.5, 0.7, 0.04),
		CFrame = L(ctx, 0, top + 3.8, D / 2 + 0.92) * CFrame.Angles(0, 0, math.rad(-4)),
		Color = Color3.fromRGB(60, 52, 48),
		Material = Enum.Material.Fabric,
		CanCollide = false,
		CanQuery = false,
	})

	-- 앞 대들보에 매달린 붉은 등 (항아리 차면 켜짐)
	local lanternCF = L(ctx, -2.2, top + H - 2.4, -D / 2 + 1.5)
	Util.segment(
		lanternCF.Position + Vector3.new(0, 1.2, 0),
		lanternCF.Position + Vector3.new(0, 0.5, 0),
		0.06,
		{ Name = "LanternString", Color = DARK_WOOD, CanCollide = false, CanQuery = false, Parent = ctx.Model }
	)
	local lantern = part(ctx, {
		Name = "PaperLantern",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.1, 1.1, 1.1),
		CFrame = lanternCF,
		Color = Color3.fromRGB(130, 36, 30),
		Material = Enum.Material.Neon,
		Transparency = 0.45,
		CanCollide = false,
		CanQuery = false,
	})
	table.insert(ctx.Lights, Util.pointLight(lantern, Color3.fromRGB(255, 90, 70), 11, 0))

	-- 깨진 기와·잔해 (앞마당)
	for _ = 1, 12 do
		local x = rng:NextNumber(-W / 2 - 2, W / 2 + 3)
		local z = rng:NextNumber(-D / 2 - 5, -D / 2 + 1)
		local t = part(ctx, {
			Name = "TileShard",
			Size = Vector3.new(rng:NextNumber(0.6, 1.1), 0.12, rng:NextNumber(0.4, 0.8)),
			CFrame = L(ctx, x, top + 0.08, z)
				* CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-12, 12))),
			Color = tile,
			CanCollide = false,
		})
		t.CastShadow = false
	end
	rubble(ctx, 8, 7, 11)
end

---------------------------------------------------------------- 진입점
local BUILDERS: { [string]: (Ctx) -> () } = {
	Altar = buildAltar,
	Cairn = buildCairn,
	Ruin = buildRuin,
}

-- kind: "Altar" | "Cairn" | "Ruin". approach: 길이 들어오는 수평 단위 벡터들.
-- 돌려주는 값: 항아리가 차면 밝아질 PointLight 목록
function ShrineBuilder.decorate(kind: string, model: Model, center: Vector3, top: number, approach: { Vector3 }, seed: number): { PointLight }
	local lakeDir = (center - Config.Map.LakeCenter) * Vector3.new(1, 0, 1)
	local back = if lakeDir.Magnitude > 0.1 then lakeDir.Unit else Vector3.new(0, 0, -1)
	local ctx: Ctx = {
		Model = model,
		Center = center,
		Top = top,
		Frame = CFrame.lookAt(center, center + back),
		Rng = Random.new(seed),
		Approach = approach,
		Lights = {},
	}
	local builder = BUILDERS[kind] or buildAltar
	builder(ctx)
	return ctx.Lights
end

return ShrineBuilder
