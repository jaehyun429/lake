-- 살목지(Dead Lake) 서버 진입점
local RunService = game:GetService("RunService")

local MapBuilder = require(script.Parent.MapBuilder)
local WaterSystem = require(script.Parent.WaterSystem)
local GhostSystem = require(script.Parent.GhostSystem)
local RoundManager = require(script.Parent.RoundManager)
local LanternSystem = require(script.Parent.LanternSystem)
local TrapSystem = require(script.Parent.TrapSystem)
local StaminaSystem = require(script.Parent.StaminaSystem)

local map = MapBuilder.build()

WaterSystem.init(map, {
	isPlaying = RoundManager.isPlaying,
	onDelivered = RoundManager.onDelivered,
})

LanternSystem.init()

GhostSystem.init(map, {
	isPlaying = RoundManager.isPlaying,
	isFilling = WaterSystem.isFilling,
	isSprinting = function(player: Player)
		return player:GetAttribute("Sprinting") == true
	end,
	isLanternOn = LanternSystem.isOn,
	dropBucket = WaterSystem.dropBucket,
	onPlayerDragged = RoundManager.onPlayerDied,
})

TrapSystem.init(map, {
	onTriggered = GhostSystem.alert,
})

RoundManager.init(map, WaterSystem, GhostSystem)
StaminaSystem.init()

RunService.Heartbeat:Connect(function(dt)
	WaterSystem.update(dt)
	GhostSystem.update(dt)
	StaminaSystem.update(dt)
end)

RoundManager.start()
print("[DeadLake] 서버 시작: 맵 생성 완료, 라운드 루프 가동")
