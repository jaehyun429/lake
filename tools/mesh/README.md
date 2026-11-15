# Meshy FBX → Roblox용 OBJ 변환

로블록스는 메시당 약 2만 삼각형까지만 받으므로 Meshy 원본(10만~78만)을 줄여야 합니다.

```bash
python3 -m venv ~/meshenv && ~/meshenv/bin/pip install pymeshlab
python3 -I tools/mesh/fbxinfo.py  model.fbx                      # 삼각형 수·크기 확인
python3 -I tools/mesh/fbx2obj.py  model.fbx raw/Name.obj Name.png # FBX → OBJ (UV 유지, 축 변환)
~/meshenv/bin/python -I tools/mesh/decimate.py raw/Name.obj assets/import/Name.obj 18000
```

텍스처는 `sips -Z 1024 Name.png` 로 줄여 OBJ 옆에 두면 Import 3D 가 같이 올립니다.
스킨(리그)이 있는 FBX 는 정적 메시로만 변환됩니다. 애니메이션은 Studio Animation Editor 로 따로 올리세요.

## 수백만 삼각형짜리 정적 메시 (static_decimate.py)

Meshy 고해상도 모델(수백만 삼각형)은 Blender(bpy) 경로가 훨씬 빠릅니다. 결과는 같은 OBJ+MTL+PNG 입니다.

```bash
~/bpyenv/bin/python -I tools/mesh/static_decimate.py 원본.fbx assets/import/Shrine.obj 18000
```

## 리그·애니메이션 유지하며 줄이기 (rig_decimate.py)

Blender 가 필요합니다. 앱 대신 pip 모듈로도 됩니다 (Python 3.11):

```bash
/opt/homebrew/bin/python3.11 -m venv ~/bpyenv && ~/bpyenv/bin/pip install bpy
~/bpyenv/bin/python -I tools/mesh/rig_decimate.py 원본.fbx assets/import/WraithRig.fbx 9500 Wraith
```

Decimate(collapse) 로 UV·스킨 가중치를 유지한 채 줄이고, 정점당 뼈 영향을 4개로 제한한 뒤 액션을 베이크해서 FBX 로 내보냅니다.
끝나면 내보낸 파일을 다시 읽어 삼각형·뼈·프레임 수를 출력합니다. 스킨 메시는 10,000 삼각형 이하로 두세요.
