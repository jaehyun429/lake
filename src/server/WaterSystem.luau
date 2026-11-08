-- 물 긷기 / 양동이 운반 / 제단에 붓기 / 양동이 버리기
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.DeadLake.Shared.Config)
local Util = require(script.Parent.Util)
local Net = require(script.Parent.Net)
local PlayerState = require(script.Parent.PlayerState)
local Assets = require(script.Parent.Assets)

type FillState = { Station: any, StartPos: Vector3, Progress: number, Active: boolean }

local WaterSystem = {}
local map: any
local ctx: { isPlaying: () -> boolean, onDelivered: (Player) -> () }
local fills: { [Player]: FillState } = {}

local function stopFilling(player: Player, f: FillState?)
	if f then
		f.Active = false
	end
	player:SetAttribute("Filling", false)
end

function WaterSystem.isFilling(player: Player): boolean
	local f = fills[player]
	return f ~= nil and f.Active
end

-- 양동이를 왼손(없으면 몸통)에 붙임. 1인칭에서는 본인에게 안 보이고 HUD 로 표시.
local function attachBucket(player: Player)
	local char = player.Character
	if not char then
		return
	end
	local holder = (char:FindFirstChild("LeftHand") or char:FindFirstChild("Left Arm") or char:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if not holder then
		return
	end
	local bucket = Instance.new("Model")
	bucket.Name = "Bucket"

	-- Bucket 메시가 있으면 그것을 손에 매닮
	local mesh =
		Assets.spawn("Bucket", bucket, { Height = Config.Assets.BucketHeight, Anchored = false, CanCollide = false, CanQuery = false, Massless = true })
	if mesh then
		Assets.placeCenter(mesh, holder.CFrame * CFrame.new(0, -1.6, 0))
		local bcf, size = mesh:GetBoundingBox()
		local d = math.max(0.6, math.min(size.X, size.Z) * 0.6)
		local meshWater = Util.part({
			Name = "Water",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, d, d),
			Color = Color3.fromRGB(30, 60, 80),
			Material = Enum.Material.Glass,
			Transparency = 0.25,
			Reflectance = 0.2,
			Anchored = false,
			CanCollide = false,
			CanQuery = false,
			Massless = true,
			Parent = bucket,
		})
		meshWater.CFrame = bcf * CFrame.new(0, size.Y * 0.3, 0) * CFrame.Angles(0, 0, math.rad(90))
		Assets.weldTo(mesh, holder)
		local w = Instance.new("WeldConstraint")
		w.Part0 = holder
		w.Part1 = meshWater
		w.Parent = meshWater
		bucket.Parent = char
		return
	end

	local body = Util.part({
		Name = "Body",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.7, 1.5, 1.5),
		Color = Color3.fromRGB(60, 64, 70),
		Material = Enum.Material.Metal,
		Anchored = false,
		CanCollide = false,
		Massless = true,
		Parent = bucket,
	})
	body.CFrame = holder.CFrame * CFrame.new(0, -1.5, 0) * CFrame.Angles(0, 0, math.rad(90))
	local water = Util.part({
		Name = "Water",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 1.3, 1.3),
		Color = Color3.fromRGB(30, 60, 80),
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		Reflectance = 0.2,
		Anchored = false,
		CanCollide = false,
		Massless = true,
		Parent = bucket,
	})
	water.CFrame = body.CFrame * CFrame.new(0.7, 0, 0)
	for _, p in { body, water } do
		local w = Instance.new("WeldConstraint")
		w.Part0 = holder
		w.Part1 = p
		w.Parent = p
	end
	bucket.Parent = char
end

function WaterSystem.giveBucket(player: Player)
	player:SetAttribute("Carrying", true)
	attachBucket(player)
	PlayerState.applySpeed(player)
	Net.notify(player, "양동이를 채웠습니다. 제단으로 가져가세요. (느려짐 · G 로 버리기)", 4)
	Net.send(player, "Sfx", "Fill")
end

function WaterSystem.dropBucket(player: Player, spill: boolean?)
	local had = player:GetAttribute("Carrying") == true
	player:SetAttribute("Carrying", false)
	local char = player.Character
	local bucket = char and char:FindFirstChild("Bucket")
	if bucket then
		bucket:Destroy()
	end
	PlayerState.applySpeed(player)
	if had and spill then
		Net.notify(player, "물을 쏟았습니다.", 2.5)
		local root = PlayerState.getRoot(player)
		if root then
			Util.playAt(root.Position, Config.Sounds.Splash, 0.6, 1.2)
		end
	end
