-- 플레이어 상태(Attribute) 헬퍼. Status: Lobby | Alive | Grabbed | Dead | Escaped
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.DeadLake.Shared.Config)

local PlayerState = {}

function PlayerState.setStatus(player: Player, status: string)
	player:SetAttribute("Status", status)
end

function PlayerState.getStatus(player: Player): string
	return (player:GetAttribute("Status") :: string?) or "Lobby"
end

function PlayerState.isAlive(player: Player): boolean
	return PlayerState.getStatus(player) == "Alive"
end

-- 살아있는 캐릭터의 루트/휴머노이드 반환 (없으면 nil)
function PlayerState.getRoot(player: Player): (BasePart?, Humanoid?)
	local char = player.Character
	if not char then
		return nil, nil
	end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if root and hum and hum.Health > 0 then
		return root, hum
	end
	return nil, nil
end

-- 달리기/양동이 상태를 반영해 이동 속도 적용
function PlayerState.applySpeed(player: Player)
	local _, hum = PlayerState.getRoot(player)
	if not hum then
		return
	end
	local P = Config.Player
	local speed = if player:GetAttribute("Sprinting") == true then P.SprintSpeed else P.WalkSpeed
	if player:GetAttribute("Carrying") == true then
		speed *= P.CarrySpeedMult
	end
	hum.WalkSpeed = speed
end

return PlayerState
