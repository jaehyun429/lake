-- 화면 UI: 타이머/양동이, 알림 배너, 물뜨기 게이지, 발목 탈출 연타, 결과, 관전 표시
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local HUD = {}
local player = Players.LocalPlayer
local gui: ScreenGui

local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextColor3 = Color3.fromRGB(225, 225, 215)
	l.TextStrokeTransparency = 0.5
	l.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

local function frame(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.fromRGB(10, 12, 14)
	f.BackgroundTransparency = 0.35
	for k, v in props do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

local timerLabel: TextLabel
local bucketLabel: TextLabel
local phaseLabel: TextLabel
local banner: TextLabel
local gaugeFrame: Frame
local gaugeFill: Frame
local gaugeText: TextLabel
local mashFrame: Frame
local mashFill: Frame

local resultFrame: Frame
local resultTitle: TextLabel
local resultReason: TextLabel
local spectateLabel: TextLabel
local helpLabel: TextLabel
local lanternLabel: TextLabel
local awareFrame: Frame
local awareFill: Frame
local awareText: TextLabel
local ghostLabel: TextLabel
local carryLabel: TextLabel
local staminaFill: Frame
local staminaTrack: Frame
local staminaHideToken = 0
local bannerToken = 0

function HUD.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "DeadLakeHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	-- 상단: 타이머 + 양동이
	local top = frame(gui, { Size = UDim2.fromOffset(260, 86), Position = UDim2.new(0.5, -130, 0, 18), BackgroundTransparency = 0.45 })
	Instance.new("UICorner", top).CornerRadius = UDim.new(0, 10)
	timerLabel = label(top, { Size = UDim2.new(1, 0, 0, 42), Position = UDim2.fromOffset(0, 4), Text = "--:--", TextSize = 34, Font = FONT_BOLD })
	bucketLabel = label(top, {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 44),
		Text = "양동이 0 / 0",
		TextSize = 18,
		TextColor3 = Color3.fromRGB(150, 195, 225),
	})
	phaseLabel =
		label(top, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 66), Text = "", TextSize = 13, TextColor3 = Color3.fromRGB(170, 170, 160) })

	-- 좌측 상단: 랜턴 상태 + 발각 게이지 + 귀신 상태
	local left = frame(gui, { Size = UDim2.fromOffset(250, 96), Position = UDim2.fromOffset(20, 18), BackgroundTransparency = 0.45 })
	Instance.new("UICorner", left).CornerRadius = UDim.new(0, 10)
	lanternLabel = label(left, {
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(12, 6),
		Text = "랜턴 꺼짐  [F]",
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = FONT_BOLD,
	})
	awareText = label(left, {
		Size = UDim2.new(1, -16, 0, 18),
		Position = UDim2.fromOffset(12, 34),
		Text = "발각",
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(190, 170, 170),
	})
	awareFrame = frame(
		left,
		{ Size = UDim2.new(1, -24, 0, 10), Position = UDim2.fromOffset(12, 54), BackgroundColor3 = Color3.fromRGB(25, 20, 20), BackgroundTransparency = 0 }
	)
	Instance.new("UICorner", awareFrame).CornerRadius = UDim.new(0, 4)
	awareFill = frame(awareFrame, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(200, 60, 50), BackgroundTransparency = 0 })
	Instance.new("UICorner", awareFill).CornerRadius = UDim.new(0, 4)
	ghostLabel = label(left, {
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.fromOffset(12, 70),
		Text = "귀신: 호수 속",
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(160, 170, 190),
	})
	carryLabel = label(gui, {
		Size = UDim2.fromOffset(250, 22),
		Position = UDim2.fromOffset(20, 118),
		Text = "",
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(150, 195, 225),
	})

	-- 알림 배너
	banner = label(gui, {
		Size = UDim2.new(0.7, 0, 0, 60),
		Position = UDim2.new(0.15, 0, 0.16, 0),
		Text = "",
		TextSize = 22,
		TextWrapped = true,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Font = FONT_BOLD,
	})

	-- 물뜨기 게이지
	-- 스태미나 바 (핫바 위). 가운데 기준으로 양쪽이 줄어듦
	staminaTrack = frame(gui, {
		Size = UDim2.fromOffset(240, 4),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -100),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
	})
	staminaFill = frame(staminaTrack, {
		Size = UDim2.new(1, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
	})

	gaugeFrame = frame(gui, { Size = UDim2.fromOffset(340, 20), Position = UDim2.new(0.5, -170, 0.78, 0), BackgroundTransparency = 0.2, Visible = false })
	Instance.new("UICorner", gaugeFrame).CornerRadius = UDim.new(0, 6)
	gaugeFill = frame(gaugeFrame, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(70, 140, 190), BackgroundTransparency = 0 })
	Instance.new("UICorner", gaugeFill).CornerRadius = UDim.new(0, 6)
	gaugeText = label(
		gaugeFrame,
		{ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, -26), Text = "물 긷는 중 - 가만히 서 있으세요", TextSize = 16 }
	)

	-- 발목 탈출 연타
	mashFrame = frame(gui, {
		Size = UDim2.fromOffset(420, 110),
		Position = UDim2.new(0.5, -210, 0.6, 0),
		BackgroundColor3 = Color3.fromRGB(40, 8, 8),
		BackgroundTransparency = 0.25,
		Visible = false,
	})
	Instance.new("UICorner", mashFrame).CornerRadius = UDim.new(0, 12)
	label(mashFrame, {
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.fromOffset(0, 8),
		Text = "발목을 잡혔다!\n[E] 를 연타해서 뿌리치세요!",
		TextSize = 22,
		Font = FONT_BOLD,
		TextColor3 = Color3.fromRGB(255, 120, 110),
	})
	local mashBg = frame(
		mashFrame,
		{ Size = UDim2.new(1, -40, 0, 16), Position = UDim2.fromOffset(20, 78), BackgroundColor3 = Color3.fromRGB(20, 20, 20), BackgroundTransparency = 0 }
	)
	Instance.new("UICorner", mashBg).CornerRadius = UDim.new(0, 6)
	mashFill = frame(mashBg, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(230, 90, 80), BackgroundTransparency = 0 })
	Instance.new("UICorner", mashFill).CornerRadius = UDim.new(0, 6)

	-- 결과 화면
	resultFrame = frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.45, Visible = false })
	resultTitle = label(resultFrame, { Size = UDim2.new(1, 0, 0, 80), Position = UDim2.new(0, 0, 0.36, 0), Text = "", TextSize = 56, Font = FONT_BOLD })
	resultReason = label(resultFrame, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0.36, 90), Text = "", TextSize = 22 })

	-- 관전 / 도움말
	spectateLabel =
		label(gui, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 1, -80), Text = "", TextSize = 18, TextColor3 = Color3.fromRGB(200, 200, 190) })
	helpLabel = label(gui, {
		Size = UDim2.new(0, 360, 0, 120),
		Position = UDim2.new(0, 20, 1, -140),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = Color3.fromRGB(180, 180, 170),
		Text = "[F] 랜턴 켜기/끄기 - 켜면 덫이 보이지만 귀신에게 발각됩니다\n[E] 물가에서 물 긷기 / 제단 앞에서 길게 눌러 붓기\n[Shift] 달리기(소음)   [G] 양동이 버리기(귀신에게 쫓길 때)\n제단을 다 채우면 귀신이 봉인되고 캠프 출구가 열립니다.",
	})
