import bpy, bmesh, math
from mathutils import Vector

def remove_hat(rider_name, fur_px=(40.5, 8.5)):
    r=bpy.data.objects[rider_name]; me=r.data
    gi={vg.name:vg.index for vg in r.vertex_groups}; hi=gi['head']
    bm=bmesh.new(); bm.from_mesh(me); uvl=bm.loops.layers.uv[0]; dl=bm.verts.layers.deform.verify()
    dele=[]
    for f in bm.faces:
        pts=[(l[uvl].uv.x*128,(1-l[uvl].uv.y)*128) for l in f.loops]
        cx=sum(p[0] for p in pts)/len(pts); cy=sum(p[1] for p in pts)/len(pts)
        if all(x<94 and y<=23.6 for x,y in pts) or (cx<94 and cy<24.2 and f.calc_center_median().z>1.25):
            dele.append(f)
    bmesh.ops.delete(bm, geom=dele, context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    edges=[e for e in bm.edges if e.is_boundary and all(v.co.z>1.2 and v[dl].get(hi,0)>0.5 for v in e.verts)]
    res=bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    poked=bmesh.ops.poke(bm, faces=res['faces'])
    FUR=(fur_px[0]/128, 1-fur_px[1]/128)
    for v in poked['verts']:
        v.co.z+=0.13; v[dl][hi]=1.0
    for f in poked['faces']:
        for l in f.loops: l[uvl].uv=FUR
    bm.normal_update(); bm.to_mesh(me); bm.free(); me.update()
    return len(dele), len(edges)

def surfboard(board_name):
    b=bpy.data.objects[board_name]; me=b.data
    L=1.05; W=0.29; yc=-0.04; ztop=0.05; th=0.07
    N=14
    def halfw(u):
        if u>=0: return W*max(0.0,(1-u**2.4))**0.62
        return W*max(0.0,(1-abs(u)**5))**0.5
    bm=bmesh.new(); uvl=bm.loops.layers.uv.new('UVMap')
    us=[-1+2*i/N for i in range(N+1)]
    us[0]=-0.985; us[-1]=0.995
    top=[];bot=[]
    for u in us:
        w=halfw(u); x=u*L
        rows_t=[]; rows_b=[]
        for s in (-1,1):
            rows_t.append(bm.verts.new((x, yc+s*w, ztop)))
            rows_b.append(bm.verts.new((x, yc+s*w*0.92, ztop-th)))
        top.append(rows_t); bot.append(rows_b)
    def uvmap(v):
        u=(v.co.x/L+1)/2; t=((v.co.y-yc)/W+1)/2
        return ((76+u*40)/128, 1-(106+t*10)/128)
    faces=[]
    for i in range(N):
        a,b2=top[i],top[i+1]
        faces.append(bm.faces.new((a[0],b2[0],b2[1],a[1])))          # deck
        c,d=bot[i],bot[i+1]
        faces.append(bm.faces.new((c[1],d[1],d[0],c[0])))           # bottom
        faces.append(bm.faces.new((a[0],c[0],d[0],b2[0])))          # rails
        faces.append(bm.faces.new((b2[1],d[1],c[1],a[1])))
    faces.append(bm.faces.new((top[0][1],bot[0][1],bot[0][0],top[0][0])))
    faces.append(bm.faces.new((top[-1][0],bot[-1][0],bot[-1][1],top[-1][1])))
    # fin under the tail
    for side in (-0.006, 0.006):
        f0=bm.verts.new((-0.86*L, yc+side, ztop-th)); f1=bm.verts.new((-0.62*L, yc+side, ztop-th)); f2=bm.verts.new((-0.84*L, yc+side, ztop-th-0.2))
        faces.append(bm.faces.new((f0,f1,f2) if side<0 else (f2,f1,f0)))
    for f in faces:
        for l in f.loops: l[uvl].uv=uvmap(l.vert)
    bmesh.ops.recalc_face_normals(bm, faces=faces[:-2])
    bm.to_mesh(me); bm.free(); me.update()
    for p in me.polygons: p.use_smooth=False
    return len(me.vertices)

def use_texture(mat_owner_names, path, newname):
    img=bpy.data.images.load(path, check_existing=True); img.reload()
    mats=set()
    for n in mat_owner_names:
        o=bpy.data.objects[n]
        m=o.data.materials[0]
        if not m.name.endswith('_Beach'):
            m=m.copy(); m.name=newname+'_Beach'
        o.data.materials[0]=m; mats.add(m)
    for m in mats:
        for nd in m.node_tree.nodes:
            if nd.type=='TEX_IMAGE': nd.image=img; nd.interpolation='Closest'
    return [m.name for m in mats]

def export(root_name, out):
    import io, contextlib, os
    bpy.ops.object.select_all(action='DESELECT')
    root=bpy.data.objects[root_name]
    for o in [root]+list(root.children_recursive):
        if o.visible_get(): o.select_set(True)
    bpy.context.view_layer.objects.active=root
    f=io.StringIO()
    with contextlib.redirect_stdout(f):
        bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, use_visible=True,
            export_animations=True, export_animation_mode='ACTIONS', export_skins=True, export_image_format='AUTO')
    return os.path.getsize(out)