end

function WaterSystem.toggleFill(player: Player, st: any)
	if not ctx.isPlaying() or not PlayerState.isAlive(player) then
		return
	end
	local f = fills[player]
	if f and f.Active then
		stopFilling(player, f)
		Net.notify(player, "물 긷기를 중단했습니다. 게이지가 서서히 줄어듭니다.", 2)
		return
	end
	if player:GetAttribute("Carrying") then
		Net.notify(player, "이미 양동이를 들고 있습니다. 제단에 먼저 부으세요.", 2.5)
		return
	end
	local root = PlayerState.getRoot(player)
	if not root or (root.Position - st.Point).Magnitude > Config.Fill.Range + 2 then
		return
	end
	if not f then
		f = { Station = st, StartPos = root.Position, Progress = 0, Active = false }
		fills[player] = f
	end
	if f.Station ~= st then
		f.Progress = 0
	end
	f.Station = st
	f.StartPos = root.Position
	f.Active = true
	player:SetAttribute("Filling", true)
	player:SetAttribute("StationName", st.Name)
	Net.notify(player, string.format("%s에서 물을 긷는 중... 가만히 서 있으세요", st.Name), 2.5)
end

function WaterSystem.tryDeliver(player: Player)
	if not ctx.isPlaying() or not PlayerState.isAlive(player) then
		return
	end
	if player:GetAttribute("Carrying") ~= true then
		Net.notify(player, "들고 있는 양동이가 없습니다.", 2)
		return
	end
	local root = PlayerState.getRoot(player)
	if not root or (root.Position - map.Altar.Position).Magnitude > 12 then
		return
	end
	WaterSystem.dropBucket(player, false)
	Util.playAt(map.Altar.Position, Config.Sounds.Pour, 0.8, 1.1)
	Net.send(player, "Sfx", "Pour")
	ctx.onDelivered(player)
end

function WaterSystem.resetPlayer(player: Player)
	fills[player] = nil
	player:SetAttribute("Fill", 0)
	player:SetAttribute("Filling", false)
	WaterSystem.dropBucket(player, false)
end

function WaterSystem.resetAll()
	for _, player in Players:GetPlayers() do
		WaterSystem.resetPlayer(player)
	end
end

function WaterSystem.update(dt: number)
	local F = Config.Fill
	for player, f in fills do
		local root = PlayerState.getRoot(player)
		if f.Active then
			local moved = if root then (root.Position - f.StartPos).Magnitude else math.huge
			if not root or not PlayerState.isAlive(player) or not ctx.isPlaying() then
				stopFilling(player, f)
			elseif moved > F.Range then
				stopFilling(player, f)
				Net.notify(player, "물가에서 너무 멀어져 긷기가 중단됐습니다.", 2)
			elseif moved > F.MoveTolerance then
				f.Progress = math.max(0, f.Progress - F.DecayPerSecond * dt)
			else
				f.Progress += dt / F.Time * (f.Station.Def.FillMult :: number)
				if f.Progress >= 1 then
					f.Progress = 0
					stopFilling(player, f)
					WaterSystem.giveBucket(player)
				end
			end
		else
			f.Progress = math.max(0, f.Progress - F.DecayPerSecond * dt)
			if f.Progress <= 0 then
				fills[player] = nil
			end
		end
		player:SetAttribute("Fill", f.Progress)
	end
end

function WaterSystem.init(mapInfo: any, context: typeof(ctx))
	map = mapInfo
	ctx = context
	for _, st in map.Stations do
		st.Prompt.Triggered:Connect(function(player: Player)
			WaterSystem.toggleFill(player, st)
		end)
	end
	map.AltarPrompt.Triggered:Connect(function(player: Player)
		WaterSystem.tryDeliver(player)
	end)
	Net.on("DropBucket", function(player)
		if PlayerState.isAlive(player) and player:GetAttribute("Carrying") == true then
			WaterSystem.dropBucket(player, true)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		fills[player] = nil
	end)
end

return WaterSystem
