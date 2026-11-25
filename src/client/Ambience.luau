-- 소리 연출: 밤 풀벌레, 호숫가 물결, 위협 저음, 추격 음악, 멀리서 들리는 소리
-- 전부 내 화면(클라이언트)에서만 재생. 크기는 Config.Audio, 소리 ID 는 Config.Sounds
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.DeadLake.Shared.Config)
local A = Config.Audio
local M = Config.Map

local Ambience = {}
local player = Players.LocalPlayer
local rng = Random.new()

local night: Sound
local lake: Sound
local drone: Sound
local chase: Sound
local threat = 0
local hunted = false

local function loop(name: string, id: string): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Looped = true
	s.Volume = 0
	s.Parent = SoundService
	s:Play()
	return s
end

-- 위치 없는(2D) 일회성 소리. seconds 를 주면 그 시간 뒤 잘라냄(긴 소리용)
function Ambience.play(id: string, volume: number, pitch: number, seconds: number?)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = pitch
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	if seconds then
		Debris:AddItem(s, seconds)
	end
end

function Ambience.setThreat(value: number)
	threat = value
end

function Ambience.setHunted(on: boolean)
	hunted = on
end

-- 플레이어 주변 먼 곳에서 나는 소리 (어느 쪽에서 났는지 방향이 느껴짐)
local function playDistant()
	local cam = workspace.CurrentCamera
	local list = Config.Sounds.Distant
	if not cam or #list == 0 or A.DistantVolume <= 0 then
		return
	end
	local angle = rng:NextNumber(0, math.pi * 2)
	local dist = rng:NextNumber(A.DistantRange[1], A.DistantRange[2])
	local part = Instance.new("Part")
	part.Name = "DistantSound"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = cam.CFrame.Position + Vector3.new(math.cos(angle) * dist, 6, math.sin(angle) * dist)
	part.Parent = workspace
	local s = Instance.new("Sound")
	s.SoundId = list[rng:NextInteger(1, #list)]
	s.Volume = A.DistantVolume
	s.PlaybackSpeed = rng:NextNumber(0.9, 1.05)
	s.RollOffMode = Enum.RollOffMode.Linear
	s.RollOffMinDistance = 20
	s.RollOffMaxDistance = A.DistantRange[2] * 2.2
	s.Parent = part
	s:Play()
	Debris:AddItem(part, 20)
end

function Ambience.init()
	night = loop("Night", Config.Sounds.Night)
	lake = loop("Lake", Config.Sounds.Lake)
	drone = loop("Drone", Config.Sounds.Drone)
	chase = loop("Chase", Config.Sounds.Chase)

	RunService.Heartbeat:Connect(function(dt: number)
		local k = math.min(1, dt * 2)
		-- 호숫가에 가까울수록 물결 소리가 큼
		local lakeTarget = 0
		local cam = workspace.CurrentCamera
		if cam then
			local d = cam.CFrame.Position - M.LakeCenter
			local fromShore = math.abs(Vector3.new(d.X, 0, d.Z).Magnitude - M.LakeRadius)
			lakeTarget = math.clamp(1 - fromShore / A.LakeFalloff, 0, 1) * A.LakeVolume
		end
		local alive = player:GetAttribute("Status") ~= "Dead"
		local chaseTarget = if hunted and alive then A.ChaseVolume else 0
		-- 쫓길 때는 풀벌레가 잦아들고 음악이 올라옴
		night.Volume += ((if chaseTarget > 0 then 0.3 else 1) * A.NightVolume - night.Volume) * k
		lake.Volume += (lakeTarget - lake.Volume) * k
		drone.Volume += (math.clamp(threat, 0, 1) * A.DroneVolume - drone.Volume) * k
		chase.Volume += (chaseTarget - chase.Volume) * math.min(1, dt * (if chaseTarget > 0 then 3 else 0.6))
	end)

	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(A.DistantInterval[1], A.DistantInterval[2]))
			playDistant()
		end
	end)
end

return Ambience
