--!strict
-- 살목지(Dead Lake) 설정값. 밸런스 조정은 여기서만 하세요.
-- 컨셉: 1인칭. 랜턴을 켜면 덫이 보이지만 귀신에게 발각된다. 호수에서 물을 길어 제단을 채우면 귀신이 봉인되고 출구가 열린다.

local Config = {}

Config.Round = {
	IntermissionTime = 20,
	RoundTime = 420, -- 7분
	EscapeTime = 90, -- 봉인 후 탈출 제한 시간
	EndingTime = 8,
	MinPlayers = 1,
	BucketTargetBase = 2, -- 목표 양동이 = Base + PerPlayer * 인원 (Min~Max)
	BucketTargetPerPlayer = 1,
	BucketTargetMin = 3,
	BucketTargetMax = 10,
}

Config.Player = {
	WalkSpeed = 14,
	SprintSpeed = 21,
	CarrySpeedMult = 0.7, -- 양동이 들면 70%
	TrapSlowTime = 3.0, -- 덫 밟은 뒤 발이 묶이는 시간(초)
	SprintStaminaTime = 5.0, -- 쉬지 않고 달릴 수 있는 시간(초)
	SprintRegenTime = 7.0, -- 0 에서 가득 차는 데 걸리는 시간(초)
	SprintMinToStart = 0.25, -- 바닥난 뒤 다시 달리려면 이만큼(비율) 회복돼야 함
}

-- 랜턴 (F 로 켜고 끄기)
Config.Lantern = {
	Range = 26, -- 켰을 때 빛 범위 (덫이 보이는 거리)
	Brightness = 1.6,
	OffGlow = 0.0, -- 껐을 때 빛 (0 = 완전 암흑)
	StartOn = false,
}

-- 물 긷기
Config.Fill = {
	Time = 6,
	MoveTolerance = 4,
	Range = 9,
	DecayPerSecond = 0.05,
}

-- 발각(Awareness): 귀신이 플레이어를 알아채는 정도 0~1. 1이 되면 사냥 시작.
Config.Awareness = {
	LanternRate = 0.35, -- 랜턴 켠 채로 귀신 가시 범위 안에 있을 때 초당 증가 (거리 보정)
	LanternNear = 40, -- 이 거리 안이면 100% 속도
	LanternFar = 170, -- 이 거리 밖이면 랜턴을 켜도 안 보임
	SprintRate = 0.5, -- 랜턴 꺼도 달리면 소음: 이 거리 안이면 증가
	SprintRange = 32,
	FillRate = 0.06, -- 물 긷는 소리
	FillRange = 110,
	SwimRate = 0.3, -- 물에 들어가면
	SwimRange = 70,
	DecayPerSecond = 0.15,
}

-- 귀신 (사냥꾼)
Config.Ghost = {
	HuntSpeed = 16.5, -- 걷기(14)보다 빠르고 달리기(21)보다 느림. 양동이 들면 못 도망침 → 버려야 함
	ReturnSpeed = 11,
	SearchTime = 6, -- 마지막 목격 지점에서 두리번거리는 시간
	GiveUpTime = 5, -- 안전지대 앞에서 기다리다 포기하는 시간
	CatchRange = 4.5,
	HearRange = 12, -- 랜턴 꺼도 이 거리 안이면 들킴
	SeeRange = 120, -- 사냥 중 랜턴 켠 플레이어를 보는 거리
	StunTime = 4, -- 뿌리쳤을 때 귀신 경직
	GrabEscapeTime = 4,
	MashRequired = 10,
	RescueHoldTime = 1.5,
	ImmunityAfterEscape = 6,
	DragTime = 3,
	SubmergeMin = 25,
	SubmergeMax = 50,
}

-- 덫 (매 라운드 위치 랜덤)
Config.Traps = {
	Base = 12, -- 개수 = Base + PerPlayer * 인원
	PerPlayer = 3,
	PathSpread = 5, -- 길 중심선에서 좌우 퍼짐
	MinSpacing = 9,
	RearmTime = 40, -- 다시 벌어지기까지
	Visible = true, -- false 면 완전 투명(어둠에서만 숨김 대신 아예 안 보임). 기본은 어둡게 칠해 랜턴 빛에만 드러남
}

Config.Map = {
	LakeCenter = Vector3.new(0, 0, 0),
	LakeRadius = 92,
	WaterLevel = -2,
	BeachWidth = 12, -- 물가 완만한 모래 경사 폭 (호수 밖)
	CampCenter = Vector3.new(0, 0, 150), -- 출발점·안전지대·출구
	SafeRadius = 28,
	GatePosition = Vector3.new(0, 0, 195),
	AltarCenter = Vector3.new(0, 0, -168), -- 호수 반대편 제단
	-- 물을 뜰 수 있는 지점 3곳. FillMult: 긷는 속도 (선착장은 귀신 코앞이라 빠름)
	Stations = {
		{ Name = "낡은 선착장", Kind = "Pier", Direction = Vector3.new(0, 0, 1), FillMult = 1.4 },
		{ Name = "갈대밭 물가", Kind = "Reeds", Direction = Vector3.new(-0.8, 0, 0.6), FillMult = 1.0 },
		{ Name = "검은 바위", Kind = "Rocks", Direction = Vector3.new(0.95, 0, -0.31), FillMult = 0.9 },
	},
}

-- Roblox 내장 효과음 임시 사용. 라이브러리 사운드 ID(rbxassetid://...)로 교체하세요.
Config.Sounds = {
	Splash = "rbxasset://sounds/impact_water.mp3",
	Heartbeat = "rbxasset://sounds/impact_explosion_03.mp3",
	Swim = "rbxasset://sounds/action_swim.mp3",
	Grab = "rbxasset://sounds/action_falling.ogg",
	Pour = "rbxasset://sounds/action_swim.mp3",
	Gate = "rbxasset://sounds/action_get_up.mp3",
	TrapSnap = "rbxasset://sounds/action_jump_land.mp3",
	Scream = "rbxasset://sounds/ouch.ogg",
	Click = "rbxasset://sounds/action_jump.mp3",
	Footstep = "rbxasset://sounds/action_footsteps_plastic.mp3",
}

-- 외부 메시 (Meshy 등). Studio 의 Import 3D 로 넣은 모델을 ReplicatedStorage.DeadLake.Assets 에 두면 자동 사용.
-- 이름에 DeadTree / Wraith / Bucket / Jar 가 들어가면 됨. 없으면 파트로 만든 기본 외형을 씀.
Config.Assets = {
	TreeHeight = 28, -- 호수 가운데 고목 높이 (스터드)
	TreeYaw = 0, -- 고목 회전 (도)
	ForestTreeHeight = { 16, 26 }, -- 숲 나무 높이 범위
	ForestMeshRatio = 0.35, -- 숲 나무 중 메시로 세울 비율 (렉 걸리면 낮추기, 0 이면 전부 파트)
	WraithHeight = 12.5, -- 귀신 키
	WraithFacing = 180, -- 귀신이 뒤로 달리면 0 으로
	WraithRunAnimationId = "", -- 업로드한 달리기 애니메이션 (rbxassetid://...). 비우면 모델 안의 KeyframeSequence 사용
	BucketHeight = 1.6, -- 들고 다니는 양동이 높이
	JarHeight = 4.2, -- 제단 항아리 높이
}

return Config
