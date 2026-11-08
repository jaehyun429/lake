#!/usr/bin/env bash
# 정적 검사: Luau 타입/린트 + 포맷 + Rojo 빌드
set -u
cd "$(dirname "$0")/.."
DEFS="${DEADLAKE_DEFS:-tools/globalTypes.d.luau}"
if [ ! -f "$DEFS" ]; then
  echo "Roblox 타입 정의 다운로드 중..."
  curl -sL -o "$DEFS" "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"
fi
echo "== luau-analyze"
luau-analyze --defs="$DEFS" src
status=$?
echo "== stylua --check"
stylua --check src
echo "== rojo build"
rojo build -o /tmp/deadlake-check.rbxlx >/dev/null && echo "rojo build OK"
exit $status
