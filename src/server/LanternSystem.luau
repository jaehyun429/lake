-- 랜턴: Tool 로 지급(1인칭에서도 보임). F 또는 클릭으로 켜고 끔. 켜면 덫이 보이지만 귀신에게 발각된다.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.DeadLake.Shared.Config)
local Util = require(script.Parent.Util)
local Net = require(script.Parent.Net)

local L = Config.Lantern
local LanternSystem = {}

local function buildTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "랜턴"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = "F: 켜기/끄기"
	tool.Grip = CFrame.new(0, -0.6, 0) * CFrame.Angles(0, 0, math.rad(0))

	local handle = Util.part({
		Name = "Handle",
		Size = Vector3.new(0.9, 1.4, 0.9),
		Color = Color3.fromRGB(40, 38, 36),
		Material = Enum.Material.Metal,
		Anchored = false,
		CanCollide = false,
		Massless = true,
		Parent = tool,
	})
	local glass = Util.part({
		Name = "Glass",
		Size = Vector3.new(0.7, 0.9, 0.7),
		Color = Color3.fromRGB(255, 190, 110),
		Material = Enum.Material.Neon,
		Transparency = 0.9,
		Anchored = false,
		CanCollide = false,
		Massless = true,
		Parent = tool,
	})
	glass.CFrame = handle.CFrame
	local ring = Util.part({
		Name = "Ring",
		Size = Vector3.new(0.15, 0.6, 0.15),
		Color = Color3.fromRGB(60, 58, 56),
		Material = Enum.Material.Metal,
		Anchored = false,
		CanCollide = false,
		Massless = true,
		Parent = tool,
	})
	ring.CFrame = handle.CFrame * CFrame.new(0, 1.0, 0)
	for _, p in { glass, ring } do
		local w = Instance.new("WeldConstraint")
		w.Part0 = handle
		w.Part1 = p
		w.Parent = p
	end
	-- 발밑 약한 빛. 앞쪽 원뿔 빛은 머리(다른 플레이어용)와 카메라(본인용, 클라이언트)에 붙는다
	local light = Instance.new("PointLight")
	light.Name = "Light"
	light.Color = Color3.fromRGB(255, 185, 110)
	light.Range = L.NearRange
	light.Brightness = 0
	light.Shadows = false
	light.Parent = handle
	return tool
end

-- 다른 플레이어 눈에 보이는 원뿔 빛. 머리 앞면에서 나감 (본인 화면에서는 클라이언트가 끄고 카메라 빛을 씀)
local function headBeam(char: Model?): SpotLight?
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if not head then
		return nil
	end
	local beam = head:FindFirstChild("LanternBeam") :: SpotLight?
	if not beam then
		beam = Instance.new("SpotLight")
		beam.Name = "LanternBeam"
		beam.Face = Enum.NormalId.Front
		beam.Color = Color3.fromRGB(255, 190, 120)
		beam.Angle = L.Angle
		beam.Range = L.Range
		beam.Brightness = 0
		beam.Shadows = true
		beam.Parent = head
	end
	return beam
end

local function applyState(player: Player, on: boolean)
	player:SetAttribute("LanternOn", on)
	local char = player.Character
	local beam = headBeam(char)
	if beam then
		beam.Brightness = if on then L.Brightness else L.OffGlow
		beam.Angle = L.Angle
		beam.Range = L.Range
	end
	local tool = char and char:FindFirstChild("랜턴") or player.Backpack:FindFirstChild("랜턴")
	if not tool then
		return
	end
	local handle = tool:FindFirstChild("Handle")
	local light = handle and handle:FindFirstChild("Light") :: PointLight?
	local glass = tool:FindFirstChild("Glass") :: BasePart?
	if light then
		light.Brightness = if on then L.NearBrightness else 0
		light.Range = L.NearRange
	end
	if glass then
		glass.Transparency = if on then 0.1 else 0.9
	end
end

function LanternSystem.isOn(player: Player): boolean
	return player:GetAttribute("LanternOn") == true
end

function LanternSystem.set(player: Player, on: boolean)
	if LanternSystem.isOn(player) == on then
		return
	end
	applyState(player, on)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		Util.playAt(root.Position, Config.Sounds.Click, 0.5, if on then 1.4 else 1.1)
	end
	Net.send(player, "Lantern", { On = on })
end

function LanternSystem.toggle(player: Player)
	LanternSystem.set(player, not LanternSystem.isOn(player))
end

-- 캐릭터 스폰 시 지급
function LanternSystem.give(player: Player, char: Model)
	local old = player.Backpack:FindFirstChild("랜턴")
	if old then
		old:Destroy()
	end
	local tool = buildTool()
	tool.Activated:Connect(function()
		LanternSystem.toggle(player)
	end)
	tool.Parent = player.Backpack
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		task.defer(function()
			hum:EquipTool(tool)
		end)
	end
	applyState(player, L.StartOn)
	Net.send(player, "Lantern", { On = L.StartOn })
end

function LanternSystem.init()
	Net.on("Lantern", function(player, data)
		if type(data) == "table" and type(data.On) == "boolean" then
			LanternSystem.set(player, data.On)
		else
			LanternSystem.toggle(player)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("LanternOn", false)
	end)
end

return LanternSystem
