--!strict
-- 살목지(Dead Lake) 설정값. 밸런스 조정은 여기서만 하세요.
-- 컨셉: 1인칭. 랜턴을 켜면 덫이 보이지만 귀신에게 발각된다. 호수에서 물을 길어 제단을 채우면 귀신이 봉인되고 출구가 열린다.

local Config = {}

-- 진행: 라운드·대기·제한시간 없음. 들어오면 바로 캠프에서 시작, 호수 주변 항아리 3개를 채우면 귀신 봉인 → 문 열림 → 탈출.
Config.Round = {
	EscapeTime = 90, -- 봉인 후 문이 열려 있는 시간. 0 이면 제한 없음
	EndingTime = 8, -- 결과 화면 시간. 지나면 맵을 되돌리고 전원 캠프에서 다시 시작
	MinPlayers = 1,
	BucketsPerJar = 1, -- 항아리 하나를 채우는 데 필요한 양동이 수
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
	-- 앞쪽 원뿔 빛 (공포게임 손전등 구도: 화면 가운데 동그라미만 밝음). 카메라 방향을 따라감
	Range = 48, -- 앞으로 뻗는 거리 (덫이 보이는 거리)
	Angle = 66, -- 원뿔 각도(도). 작을수록 동그라미가 좁음
	Brightness = 4.5,
	-- 발밑 약한 빛 (켰을 때만). 0 이면 앞쪽만 보임
	NearRange = 12,
	NearBrightness = 0.9,
	OffGlow = 0.0, -- 껐을 때 빛 (0 = 완전 암흑)
	StartOn = false,
	ScreenVignette = 0.2, -- 켰을 때 화면 가장자리 어둡기(0~1). 가운데 동그라미 느낌
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
	-- 채워야 하는 항아리(사당) 3곳. 호수 주변에 흩어져 있고 길로 이어짐. 전부 채우면 봉인.
	-- Kind: Altar(돌 제단상·비석·금줄 기둥·석등) / Cairn(돌탑 여러 개·천 장대) / Ruin(기와지붕 반쯤 내려앉은 사당)
	Shrines = {
		{ Name = "건너편 제단", Position = Vector3.new(0, 0, -168), Kind = "Altar" },
		{ Name = "서쪽 돌탑", Position = Vector3.new(-160, 0, -40), Kind = "Cairn" },
		{ Name = "동쪽 무너진 사당", Position = Vector3.new(160, 0, 10), Kind = "Ruin" },
	},
	-- 물을 뜰 수 있는 지점 3곳. FillMult: 긷는 속도 (선착장은 귀신 코앞이라 빠름)
	Stations = {
		{ Name = "낡은 선착장", Kind = "Pier", Direction = Vector3.new(0, 0, 1), FillMult = 1.4 },
		{ Name = "갈대밭 물가", Kind = "Reeds", Direction = Vector3.new(-0.8, 0, 0.6), FillMult = 1.0 },
		{ Name = "검은 바위", Kind = "Rocks", Direction = Vector3.new(0.95, 0, -0.31), FillMult = 0.9 },
	},
}

-- 효과음·환경음. Roblox 가 라이선스한 공개 라이브러리(ProSoundEffects / APMOfficial) 소리라 누구나 쓸 수 있음.
-- 마음에 안 드는 소리는 Studio Toolbox → Audio 에서 골라 ID 만 바꾸면 됨.
local function id(n: number): string
	return "rbxassetid://" .. n
end
Config.Sounds = {
	-- 일회성 효과음
	Splash = id(9120585252), -- 큰 물보라 (귀신이 솟을 때, 물 쏟을 때)
	Fill = id(9117823374), -- 양동이에 물이 찼을 때
	Pour = id(9120575856), -- 항아리에 붓기
	Grab = id(9113980319), -- 붙잡힘: 괴물 으르렁
	Scream = id(9043346594), -- 귀신 비명
	TrapSnap = id(9116723292), -- 덫 쇳소리
	Click = id(9114480271), -- 랜턴 딸깍
	Gate = id(9120877884), -- 출구 문 삐걱
	Stinger = id(9047014318), -- 귀신이 나를 발견했을 때
	Bell = id(9125597663), -- 봉인: 절 종소리
	Rumble = id(9112824733), -- 봉인: 낮은 울림
	Win = id(9042971851), -- 탈출 성공
	-- 계속 도는 소리
	Night = id(9112881910), -- 늪 벌레 소리
	Rain = id(9112854440), -- 나뭇잎에 떨어지는 비
	Bgm = id(1842083590), -- 배경 음악: 어둡고 눅눅한 질감
	Lake = id(9116203162), -- 호숫가 물결 (물가에 가까울수록 큼)
	Drone = id(9114353539), -- 불길한 저음 (위협이 높을수록 큼)
	Chase = id(9114353372), -- 쫓길 때: 깊게 울리는 불길한 저음 (쿵쿵거리는 타격음 없는 것)
	Heartbeat = id(9043365842), -- 심장박동 (96BPM 루프)
	GhostLoop = id(9125440168), -- 귀신 몸에서 나는 속삭임 (가까이 오면 들림)
	-- 가끔 멀리서 들리는 소리 (부엉이, 나뭇가지, 바람)
	Distant = {
		id(9117181540),
		id(9117181875),
		id(9120258937),
		id(9119232293),
		id(9120697823),
		id(9120698168),
		id(9120015808), -- 천둥
	},
}

