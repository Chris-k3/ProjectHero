"""
Automated low-poly 3D asset generator for ZOMB-BAND (Project Zomboid Build 42).
Generates UV-mapped palette textures (.png) and single-mesh static models (.fbx)
scaled and oriented for Project Zomboid's JAssImp static mesh loader:
  - AcousticGuitar.fbx
  - ElectricGuitar.fbx
  - BassGuitar.fbx
  - DrumKit_Prop.fbx
  - MicrophoneStand.fbx

Usage:
  blender --background --python generate_band_assets.py
"""

import math
import os
import struct
import zlib

import bpy
import bmesh
from mathutils import Matrix, Vector


ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR = os.path.join(ROOT_DIR, "mods", "Zomb-Band", "42", "media", "models_X", "ZombBand")
TEXTURES_DIR = os.path.join(ROOT_DIR, "mods", "Zomb-Band", "42", "media", "textures", "ZombBand")


# ---------------------------------------------------------------------------
# Pure-Python 4x4 / 128x128 Palette PNG Writer (16 solid color tiles in a 4x4 grid)
# ---------------------------------------------------------------------------

def write_palette_png(filepath, colors_rgba, size=128):
    """Write a 4x4 color-swatches PNG texture so faces can UV-map cleanly to tile (idx % 4, idx // 4)."""
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    palette = list(colors_rgba)
    while len(palette) < 16:
        palette.append((128, 128, 128, 255))

    cell = size // 4
    rows = []
    for y in range(size):
        gy = min(3, y // cell)
        # PNG row top-to-bottom corresponds to UV V from 1.0 down to 0.0;
        # map tile index row 0 at bottom (V in 0..0.25) or directly compute UV from top.
        row = bytearray([0])  # filter type 0
        for x in range(size):
            gx = min(3, x // cell)
            idx = (3 - gy) * 4 + gx
            r, g, b, a = palette[idx]
            # Subtle shading gradient near tile center for crisp low-poly depth
            lx = ((x % cell) / float(cell)) - 0.5
            ly = ((y % cell) / float(cell)) - 0.5
            shade = max(0.88, min(1.06, 1.03 - 0.22 * (lx * lx + ly * ly)))
            row.extend((
                min(255, max(0, int(r * shade))),
                min(255, max(0, int(g * shade))),
                min(255, max(0, int(b * shade))),
                a,
            ))
        rows.append(bytes(row))

    raw = b"".join(rows)

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(filepath, "wb") as fh:
        fh.write(png)


def tile_uv_center(slot_index):
    gx = slot_index % 4
    gy = slot_index // 4
    return ((gx + 0.5) * 0.25, (gy + 0.5) * 0.25)


# ---------------------------------------------------------------------------
# BMesh Low-Poly Geometry Builders
# ---------------------------------------------------------------------------

class LowPolyBuilder:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv_layer = self.bm.loops.layers.uv.new("UVMap")

    def _assign_uv(self, faces, slot_index):
        cu, cv = tile_uv_center(slot_index)
        half = 0.08
        offsets = [(-half, -half), (half, -half), (half, half), (-half, half)]
        for f in faces:
            for i, loop in enumerate(f.loops):
                du, dv = offsets[i % 4]
                loop[self.uv_layer].uv = (cu + du, cv + dv)

    def add_box(self, size_xyz, center_xyz=(0.0, 0.0, 0.0), rot_euler=(0.0, 0.0, 0.0), slot=0):
        sx, sy, sz = size_xyz
        mat = (
            Matrix.Translation(Vector(center_xyz))
            @ Matrix.Rotation(rot_euler[2], 4, "Z")
            @ Matrix.Rotation(rot_euler[1], 4, "Y")
            @ Matrix.Rotation(rot_euler[0], 4, "X")
            @ Matrix.Diagonal(Vector((sx, sy, sz, 1.0)))
        )
        ret = bmesh.ops.create_cube(self.bm, size=1.0, matrix=mat)
        verts = ret["verts"]
        faces = [f for f in self.bm.faces if all(v in verts for v in f.verts)]
        self._assign_uv(faces, slot)
        return faces

    def add_cylinder(self, radius1, radius2, depth, segments=12, center_xyz=(0.0, 0.0, 0.0), rot_euler=(0.0, 0.0, 0.0), slot=0, cap_ends=True):
        mat = (
            Matrix.Translation(Vector(center_xyz))
            @ Matrix.Rotation(rot_euler[2], 4, "Z")
            @ Matrix.Rotation(rot_euler[1], 4, "Y")
            @ Matrix.Rotation(rot_euler[0], 4, "X")
        )
        ret = bmesh.ops.create_cone(
            self.bm,
            cap_ends=cap_ends,
            cap_tris=True,
            segments=segments,
            radius1=radius1,
            radius2=radius2,
            depth=depth,
            matrix=mat,
        )
        verts = ret["verts"]
        faces = [f for f in self.bm.faces if all(v in verts for v in f.verts)]
        self._assign_uv(faces, slot)
        return faces

    def add_uv_sphere(self, radius, u_segments=12, v_segments=8, center_xyz=(0.0, 0.0, 0.0), scale_xyz=(1.0, 1.0, 1.0), slot=0):
        mat = (
            Matrix.Translation(Vector(center_xyz))
            @ Matrix.Diagonal(Vector((scale_xyz[0], scale_xyz[1], scale_xyz[2], 1.0)))
        )
        ret = bmesh.ops.create_uvsphere(
            self.bm,
            u_segments=u_segments,
            v_segments=v_segments,
            radius=radius,
            matrix=mat,
        )
        verts = ret["verts"]
        faces = [f for f in self.bm.faces if all(v in verts for v in f.verts)]
        self._assign_uv(faces, slot)
        return faces

    def add_extruded_profile(self, points_xz, thickness_y, center_y=0.0, front_slot=0, back_slot=1, side_slot=2):
        """Create a closed 2D (X, Z) polygon extruded along Y from center_y - thickness/2 to center_y + thickness/2."""
        y_front = center_y - thickness_y * 0.5  # -Y maps to +Z (front face in PZ)
        y_back = center_y + thickness_y * 0.5
        front_verts = [self.bm.verts.new((x, y_front, z)) for (x, z) in points_xz]
        back_verts = [self.bm.verts.new((x, y_back, z)) for (x, z) in points_xz]
        self.bm.verts.ensure_lookup_table()

        front_face = self.bm.faces.new(list(reversed(front_verts)))
        back_face = self.bm.faces.new(back_verts)
        side_faces = []
        n = len(points_xz)
        for i in range(n):
            j = (i + 1) % n
            sf = self.bm.faces.new((front_verts[i], front_verts[j], back_verts[j], back_verts[i]))
            side_faces.append(sf)

        self._assign_uv([front_face], front_slot)
        self._assign_uv([back_face], back_slot)
        self._assign_uv(side_faces, side_slot)
        return [front_face, back_face] + side_faces

    def add_ring_disc(self, inner_r, outer_r, z_or_y_center, segments=16, axis="Y", slot=0):
        """Flat annular ring (e.g. acoustic rosette around soundhole)."""
        verts_in = []
        verts_out = []
        for i in range(segments):
            ang = (2.0 * math.pi * i) / segments
            ca, sa = math.cos(ang), math.sin(ang)
            if axis == "Y":
                cx, cz = z_or_y_center[0], z_or_y_center[2]
                cy = z_or_y_center[1]
                verts_in.append(self.bm.verts.new((cx + inner_r * ca, cy, cz + inner_r * sa)))
                verts_out.append(self.bm.verts.new((cx + outer_r * ca, cy, cz + outer_r * sa)))
            else:
                cx, cy, cz = z_or_y_center
                verts_in.append(self.bm.verts.new((cx + inner_r * ca, cy + inner_r * sa, cz)))
                verts_out.append(self.bm.verts.new((cx + outer_r * ca, cy + outer_r * sa, cz)))
        faces = []
        for i in range(segments):
            j = (i + 1) % segments
            faces.append(self.bm.faces.new((verts_in[i], verts_out[i], verts_out[j], verts_in[j])))
        self._assign_uv(faces, slot)
        return faces

    def export_fbx(self, name, texture_path, fbx_path):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        bmesh.ops.triangulate(self.bm, faces=self.bm.faces)

        mesh = bpy.data.meshes.new(name)
        self.bm.to_mesh(mesh)
        self.bm.free()

        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)

        # Single material referencing the PNG palette texture
        mat = bpy.data.materials.new(name=f"{name}_Mat")
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        tex_node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        if os.path.exists(texture_path):
            tex_node.image = bpy.data.images.load(texture_path)
        if bsdf:
            mat.node_tree.links.new(bsdf.inputs["Base Color"], tex_node.outputs["Color"])
            bsdf.inputs["Roughness"].default_value = 0.45
        mesh.materials.append(mat)

        os.makedirs(os.path.dirname(fbx_path), exist_ok=True)
        bpy.ops.export_scene.fbx(
            filepath=fbx_path,
            use_selection=True,
            object_types={"MESH"},
            global_scale=0.01,
            apply_unit_scale=True,
            apply_scale_options="FBX_SCALE_ALL",
            axis_forward="-Z",
            axis_up="Y",
            bake_space_transform=False,
            use_mesh_modifiers=True,
            mesh_smooth_type="OFF",
            add_leaf_bones=False,
            path_mode="RELATIVE",
        )
        print(f"[ZOMB-BAND] Exported {fbx_path} ({len(mesh.vertices)} verts, {len(mesh.polygons)} tris)")


# ---------------------------------------------------------------------------
# Symmetric Guitar Contour Helper (oriented along Z in Blender -> Y in PZ)
# ---------------------------------------------------------------------------

def symmetric_contour(half_profile_xz):
    """Build closed clockwise/counterclockwise contour from right-side (x >= 0, z) points bottom-to-top."""
    right = list(half_profile_xz)
    left = [(-x, z) for (x, z) in reversed(right) if x > 1e-5]
    return right + left


# ---------------------------------------------------------------------------
# 1. AcousticGuitar.fbx
# ---------------------------------------------------------------------------

def build_acoustic_guitar():
    tex_path = os.path.join(TEXTURES_DIR, "AcousticGuitar.png")
    fbx_path = os.path.join(MODELS_DIR, "AcousticGuitar.fbx")
    write_palette_png(tex_path, [
        (214, 158, 92, 255),   # 0: Sitka spruce soundboard
        (112, 54, 28, 255),    # 1: Mahogany back
        (132, 66, 34, 255),    # 2: Mahogany sides & neck
        (52, 31, 22, 255),     # 3: Rosewood fretboard & bridge
        (22, 14, 10, 255),     # 4: Soundhole dark interior
        (238, 224, 192, 255),  # 5: Cream binding / rosette / saddle
        (196, 202, 210, 255),  # 6: Silver tuning machines & frets
        (88, 28, 22, 255),     # 7: Tortoiseshell teardrop pickguard
    ])

    b = LowPolyBuilder()
    # Dreadnought body contour: total guitar length ~1.02m (Z in [-0.45, +0.57])
    half_body = [
        (0.00, -0.45),
        (0.09, -0.44),
        (0.16, -0.39),
        (0.185, -0.31),
        (0.165, -0.22),
        (0.115, -0.15),  # waist
        (0.135, -0.08),
        (0.145, -0.01),
        (0.115,  0.05),
        (0.055,  0.08),
        (0.00,   0.085),
    ]
    b.add_extruded_profile(symmetric_contour(half_body), thickness_y=0.095, center_y=-0.015, front_slot=0, back_slot=1, side_slot=2)

    # Central soundhole recessed dark disc + cream rosette ring on front soundboard (y ~ -0.063)
    b.add_cylinder(0.048, 0.048, 0.006, segments=18, center_xyz=(0.0, -0.063, -0.065), rot_euler=(math.pi * 0.5, 0.0, 0.0), slot=4)
    b.add_ring_disc(0.050, 0.060, (0.0, -0.0665, -0.065), segments=18, axis="Y", slot=5)

    # Teardrop pickguard to the bass/treble side of soundhole
    b.add_cylinder(0.042, 0.042, 0.003, segments=12, center_xyz=(0.062, -0.065, -0.105), rot_euler=(math.pi * 0.5, 0.0, 0.0), slot=7)

    # Rosewood bridge + cream bone saddle
    b.add_box((0.145, 0.010, 0.028), center_xyz=(0.0, -0.067, -0.235), slot=3)
    b.add_box((0.082, 0.014, 0.005), center_xyz=(0.0, -0.071, -0.232), slot=5)

    # Neck + Heel + Fretboard
    b.add_box((0.048, 0.024, 0.365), center_xyz=(0.0, -0.048, 0.255), slot=2)
    b.add_box((0.046, 0.036, 0.055), center_xyz=(0.0, -0.032, 0.092), slot=2)
    b.add_box((0.050, 0.007, 0.415), center_xyz=(0.0, -0.063, 0.230), slot=3)
    b.add_box((0.050, 0.009, 0.005), center_xyz=(0.0, -0.065, 0.438), slot=5)  # nut

    # Headstock + 6 tuning pegs (3+3)
    b.add_box((0.068, 0.015, 0.135), center_xyz=(0.0, -0.048, 0.502), rot_euler=(-0.12, 0.0, 0.0), slot=2)
    for side in (-1.0, 1.0):
        for i in range(3):
            zp = 0.462 + i * 0.036
            b.add_box((0.022, 0.008, 0.012), center_xyz=(side * 0.044, -0.044, zp), slot=6)

    b.export_fbx("AcousticGuitar", tex_path, fbx_path)


# ---------------------------------------------------------------------------
# 2. ElectricGuitar.fbx
# ---------------------------------------------------------------------------

def build_electric_guitar():
    tex_path = os.path.join(TEXTURES_DIR, "ElectricGuitar.png")
    fbx_path = os.path.join(MODELS_DIR, "ElectricGuitar.fbx")
    write_palette_png(tex_path, [
        (186, 28, 36, 255),    # 0: Candy apple red gloss body
        (148, 20, 28, 255),    # 1: Deep crimson back/bevel
        (218, 178, 122, 255),  # 2: Maple neck & headstock
        (56, 34, 24, 255),     # 3: Rosewood fretboard
        (242, 240, 232, 255),  # 4: White 3-ply pickguard
        (32, 32, 36, 255),     # 5: Black humbucker bobbins & knobs
        (206, 212, 220, 255),  # 6: Chrome bridge, neck plate, tuners
        (235, 200, 96, 255),   # 7: Gold logo / strap pins
    ])

    b = LowPolyBuilder()
    # Asymmetric double-cutaway electric body contour (Z in [-0.43, +0.57])
    contour = [
        (0.00,  -0.43),
        (0.09,  -0.42),
        (0.155, -0.37),
        (0.165, -0.28),
        (0.125, -0.18),
        (0.110, -0.11),
        (0.135, -0.03),
        (0.125,  0.05),   # right cutaway horn (shorter treble horn)
        (0.088,  0.04),
        (0.062, -0.02),
        (0.032,  0.04),
        (-0.032, 0.04),
        (-0.065, 0.00),
        (-0.095, 0.085),  # left cutaway horn (longer bass horn)
        (-0.135, 0.075),
        (-0.150, -0.01),
        (-0.115, -0.11),
        (-0.130, -0.19),
        (-0.165, -0.29),
        (-0.150, -0.38),
        (-0.085, -0.42),
    ]
    b.add_extruded_profile(contour, thickness_y=0.044, center_y=-0.020, front_slot=0, back_slot=1, side_slot=1)

    # Pickguard plate
    pg = [
        (-0.05, -0.25), (0.085, -0.26), (0.105, -0.16), (0.075, -0.04),
        (0.035, 0.02), (-0.035, 0.02), (-0.065, -0.08), (-0.065, -0.18),
    ]
    b.add_extruded_profile(pg, thickness_y=0.004, center_y=-0.044, front_slot=4, back_slot=4, side_slot=5)

    # Dual humbucker pickups + chrome bridge + control knobs
    b.add_box((0.072, 0.010, 0.034), center_xyz=(0.0, -0.048, -0.065), slot=5)
    b.add_box((0.072, 0.010, 0.034), center_xyz=(0.0, -0.048, -0.165), slot=5)
    b.add_box((0.082, 0.012, 0.042), center_xyz=(0.0, -0.048, -0.245), slot=6)
    for kx, kz in ((0.085, -0.265), (0.110, -0.305)):
        b.add_cylinder(0.012, 0.010, 0.014, segments=10, center_xyz=(kx, -0.050, kz), rot_euler=(math.pi * 0.5, 0.0, 0.0), slot=5)

    # Maple neck + rosewood fingerboard + 6-in-line angled headstock
    b.add_box((0.045, 0.022, 0.405), center_xyz=(0.0, -0.030, 0.235), slot=2)
    b.add_box((0.047, 0.006, 0.425), center_xyz=(0.0, -0.044, 0.225), slot=3)
    b.add_box((0.058, 0.014, 0.145), center_xyz=(-0.008, -0.030, 0.505), rot_euler=(0.0, 0.0, 0.08), slot=2)
    for i in range(6):
        zp = 0.452 + i * 0.020
        b.add_box((0.018, 0.008, 0.010), center_xyz=(-0.042, -0.030, zp), slot=6)

    b.export_fbx("ElectricGuitar", tex_path, fbx_path)


# ---------------------------------------------------------------------------
# 3. BassGuitar.fbx
# ---------------------------------------------------------------------------

def build_bass_guitar():
    tex_path = os.path.join(TEXTURES_DIR, "BassGuitar.png")
    fbx_path = os.path.join(MODELS_DIR, "BassGuitar.fbx")
    write_palette_png(tex_path, [
        (28, 52, 98, 255),     # 0: Midnight metallic blue body
        (20, 38, 74, 255),     # 1: Deep navy back/sides
        (222, 184, 128, 255),  # 2: Maple long-scale neck & headstock
        (48, 30, 22, 255),     # 3: Dark rosewood fretboard
        (232, 228, 218, 255),  # 4: Vintage parchment pickguard
        (28, 28, 32, 255),     # 5: Split P/J bass pickups
        (208, 214, 222, 255),  # 6: Heavy chrome bass bridge, control plate & clover tuners
        (165, 52, 38, 255),    # 7: Accent detail
    ])

    b = LowPolyBuilder()
    # Longer 34"-scale offset electric bass (~1.14m total length: Z in [-0.46, +0.68])
    contour = [
        (0.01,  -0.46),
        (0.10,  -0.45),
        (0.170, -0.39),
        (0.175, -0.29),
        (0.130, -0.18),
        (0.115, -0.10),
        (0.138, -0.01),
        (0.122,  0.065),
        (0.085,  0.055),
        (0.058, -0.01),
        (0.030,  0.05),
        (-0.030, 0.05),
        (-0.065, 0.01),
        (-0.105, 0.115),  # extended upper bass horn for balance
        (-0.145, 0.105),
        (-0.158, 0.01),
        (-0.120, -0.10),
        (-0.138, -0.20),
        (-0.178, -0.31),
        (-0.158, -0.41),
        (-0.085, -0.455),
    ]
    b.add_extruded_profile(contour, thickness_y=0.045, center_y=-0.020, front_slot=0, back_slot=1, side_slot=1)

    # Pickguard + chrome J-bass control plate
    pg = [
        (-0.055, -0.24), (0.075, -0.25), (0.098, -0.14), (0.072, -0.02),
        (0.032, 0.03), (-0.035, 0.03), (-0.068, -0.07), (-0.068, -0.17),
    ]
    b.add_extruded_profile(pg, thickness_y=0.004, center_y=-0.044, front_slot=4, back_slot=4, side_slot=5)
    b.add_box((0.042, 0.005, 0.115), center_xyz=(0.098, -0.045, -0.295), rot_euler=(0.0, 0.0, -0.28), slot=6)

    # Split P-bass pickup + J-bass bridge pickup + heavy mass bridge
    b.add_box((0.040, 0.010, 0.022), center_xyz=(-0.020, -0.048, -0.115), slot=5)
    b.add_box((0.040, 0.010, 0.022), center_xyz=(0.022, -0.048, -0.138), slot=5)
    b.add_box((0.086, 0.010, 0.020), center_xyz=(0.0, -0.048, -0.215), slot=5)
    b.add_box((0.088, 0.014, 0.050), center_xyz=(0.0, -0.048, -0.315), slot=6)

    # Long 34" scale neck + 4 large clover-leaf bass tuners
    b.add_box((0.044, 0.023, 0.480), center_xyz=(0.0, -0.030, 0.280), slot=2)
    b.add_box((0.046, 0.006, 0.495), center_xyz=(0.0, -0.044, 0.272), slot=3)
    b.add_box((0.068, 0.015, 0.165), center_xyz=(-0.010, -0.030, 0.595), rot_euler=(0.0, 0.0, 0.07), slot=2)
    for i in range(4):
        zp = 0.540 + i * 0.032
        b.add_box((0.026, 0.009, 0.016), center_xyz=(-0.050, -0.030, zp), slot=6)

    b.export_fbx("BassGuitar", tex_path, fbx_path)


# ---------------------------------------------------------------------------
# 4. DrumKit_Prop.fbx (Floor-standing 5-piece kit + hi-hat + crash + ride)
#    Built on Z = 0 floor plane in Blender -> stands upright on Y = 0 in PZ!
# ---------------------------------------------------------------------------

def build_drumkit_prop():
    tex_path = os.path.join(TEXTURES_DIR, "DrumKit_Prop.png")
    fbx_path = os.path.join(MODELS_DIR, "DrumKit_Prop.fbx")
    write_palette_png(tex_path, [
        (152, 24, 32, 255),    # 0: Stage-red lacquer drum shells
        (238, 234, 224, 255),  # 1: Coated white batter drumheads
        (28, 28, 32, 255),     # 2: Matte black kick hoops, resonant head & throne cushion
        (206, 212, 222, 255),  # 3: Chrome rims, lugs & stands
        (218, 178, 74, 255),   # 4: B20 bronze cymbals (hi-hat, crash, ride)
        (48, 48, 54, 255),     # 5: Rubber feet & kick pedal footboard
        (185, 42, 48, 255),    # 6: Highlight shell wrap
        (248, 244, 236, 255),  # 7: Front kick logo badge
    ])

    b = LowPolyBuilder()

    def add_drum_vertical(radius, depth, center_xyz, tilt_xy=(0.0, 0.0)):
        # Shell + top/bottom chrome counterhoops + coated batter head
        b.add_cylinder(radius, radius, depth, segments=16, center_xyz=center_xyz, rot_euler=(tilt_xy[0], tilt_xy[1], 0.0), slot=0)
        b.add_cylinder(radius * 1.03, radius * 1.03, depth * 0.14, segments=16,
                       center_xyz=(center_xyz[0], center_xyz[1], center_xyz[2] + depth * 0.45),
                       rot_euler=(tilt_xy[0], tilt_xy[1], 0.0), slot=3)
        b.add_cylinder(radius * 1.03, radius * 1.03, depth * 0.14, segments=16,
                       center_xyz=(center_xyz[0], center_xyz[1], center_xyz[2] - depth * 0.45),
                       rot_euler=(tilt_xy[0], tilt_xy[1], 0.0), slot=3)
        b.add_cylinder(radius * 0.98, radius * 0.98, 0.012, segments=16,
                       center_xyz=(center_xyz[0], center_xyz[1], center_xyz[2] + depth * 0.505),
                       rot_euler=(tilt_xy[0], tilt_xy[1], 0.0), slot=1)

    def add_tripod_stand(base_xy, top_z, cym_tilt=(0.0, 0.0), cym_radius=None):
        bx, by = base_xy
        # Center vertical chrome tube
        b.add_cylinder(0.013, 0.011, top_z, segments=8, center_xyz=(bx, by, top_z * 0.5), slot=3)
        # 3 tripod legs down to Z = 0
        for i in range(3):
            ang = (2.0 * math.pi * i) / 3.0 + 0.4
            lx = bx + math.cos(ang) * 0.14
            ly = by + math.sin(ang) * 0.14
            b.add_cylinder(0.009, 0.008, 0.34, segments=6,
                           center_xyz=((bx + lx) * 0.5, (by + ly) * 0.5, 0.13),
                           rot_euler=(-math.sin(ang) * 0.68, math.cos(ang) * 0.68, 0.0), slot=3)
            b.add_box((0.028, 0.028, 0.022), center_xyz=(lx * 1.15 - bx * 0.15, ly * 1.15 - by * 0.15, 0.011), slot=5)
        if cym_radius is not None:
            # Bronze cymbal cone + bell dome
            b.add_cylinder(cym_radius, cym_radius * 0.16, 0.022, segments=18,
                           center_xyz=(bx, by, top_z + 0.01),
                           rot_euler=(cym_tilt[0], cym_tilt[1], 0.0), slot=4)
            b.add_cylinder(cym_radius * 0.22, cym_radius * 0.10, 0.025, segments=12,
                           center_xyz=(bx, by, top_z + 0.026),
                           rot_euler=(cym_tilt[0], cym_tilt[1], 0.0), slot=4)

    # 1) 22" x 16" Bass Drum resting horizontally along Y axis at center (Z = 0.02..0.58)
    kick_r = 0.28
    kick_d = 0.42
    kick_z = 0.30
    b.add_cylinder(kick_r, kick_r, kick_d, segments=20, center_xyz=(0.0, -0.06, kick_z), rot_euler=(math.pi * 0.5, 0.0, 0.0), slot=0)
    b.add_cylinder(kick_r * 1.03, kick_r * 1.03, 0.04, segments=20, center_xyz=(0.0, -0.26, kick_z), rot_euler=(math.pi * 0.5, 0.0, 0.0), slot=2)
    b.add_cylinder(kick_r * 1.03, kick_r * 1.03, 0.04, segments=20, center_xyz=(0.0,  0.14, kick_z), rot_euler=(math.pi * 0.5, 0.0, 0.0), slot=2)
    b.add_cylinder(kick_r * 0.97, kick_r * 0.97, 0.01, segments=20, center_xyz=(0.0, -0.275, kick_z), rot_euler=(math.pi * 0.5, 0.0, 0.0), slot=2)
    b.add_cylinder(kick_r * 0.97, kick_r * 0.97, 0.01, segments=20, center_xyz=(0.0,  0.155, kick_z), rot_euler=(math.pi * 0.5, 0.0, 0.0), slot=1)
    # Kick drum spurs on floor Z=0 + kick pedal
    for side in (-1.0, 1.0):
        b.add_cylinder(0.010, 0.008, 0.28, segments=6, center_xyz=(side * 0.27, -0.14, 0.13), rot_euler=(0.0, side * 0.45, 0.0), slot=3)
    b.add_box((0.09, 0.22, 0.025), center_xyz=(0.0, 0.26, 0.014), slot=5)

    # 2) Double Tom Mount + 10" High Tom & 12" Mid Tom angled towards drummer (+Y)
    b.add_cylinder(0.016, 0.016, 0.24, segments=8, center_xyz=(0.0, -0.04, 0.66), slot=3)
    add_drum_vertical(0.135, 0.19, (-0.155, 0.02, 0.78), tilt_xy=(0.28, 0.10))
    add_drum_vertical(0.155, 0.21, ( 0.165, 0.02, 0.76), tilt_xy=(0.28, -0.10))

    # 3) 14" Snare Drum on stand (drummer's left: -X, +Y)
    add_tripod_stand((-0.34, 0.24), top_z=0.58)
    add_drum_vertical(0.18, 0.14, (-0.34, 0.24, 0.66), tilt_xy=(0.10, 0.05))

    # 4) 16" Floor Tom on 3 legs (drummer's right: +X, +Y)
    add_drum_vertical(0.205, 0.36, (0.39, 0.20, 0.44))
    for i in range(3):
        ang = (2.0 * math.pi * i) / 3.0
        lx = 0.39 + math.cos(ang) * 0.205
        ly = 0.20 + math.sin(ang) * 0.205
        b.add_cylinder(0.008, 0.008, 0.44, segments=6, center_xyz=(lx, ly, 0.22), slot=3)

    # 5) 14" Hi-Hat Stand (pair of cymbals + clutch rod + pedal)
    add_tripod_stand((-0.52, 0.12), top_z=0.88)
    b.add_cylinder(0.175, 0.04, 0.016, segments=16, center_xyz=(-0.52, 0.12, 0.875), slot=4)
    b.add_cylinder(0.175, 0.04, 0.018, segments=16, center_xyz=(-0.52, 0.12, 0.900), slot=4)
    b.add_cylinder(0.006, 0.006, 0.14, segments=6, center_xyz=(-0.52, 0.12, 0.95), slot=3)

    # 6) 18" Crash Cymbal Stand (left front) & 20" Ride Cymbal Stand (right front)
    add_tripod_stand((-0.44, -0.20), top_z=1.12, cym_tilt=(0.22, 0.12), cym_radius=0.225)
    add_tripod_stand(( 0.48, -0.14), top_z=1.02, cym_tilt=(0.20, -0.14), cym_radius=0.255)

    # 7) Drummer Throne Stool at back (+Y) so seated/standing drummer looks natural
    add_tripod_stand((0.0, 0.56), top_z=0.46)
    b.add_cylinder(0.16, 0.16, 0.075, segments=16, center_xyz=(0.0, 0.56, 0.49), slot=2)

    b.export_fbx("DrumKit_Prop", tex_path, fbx_path)


# ---------------------------------------------------------------------------
# 5. MicrophoneStand.fbx (Weighted round base + vertical boom/pole + vocal mic)
# ---------------------------------------------------------------------------

def build_microphone_stand():
    tex_path = os.path.join(TEXTURES_DIR, "MicrophoneStand.png")
    fbx_path = os.path.join(MODELS_DIR, "MicrophoneStand.fbx")
    write_palette_png(tex_path, [
        (30, 32, 36, 255),     # 0: Matte black cast-iron base & lower shaft
        (46, 48, 54, 255),     # 1: Dark gunmetal microphone body & clip
        (208, 214, 224, 255),  # 2: Chrome upper shaft, clutch collar & capsule ring
        (172, 178, 188, 255),  # 3: Steel wire-mesh vocal grille
        (18, 18, 22, 255),     # 4: XLR cable / rubber base rim
        (196, 44, 44, 255),    # 5: Red mute/power indicator ring
    ])

    b = LowPolyBuilder()
    # Heavy round cast-iron stage base resting flat on Z = 0 (diameter ~26 cm)
    b.add_cylinder(0.135, 0.125, 0.024, segments=20, center_xyz=(0.0, 0.0, 0.012), slot=4)
    b.add_cylinder(0.122, 0.042, 0.032, segments=20, center_xyz=(0.0, 0.0, 0.036), slot=0)

    # Lower matte black pole (0.05m -> 0.85m) + knurled clutch collar + chrome upper pole (0.85m -> 1.38m)
    b.add_cylinder(0.013, 0.013, 0.80, segments=10, center_xyz=(0.0, 0.0, 0.45), slot=0)
    b.add_cylinder(0.020, 0.020, 0.055, segments=12, center_xyz=(0.0, 0.0, 0.85), slot=2)
    b.add_cylinder(0.010, 0.010, 0.53, segments=10, center_xyz=(0.0, 0.0, 1.115), slot=2)

    # Short angled boom arm / swivel mic clip at top (~1.38m - 1.46m, mouth height for PZ character!)
    b.add_box((0.028, 0.032, 0.038), center_xyz=(0.0, 0.0, 1.39), slot=1)
    b.add_cylinder(0.016, 0.016, 0.042, segments=10, center_xyz=(0.0, 0.012, 1.425), rot_euler=(-0.35, 0.0, 0.0), slot=1)

    # Dynamic cardioid vocal microphone (SM58-style tapered handle + chrome band + spherical mesh grille)
    # Tilted slightly towards the singer (+Y in Blender -> -Z/singer side)
    mic_tilt = (1.22, 0.0, 0.0)
    b.add_cylinder(0.013, 0.019, 0.135, segments=12, center_xyz=(0.0, 0.022, 1.448), rot_euler=mic_tilt, slot=1)
    b.add_cylinder(0.0205, 0.0205, 0.008, segments=12, center_xyz=(0.0, -0.036, 1.470), rot_euler=mic_tilt, slot=2)
    b.add_uv_sphere(0.025, u_segments=14, v_segments=10, center_xyz=(0.0, -0.058, 1.478), scale_xyz=(1.0, 1.08, 1.0), slot=3)

    b.export_fbx("MicrophoneStand", tex_path, fbx_path)


def main():
    os.makedirs(MODELS_DIR, exist_ok=True)
    os.makedirs(TEXTURES_DIR, exist_ok=True)
    build_acoustic_guitar()
    build_electric_guitar()
    build_bass_guitar()
    build_drumkit_prop()
    build_microphone_stand()
    print("[ZOMB-BAND] All 5 low-poly 3D band assets generated successfully.")


if __name__ == "__main__":
    main()