HAIR_PX=(40.5, 8.5)   # the old beanie area of the texture gets repainted as hair

def add_hair(rider_name, seed=1, quills=False):
    """Voluminous spiky hair: a solid rounded hair mass on the head, chunky spikes sweeping
    up and back out of it, a full fringe above the eyes and tufts over the ears."""
    import random
    random.seed(seed)
    r=bpy.data.objects[rider_name]; me=r.data
    gi={vg.name:vg.index for vg in r.vertex_groups}; hi=gi['head']
    bm=bmesh.new(); bm.from_mesh(me); uvl=bm.loops.layers.uv[0]; dl=bm.verts.layers.deform.verify()
    hv=[v for v in bm.verts if v[dl].get(hi,0)>0.5 and abs(v.co.x)<0.3]
    top=max(v.co.z for v in hv)
    cap=[v.co for v in hv if v.co.z>top-0.3]
    c=sum(cap,Vector())/len(cap); c.z=top-0.2
    HUV=(HAIR_PX[0]/128, 1-HAIR_PX[1]/128); TIP=((HAIR_PX[0]+30)/128, 1-(HAIR_PX[1]+4)/128)
    if quills:   # hedgehog: use the brown spine colours (pale tips) from his back
        HUV=(110.5/128, 1-98.5/128); TIP=(110.5/128, 1-86.5/128)
    new_faces=[]
    def setuv(f, tipverts=()):
        for l in f.loops: l[uvl].uv=TIP if l.vert in tipverts else HUV
    # 1) hair mass: the top of an ellipsoid, tipped back a little, hugging the head
    centre=c+Vector((0,0.06,0.1)); R=Vector((0.37,0.41,0.25))
    segs, rings = 12, 6
    grid=[]
    for i in range(rings+1):
        ph=(math.pi/2)*(1-i/rings)            # top (pi/2) down to the equator (0)
        row=[]
        for k in range(segs):
            th=2*math.pi*k/segs
            x=math.cos(ph)*math.sin(th); y=math.cos(ph)*math.cos(th); z=math.sin(ph)
            drop = 0.22*max(0.0,y) - 0.12*max(0.0,-y)   # lower at the back, lifted off the face
            p=centre+Vector((x*R.x, y*R.y, z*R.z - drop*(1-z)))
            v=bm.verts.new(p); v[dl][hi]=1.0; row.append(v)
        grid.append(row)
    topv=bm.verts.new(centre+Vector((0,0,R.z))); topv[dl][hi]=1.0
    for k in range(segs):
        f=bm.faces.new((topv, grid[0][(k+1)%segs], grid[0][k])); setuv(f); new_faces.append(f)
    for i in range(rings):
        for k in range(segs):
            f=bm.faces.new((grid[i][k], grid[i][(k+1)%segs], grid[i+1][(k+1)%segs], grid[i+1][k])); setuv(f); new_faces.append(f)
    def surf(th, ph):
        x=math.cos(ph)*math.sin(th); y=math.cos(ph)*math.cos(th); z=math.sin(ph)
        drop=0.22*max(0.0,y) - 0.12*max(0.0,-y)
        return centre+Vector((x*R.x, y*R.y, z*R.z - drop*(1-z))), Vector((x,y,z))
    # 2) chunky spikes
    def spike(base, d, length, radius, sides=5):
        d=d.normalized(); q=d.to_track_quat('Z','Y').to_matrix(); ring=[]
        for k in range(sides):
            a=k*2*math.pi/sides
            v=bm.verts.new(base+q@Vector((math.cos(a)*radius, math.sin(a)*radius*0.75, 0))); v[dl][hi]=1.0; ring.append(v)
        tip=bm.verts.new(base+d*length); tip[dl][hi]=1.0
        for k in range(sides):
            f=bm.faces.new((ring[k],ring[(k+1)%sides],tip)); setuv(f,(tip,)); new_faces.append(f)
        f=bm.faces.new(list(reversed(ring))); setuv(f); new_faces.append(f)
    back=Vector((0,1,0))
    if quills:
        # a dense crown of quills over the whole head, sweeping back like his back spines
        # neat overlapping rows, lying close to the head and sweeping back like his back spines
        for row,ph in enumerate([1.35,1.1,0.85,0.6,0.35,0.12]):
            count=6+row*2
            for k in range(count):
                th=-2.2+4.4*(k+0.5)/count+random.uniform(-0.06,0.06)
                p,n=surf(th, ph)
                if n.y < -0.45 and ph < 0.7:
                    continue        # keep the face clear
                tang=(back - n*back.dot(n)).normalized()      # along the head, towards the back
                d=n*0.28+tang*1.0
                spike(p-n*0.05, d, random.uniform(0.2,0.27), 0.06, sides=4)
        bm.normal_update(); bm.to_mesh(me); bm.free(); me.update()
        for p in me.polygons[-len(new_faces):]: p.use_smooth=False
        return len(new_faces)
    # crown and back: rows of big spikes sweeping back
    for row,(ph,count,length,rad) in enumerate([(1.15,4,0.3,0.12),(0.75,6,0.32,0.12),(0.38,6,0.28,0.11),(0.08,5,0.24,0.1)]):
        for k in range(count):
            th=math.radians(-100+200*(k+0.5)/count)+random.uniform(-0.08,0.08)   # around the back half + sides
            th=math.pi+th*0.95 if row>0 else th*0.9
            p,n=surf(th, ph)
            d=n*0.8+back*0.55+Vector((0,0,0.35 if row<2 else -0.05))
            spike(p-n*0.04, d, length*random.uniform(0.9,1.15), rad)
    # a few spikes standing up on top
    for k in range(3):
        p,n=surf(random.uniform(-0.8,0.8), random.uniform(1.0,1.35))
        spike(p-n*0.03, n+back*0.3, random.uniform(0.24,0.3), 0.11)
    # fringe: thick spikes along the front edge, pointing forwards and a little down
    for k in range(5):
        x=-0.3+0.6*k/4
        p,n=surf(math.radians(x*120), 0.4)
        spike(p+Vector((0,0.03,0)), Vector((x*0.6,-1.0,-0.12+random.uniform(-0.06,0.06))), random.uniform(0.15,0.2), 0.085)
    # tufts over the ears / sides
    for s in (-1,1):
        for k in range(2):
            p,n=surf(s*math.radians(80+25*k), 0.15)
            spike(p, Vector((s*1.0,0.35+0.3*k,-0.25)), random.uniform(0.18,0.22), 0.09)
    bm.normal_update(); bm.to_mesh(me); bm.free(); me.update()
    for p in me.polygons[-len(new_faces):]: p.use_smooth=False
    return len(new_faces)

