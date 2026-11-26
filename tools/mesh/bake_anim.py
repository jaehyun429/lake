"""리그 FBX 의 애니메이션을 Luau 데이터 모듈로 굽습니다 (Blender bpy 필요).

Studio 의 애니메이션 임포트는 뼈 축이 어긋나 귀신이 누워서 달리는 문제가 있어서,
각 뼈가 기본 자세에서 얼마나 움직였는지(월드 기준 회전·이동)를 프레임별로 뽑아 코드가 직접 재생합니다.
축·크기는 게임 안에서 뼈 위치를 보고 스스로 맞추므로 임포트 설정과 무관합니다.

사용법:
  ~/bpyenv/bin/python -I tools/mesh/bake_anim.py assets/import/WraithRig.fbx src/shared/WraithAnim.luau
"""
import os
import sys

import bpy

src, dst = os.path.abspath(sys.argv[-2]), os.path.abspath(sys.argv[-1])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src, use_anim=True, ignore_leaf_bones=True, automatic_bone_orientation=False)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
act = arm.animation_data.action
f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
scene = bpy.context.scene
fps = scene.render.fps / scene.render.fps_base

# 부모가 항상 먼저 오도록 정렬
bones = []


def walk(b):
    bones.append(b)
    for c in b.children:
        walk(c)


for b in arm.data.bones:
    if not b.parent:
        walk(b)

W = arm.matrix_world
rest = {b.name: W @ b.matrix_local for b in bones}


def r(v):
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


out = []
out.append("-- tools/mesh/bake_anim.py 가 만든 파일입니다. 직접 고치지 마세요.")
out.append(f"-- 원본: {os.path.basename(src)} / 액션 {act.name} / 프레임 {f0}-{f1} / {fps:g}fps")
out.append("-- Rest: 기본 자세의 뼈 위치 (Blender 좌표). Frames[f][i] = {tx,ty,tz, qx,qy,qz,qw}: i번째 뼈가 기본 자세에서 움직인 양 (월드 기준)")
out.append("return {")
out.append(f"\tFps = {fps:g},")
out.append("\tBones = { " + ", ".join('"' + b.name + '"' for b in bones) + " },")
out.append("\tParents = { " + ", ".join(str(bones.index(b.parent) + 1 if b.parent else 0) for b in bones) + " },")
out.append("\tRest = {")
for b in bones:
    p = rest[b.name].translation
    out.append(f"\t\t{{ {r(p.x)}, {r(p.y)}, {r(p.z)} }},")
out.append("\t},")
out.append("\tFrames = {")
# 마지막 프레임은 첫 프레임과 같은 자세(루프)라 뺌
for f in range(f0, f1):
    scene.frame_set(f)
    row = []
    for b in bones:
        A = W @ arm.pose.bones[b.name].matrix
        D = A @ rest[b.name].inverted()
        t = D.translation
        q = D.to_quaternion()
        row.append("{" + ",".join(r(v) for v in (t.x, t.y, t.z, q.x, q.y, q.z, q.w)) + "}")
    out.append("\t\t{ " + ", ".join(row) + " },")
out.append("\t},")
out.append("}")
open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
print(f"[bake] 뼈 {len(bones)}개, 프레임 {f1 - f0}개, {fps:g}fps -> {dst}")
