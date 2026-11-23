"""Builds the chinchilla (Ignatius) and West Highland terrier (Barney) riders from Piao's rig.

Run on a COPY of red_panda.blend or red_panda_beach.blend:
  blender -b copy.blend --python new_rider_build.py -- <chinchilla|westie> <snow|beach>
Writes <rider>[_beach].blend, its texture, and ../<rider>[_beach].glb.
"""
import bpy, bmesh, math, os, sys
import numpy as np
from mathutils import Vector

HERE = r"C:\Users\luker\OneDrive\Documents\super-snowbaoarding!\assets\models\source"
TEX = os.path.join(HERE, "textures")

# Colours in the red panda texture (sRGB 0-255) -> a named slot.
KEYS = {
    "fur": (200, 85, 38), "fur_dark": (140, 45, 28), "hair_dark": (60, 30, 25),
    "cream": (250, 245, 235), "ink": (25, 22, 25),
    "hat": (48, 135, 75), "hat_dark": (30, 100, 58),
    "jacket": (240, 185, 45), "jacket_2": (250, 160, 20),
    "pants": (65, 58, 75), "board": (35, 175, 165),
    "swim": (115, 25, 35), "swim_dark": (70, 15, 20), "swim_light": (175, 60, 55),
    "skin_a": (215, 130, 105), "skin_b": (225, 155, 135),
    "goggle": (250, 100, 10), "lens": (150, 250, 220),
}

RIDERS = {
    "chinchilla": {
        "root": "Chinchilla",
        "pal": {
            "fur": (150, 155, 168), "fur_dark": (98, 101, 116), "hair_dark": (66, 68, 84),
            "hat": (118, 66, 170), "hat_dark": (82, 44, 128),
            "jacket": (238, 112, 158), "jacket_2": (250, 200, 90),
            "pants": (44, 48, 92), "board": (120, 96, 235),
            "swim": (168, 172, 186), "swim_dark": (110, 113, 128), "swim_light": (205, 208, 218),
            "skin_a": (196, 200, 210), "skin_b": (210, 213, 222),
        },
        "ear_colour": (172, 176, 188), "ear_inner": (240, 170, 185),
    },
    "westie": {
        "root": "Westie",
        "pal": {
            "fur": (244, 240, 228), "fur_dark": (208, 200, 186), "hair_dark": (176, 168, 156),
            "hat": (36, 58, 138), "hat_dark": (24, 38, 100),
            "jacket": (214, 48, 54), "jacket_2": (250, 205, 70),
            "pants": (44, 50, 78), "board": (240, 190, 50),
            "swim": (250, 247, 238), "swim_dark": (205, 198, 186), "swim_light": (255, 253, 246),
            "skin_a": (235, 228, 214), "skin_b": (245, 240, 228),
        },
        "ear_colour": (236, 230, 216), "ear_inner": (238, 176, 170),
    },
}

# Spare texels in the atlas used by the new parts.
PX_BLACK, PX_WHITE, PX_WHISKER, PX_PINK = (104, 47), (110, 47), (116, 47), (122, 47)
PX_FUR, PX_FUR_DARK = (98, 47), (100, 47)


def uv_of(px):
    return ((px[0] + 0.5) / 128, 1 - (px[1] + 0.5) / 128)


def paint(src_path, out_path, cfg):
    im = bpy.data.images.load(src_path, check_existing=False)
    w, h = im.size
    a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1].copy()
    rgb = a[..., :3]
    names = list(KEYS)
    keys = np.array([KEYS[n] for n in names], dtype=np.float32) / 255
    idx = np.argmin(((rgb[:, :, None, :] - keys[None, None]) ** 2).sum(-1), axis=2)
    out = rgb.copy()
    for i, n in enumerate(names):
        if n in cfg["pal"]:
            t = np.array(cfg["pal"][n], dtype=np.float32) / 255
            m = idx == i
            out[m] = np.clip(t + (rgb[m] - keys[i]) * 0.5, 0, 1)

    # face: the panda's brown eye patches become plain fur
    fur = np.array(cfg["pal"]["fur"], dtype=np.float32) / 255
    y0, y1, x0, x1 = 22, 46, 9, 39
    f = rgb[y0:y1, x0:x1]
    lum = f.mean(-1)
    brown = (f[..., 0] > f[..., 1] * 1.2) & (lum > 0.18) & (lum < 0.65)
    out[y0:y1, x0:x1][brown] = fur

    # ears: plain outer colour, soft pink inside
    out[0:24, 96:128] = np.array(cfg["ear_colour"], dtype=np.float32) / 255
    pink = np.array(cfg["ear_inner"], dtype=np.float32) / 255

    out[PX_PINK[1], PX_PINK[0]] = pink
    out[PX_FUR[1], PX_FUR[0]] = fur
    out[PX_FUR_DARK[1], PX_FUR_DARK[0]] = np.array(cfg["pal"]["fur_dark"], dtype=np.float32) / 255
    for px, c in ((PX_BLACK, (0.05, 0.05, 0.06)), (PX_WHITE, (0.98, 0.97, 0.93)), (PX_WHISKER, (0.92, 0.92, 0.95))):
        out[px[1], px[0]] = c

    a[..., :3] = out
    a[..., 3] = 1.0
    res = bpy.data.images.new(os.path.basename(out_path), w, h, alpha=True)
    res.pixels.foreach_set(a[::-1].ravel())
    res.filepath_raw = out_path
    res.file_format = "PNG"
    res.save()
    bpy.data.images.remove(res)
    bpy.data.images.remove(im)
    img = bpy.data.images.load(out_path, check_existing=False)
    img.name = os.path.basename(out_path)
    return img


