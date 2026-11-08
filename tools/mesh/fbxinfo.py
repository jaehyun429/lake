import sys, struct, zlib

def read_node(f, ver):
    if ver >= 7500:
        end, nprops, plen = struct.unpack('<QQQ', f.read(24))
        nlen = struct.unpack('<B', f.read(1))[0]
    else:
        end, nprops, plen = struct.unpack('<III', f.read(12))
        nlen = struct.unpack('<B', f.read(1))[0]
    if end == 0:
        return None
    name = f.read(nlen).decode('latin1')
    props = []
    for _ in range(nprops):
        t = f.read(1)
        if t in b'YCIFDL':
            fmt = {b'Y':'<h', b'C':'<?', b'I':'<i', b'F':'<f', b'D':'<d', b'L':'<q'}[t]
            props.append(struct.unpack(fmt, f.read(struct.calcsize(fmt)))[0])
        elif t in b'fdlib':
            alen, enc, clen = struct.unpack('<III', f.read(12))
            raw = f.read(clen)
            if enc:
                raw = zlib.decompress(raw)
            fmt = {b'f':'f', b'd':'d', b'l':'q', b'i':'i', b'b':'?'}[t]
            props.append(list(struct.unpack('<%d%s' % (alen, fmt), raw)))
        elif t in b'SR':
            l = struct.unpack('<I', f.read(4))[0]
            props.append(f.read(l))
        else:
            raise ValueError('bad prop type %r' % t)
    children = []
    while f.tell() < end:
        c = read_node(f, ver)
        if c is None:
            break
        children.append(c)
    f.seek(end)
    return (name, props, children)

def walk(node, depth, out):
    name, props, children = node
    out.append((depth, name, props))
    for c in children:
        walk(c, depth + 1, out)

path = sys.argv[1]
with open(path, 'rb') as f:
    magic = f.read(23)
    ver = struct.unpack('<I', f.read(4))[0]
    print('version', ver)
    nodes = []
    while True:
        n = read_node(f, ver)
        if n is None:
            break
        nodes.append(n)
flat = []
for n in nodes:
    walk(n, 0, flat)
polys = 0; verts = 0; meshes = 0
mins = [1e18]*3; maxs = [-1e18]*3
unit = None
for depth, name, props in flat:
    if name == 'UnitScaleFactor' or (name == 'P' and props and props[0] == b'UnitScaleFactor'):
        unit = props[-1]
    if name == 'Vertices':
        meshes += 1
        v = props[0]; verts += len(v)//3
        for i in range(0, len(v), 3):
            for k in range(3):
                mins[k] = min(mins[k], v[i+k]); maxs[k] = max(maxs[k], v[i+k])
    if name == 'PolygonVertexIndex':
        idx = props[0]
        # count polygons (negative index marks last vertex of polygon); triangles = sum(n-2)
        n = 0; tris = 0; count = 0
        for x in idx:
            n += 1
            if x < 0:
                tris += n - 2; count += 1; n = 0
        polys += tris
    if name == 'AnimationStack':
        print('animstack', props[1] if len(props) > 1 else props)
    if name == 'Model' and len(props) > 2:
        print('model', props[1].split(b'\x00')[0].decode('latin1', 'replace'), props[2])
print('unit', unit, 'meshes', meshes, 'verts', verts, 'triangles', polys)
print('bbox min', [round(x,2) for x in mins], 'max', [round(x,2) for x in maxs], 'size', [round(maxs[i]-mins[i],2) for i in range(3)])
