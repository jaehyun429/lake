-- 덫: 매 라운드 길 위에 랜덤 배치. 밟으면 발이 묶이고 귀신이 그 자리로 달려온다. 랜턴 빛에만 드러나는 어두운 색.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.DeadLake.Shared.Config)
local Util = require(script.Parent.Util)
local Net = require(script.Parent.Net)
local PlayerState = require(script.Parent.PlayerState)

local T = Config.Traps
local M = Config.Map

local TrapSystem = {}
local map: any
local ctx: { onTriggered: (Player, Vector3) -> () }
local folder: Folder?
local traps: { { Model: Model, Position: Vector3, Armed: boolean, Jaws: { BasePart } } } = {}
local rng = Random.new()

local function buildTrap(parent: Instance, pos: Vector3): (Model, { BasePart })
	local m = Instance.new("Model")
	m.Name = "Trap"
	Util.part({
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.25, 3.2, 3.2),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(22, 20, 18),
		Material = Enum.Material.Metal,
		Reflectance = 0.15,
		CanCollide = false,
		Parent = m,
	})
	Util.part({
		Name = "Plate",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 1.4, 1.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(70, 64, 56),
		Material = Enum.Material.Metal,
		Reflectance = 0.25,
		CanCollide = false,
		Parent = m,
	})
	local jaws = {}
	for _, s in { -1, 1 } do
		local jaw = Util.part({
			Name = "Jaw",
			Size = Vector3.new(3.0, 0.15, 0.6),
			CFrame = CFrame.new(pos + Vector3.new(0, 0.3, s * 1.3)) * CFrame.Angles(math.rad(s * 8), 0, 0),
			Color = Color3.fromRGB(90, 86, 80),
			Material = Enum.Material.Metal,
			Reflectance = 0.3,
			CanCollide = false,
			Parent = m,
		})
		for i = -2, 2 do
			Util.part({
				Name = "Tooth",
				Size = Vector3.new(0.18, 0.5, 0.18),
				CFrame = jaw.CFrame * CFrame.new(i * 0.6, 0.3, 0),
				Color = Color3.fromRGB(110, 105, 95),
				Material = Enum.Material.Metal,
				Reflectance = 0.3,
				CanCollide = false,
				Parent = m,
			}).Parent =
				jaw
		end
		table.insert(jaws, jaw)
	end
	-- 감지 영역
	local sensor = Util.part({
		Name = "Sensor",
		Size = Vector3.new(2.6, 2, 2.6),
		Position = pos + Vector3.new(0, 1, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = m,
	})
	m.PrimaryPart = sensor
	m.Parent = parent
	return m, jaws
end

local function setJaws(trap: any, closed: boolean)
	for _, jaw in trap.Jaws do
		local s = if jaw.Position.Z > trap.Position.Z then 1 else -1
		local goal = if closed
			then CFrame.new(trap.Position + Vector3.new(0, 0.9, s * 0.25)) * CFrame.Angles(math.rad(s * 80), 0, 0)
			else CFrame.new(trap.Position + Vector3.new(0, 0.3, s * 1.3)) * CFrame.Angles(math.rad(s * 8), 0, 0)
		Util.tween(jaw, if closed then 0.08 else 0.6, { CFrame = goal }, if closed then Enum.EasingStyle.Linear else Enum.EasingStyle.Sine)
	end
end

local function trigger(trap: any, player: Player)
	if not trap.Armed then
		return
	end
	trap.Armed = false
	setJaws(trap, true)
	Util.playAt(trap.Position, Config.Sounds.TrapSnap, 1, 0.6)
	local _, hum = PlayerState.getRoot(player)
	if hum then
		-- 발이 묶임: 잠시 이동 불가
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		task.delay(Config.Player.TrapSlowTime, function()
			if hum.Parent then
				hum.JumpPower = 50
				PlayerState.applySpeed(player)
			end
		end)
	end
	Net.send(player, "Trapped", { Time = Config.Player.TrapSlowTime })
	Net.notify(player, "덫을 밟았다! 쇳소리가 호수까지 울려 퍼졌다...", 3)
	ctx.onTriggered(player, trap.Position)
	task.delay(T.RearmTime, function()
		if trap.Model.Parent then
			trap.Armed = true
			setJaws(trap, false)
		end
	end)
end

function TrapSystem.clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(traps)
end

-- 길 위에 count 개 배치. 캠프·제단·물가 바로 앞은 비움.
function TrapSystem.spawn(count: number)
	TrapSystem.clear()
	local f = Instance.new("Folder")
	f.Name = "Traps"
	f.Parent = map.Folder
	folder = f

	local segs = map.PathSegments :: { { Vector3 } }
	local totalLen = 0
	for _, seg in segs do
		totalLen += (seg[2] - seg[1]).Magnitude
	end
	local placed: { Vector3 } = {}
	local tries = 0
	while #placed < count and tries < count * 40 do
		tries += 1
		-- 길이에 비례해 세그먼트 선택
		local pick = rng:NextNumber(0, totalLen)
		local seg = segs[#segs]
		for _, sg in segs do
			local l = (sg[2] - sg[1]).Magnitude
			if pick <= l then
				seg = sg
				break
			end
			pick -= l
		end
		local a, b = seg[1], seg[2]
		local dir = (b - a).Unit
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local t = rng:NextNumber(0.08, 0.92)
		local pos = a:Lerp(b, t) + side * rng:NextNumber(-T.PathSpread, T.PathSpread)
		local ok = (pos - M.CampCenter * Vector3.new(1, 0, 1)).Magnitude > M.SafeRadius + 6
			and (pos - M.AltarCenter * Vector3.new(1, 0, 1)).Magnitude > 14
			and ((pos - M.LakeCenter) * Vector3.new(1, 0, 1)).Magnitude > M.LakeRadius + 6
		if ok then
			for _, st in map.Stations do
				if ((st.Point - pos) * Vector3.new(1, 0, 1)).Magnitude < 10 then
					ok = false
				end
			end
		end
		if ok then
			for _, q in placed do
				if (q - pos).Magnitude < T.MinSpacing then
					ok = false
					break
				end
			end
		end
		if ok then
			table.insert(placed, pos)
			local model, jaws = buildTrap(f, pos)
			local trap = { Model = model, Position = pos, Armed = true, Jaws = jaws }
			table.insert(traps, trap)
			local sensor = model.PrimaryPart :: BasePart
			sensor.Touched:Connect(function(hit: BasePart)
				local char = hit.Parent
				local player = char and Players:GetPlayerFromCharacter(char)
				if
					player
					and PlayerState.isAlive(player)
					and (
						hit.Name == "LeftFoot"
						or hit.Name == "RightFoot"
						or hit.Name == "Left Leg"
						or hit.Name == "Right Leg"
						or hit.Name == "HumanoidRootPart"
					)
				then
					trigger(trap, player)
				end
			end)
		end
	end
end

function TrapSystem.init(mapInfo: any, context: typeof(ctx))
	map = mapInfo
	ctx = context
end

return TrapSystem
