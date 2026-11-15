"""parts.json 의 로블록스 파트들을 Blender 에 세워 렌더한다. 사용: python -I render_parts.py parts.json out_prefix"""
import json, math, sys
import bpy, bmesh
from mathutils import Matrix, Vector

parts = json.load(open(sys.argv[1]))
prefix = sys.argv[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# Roblox(Y-up, 오른손) -> Blender(Z-up): (x, y, z) -> (x, -z, y)
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
Ci = C.inverted()

mats = {}
def material(color, transparency):
    key = (tuple(round(c, 3) for c in color), round(transparency, 2))
    if key in mats:
        return mats[key]
    m = bpy.data.materials.new("m")
    m.diffuse_color = (*color, 1 - transparency)
    m.roughness = 0.9
    mats[key] = m
    return m

def wedge_mesh():
    # Roblox WedgePart: +Z 쪽이 높고 -Z 로 내려가는 경사. 단위 크기 1 (중심 원점)
    bm = bmesh.new()
    v = [bm.verts.new(p) for p in [(-.5,-.5,-.5),(.5,-.5,-.5),(.5,-.5,.5),(-.5,-.5,.5),(-.5,.5,.5),(.5,.5,.5)]]
    # 로블록스 로컬 (x,y,z): 바닥 4개 + 뒤쪽(+z) 위 2개
    for f in [(0,1,2,3),(3,2,5,4),(0,4,5,1),(0,3,4),(1,5,2)]:
        bm.faces.new([v[i] for i in f])
    me = bpy.data.meshes.new("wedge"); bm.to_mesh(me); return me

def box_mesh():
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0); me = bpy.data.meshes.new("box"); bm.to_mesh(me); return me
def cyl_mesh():
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=0.5, radius2=0.5, depth=1.0)
    # Blender 원기둥 축은 Z, 로블록스 Cylinder 축은 X → 로컬에서 Z→X 로 회전
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0,0,0), matrix=Matrix.Rotation(math.radians(90), 3, 'Y'))
    me = bpy.data.meshes.new("cyl"); bm.to_mesh(me); return me
def ball_mesh():
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=0.5); me = bpy.data.meshes.new("ball"); bm.to_mesh(me); return me

MESH = {"box": box_mesh(), "cyl": cyl_mesh(), "ball": ball_mesh(), "wedge": wedge_mesh()}
for me in MESH.values():
    for p in me.polygons: p.use_smooth = False

groups = {}
for p in parts:
    if p["tag"] == "meta":
        continue
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p["cf"]
    # 로블록스 CFrame 행렬 (행 우선)
    R = Matrix(((r00, r01, r02, x), (r10, r11, r12, y), (r20, r21, r22, z), (0, 0, 0, 1)))
    S = Matrix.Diagonal((*p["size"], 1))
    M = C @ R @ S  # 로컬 단위 메시 → 로블록스 → 블렌더
    kind = "box"
    if p["class"] == "WedgePart": kind = "wedge"
    elif p["shape"].endswith("Cylinder"): kind = "cyl"
    elif p["shape"].endswith("Ball"): kind = "ball"
    ob = bpy.data.objects.new(p["name"], MESH[kind])
    ob.matrix_world = M
    ob.data = MESH[kind]
    # 재질은 오브젝트 단위로 (메시 공유)
    ob.color = (*p["color"], 1 - p["transparency"])
    scene.collection.objects.link(ob)
    groups.setdefault(p["tag"], []).append(ob)

scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "OBJECT"
scene.display.shading.show_shadows = True
scene.display.shading.shadow_intensity = 0.6
scene.display.shading.show_cavity = True
scene.render.resolution_x = 1100; scene.render.resolution_y = 700
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
world = bpy.data.worlds.new("w"); scene.world = world; world.color = (0.15, 0.17, 0.2)

cam_data = bpy.data.cameras.new("Cam"); cam_data.lens = 28
cam = bpy.data.objects.new("Cam", cam_data); scene.collection.objects.link(cam); scene.camera = cam

def center_of(obs):
    lo = Vector((1e9,)*3); hi = Vector((-1e9,)*3)
    for ob in obs:
        if ob.dimensions.length > 60: continue  # 땅 제외
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            lo = Vector(min(a, b) for a, b in zip(lo, w)); hi = Vector(max(a, b) for a, b in zip(hi, w))
    return (lo + hi) / 2, hi - lo

for tag, obs in groups.items():
    # 다른 그룹 숨김
    for t2, o2 in groups.items():
        for ob in o2: ob.hide_render = (t2 != tag)
    ctr, dim = center_of(obs)
    # 호수(원점) 쪽에서 바라봄: 로블록스 호수중심 (0,0,0) → 블렌더 (0,0,0)
    toward = (Vector((0, 0, 0)) - ctr); toward.z = 0; toward.normalize()
    for i, (yaw, dist, height) in enumerate([(0, 1.25, 0.55), (40, 1.1, 0.35), (-55, 1.0, 1.0)]):
        d = Matrix.Rotation(math.radians(yaw), 3, 'Z') @ toward
        span = max(dim.x, dim.y, 14)
        cam.location = ctr + d * span * dist + Vector((0, 0, span * height))
        look = ctr + Vector((0, 0, dim.z * 0.25)) - cam.location
        cam.rotation_euler = look.to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = f"{prefix}_{tag}_{i}.png"
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath)
