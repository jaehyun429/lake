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