HAIRCUT_LIB = r"C:\Users\luker\OneDrive\Documents\super-snowbaoarding!\assets\models\source\bao_haircut.blend"

def add_haircut(rider_name, tame=0.3):
    """Bao's haircut from the platformer (rounded mop, pointed bangs, short spikes round the
    edge), joined into the rider, rigged to the head and coloured with the hair texture area."""
    with bpy.data.libraries.load(HAIRCUT_LIB, link=False) as (src, dst):
        dst.objects=['BaoHairRest']
    hair=dst.objects[0]
    r=bpy.data.objects[rider_name]; me=r.data
    gi={vg.name:vg.index for vg in r.vertex_groups}; hi=gi['head']
    bm=bmesh.new(); bm.from_mesh(me); uvl=bm.loops.layers.uv[0]; dl=bm.verts.layers.deform.verify()
    hb=bmesh.new(); hb.from_mesh(hair.data)
    HUV=(HAIR_PX[0]/128, 1-HAIR_PX[1]/128)
    # The mop's surface: an ellipsoid a little bigger than the head. Anything sticking out
    # past it (the spikes) is pulled most of the way back in, so it reads as soft tufts.
    hv=[v.co for v in bm.verts if v[dl].get(hi,0)>0.5 and v.co.z>0.95]
    lo=Vector([min(c[i] for c in hv) for i in range(3)]); up=Vector([max(c[i] for c in hv) for i in range(3)])
    ctr=(lo+up)/2; rad=(up-lo)/2
    rad=Vector((rad.x*1.18, rad.y*1.2, rad.z*1.22)); ctr.z+=0.04
    for v in hb.verts:
        d=v.co-ctr
        k=math.sqrt((d.x/rad.x)**2+(d.y/rad.y)**2+(d.z/rad.z)**2)
        if k>1.0:
            v.co=ctr+d*((1.0+(k-1.0)*tame)/k)
    vmap={}
    for v in hb.verts:
        nv=bm.verts.new(v.co); nv[dl][hi]=1.0; vmap[v]=nv
    n=0
    for f in hb.faces:
        try:
            nf=bm.faces.new([vmap[v] for v in f.verts])
        except ValueError:
            continue
        for l in nf.loops: l[uvl].uv=HUV
        nf.smooth=True; n+=1
    hb.free()
    bm.normal_update(); bm.to_mesh(me); bm.free(); me.update()
    bpy.data.objects.remove(hair, do_unlink=True)
    return n

