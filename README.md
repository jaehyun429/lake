# 살목지 (Dead Lake) — Roblox 1인칭 협동 공포게임

> **호수의 물을 길어 반대편 제단을 채우면 귀신이 봉인되고 출구가 열린다.**
> 랜턴을 켜면 덫이 보이지만 귀신에게 발각된다. 끄면 안전하지만 덫이 안 보인다. 껐다 켰다 하며 물을 나르는 게임.

Rojo 프로젝트입니다. 맵·귀신·덫·UI 전부 스크립트로 생성되므로 Studio에 동기화하고 **Play**만 누르면 됩니다.

## Studio(Team Create "Dead Lake")에 넣기

1. 터미널에서 이 폴더로 이동해 서버 실행:
   ```bash
   cd ~/Desktop/Deadlake
   rojo serve
   ```
2. Roblox Studio에서 Dead Lake 플레이스를 연다 → 상단 **Plugins** 탭 → **Rojo** → **Connect** (localhost:34872).
3. 변경 확인 창이 뜨면 **Accept**. (Lighting 속성, Players.CharacterAutoLoads=false 가 함께 들어갑니다.)
4. **Play** (F5). 서버가 시작되면 지형·호수·버드나무·캠프·물가·출구가 자동 생성되고 20초 대기 후 라운드가 시작됩니다.
   - 편집 모드에서 맵을 미리 보고 싶으면 명령줄(View → Command Bar)에:
     `require(game.ServerScriptService.DeadLake.MapBuilder).build()`
5. 코드를 고치면 `rojo serve`가 켜져 있는 동안 Studio에 즉시 반영됩니다. 다른 팀원은 Team Create로 그 결과를 봅니다.

Rojo 연결이 안 되면 `rojo build -o Deadlake.rbxl` 로 만든 파일을 Studio에서 열어 확인할 수 있습니다.

> 주의: 서버가 시작될 때 Workspace의 기본 `Baseplate`/`SpawnLocation`을 지우고, 호수 중심 기준 760×760 영역의 Terrain을 다시 채웁니다. (Play 세션 안에서만 일어나며 편집 중인 플레이스는 건드리지 않습니다.)

## 조작

| 입력 | 동작 |
|---|---|
| F (또는 랜턴 클릭) | 랜턴 켜기/끄기 |
| E (물가 마커 앞) | 물 긷기 시작 / 중단 |
| E 길게 (제단 앞) | 물 붓기 |
| G | 들고 있는 양동이 버리기 (귀신에게 쫓길 때 속도 회복) |
| Shift | 달리기 (소음 → 가까이 있으면 발각) |
| E 연타 (붙잡혔을 때) | 뿌리치기 |
| E 길게 (잡힌 팀원 옆) | 구조하기 |
| ← → (관전 중) | 관전 대상 전환 |

모바일은 랜턴/버리기/달리기/뿌리치기 버튼이 자동으로 생깁니다. 카메라는 1인칭 고정입니다.

## 핵심 루프

1. 캠프(안전지대)에서 출발. 랜턴은 꺼진 상태.
2. 호수 물가 3곳 중 하나에서 E 로 6초간 물을 긷는다. 귀신은 호수 가운데 버드나무 옆에 잠겨 있다 → **물가에서는 랜턴을 꺼야** 발각 게이지가 안 찬다.
3. 양동이를 들고(속도 70%) 호수 반대편 **제단**까지 길을 따라간다. 길 위에는 매 라운드 랜덤한 위치에 **덫**이 있다. 어두워서 랜턴 없이는 안 보인다.
4. 덫을 밟으면 3초간 발이 묶이고 쇳소리에 귀신이 그 자리로 달려온다(속도 16.5 = 걷기보다 빠르고 달리기보다 느림). 양동이를 들고는 못 도망치므로 **G 로 버리고** 달리거나, 랜턴을 끄고 숨는다.
5. 귀신은 랜턴 불빛(120스터드), 12스터드 안의 기척, 32스터드 안의 달리기 소음, 물에 들어간 플레이어를 감지한다. 놓치면 마지막 목격 지점을 6초 뒤지고 호수로 돌아간다. 캠프 안전지대 안으로는 못 들어온다.
6. 붙잡히면 4초 안에 E 10회 연타 또는 팀원 구조(1.5초 홀드). 실패하면 호수로 끌려가 탈락(관전).
7. 제단에 목표 수만큼 부으면 **봉인**(귀신이 호수 중심으로 끌려가 가라앉음) → 캠프 출구 문이 열리고 90초 안에 1명 이상 나가면 승리.

## 결정 사항 (초기값) — 전부 `src/shared/Config.luau`

