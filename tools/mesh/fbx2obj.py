import sys, struct, zlib, os, math
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fbxinfo.py')).read().split("path = sys.argv[1]")[0])
src, out, texname = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src, 'rb') as f:
    f.read(23); ver = struct.unpack('<I', f.read(4))[0]
    nodes = []
    while True:
        n = read_node(f, ver)
        if n is None: break
        nodes.append(n)
objs = [n for n in nodes if n[0] == 'Objects'][0][2]
conns = [n for n in nodes if n[0] == 'Connections'][0][2]
parent = {c[1][1]: c[1][2] for c in conns if c[1][0] == b'OO'}
models = {}
for n in objs:
    if n[0] == 'Model':
        props = {}
        for ch in n[2]:
            if ch[0] == 'Properties70':
                for p in ch[2]:
                    props[p[1][0].decode()] = p[1][4:]
        models[n[1][0]] = props
geom = [n for n in objs if n[0] == 'Geometry'][0]
def child(node, name):
    for c in node[2]:
        if c[0] == name: return c
    return None
verts = child(geom, 'Vertices')[1][0]
idx = child(geom, 'PolygonVertexIndex')[1][0]
uvnode = child(geom, 'LayerElementUV')
uvs, uvidx, mapping, ref = None, None, None, None
if uvnode:
    uvs = child(uvnode, 'UV')[1][0]
    mapping = child(uvnode, 'MappingInformationType')[1][0].decode()
    ref = child(uvnode, 'ReferenceInformationType')[1][0].decode()
    ui = child(uvnode, 'UVIndex')
    uvidx = ui[1][0] if ui else None
print('mapping', mapping, ref, 'uvs', len(uvs)//2 if uvs else 0, flush=True)
# transform chain (rotation XYZ euler + scaling), ignore translation
def rot_matrix(rx, ry, rz):
    cx, sx = math.cos(math.radians(rx)), math.sin(math.radians(rx))
    cy, sy = math.cos(math.radians(ry)), math.sin(math.radians(ry))
    cz, sz = math.cos(math.radians(rz)), math.sin(math.radians(rz))
    Rx = [[1,0,0],[0,cx,-sx],[0,sx,cx]]
    Ry = [[cy,0,sy],[0,1,0],[-sy,0,cy]]
    Rz = [[cz,-sz,0],[sz,cz,0],[0,0,1]]
    def mm(a,b): return [[sum(a[i][k]*b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return mm(Rz, mm(Ry, Rx))
def apply(m, v): return [sum(m[i][k]*v[k] for k in range(3)) for i in range(3)]
uid = parent.get(geom[1][0])
chain = []
while uid in models:
    chain.append(models[uid]); uid = parent.get(uid)
def xform(v):
    for props in chain:
        s = props.get('Lcl Scaling', [1,1,1]); r = props.get('Lcl Rotation', [0,0,0]); pr = props.get('PreRotation')
        v = [v[i]*s[i] for i in range(3)]
        v = apply(rot_matrix(*r), v)
        if pr: v = apply(rot_matrix(*pr), v)
    return v
nv = len(verts)//3
vout = [xform(verts[i*3:i*3+3]) for i in range(nv)]
# polygons
polys = []; cur = []
for pv, x in enumerate(idx):
    vi = x if x >= 0 else -x - 1
    cur.append((vi, pv))
    if x < 0:
        polys.append(cur); cur = []
def uv_of(vi, pv):
    if uvs is None: return None
    if mapping == 'ByPolygonVertex':
        k = uvidx[pv] if ref == 'IndexToDirect' else pv
    else:  # ByVertice
        k = uvidx[vi] if (ref == 'IndexToDirect' and uvidx) else vi
    return (uvs[k*2], uvs[k*2+1])
uvmap = {}; uvlist = []
def uvi(uv):
    if uv not in uvmap:
        uvmap[uv] = len(uvlist) + 1; uvlist.append(uv)
    return uvmap[uv]
faces = []
for poly in polys:
    for i in range(1, len(poly) - 1):
        tri = [poly[0], poly[i], poly[i+1]]
        faces.append([(vi + 1, uvi(uv_of(vi, pv)) if uvs is not None else None) for vi, pv in tri])
base = os.path.splitext(os.path.basename(out))[0]
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'w') as f:
    f.write('mtllib %s.mtl\nusemtl %s\n' % (base, base))
    for v in vout: f.write('v %.6f %.6f %.6f\n' % tuple(v))
    for uv in uvlist: f.write('vt %.6f %.6f\n' % uv)
    for fc in faces:
        f.write('f ' + ' '.join(('%d/%d' % (a, b)) if b else str(a) for a, b in fc) + '\n')
with open(os.path.join(os.path.dirname(out), base + '.mtl'), 'w') as f:
    f.write('newmtl %s\nKa 1 1 1\nKd 1 1 1\nKs 0 0 0\nmap_Kd %s\n' % (base, texname))
mins = [min(v[i] for v in vout) for i in range(3)]; maxs = [max(v[i] for v in vout) for i in range(3)]
print('wrote', out, 'verts', nv, 'tris', len(faces), 'size', [round(maxs[i]-mins[i], 3) for i in range(3)], flush=True)
