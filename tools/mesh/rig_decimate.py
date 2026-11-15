"""리그·애니메이션을 유지한 채 FBX 삼각형 수를 줄여 로블록스용 FBX 로 다시 내보냅니다 (Blender 필요).

사용법 (둘 중 하나):
  blender -b --python tools/mesh/rig_decimate.py -- <입력.fbx> <출력.fbx> [목표 삼각형=9500] [모델 이름=Wraith]
  <bpy 가 설치된 python> -I tools/mesh/rig_decimate.py <입력.fbx> <출력.fbx> [목표 삼각형] [모델 이름]
  (bpy 모듈: python3.11 -m venv bpyenv && bpyenv/bin/pip install bpy)

- Decimate(collapse) 는 UV 와 버텍스 그룹(스킨 가중치)을 보존합니다.
- 정점당 뼈 영향은 로블록스 한도인 4개로 제한하고 정규화합니다.
- 애니메이션(Mixamo Running 등)은 액션을 그대로 베이크해서 내보냅니다. 리프 본은 추가하지 않습니다.
- 텍스처는 FBX 에 포함(embed)되고, 같은 폴더에 PNG 도 복사됩니다.
- 끝나면 내보낸 파일을 다시 읽어 삼각형·뼈·프레임 수를 출력합니다.
"""
import os
import shutil
import sys

import bpy


def args():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    else:
        argv = argv[1:]
    if len(argv) < 2:
        print(__doc__)
        sys.exit(2)
    src = os.path.abspath(argv[0])
    dst = os.path.abspath(argv[1])
    target = int(argv[2]) if len(argv) > 2 else 9500
    name = argv[3] if len(argv) > 3 else os.path.splitext(os.path.basename(dst))[0]
    return src, dst, target, name


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_fbx(path):
    """Blender 버전마다 FBX 임포터 옵션이 달라서 안 받는 인자는 빼고 다시 시도."""
    kwargs = dict(filepath=path, use_anim=True, ignore_leaf_bones=True, automatic_bone_orientation=False, use_custom_normals=True)
    while True:
        try:
            return bpy.ops.import_scene.fbx(**kwargs)
        except TypeError as e:
            msg = str(e)
            removed = False
            for k in list(kwargs):
                if k != "filepath" and k in msg:
                    kwargs.pop(k)
                    removed = True
            if not removed:
                raise


def tri_count(obj):
    me = obj.data
    return sum(len(p.vertices) - 2 for p in me.polygons)


def mesh_objects():
    return [o for o in bpy.data.objects if o.type == "MESH"]


def armature_objects():
    return [o for o in bpy.data.objects if o.type == "ARMATURE"]