def islands(bm):
    seen, out = set(), []
    for v0 in bm.verts:
        if v0 in seen:
            continue
        stack, part = [v0], []
        seen.add(v0)
        while stack:
            v = stack.pop()
            part.append(v)
            for e in v.link_edges:
                o = e.other_vert(v)
                if o not in seen:
                    seen.add(o)
                    stack.append(o)
        out.append(part)
    return out


class Builder:
    def __init__(self, obj):
        self.obj = obj
        self.g = {vg.name: vg.index for vg in obj.vertex_groups}
        self.bm = bmesh.new()
        self.bm.from_mesh(obj.data)
        self.uv = self.bm.loops.layers.uv[0]
        self.dl = self.bm.verts.layers.deform.verify()

    def bone_of(self, part):
        tot = {}
        for v in part:
            for k, w in v[self.dl].items():
                tot[k] = tot.get(k, 0) + w
        return max(tot, key=tot.get) if tot else -1

    def ears(self):
        out = []
        for part in islands(self.bm):
            b = self.bone_of(part)
            if b in (self.g["ear.L"], self.g["ear.R"]):
                faces = {f for v in part for f in v.link_faces}
                out.append((part, len(faces) == 1, 1 if b == self.g["ear.R"] else -1))
        return out

    def round_ears(self, cx, cz, rx, rz):
        for part, inner, side in self.ears():
            mx = sum(v.co.x for v in part) / len(part)
            mz = sum(v.co.z for v in part) / len(part)
            k = 0.74 if inner else 1.0
            for v in part:
                a = math.atan2(v.co.z - mz, v.co.x - mx)
                v.co.x = side * cx + math.cos(a) * rx * k
                v.co.z = cz + math.sin(a) * rz * k
                if inner:
                    v.co.y -= 0.012

    def point_ears(self, px, pz, sx, sz):
        for part, _inner, side in self.ears():
            for v in part:
                v.co.x = side * px + (v.co.x - side * px) * sx
                v.co.z = pz + (v.co.z - pz) * sz

    def short_tail(self, k):
        base = Vector((0.0, 0.2, 0.5))
        t1 = self.g["tail1"]
        tails = {self.g[n] for n in ("tail1", "tail2", "tail3")}
        for part in islands(self.bm):
            if self.bone_of(part) not in tails:
                continue
            for v in part:
                d = v.co - base
                v.co = base + Vector((d.x * 0.9, d.y * k, d.z * k + abs(d.y) * 0.25))
                for g in list(v[self.dl].keys()):
                    del v[self.dl][g]
                v[self.dl][t1] = 1.0

    def _vert(self, p):
        v = self.bm.verts.new(p)
        v[self.dl][self.g["head"]] = 1.0
        return v

    def _face(self, vs, px):
        try:
            f = self.bm.faces.new(vs)
        except ValueError:
            return
        for l in f.loops:
            l[self.uv].uv = uv_of(px)
        f.smooth = False

    def blob(self, c, r, px, segs=8, rings=4):
        grid = []
        for i in range(1, rings):
            ph = math.pi * i / rings - math.pi / 2
            grid.append([self._vert(c + Vector((math.cos(ph) * math.cos(t) * r.x, math.cos(ph) * math.sin(t) * r.y, math.sin(ph) * r.z)))
                         for t in (2 * math.pi * k / segs for k in range(segs))])
        bot, top = self._vert(c - Vector((0, 0, r.z))), self._vert(c + Vector((0, 0, r.z)))
        for k in range(segs):
            n = (k + 1) % segs
            self._face((bot, grid[0][n], grid[0][k]), px)
            self._face((top, grid[-1][k], grid[-1][n]), px)
            for i in range(len(grid) - 1):
                self._face((grid[i][k], grid[i][n], grid[i + 1][n], grid[i + 1][k]), px)

    def spike(self, base, d, length, radius, px, sides=4):
        d = d.normalized()
        q = d.to_track_quat("Z", "Y").to_matrix()
        ring = [self._vert(base + q @ Vector((math.cos(a) * radius, math.sin(a) * radius, 0)))
                for a in (k * 2 * math.pi / sides for k in range(sides))]
        tip = self._vert(base + d * length)
        for k in range(sides):
            self._face((ring[k], ring[(k + 1) % sides], tip), px)
        self._face(list(reversed(ring)), px)

    def whiskers(self):
        for s in (-1, 1):
            for dz in (-0.035, 0.0, 0.035):
                a = Vector((s * 0.12, -0.345, 1.075 + dz))
                b = Vector((s * 0.36, -0.31, 1.075 + dz * 2.0))
                w = Vector((0, 0, 0.005))
                vs = [self._vert(a - w), self._vert(b - w), self._vert(b + w), self._vert(a + w)]
                self._face(vs if s > 0 else list(reversed(vs)), PX_WHISKER)
                self._face(list(reversed(vs)) if s > 0 else vs, PX_WHISKER)

    def fatten(self, amount=0.38, centre=0.62, spread=0.24):
        """Rounds out the belly and hips; strongest at height `centre`, fading to the neck and knees."""
        body = {self.g[n] for n in ("spine", "pelvis", "thigh.L", "thigh.R")}
        for part in islands(self.bm):
            if self.bone_of(part) not in body:
                continue
            for v in part:
                k = 1.0 + amount * math.exp(-((v.co.z - centre) / spread) ** 2)
                v.co.x *= k
                v.co.y *= k

    def plain_tail(self, dark_tip_from=None):
        """Replaces the panda's tail rings with plain fur (optionally a darker tip)."""
        base = Vector((0.0, 0.2, 0.5))
        tails = {self.g[n] for n in ("tail1", "tail2", "tail3")}
        for part in islands(self.bm):
            if self.bone_of(part) not in tails:
                continue
            for f in {f for v in part for f in v.link_faces}:
                far = dark_tip_from is not None and (f.calc_center_median() - base).length > dark_tip_from
                for l in f.loops:
                    l[self.uv].uv = uv_of(PX_FUR_DARK if far else PX_FUR)

    def finish(self):
        for part, inner, _side in self.ears():      # only the inner ear is pink
            if inner:
                for f in {f for v in part for f in v.link_faces}:
                    for l in f.loops:
                        l[self.uv].uv = uv_of(PX_PINK)
        self.bm.normal_update()
        self.bm.to_mesh(self.obj.data)
        self.bm.free()
        self.obj.data.update()


