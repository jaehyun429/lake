import sys, os, pymeshlab
src, out_obj, target = sys.argv[1], sys.argv[2], int(sys.argv[3])
ms = pymeshlab.MeshSet()
ms.load_new_mesh(src)
m = ms.current_mesh()
print('in', m.vertex_number(), m.face_number(), 'wedgeUV', m.has_wedge_tex_coord(), flush=True)
ms.meshing_remove_duplicate_vertices()
if ms.current_mesh().face_number() > target:
    ms.meshing_decimation_quadric_edge_collapse_with_texture(targetfacenum=target, qualitythr=0.3, preserveboundary=True, optimalplacement=True, planarquadric=True)
ms.meshing_remove_unreferenced_vertices()
ms.compute_normal_per_vertex()
m = ms.current_mesh()
print('out', m.vertex_number(), m.face_number(), flush=True)
ms.save_current_mesh(out_obj, save_vertex_normal=True, save_wedge_texcoord=True, save_wedge_normal=False, save_vertex_color=False, save_polygonal=False)
base = os.path.splitext(os.path.basename(out_obj))[0]
d = os.path.dirname(out_obj)
# rewrite material references to our own <base>.mtl
lines = open(out_obj).read().split('\n')
outl = ['mtllib %s.mtl' % base, 'usemtl %s' % base] + [l for l in lines if not (l.startswith('mtllib') or l.startswith('usemtl'))]
open(out_obj, 'w').write('\n'.join(outl))
for f in os.listdir(d):
    if f.endswith('.obj.mtl'):
        os.remove(os.path.join(d, f))
print('wrote', out_obj, flush=True)