end

function HUD.setTimer(seconds: number)
	local s = math.max(0, math.floor(seconds))
	timerLabel.Text = string.format("%02d:%02d", s // 60, s % 60)
	timerLabel.TextColor3 = if s <= 30 then Color3.fromRGB(240, 90, 80) else Color3.fromRGB(225, 225, 215)
end

function HUD.setBuckets(n: number, target: number)
	bucketLabel.Text = string.format("양동이 %d / %d", n, target)
end

function HUD.setPhase(phase: string)
	local names = {
		Waiting = "플레이어 대기 중",
		Intermission = "다음 판 준비 중",
		Playing = "호수의 물로 제단을 채우세요",
		Sealing = "봉인 중...",
		Escape = "봉인 완료! 캠프 출구로 탈출하세요",
		Ended = "라운드 종료",
	}
	phaseLabel.Text = names[phase] or phase
	helpLabel.Visible = phase == "Intermission" or phase == "Waiting"
	if phase ~= "Ended" then
		resultFrame.Visible = false
	end
end

function HUD.banner(text: string, seconds: number)
	bannerToken += 1
	local token = bannerToken
	banner.Text = text
	banner.TextTransparency = 0
	banner.TextStrokeTransparency = 0.3
	task.delay(seconds, function()
		if bannerToken == token then
			TweenService:Create(banner, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

function HUD.setGauge(visible: boolean, progress: number, paused: boolean)
	gaugeFrame.Visible = visible
	gaugeFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
	if paused then
		gaugeText.Text = "움직이면 물이 흔들립니다 - 멈추세요"
		gaugeFill.BackgroundColor3 = Color3.fromRGB(170, 130, 60)
	else
		gaugeText.Text = string.format("물 긷는 중 %d%% - 가만히 서 있으세요", math.floor(progress * 100))
		gaugeFill.BackgroundColor3 = Color3.fromRGB(70, 140, 190)
	end
end

function HUD.showMash(visible: boolean)
	mashFrame.Visible = visible
	if visible then
		mashFill.Size = UDim2.fromScale(0, 1)
	end
end

function HUD.setMash(count: number, required: number)
	mashFill.Size = UDim2.fromScale(math.clamp(count / required, 0, 1), 1)
end

function HUD.showResult(win: boolean, reason: string)
	resultFrame.Visible = true
	resultTitle.Text = if win then "살아서 돌아왔다" else "살목지에 삼켜졌다"
	resultTitle.TextColor3 = if win then Color3.fromRGB(190, 230, 200) else Color3.fromRGB(220, 70, 60)
	resultReason.Text = reason
end

-- 달리기 스태미나: 인벤토리(핫바) 바로 위, 반투명 흰 줄이 양쪽 끝에서 가운데로 줄어듦. 가득 차면 서서히 사라짐
function HUD.setStamina(value: number)
	local v = math.clamp(value, 0, 1)
	TweenService:Create(staminaFill, TweenInfo.new(0.12, Enum.EasingStyle.Linear), { Size = UDim2.new(v, 0, 1, 0) }):Play()
	staminaFill.BackgroundColor3 = if v < 0.26 then Color3.fromRGB(255, 150, 140) else Color3.fromRGB(255, 255, 255)
	staminaHideToken += 1
	local token = staminaHideToken
	if v < 0.999 then
		staminaTrack.BackgroundTransparency = 0.85
		staminaFill.BackgroundTransparency = 0.35
	else
		task.delay(0.8, function()
			if token == staminaHideToken then
				TweenService:Create(staminaTrack, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
				TweenService:Create(staminaFill, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
			end
		end)
	end
end

function HUD.setLantern(on: boolean)
	lanternLabel.Text = if on then "랜턴 켜짐  [F]" else "랜턴 꺼짐  [F]"
	lanternLabel.TextColor3 = if on then Color3.fromRGB(255, 200, 120) else Color3.fromRGB(150, 150, 145)
end

function HUD.setAwareness(value: number)
	awareFill.Size = UDim2.fromScale(math.clamp(value, 0, 1), 1)
	awareText.Text = if value >= 0.99 then "발각됐다!" elseif value > 0.6 then "발각 - 눈치채고 있다" else "발각"
	awareText.TextColor3 = if value > 0.6 then Color3.fromRGB(240, 110, 100) else Color3.fromRGB(190, 170, 170)
end

function HUD.setGhost(state: string, targetIsMe: boolean)
	local names = {
		Lurking = "귀신: 호수 속",
		Hunting = if targetIsMe then "귀신: 당신을 쫓고 있다!" else "귀신: 누군가를 쫓는 중",
		Searching = "귀신: 근처를 뒤지는 중",
		Returning = "귀신: 호수로 돌아가는 중",
		Stunned = "귀신: 비틀거린다",
		Sealed = "귀신: 봉인됨",
	}
	ghostLabel.Text = names[state] or ("귀신: " .. state)
	ghostLabel.TextColor3 = if state == "Hunting" and targetIsMe
		then Color3.fromRGB(255, 90, 80)
		elseif state == "Sealed" then Color3.fromRGB(150, 220, 180)
		else Color3.fromRGB(160, 170, 190)
end

function HUD.setCarrying(on: boolean)
	carryLabel.Text = if on then "양동이 들고 있음 (느려짐 · G 버리기)" else ""
end

function HUD.setSpectate(text: string)
	spectateLabel.Text = text
end

return HUD