def select_only(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def join_meshes(meshes):
    if len(meshes) == 1:
        return meshes[0]
    select_only(meshes[0])
    for m in meshes[1:]:
        m.select_set(True)
    bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


def decimate(obj, target):
    before = tri_count(obj)
    if before <= target:
        print(f"[rig] 삼각형 {before} <= {target}, 감소 생략")
        return before, before
    select_only(obj)
    if bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    mod = obj.modifiers.new("DeadLakeDecimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = max(0.001, target / before * 0.98)
    mod.use_collapse_triangulate = True
    # Armature 모디파이어보다 앞에 두고 적용해야 스킨이 유지된 메시에 적용됨
    bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    after = tri_count(obj)
    print(f"[rig] 삼각형 {before} -> {after}")
    return before, after


def limit_weights(obj, limit=4):
    """정점당 가중치를 상위 limit 개만 남기고 정규화 (로블록스는 4개까지)."""
    me = obj.data
    groups = obj.vertex_groups
    if not groups:
        print("[rig] 경고: 버텍스 그룹(스킨 가중치)이 없음")
        return
    trimmed = 0
    for v in me.vertices:
        ws = [(g.weight, g.group) for g in v.groups if g.weight > 0]
        if not ws:
            continue
        ws.sort(reverse=True)
        keep = ws[:limit]
        drop = ws[limit:]
        if drop:
            trimmed += 1
            for _, gi in drop:
                groups[gi].remove([v.index])
        total = sum(w for w, _ in keep)
        if total > 0:
            for w, gi in keep:
                groups[gi].add([v.index], w / total, "REPLACE")
    print(f"[rig] 가중치 4개 초과였던 정점 {trimmed}개 정리, 그룹 {len(groups)}개")


def rename(arm, mesh, name):
    if arm:
        arm.name = name
        arm.data.name = name + "Armature"
    mesh.name = name + "Mesh"
    mesh.data.name = name + "Mesh"


def fix_materials(mesh):
    """Roblox 가 읽을 수 있게 Principled BSDF 의 Base Color 에 이미지가 꽂혀 있는지 확인."""
    for slot in mesh.material_slots:
        mat = slot.material
        if not mat or not mat.use_nodes:
            continue
        imgs = [n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image]
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if imgs and bsdf and not bsdf.inputs["Base Color"].is_linked:
            mat.node_tree.links.new(imgs[0].outputs["Color"], bsdf.inputs["Base Color"])
        for n in imgs:
            print(f"[rig] 텍스처: {n.image.name} ({n.image.size[0]}x{n.image.size[1]})")


def export(dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.fbx(
        filepath=dst,
        use_selection=False,
        object_types={"ARMATURE", "MESH"},
        use_mesh_modifiers=True,
        mesh_smooth_type="FACE",
        use_custom_props=False,
        add_leaf_bones=False,
        primary_bone_axis="Y",
        secondary_bone_axis="X",
        armature_nodetype="NULL",
        bake_anim=True,
        bake_anim_use_all_bones=True,
        bake_anim_use_nla_strips=False,
        bake_anim_use_all_actions=False,
        bake_anim_force_startend_keying=True,
        bake_anim_step=1.0,
        bake_anim_simplify_factor=1.0,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_UNITS",
        axis_forward="-Z",
        axis_up="Y",
        path_mode="COPY",
        embed_textures=True,
    )


def copy_textures(src_dir, dst_dir, name):
    """원본 폴더의 베이스 컬러 PNG 를 <이름>.png 로 복사 (FBX 임포터가 못 읽을 때 수동 적용용)."""
    for f in os.listdir(src_dir):
        low = f.lower()
        if low.endswith(".png") and not any(k in low for k in ("normal", "metallic", "roughness")):
            shutil.copyfile(os.path.join(src_dir, f), os.path.join(dst_dir, name + ".png"))
            print(f"[rig] 텍스처 복사: {f} -> {name}.png")
            return


def verify(dst):
    reset_scene()
    import_fbx(dst)
    meshes = mesh_objects()
    arms = armature_objects()
    tris = sum(tri_count(m) for m in meshes)
    bones = sum(len(a.data.bones) for a in arms)
    frames = None
    for a in arms:
        if a.animation_data and a.animation_data.action:
            fr = a.animation_data.action.frame_range
            frames = (int(fr[0]), int(fr[1]))
    maxinf = 0
    for m in meshes:
        for v in m.data.vertices:
            maxinf = max(maxinf, len([g for g in v.groups if g.weight > 0.0001]))
    print("[rig] ===== 검증 =====")
    print(f"[rig] 메시 {len(meshes)}개, 삼각형 {tris}, 리그 {len(arms)}개, 뼈 {bones}개, 정점당 최대 영향 {maxinf}")
    print(f"[rig] 애니메이션 프레임: {frames}")
    if tris > 10000:
        print("[rig] 경고: 삼각형이 10,000 을 넘어 스킨 메시 임포트가 거부될 수 있음")
    if frames is None:
        print("[rig] 경고: 애니메이션이 없음")


def main():
    src, dst, target, name = args()
    reset_scene()
    import_fbx(src)
    meshes = mesh_objects()
    arms = armature_objects()
    if not meshes:
        print("[rig] 메시가 없음")
        sys.exit(1)
    arm = arms[0] if arms else None
    print(f"[rig] 입력: 메시 {len(meshes)}개, 리그 {len(arms)}개, 뼈 {len(arm.data.bones) if arm else 0}개")
    if arm and arm.animation_data and arm.animation_data.action:
        fr = arm.animation_data.action.frame_range
        print(f"[rig] 액션: {arm.animation_data.action.name} 프레임 {int(fr[0])}-{int(fr[1])}")
        bpy.context.scene.frame_start = int(fr[0])
        bpy.context.scene.frame_end = int(fr[1])
    mesh = join_meshes(meshes)
    decimate(mesh, target)
    limit_weights(mesh, 4)
    select_only(mesh)
    bpy.ops.object.shade_smooth()
    fix_materials(mesh)
    rename(arm, mesh, name)
    export(dst)
    copy_textures(os.path.dirname(src), os.path.dirname(dst), name)
    print(f"[rig] 내보냄: {dst}")
    verify(dst)


main()
