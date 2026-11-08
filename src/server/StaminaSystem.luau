-- 달리기 스태미나: Shift 를 오래 누르면 줄고, 놓으면 회복. 바닥나면 서버가 달리기를 끔.
-- 값은 Player 속성 "Stamina"(0~1) 로 클라이언트에 전달되어 HUD 바로 표시됨.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.DeadLake.Shared.Config)
local PlayerState = require(script.Parent.PlayerState)

local StaminaSystem = {}
local stamina: { [Player]: number } = {}
local exhausted: { [Player]: boolean } = {}

function StaminaSystem.canSprint(player: Player): boolean
	return not exhausted[player] and (stamina[player] or 1) > 0.02
end

function StaminaSystem.reset(player: Player)
	stamina[player] = 1
	exhausted[player] = false
	player:SetAttribute("Stamina", 1)
end

local function publish(player: Player, value: number)
	local prev = player:GetAttribute("Stamina") :: number?
	if prev == nil or math.abs(prev - value) >= 0.004 or value == 0 or value == 1 then
		player:SetAttribute("Stamina", value)
	end
end

function StaminaSystem.update(dt: number)
	local P = Config.Player
	for _, player in Players:GetPlayers() do
		local s = stamina[player] or 1
		if not PlayerState.isAlive(player) then
			if s ~= 1 then
				StaminaSystem.reset(player)
			end
			continue
		end
		local root = PlayerState.getRoot(player)
		local moving = root ~= nil and (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude > 1.5
		if player:GetAttribute("Sprinting") == true and moving then
			s -= dt / P.SprintStaminaTime
			if s <= 0 then
				s = 0
				exhausted[player] = true
				player:SetAttribute("Sprinting", false)
				PlayerState.applySpeed(player)
			end
		else
			s = math.min(1, s + dt / P.SprintRegenTime)
			if exhausted[player] and s >= P.SprintMinToStart then
				exhausted[player] = false
			end
		end
		stamina[player] = s
		publish(player, s)
	end
end

function StaminaSystem.init()
	Players.PlayerRemoving:Connect(function(player)
		stamina[player] = nil
		exhausted[player] = nil
	end)
end

return StaminaSystem
