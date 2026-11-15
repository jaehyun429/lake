-- 관리자(테스트) 모드: P 키로 켜고 끔. 켜면 그 사람 화면만 대낮처럼 밝아짐 (다른 플레이어에겐 영향 없음).
-- 허용 대상: Studio 안, 플레이스 소유자, Config.Admin.Users 에 적힌 이름. 그 외에는 요청을 무시한다.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.DeadLake.Shared.Config)
local Net = require(script.Parent.Net)

local AdminSystem = {}

function AdminSystem.isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId then
		return true
	end
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(game.CreatorId)
		end)
		if ok and rank >= Config.Admin.GroupRank then
			return true
		end
	end
	for _, name in Config.Admin.Users do
		if name == player.Name or name == player.DisplayName then
			return true
		end
	end
	return false
end

function AdminSystem.init()
	Net.on("Admin", function(player)
		if not AdminSystem.isAdmin(player) then
			return
		end
		local on = player:GetAttribute("Admin") ~= true
		player:SetAttribute("Admin", on)
		Net.notify(player, if on then "관리자 모드 켜짐: 화면이 밝아집니다 (P 로 끄기)" else "관리자 모드 꺼짐", 2.5)
	end)
end

return AdminSystem
