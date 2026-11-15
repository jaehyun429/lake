# 파트 모델 미리보기 (Studio 없이)

서버 빌더(ShrineBuilder 등)를 로블록스 API 모킹 위에서 `luau` CLI 로 실행해 파트 목록을 JSON 으로 뽑고, Blender(bpy) 로 렌더합니다.

```bash
python3 tools/preview/gen_dryrun.py . /tmp/parts.json          # luau 필요 (brew install luau)
~/bpyenv/bin/python -I tools/preview/render_parts.py /tmp/parts.json /tmp/shrine   # bpy 모듈 (tools/mesh/README.md 참고)
```

`/tmp/shrine_<Kind>_<n>.png` 가 생깁니다. 재질·조명은 실제와 다르고 형태·배치 확인용입니다.
`mock_roblox.luau` 는 Vector3/CFrame/Instance/Enum/Random 의 최소 구현이라 다른 모듈을 돌리려면 필요한 API 를 추가하세요.