-- 소리 크기 (0 이면 꺼짐)
Config.Audio = {
	NightVolume = 0.15,
	RainVolume = 0.4,
	BgmVolume = 0.3,
	LakeVolume = 0.5, -- 물가에 섰을 때 최대
	LakeFalloff = 60, -- 물가에서 이만큼 멀어지면 안 들림
	DroneVolume = 0.6, -- 위협 최대일 때
	ChaseVolume = 0.7,
	HeartbeatVolume = 0.5,
	GhostLoopVolume = 1.2,
	GhostLoopRange = 75, -- 귀신 속삭임이 들리는 거리
	DistantVolume = 0.5,
	DistantInterval = { 18, 45 }, -- 멀리서 들리는 소리 간격 (초)
	DistantRange = { 55, 110 }, -- 플레이어로부터 거리
}

-- 귀신 연출 (내 화면에서만)
Config.Scare = {
	GrabLookTime = 1.1, -- 붙잡힌 순간 화면이 귀신 얼굴로 돌아가 있는 시간 (0 이면 끔)
	GrabZoom = 22, -- 그때 시야각을 얼마나 좁힐지 (확대)
	GrabFaceHeight = 4.2, -- 귀신 몸통 중심에서 얼굴까지 높이 (메시 귀신 얼굴이 안 맞으면 조정)
	FlickerThreat = 0.55, -- 위협값이 이 이상이면 랜턴이 깜빡이기 시작 (1 이면 끔)
	DeathText = "호수가 당신을 삼켰다...",
	DeathHold = 2, -- 암전된 채 글씨가 떠 있는 시간
}

-- 관리자(테스트) 모드: P 키. 켠 사람 화면만 대낮처럼 밝아짐. Studio 안과 플레이스 소유자는 항상 허용.
Config.Admin = {
	Users = { "jaehyun429" }, -- 추가로 허용할 로블록스 사용자 이름(또는 표시 이름)
	GroupRank = 254, -- 그룹 소유 플레이스일 때 이 등급 이상이면 허용
	SpeedMult = 2, -- 켜면 이동 속도 배율
	-- 켜면: 귀신이 무시(발각 안 됨, 쫓던 중이면 놓침), 덫에 안 걸림, 덫이 빨갛게 표시, 스태미나 안 닳음, 화면 밝음
}

-- 외부 메시 (Meshy 등). Studio 의 Import 3D 로 넣은 모델을 ReplicatedStorage.DeadLake.Assets 에 두면 자동 사용.
-- 이름에 DeadTree / Wraith / Bucket / Jar / Shrine 가 들어가면 됨. 없으면 파트로 만든 기본 외형을 씀.
Config.Assets = {
	TreeHeight = 28, -- 호수 가운데 고목 높이 (스터드)
	TreeYaw = 0, -- 고목 회전 (도)
	ForestTreeHeight = { 16, 26 }, -- 숲 나무 높이 범위
	ForestMeshRatio = 0.35, -- 숲 나무 중 메시로 세울 비율 (렉 걸리면 낮추기, 0 이면 전부 파트)
	WraithHeight = 12.5, -- 귀신 키
	WraithFacing = 180, -- 귀신이 뒤로 달리면 0 으로
	-- 귀신 달리기 동작: "Baked" = 코드가 뼈를 직접 움직임(권장, Studio 애니메이션 임포트 불필요) /
	-- "Keyframe" = Studio 로 가져온 애니메이션 사용(누워서 달리면 Baked 로) / "None" = 동작 없이 미끄러짐
	WraithAnimation = "Baked",
	WraithRunSpeed = 1, -- Baked 재생 속도 배율
	WraithRunAnimationId = "", -- Keyframe 일 때: 업로드한 애니메이션 ID. 비우면 모델 안의 KeyframeSequence 사용
	BucketHeight = 1.6, -- 들고 다니는 양동이 높이
	JarHeight = 4.2, -- 제단 항아리 높이
	ShrineHeight = 14, -- 동쪽 사당 건물(Meshy 메시) 높이. 메시가 없으면 파트로 지음
	ShrineYaw = 0, -- 사당 메시가 호수를 등지면 180 으로
	ShrineOffset = 5.5, -- 항아리에서 뒤로 몇 스터드 떨어뜨려 세울지
}

return Config