def build(rider, mode):
    cfg = RIDERS[rider]
    beach = mode == "beach"
    suffix = "_beach" if beach else ""
    src = "piao_beach_texture.png" if beach else "red_panda_texture.png"
    img = paint(os.path.join(TEX, src), os.path.join(TEX, f"{rider}{suffix}_texture.png"), cfg)

    obj = bpy.data.objects["RedPandaRider"]
    board = bpy.data.objects["RedPandaBoard"]
    b = Builder(obj)
    if rider == "chinchilla":
        b.round_ears(0.34, 1.62, 0.215, 0.235)
        b.blob(Vector((0, -0.345, 1.075)), Vector((0.10, 0.05, 0.06)), PX_WHITE)
        b.blob(Vector((0, -0.395, 1.105)), Vector((0.03, 0.02, 0.022)), PX_BLACK, 6, 3)
        b.whiskers()
        b.plain_tail(dark_tip_from=0.75)
        b.fatten()
    else:
        b.point_ears(0.28, 1.40, 0.62, 0.68)
        b.short_tail(0.42)
        b.plain_tail()
        b.blob(Vector((0, -0.375, 1.065)), Vector((0.125, 0.10, 0.085)), PX_WHITE)
        b.blob(Vector((0, -0.475, 1.105)), Vector((0.045, 0.03, 0.035)), PX_BLACK, 6, 3)
        c = Vector((0, -0.2, 1.12))
        for k in range(9):                      # soft white ruff round the cheeks and chin
            a = math.radians(-165 + 150 * k / 8)
            n = Vector((math.cos(a) * 0.8, -0.45, math.sin(a) * 0.7 - 0.25))
            p = c + Vector((math.cos(a) * 0.29, -0.06, math.sin(a) * 0.24))
            b.spike(p, n, 0.09 if k % 2 else 0.12, 0.07, PX_WHITE)
    b.finish()

    for m in {*obj.data.materials, *board.data.materials}:
        if m and m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE":
                    n.image = img
                    n.interpolation = "Closest"

    root = bpy.data.objects["RedPanda"]
    root.name = cfg["root"]
    obj.name = cfg["root"] + "Rider"
    board.name = cfg["root"] + "Board"

    bpy.ops.object.select_all(action="DESELECT")
    for o in [root] + list(root.children_recursive):
        if o.visible_get():
            o.select_set(True)
    bpy.context.view_layer.objects.active = root
    glb = os.path.join(os.path.dirname(HERE), f"{rider}{suffix}.glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, use_visible=True,
                              export_animations=True, export_animation_mode="ACTIONS", export_skins=True,
                              export_image_format="AUTO")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, f"{rider}{suffix}.blend"))
    print("BUILT", rider, mode, os.path.getsize(glb), "verts", len(obj.data.vertices))


argv = sys.argv[sys.argv.index("--") + 1:]
build(argv[0], argv[1])
