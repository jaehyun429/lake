"""정적(리그 없는) Meshy FBX 를 Blender(bpy) 로 읽어 삼각형을 줄이고 OBJ+MTL+PNG 로 내보냅니다.
수백만 삼각형짜리도 처리 가능 (fbx2obj.py 의 순수 파이썬 경로보다 훨씬 빠름).

사용법:
  <bpy 가 설치된 python> -I tools/mesh/static_decimate.py <입력.fbx> <출력.obj> [목표 삼각형=18000]
  (출력 이름이 Name.obj 면 Name.mtl, Name.png 가 같이 생김)
"""
import os
import shutil
import subprocess
import sys

import bpy


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    if len(argv) < 2:
        print(__doc__)
        sys.exit(2)
    src = os.path.abspath(argv[0])
    dst = os.path.abspath(argv[1])
    target = int(argv[2]) if len(argv) > 2 else 18000
    name = os.path.splitext(os.path.basename(dst))[0]
    out_dir = os.path.dirname(dst)
    os.makedirs(out_dir, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=src, use_anim=False)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        print("[static] 메시 없음")
        sys.exit(1)
    bpy.ops.object.select_all(action="DESELECT")
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    # 부모 변환(Meshy 는 보통 -90° X 회전 + 스케일)을 메시에 구워 넣음
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    before = tri_count(obj)
    print(f"[static] 입력 삼각형 {before}")
    if before > target:
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = max(0.0005, target / before * 0.98)
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    after = tri_count(obj)
    print(f"[static] 출력 삼각형 {after}")
    obj.name = name
    obj.data.name = name
    bpy.ops.object.shade_smooth()

    # 재질: 베이스 컬러 이미지 하나만 남기고 Name.png 로
    base_img = None
    for slot in obj.material_slots:
        mat = slot.material
        if not mat or not mat.node_tree:
            continue
        for n in mat.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image and "normal" not in n.image.name.lower() and "rough" not in n.image.name.lower() and "metal" not in n.image.name.lower():
                base_img = n.image
                break
        if base_img:
            break
    png_out = os.path.join(out_dir, name + ".png")
    if base_img:
        base_img.filepath_raw = png_out
        base_img.file_format = "PNG"
        base_img.save()
    else:
        # 원본 폴더에서 베이스 컬러 PNG 추정
        for f in os.listdir(os.path.dirname(src)):
            low = f.lower()
            if low.endswith(".png") and not any(k in low for k in ("normal", "metallic", "roughness")):
                shutil.copyfile(os.path.join(os.path.dirname(src), f), png_out)
                break
    if os.path.exists(png_out):
        subprocess.run(["sips", "-Z", "1024", png_out], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(f"[static] 텍스처: {png_out} (1024px 로 축소)")

    # OBJ 내보내기 (Y 위, -Z 앞 = 로블록스 기준)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.wm.obj_export(
        filepath=dst,
        export_selected_objects=True,
        export_uv=True,
        export_normals=True,
        export_materials=True,
        export_triangulated_mesh=True,
        forward_axis="NEGATIVE_Z",
        up_axis="Y",
        path_mode="RELATIVE",
    )
    # MTL 을 단순하게 다시 씀 (Import 3D 가 읽기 쉬운 형태)
    with open(os.path.join(out_dir, name + ".mtl"), "w") as f:
        f.write(f"newmtl {name}\nKd 1 1 1\nmap_Kd {name}.png\n")
    # OBJ 의 usemtl 을 통일
    lines = open(dst).read().splitlines()
    with open(dst, "w") as f:
        for ln in lines:
            if ln.startswith("mtllib"):
                f.write(f"mtllib {name}.mtl\n")
            elif ln.startswith("usemtl"):
                f.write(f"usemtl {name}\n")
            else:
                f.write(ln + "\n")
    dims = obj.dimensions
    print(f"[static] 크기(x,y,z 블렌더 기준): {dims.x:.2f} {dims.y:.2f} {dims.z:.2f}")
    print(f"[static] 내보냄: {dst}")


main()
