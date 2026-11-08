-- 탈락/탈출한 플레이어의 관전 카메라. ← → 로 대상 전환.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Spectate = {}
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local active = false
local targetIndex = 1
local onTargetChanged: ((string) -> ())? = nil

local function aliveTargets(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p ~= player then
			local st = p:GetAttribute("Status")
			local char = p.Character
			if (st == "Alive" or st == "Grabbed") and char and char:FindFirstChildOfClass("Humanoid") then
				table.insert(list, p)
			end
		end
	end
	return list
end

local function apply()
	if not active then
		return
	end
	local targets = aliveTargets()
	if #targets == 0 then
		camera.CameraType = Enum.CameraType.Scriptable
		-- 호수를 내려다보는 고정 시점
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 70, 190), Vector3.new(0, 0, 0))
		if onTargetChanged then
			onTargetChanged("관전 중 - 살아있는 플레이어가 없습니다")
		end
		return
	end
	if targetIndex > #targets then
		targetIndex = 1
	elseif targetIndex < 1 then
		targetIndex = #targets
	end
	local t = targets[targetIndex]
	local hum = t.Character and t.Character:FindFirstChildOfClass("Humanoid")
	camera.CameraType = Enum.CameraType.Custom
	if hum then
		camera.CameraSubject = hum
	end
	if onTargetChanged then
		onTargetChanged(string.format("관전 중: %s   (← → 전환)", t.DisplayName))
	end
end

function Spectate.init(callback: (string) -> ())
	onTargetChanged = callback
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not active then
			return
		end
		if input.KeyCode == Enum.KeyCode.Right then
			targetIndex += 1
			apply()
		elseif input.KeyCode == Enum.KeyCode.Left then
			targetIndex -= 1
			apply()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if active then
				apply()
			end
		end
	end)
end

function Spectate.setActive(on: boolean)
	if on == active then
		return
	end
	active = on
	if on then
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMaxZoomDistance = 30
		apply()
	else
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		player.CameraMaxZoomDistance = 0.5
		camera.CameraType = Enum.CameraType.Custom
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraSubject = hum
		end
		if onTargetChanged then
			onTargetChanged("")
		end
	end
end

return Spectate