| 항목 | 현재 값 | Config |
|---|---|---|
| 한 판 | 7분 + 탈출 90초, 대기 20초, 솔로 허용 | `Round` |
| 목표 양동이 | 2 + 인원 (3~10) | `Round.BucketTarget*` |
| 물 긷기 | 6초, 시작 지점 4스터드 안에서는 유지, 중단 시 초당 5% 감소 | `Fill` |
| 물가 | 선착장 1.4× (귀신 코앞, 빠름) / 갈대밭 1.0× / 검은 바위 0.9× (제단에 가까움) | `Map.Stations` |
| 랜턴 | 카메라 방향 원뿔 빛(58°, 42스터드) + 발밑 약한 빛. 켜면 화면 가장자리가 어두워져 가운데 동그라미만 밝음. 시작은 꺼짐 | `Lantern` |
| 달리기 스태미나 | 5초 지속, 7초에 완전 회복, 바닥나면 25% 찰 때까지 못 달림. 핫바 위 흰 줄이 양쪽에서 줄어듦 | `Player.Sprint*` |
| 지형 | 땅은 전부 평평(0), 물가만 12스터드 폭 완만한 모래 경사. 수면 가장자리에 물거품 띠 | `Map.BeachWidth` |
| 발각 | 랜턴: 40스터드 안 0.35/s → 170스터드에서 0. 달리기 0.5/s(32 안), 긷기 0.06/s, 수영 0.3/s. 감소 0.15/s | `Awareness` |
| 귀신 | 추격 16.5, 복귀 11, 수색 6초, 포착 4.5, 경직 4초, 끌려감 3초 | `Ghost` |
| 덫 | 12 + 3×인원, 길 중심선 ±5, 간격 9, 40초 후 재장전, 3초 속박 | `Traps`, `Player.TrapSlowTime` |
| 맵 | 호수 반경 92, 캠프 z=+150(안전지대 28), 제단 z=−168, 출구 z=+195 | `Map` |

### 첫 플레이 테스트 체크리스트
- 랜턴 없이 덫이 정말 안 보이는가? (너무 잘 보이면 `Lighting` 더 어둡게, 너무 안 보이면 `Lantern.Range` ↑)
- 랜턴을 끄고 달릴 때 길·나룻배·나무 윤곽이 보이는가? (기본 밝기는 `default.project.json` 의 Lighting.Brightness / OutdoorAmbient)
- 랜턴 원뿔이 너무 좁거나 넓으면 `Lantern.Angle`, 가장자리 어둡기는 `Lantern.ScreenVignette`
- 물가에서 "랜턴 끄고 긷기"를 스스로 알아내는가?
- 귀신에게 쫓길 때 "양동이 버리기 vs 버티기" 선택이 생기는가?
- 억울한 죽음: 덫 밟고 3초 속박 + 추격 속도 조합이 너무 가혹하면 `TrapSlowTime` ↓ 또는 `HuntSpeed` ↓
- 한 판이 5~7분에 끝나는가?

## 외부 메시 넣기 (Meshy 모델)

`assets/import/` 에 로블록스 한도(메시당 2만 삼각형)에 맞게 줄인 OBJ + 텍스처가 있습니다.

| 파일 | 쓰이는 곳 | 삼각형 |
|---|---|---|
| `DeadTree.obj` | 호수 가운데 고목 + 숲 나무 일부 | 18,000 |
| `Wraith.obj` | 귀신 몸 (정적 메시, 애니메이션 없음) | 18,000 |
| `Bucket.obj` | 들고 다니는 양동이 + 물가 소품 | 8,000 |
| `Jar.obj` | 제단 항아리 (물 붓는 곳) | 9,500 |

1. Studio 상단 **Home → Import 3D** 로 `.obj` 를 하나씩 가져옵니다 (텍스처는 같은 폴더의 `.png` 를 자동으로 읽음).
2. Workspace 에 들어온 모델을 **ReplicatedStorage → DeadLake → Assets** 로 드래그합니다. 이름은 파일명 그대로면 됩니다.
3. Play 하면 코드가 자동으로 찾아 씁니다. 없는 것은 기존 파트 외형으로 나옵니다.
   크기·방향은 `Config.Assets` 에서 조정 (`WraithFacing`: 귀신이 뒤로 달리면 0).

귀신 달리기 애니메이션은 원본 FBX(`assets/Wraith/`)를 **Avatar → Animation Editor → Import from FBX** 로 올려 퍼블리시한 뒤
그 ID 를 `Config.Assets.WraithRunAnimationId` 에 넣으면 재생됩니다 (리그가 있는 모델을 Assets 에 넣었을 때만).

## 파일 구조

```
default.project.json         Rojo 트리 (Remotes, GameState, Lighting 설정 포함)
src/shared/Config.luau       모든 밸런스 숫자
src/server/Main.server.luau  서버 진입점
src/server/MapBuilder.luau   지형·호수·버드나무·캠프·제단·물가·출구·숲 생성
src/server/GhostBuilder.luau 귀신 본체 / 파문 / 물보라
src/server/RoundManager.luau 라운드 상태 머신, 스폰, 제단 채움/봉인, 승패 판정, 출구 문
src/server/WaterSystem.luau  물 긷기 게이지, 양동이 운반/버리기, 제단에 붓기
src/server/GhostSystem.luau  발각 게이지, 사냥꾼 AI(추격/수색/복귀/경직/봉인), 붙잡기, 탈출/구조, 끌려감
src/server/TrapSystem.luau   덫 랜덤 배치, 밟기 감지, 귀신 호출, 재장전
src/server/LanternSystem.luau 랜턴 Tool 지급, 켜기/끄기
src/server/Net.luau          RemoteEvent 래퍼 / PlayerState.luau 상태 헬퍼 / Util.luau 파트 유틸
src/client/Main.client.luau  입력(달리기·연타), 서버 메시지 처리
src/client/HUD.luau          타이머·양동이·배너·게이지·연타·결과 UI
src/client/Effects.luau      비네트·심장박동·흔들림
src/client/Spectate.luau     관전 카메라
tools/check.sh               luau-analyze + stylua + rojo build
```

상태는 Attribute 로 복제됩니다: `ReplicatedStorage.DeadLake.GameState` (Phase, TimeLeft, Buckets, Target, Result, Reason), `Player` (Status, Carrying, Fill, Filling, Awareness, Threat, Sprinting, LanternOn).