HAIR_DARK_PX=(9.5, 18.5); HAIR_LIGHT_PX=(75.5, 13.5)

def add_layers(rider_name, quills=False, seed=3):
    """Layered hair: tiers of flat, tapered locks lying on the head like shingles - a darker
    under-layer peeking out at the nape, mid layers, a lighter top layer and short bangs.
    Call BEFORE add_haircut / add_hair so the head shape isn't measured off the new hair."""
    import random
    random.seed(seed)
    r=bpy.data.objects[rider_name]; me=r.data
    gi={vg.name:vg.index for vg in r.vertex_groups}; hi=gi['head']
    bm=bmesh.new(); bm.from_mesh(me); uvl=bm.loops.layers.uv[0]; dl=bm.verts.layers.deform.verify()
    hv=[v.co for v in bm.verts if v[dl].get(hi,0)>0.5 and v.co.z>0.95]
    lo=Vector([min(c[i] for c in hv) for i in range(3)]); up=Vector([max(c[i] for c in hv) for i in range(3)])
    ctr=(lo+up)/2; rad=(up-lo)/2
    rad=Vector((rad.x*1.18, rad.y*1.2, rad.z*1.22)); ctr.z+=0.04
    uv=lambda px:(px[0]/128, 1-px[1]/128)
    DARK, BASE, LIGHT = uv(HAIR_DARK_PX), uv(HAIR_PX), uv(HAIR_LIGHT_PX)
    if quills:
        BASE=(110.5/128, 1-98.5/128); LIGHT=(110.5/128, 1-86.5/128)
    nf=[0]
    def nv(p):
        v=bm.verts.new(p); v[dl][hi]=1.0; return v
    def face(vs, col):
        try: f=bm.faces.new(vs)
        except ValueError: return
        for l in f.loops: l[uvl].uv=col
        f.smooth=False; nf[0]+=1
    def surf(az, el, s):
        u=Vector((math.cos(el)*math.sin(az), math.cos(el)*math.cos(az), math.sin(el)))
        p=ctr+Vector((u.x*rad.x, u.y*rad.y, u.z*rad.z))*s
        n=Vector((u.x/rad.x, u.y/rad.y, u.z/rad.z)).normalized()
        return p, n
    def lock(p, n, aim, L, W, flare, col, thick=0.03, segs=3):
        t=(aim - n*aim.dot(n)).normalized(); b=n.cross(t).normalized()
        top=[]; bot=[]
        for i in range(segs):
            f=i/segs
            c=p - n*0.03 + t*L*f + n*(flare*L*f**1.5)
            w=W*(1-f)**0.7 * (0.8+0.4*math.sin(math.pi*min(1,f*2)))   # widest a little way down
            top.append((nv(c+b*w), nv(c-b*w))); bot.append((nv(c+b*w-n*thick*(1-f)), nv(c-b*w-n*thick*(1-f))))
        tip=nv(p - n*0.03 + t*L + n*flare*L)
        for i in range(segs-1):
            face([top[i][0], top[i+1][0], top[i+1][1], top[i][1]], col)
            face([bot[i][1], bot[i+1][1], bot[i+1][0], bot[i][0]], DARK)
            face([top[i][0], bot[i][0], bot[i+1][0], top[i+1][0]], col)
            face([top[i][1], top[i+1][1], bot[i+1][1], bot[i][1]], col)
        a,c_=top[-1]; ba,bc=bot[-1]
        face([a, tip, c_], col); face([bc, tip, ba], DARK)
        face([a, ba, tip], col); face([c_, tip, bc], col)
    down=Vector((0,0,-1)); back=Vector((0,1,0))
    if quills:
        # tiers of flat quills sweeping back over the head, darker underneath
        rows=[(0.05,1.5,8,0.26,0.05,0.1,DARK,1.0),(0.4,1.7,9,0.26,0.055,0.1,BASE,1.03),
              (0.75,2.0,9,0.24,0.055,0.08,BASE,1.05),(1.1,2.6,8,0.22,0.055,0.08,LIGHT,1.07)]
        for el,span,count,L,W,fl,col,s in rows:
            for k in range(count):
                az=-span+2*span*(k+0.5)/count+random.uniform(-0.05,0.05)
                p,n=surf(az,el,s)
                lock(p,n,back*1.0+down*0.35,L*random.uniform(0.9,1.1),W,fl,col)
    else:
        rows=[(-0.05,1.9,9,0.24,0.085,0.1,DARK,1.0),     # under-layer peeking out at the nape
              (0.30,2.05,9,0.24,0.09,0.09,BASE,1.03),
              (0.65,2.35,9,0.22,0.095,0.08,BASE,1.05),
              (1.00,math.pi,7,0.20,0.10,0.06,LIGHT,1.07)] # top layer, all the way round
        for row,(el,span,count,L,W,fl,col,s) in enumerate(rows):
            off=0.5*(row%2)
            for k in range(count):
                az=-span+2*span*((k+0.5+off)%count)/count+random.uniform(-0.05,0.05)
                p,n=surf(az,el,s)
                lock(p,n,down,L*random.uniform(0.9,1.1),W,fl,col)
        # short layered bangs across the forehead
        for k in range(5):
            az=math.pi+(-0.6+1.2*k/4)
            p,n=surf(az,0.62,1.04)
            lock(p,n,down+Vector((0,-0.3,0)),random.uniform(0.13,0.16),0.08,0.15,BASE)
    bm.normal_update(); bm.to_mesh(me); bm.free(); me.update()
    return nf[0]
