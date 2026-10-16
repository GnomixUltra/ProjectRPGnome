# -*- coding: utf-8 -*-
"""
NIGHTREALM — 3D RPG от первого лица в духе Skyrim / Two Worlds / Dark Messiah.
Ночной открытый мир, холмы, деревья, камни, враги с ИИ ближнего боя,
меч, полоски здоровья и выносливости (выносливость тратится на бег).

Python + Pygame + NumPy. Собственный растеризатор с Z-буфером.
Управление: WASD — движение, мышь — обзор, SHIFT — бег, ЛКМ — удар, ESC — меню.
"""

import math
import os
import random
import sys

os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")
import numpy as np
import pygame

# ----------------------------------------------------------------------------
# Конфиг
# ----------------------------------------------------------------------------
SCREEN_W, SCREEN_H = 960, 540
FOV = math.radians(72.0)
NEAR = 0.12
FAR_CLIP = 95.0
EYE_HEIGHT = 1.7
TILE = 8.0
GRID = 24
WORLD_SIZE = TILE * GRID
MOON_DIR = np.array([-0.45, 0.8, 0.3])
MOON_DIR = MOON_DIR / np.linalg.norm(MOON_DIR)
AMBIENT = 0.30          # ночное освещение — лунный свет
DIFFUSE = 0.75


def asset_path(name):
    if getattr(sys, "frozen", False):
        base = os.path.join(getattr(sys, "_MEIPASS", "."), "assets")
    else:
        base = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
    return os.path.join(base, name)


# ----------------------------------------------------------------------------
# Ландшафт
# ----------------------------------------------------------------------------
_rng = random.Random(1337)
_grad_cache = {}

def _grad(ix, iz):
    key = (ix & 255, iz & 255)
    if key not in _grad_cache:
        a = _rng.uniform(0, math.tau)
        _grad_cache[key] = (math.cos(a), math.sin(a))
    return _grad_cache[key]

def _smooth(t):
    return t * t * (3 - 2 * t)

def terrain_height(x, z):
    def octave(scale, amp):
        sx, sz = x / scale, z / scale
        x0, z0 = int(math.floor(sx)), int(math.floor(sz))
        fx, fz = _smooth(sx - x0), _smooth(sz - z0)
        n00 = _grad(x0, z0)[0]*fx + _grad(x0, z0)[1]*fz
        n10 = _grad(x0+1, z0)[0]*(fx-1) + _grad(x0+1, z0)[1]*fz
        n01 = _grad(x0, z0+1)[0]*fx + _grad(x0, z0+1)[1]*(fz-1)
        n11 = _grad(x0+1, z0+1)[0]*(fx-1) + _grad(x0+1, z0+1)[1]*(fz-1)
        nx0 = n00 + (n10 - n00) * fx
        nx1 = n01 + (n11 - n01) * fx
        return (nx0 + (nx1 - nx0) * fz) * amp
    h = octave(30.0, 4.5) + octave(11.0, 1.6) + 2.0
    d = math.hypot(x - WORLD_SIZE/2, z - WORLD_SIZE/2)
    if d < 18.0:
        k = (18.0 - d) / 18.0
        h = h * (1 - k) + 2.0 * k
    return h


# ----------------------------------------------------------------------------
# Сцена: список треугольников (numpy) + интерактивные объекты
# ----------------------------------------------------------------------------
def build_scene():
    verts_list = []      # (3,3) float
    colors_list = []     # (3,) float 0..1 базовый цвет
    uvs_list = []        # (3,2) float или nan
    tex_ids = []         # 0 = без текстуры, 1 = grass, 2 = dirt

    H = [[terrain_height(xi*TILE, zi*TILE) for zi in range(GRID+1)] for xi in range(GRID+1)]

    def add_tri(p0, p1, p2, color, uv=None, tex=0):
        verts_list.append(np.array([p0, p1, p2], dtype=np.float64))
        colors_list.append(np.array(color, dtype=np.float64))
        if uv is None:
            uv = np.full((3, 2), np.nan)
        uvs_list.append(np.asarray(uv, dtype=np.float64))
        tex_ids.append(tex)

    grass_col = (0.16, 0.30, 0.13)
    dirt_col = (0.28, 0.20, 0.13)

    for xi in range(GRID):
        for zi in range(GRID):
            p00 = (xi*TILE, H[xi][zi], zi*TILE)
            p10 = ((xi+1)*TILE, H[xi+1][zi], zi*TILE)
            p01 = (xi*TILE, H[xi][zi+1], (zi+1)*TILE)
            p11 = ((xi+1)*TILE, H[xi+1][zi+1], (zi+1)*TILE)
            n = np.cross(np.subtract(p10, p00), np.subtract(p01, p00))
            nl = np.linalg.norm(n) or 1.0
            n = n / nl
            light = AMBIENT + DIFFUSE * max(0.0, float(np.dot(n, MOON_DIR)))
            lc = tuple(min(1.0, c*light*1.6) for c in grass_col)
            uv00 = (p00[0]*0.5 % 256, p00[2]*0.5 % 256)
            uv10 = (p10[0]*0.5 % 256, p10[2]*0.5 % 256)
            uv01 = (p01[0]*0.5 % 256, p01[2]*0.5 % 256)
            uv11 = (p11[0]*0.5 % 256, p11[2]*0.5 % 256)
            add_tri(p00, p11, p01, lc, (uv00, uv11, uv01), 1)
            add_tri(p00, p10, p11, lc, (uv00, uv10, uv11), 1)
            # стены-обрывы по краям мира (земля)
            wall_uv = lambda p, y: (p[0]*0.5 % 256, y*0.5 % 256)
            if xi == 0:
                dl = tuple(min(1.0, c*light*1.5) for c in dirt_col)
                a, b = (p00[0], -6.0, p00[2]), (p01[0], -6.0, p01[2])
                add_tri(p01, p00, a, dl, (wall_uv(p01, p01[1]), wall_uv(p00, p00[1]), wall_uv(a, -6)), 2)
                add_tri(p01, a, b, dl, (wall_uv(p01, p01[1]), wall_uv(a, -6), wall_uv(b, -6)), 2)
            if xi == GRID-1:
                dl = tuple(min(1.0, c*light*1.5) for c in dirt_col)
                a, b = (p11[0], -6.0, p11[2]), (p10[0], -6.0, p10[2])
                add_tri(p10, p11, a, dl, (wall_uv(p10, p10[1]), wall_uv(p11, p11[1]), wall_uv(a, -6)), 2)
                add_tri(p10, a, b, dl, (wall_uv(p10, p10[1]), wall_uv(a, -6), wall_uv(b, -6)), 2)
            if zi == 0:
                dl = tuple(min(1.0, c*light*1.5) for c in dirt_col)
                a, b = (p10[0], -6.0, p10[2]), (p00[0], -6.0, p00[2])
                add_tri(p00, p10, a, dl, (wall_uv(p00, p00[1]), wall_uv(p10, p10[1]), wall_uv(a, -6)), 2)
                add_tri(p00, a, b, dl, (wall_uv(p00, p00[1]), wall_uv(a, -6), wall_uv(b, -6)), 2)
            if zi == GRID-1:
                dl = tuple(min(1.0, c*light*1.5) for c in dirt_col)
                a, b = (p01[0], -6.0, p01[2]), (p11[0], -6.0, p11[2])
                add_tri(p11, p01, a, dl, (wall_uv(p11, p11[1]), wall_uv(p01, p01[1]), wall_uv(a, -6)), 2)
                add_tri(p11, a, b, dl, (wall_uv(p11, p11[1]), wall_uv(a, -6), wall_uv(b, -6)), 2)

    rng = random.Random(7)
    obstacles = []   # (x, z, radius)

    # --- деревья: стволовая призма + конус кроны (реальная геометрия) ---
    for _ in range(110):
        tx = rng.uniform(6, WORLD_SIZE-6)
        tz = rng.uniform(6, WORLD_SIZE-6)
        if math.hypot(tx-WORLD_SIZE/2, tz-WORLD_SIZE/2) < 13:
            continue
        ty = terrain_height(tx, tz)
        h = rng.uniform(4.5, 7.5)
        r = rng.uniform(0.35, 0.55)
        bark = (0.22, 0.15, 0.10)
        leaf_base = [(0.09, 0.22, 0.10), (0.11, 0.26, 0.12), (0.08, 0.19, 0.09)][rng.randrange(3)]
        sides = 5
        cs = [(tx+r*math.cos(a), tz+r*math.sin(a)) for a in
              [i*math.tau/sides for i in range(sides)]]
        top_ring = [(x, ty+h*0.55, z) for (x, z) in cs]
        bot_ring = [(x, ty, z) for (x, z) in cs]
        for i in range(sides):
            j = (i+1) % sides
            midy = ty + h*0.27
            nrm_ang = (cs[i][0]+cs[j][0])/2 - tx, (cs[i][1]+cs[j][1])/2 - tz
            ln = math.hypot(*nrm_ang) or 1
            lx, lz = nrm_ang[0]/ln, nrm_ang[1]/ln
            light = AMBIENT + DIFFUSE*max(0.05, 0.55*abs(lx*MOON_DIR[0]+lz*MOON_DIR[2]) + 0.3*MOON_DIR[1])
            col = tuple(min(1.0, c*light*1.7) for c in bark)
            add_tri(bot_ring[i], top_ring[j], bot_ring[j], col)
            add_tri(bot_ring[i], top_ring[i], top_ring[j], col)
        # крона — два яруса конусов
        cr = r*3.4
        cone_sides = 6
        for tier, (base_y, apex_y, rad) in enumerate([
                (ty+h*0.45, ty+h*0.75, cr),
                (ty+h*0.70, ty+h*1.05, cr*0.65)]):
            ring = [(tx+rad*math.cos(a), base_y, tz+rad*math.sin(a))
                    for a in [i*math.tau/cone_sides + 0.3 for i in range(cone_sides)]]
            apex = (tx, apex_y, tz)
            lb = leaf_base if tier == 0 else tuple(c*0.85 for c in leaf_base)
            for i in range(cone_sides):
                j = (i+1) % cone_sides
                mx, mz = (ring[i][0]+ring[j][0])/2 - tx, (ring[i][2]+ring[j][2])/2 - tz
                mn = math.hypot(mx, mz) or 1
                slope = 0.55
                nx_, ny_, nz_ = mx/mn*slope, 0.8, mz/mn*slope
                light = AMBIENT + DIFFUSE*max(0.05, nx_*MOON_DIR[0]+ny_*MOON_DIR[1]+nz_*MOON_DIR[2])
                col = tuple(min(1.0, c*light*1.9) for c in lb)
                add_tri(ring[i], apex, ring[j], col)
        obstacles.append((tx, tz, r+0.75))

    # --- камни: низкие многогранники ---
    for _ in range(55):
        rx = rng.uniform(4, WORLD_SIZE-4)
        rz = rng.uniform(4, WORLD_SIZE-4)
        ry = terrain_height(rx, rz)
        s = rng.uniform(0.6, 1.9)
        rock_col = (0.30, 0.30, 0.34)
        pts = []
        rr_jit = [rng.uniform(-0.15, 0.15) for _ in range(6)]
        for a_i in range(6):
            ang = a_i*math.tau/6
            pts.append((rx+math.cos(ang)*(s+rr_jit[a_i]), rz+math.sin(ang)*(s+rr_jit[a_i])))
        apex = (rx, ry+s*1.15, rz)
        for i in range(6):
            j = (i+1) % 6
            mx, mz = (pts[i][0]+pts[j][0])/2 - rx, (pts[i][1]+pts[j][1])/2 - rz
            mn = math.hypot(mx, mz) or 1
            light = AMBIENT + DIFFUSE*max(0.05, 0.5*(mx/mn*MOON_DIR[0]+mz/mn*MOON_DIR[2]) + 0.45*MOON_DIR[1])
            col = tuple(min(1.0, c*light*1.6) for c in rock_col)
            add_tri((pts[i][0], ry, pts[i][1]), apex, (pts[j][0], ry, pts[j][1]), col)
        obstacles.append((rx, rz, s+0.45))

    return (np.array(verts_list), np.array(colors_list),
            np.array(uvs_list), np.array(tex_ids), obstacles)


# ----------------------------------------------------------------------------
# Враги
# ----------------------------------------------------------------------------
class Enemy:
    def __init__(self, x, z, hp=50.0):
        self.x, self.z = x, z
        self.y = terrain_height(x, z)
        self.hp = hp
        self.max_hp = hp
        self.speed = 2.6
        self.attack_cd = 0.0
        self.hit_flash = 0.0
        self.alive = True

    def update(self, dt, player, others):
        dt = min(dt, 0.05)
        self.y = terrain_height(self.x, self.z)
        self.attack_cd = max(0.0, self.attack_cd - dt)
        self.hit_flash = max(0.0, self.hit_flash - dt)
        dx, dz = player.x - self.x, player.z - self.z
        dist = math.hypot(dx, dz)
        if dist > 1.5 and dist < 45:
            vx, vz = dx/dist*self.speed, dz/dist*self.speed
            for o in others:
                if o is not self and o.alive:
                    ox, oz = self.x-o.x, self.z-o.z
                    od = math.hypot(ox, oz)
                    if 0 < od < 1.3:
                        vx += ox/od*1.5
                        vz += oz/od*1.5
            l = math.hypot(vx, vz) or 1
            self.x += vx/l*self.speed*dt
            self.z += vz/l*self.speed*dt
        elif dist <= 1.5 and self.attack_cd <= 0 and player.hp > 0:
            self.attack_cd = 1.3
            player.damage(9)


def enemy_geometry(e):
    """Возвращает tris (n,3,3), colors (n,3), для одного врага."""
    x, y, z = e.x, e.y, e.z
    flash = e.hit_flash > 0
    body = (0.85, 0.75, 0.72) if flash else (0.42, 0.13, 0.12)
    dark = (0.9, 0.8, 0.78) if flash else (0.28, 0.08, 0.08)
    skin = (0.95, 0.9, 0.85) if flash else (0.55, 0.44, 0.32)
    eye = (0.95, 0.2, 0.15)
    s = 0.5
    v, c = [], []
    def tri(a, b, cc, col):
        v.append([a, b, cc]); c.append(col)
    bx = bz = s*0.8
    corners = [(x-bx, z-bz), (x+bx, z-bz), (x+bx, z+bz), (x-bx, z+bz)]
    top_y = y + s*2.4
    for i in range(4):
        x1, z1 = corners[i]; x2, z2 = corners[(i+1) % 4]
        tri((x1, y, z1), (x2, top_y, z2), (x2, y, z2), body)
        tri((x1, y, z1), (x1, top_y, z1), (x2, top_y, z2), dark)
    # верхняя крышка
    tri((corners[0][0], top_y, corners[0][1]), (corners[1][0], top_y, corners[1][1]),
        (corners[2][0], top_y, corners[2][1]), dark)
    tri((corners[0][0], top_y, corners[0][1]), (corners[2][0], top_y, corners[2][1]),
        (corners[3][0], top_y, corners[3][1]), dark)
    # голова
    hy = top_y + s*0.75
    r = s*0.55
    ring = [(x+r*math.cos(a), z+r*math.sin(a)) for a in [i*math.tau/5 for i in range(5)]]
    apex = (x, hy+r, z)
    base = (x, hy-r*0.6, z)
    for i in range(5):
        j = (i+1) % 5
        tri((ring[i][0], hy-r*0.6, ring[i][1]), apex, (ring[j][0], hy-r*0.6, ring[j][1]), skin)
    # глаза-точки (крошечные красные треуг.)
    fwd_x, fwd_z = math.sin(0), math.cos(0)
    for ex_off in (-r*0.4, r*0.4):
        px_, pz_ = x+ex_off, z - r*0.85
        tri((px_-0.05, hy, pz_), (px_+0.05, hy, pz_), (px_, hy+0.06, pz_-0.05), eye)
    return np.array(v, dtype=np.float64), np.array(c, dtype=np.float64)


# ----------------------------------------------------------------------------
# Растеризатор с Z-буфером
# ----------------------------------------------------------------------------
class Rasterizer:
    def __init__(self, textures):
        self.textures = textures          # dict[str] -> np.ndarray (H,W,3) uint8
        self.frame = np.zeros((SCREEN_H, SCREEN_W, 3), dtype=np.uint8)
        self.zbuf = np.zeros((SCREEN_H, SCREEN_W), dtype=np.float32)
        self.fog_color = np.array([10, 14, 30], dtype=np.float32)
        self._basis = None

    def set_camera(self, pos, yaw, pitch):
        cp, sp = math.cos(pitch), math.sin(pitch)
        cy, sy = math.cos(yaw), math.sin(yaw)
        fwd = np.array([sy*cp, sp, cy*cp])
        right = np.array([cy, 0.0, -sy])
        up = np.cross(right, fwd)
        self.cam = np.asarray(pos, dtype=np.float64)
        self.R = np.stack([right, up, fwd])       # world -> view
        self.fx = (SCREEN_W/2) / math.tan(FOV/2)
        self.fy = self.fx

    def to_view(self, pts):
        return (pts - self.cam) @ self.R.T

    def render_triangles(self, verts, colors, uvs, tex_ids):
        """verts:(n,3,3) colors:(n,3) uvs:(n,3,2) tex_ids:(n,)"""
        view = self.to_view(verts.reshape(-1, 3)).reshape(-1, 3, 3)
        # отсечение по ближней и дальней плоскостям
        far_ok = (view[:, :, 2] > NEAR).any(axis=1) & (view[:, :, 2] <= FAR_CLIP).all(axis=1)
        # backface culling
        e1 = view[:, 1] - view[:, 0]
        e2 = view[:, 2] - view[:, 0]
        nz = e1[:, 0]*e2[:, 1] - e1[:, 1]*e2[:, 0]
        front = nz < 0
        mask = far_ok & front
        if not mask.any():
            return
        view = view[mask]; colors = colors[mask]
        uvs_m = uvs[mask] if uvs is not None else None
        tex_m = tex_ids[mask] if tex_ids is not None else None
        # fog по глубине центра
        zc = view.mean(axis=1)
        fog_t = np.clip((np.maximum(zc[:, 2], 0.0) / 90.0) ** 1.6, 0, 0.92)

        v2d = np.empty_like(view)
        zz = np.maximum(view[:, :, 2], NEAR)
        v2d[:, :, 0] = view[:, :, 0] / zz * self.fx + SCREEN_W/2
        v2d[:, :, 1] = -view[:, :, 1] / zz * self.fy + SCREEN_H/2

        order = np.argsort(-zc[:, 2])      # back-to-front — стабильная картинка без артефактов Z-буфера
        for i in order:
            self._draw_one(v2d[i], view[i, :, 2], colors[i], fog_t[i],
                           uvs_m[i] if uvs_m is not None else None,
                           int(tex_m[i]) if tex_m is not None else 0)

    def _shade_color(self, base, fog_t):
        col = base * 255.0
        col = col * (1-fog_t) + self.fog_color * fog_t
        return np.clip(col, 0, 255).astype(np.uint8)

    def _draw_one(self, pts, zverts, color, fog_t, uvs, tex_id):
        xs = pts[:, 0]; ys = pts[:, 1]
        # отсечение по ближней плоскости: если часть треугольника за камерой —
        # обрезаем его плоскостью z=NEAR (Sutherland–Hodgman)
        zs = view_z = zverts
        if (zs < NEAR).any():
            poly = [(pts[i], zs[i]) for i in range(3)]
            clipped = []
            n = len(poly)
            for i in range(n):
                cur_p, cur_z = poly[i]
                nxt_p, nxt_z = poly[(i+1) % n]
                cur_in = cur_z >= NEAR
                nxt_in = nxt_z >= NEAR
                if cur_in:
                    clipped.append((cur_p, cur_z))
                    if not nxt_in:
                        t = (NEAR - cur_z) / (nxt_z - cur_z)
                        clipped.append((cur_p + (nxt_p-cur_p)*t, NEAR))
                elif nxt_in:
                    t = (NEAR - cur_z) / (nxt_z - cur_z)
                    clipped.append((cur_p + (nxt_p-cur_p)*t, NEAR))
            if len(clipped) < 3:
                return
            fan = clipped[0]
            for k in range(1, len(clipped)-1):
                self._fill_tri(np.array([fan[0], clipped[k][0], clipped[k+1][0]]),
                               np.array([fan[1], clipped[k][1], clipped[k+1][1]]),
                               color, fog_t, uvs, tex_id)
            return
        self._fill_tri(pts, zs, color, fog_t, uvs, tex_id)

    def _fill_tri(self, pts, zverts, color, fog_t, uvs, tex_id):
        xs = pts[:, 0]; ys = pts[:, 1]
        minx = max(int(np.floor(xs.min())), 0)
        maxx = min(int(np.ceil(xs.max())), SCREEN_W-1)
        miny = max(int(np.floor(ys.min())), 0)
        maxy = min(int(np.ceil(ys.max())), SCREEN_H-1)
        if minx > maxx or miny > maxy:
            return
        if maxx < 0 or minx >= SCREEN_W or maxy < 0 or miny >= SCREEN_H:
            return          # полностью вне экрана
        minx, miny = max(minx, 0), max(miny, 0)
        maxx, maxy = min(maxx, SCREEN_W-1), min(maxy, SCREEN_H-1)
        if (maxx-minx)*(maxy-miny) > 450*450 and tex_id == 0:
            return          # гигантский одноцветный полигон почти всегда за камерой/крайне близко
        area = (pts[1,0]-pts[0,0])*(pts[2,1]-pts[0,1]) - (pts[2,0]-pts[0,0])*(pts[1,1]-pts[0,1])
        if abs(area) < 1e-6:
            return
        if (maxx-minx)*(maxy-miny) > 60*60*40 and tex_id == 0:
            # очень большие одноцветные полигоны рисуем pygame-полигоном ниже не можем —
            # просто ограничиваем: пропускаем (такое бывает для треугольников за экраном)
            pass
        yy, xx = np.mgrid[miny:maxy+1, minx:maxx+1]
        w0 = ((pts[1,0]-xx)*(pts[2,1]-pts[1,1]) - (pts[1,1]-yy)*(pts[2,0]-pts[1,0])) / area
        w1 = ((pts[2,0]-xx)*(pts[0,1]-pts[2,1]) - (pts[0,1]-yy)*(pts[2,0]-pts[0,0])) / area
        w2 = 1.0 - w0 - w1
        inside = (w0 >= -0.001) & (w1 >= -0.001) & (w2 >= -0.001)
        if not inside.any():
            return
        izb = self.zbuf[miny:maxy+1, minx:maxx+1]
        z = w0*zverts[0] + w1*zverts[1] + w2*zverts[2]
        write = inside & (z < izb)
        if not write.any():
            return
        flat_idx = np.where(write)
        sel_y = flat_idx[0] + miny
        sel_x = flat_idx[1] + minx
        self.zbuf[sel_y, sel_x] = z[write]
        if tex_id and uvs is not None and not np.isnan(uvs).any():
            tex = self.textures[tex_id]
            th, tw = tex.shape[0], tex.shape[1]
            uu = (w0*uvs[0,0] + w1*uvs[1,0] + w2*uvs[2,0])[write] % tw
            vv = (w0*uvs[0,1] + w1*uvs[1,1] + w2*uvs[2,1])[write] % th
            rgb = tex[vv.astype(np.int32), uu.astype(np.int32)].astype(np.float32)
            mult = np.clip(color*2.2, 0.12, 1.4)[None, :]
            rgb = rgb * mult
            rgb = rgb * (1-fog_t) + self.fog_color*fog_t
            self.frame[sel_y, sel_x] = np.clip(rgb, 0, 255).astype(np.uint8)
        else:
            self.frame[sel_y, sel_x] = self._shade_color(color, fog_t)

    def clear(self):
        self.frame[:] = 0
        self.zbuf[:] = 1e9


# ----------------------------------------------------------------------------
# Игрок
# ----------------------------------------------------------------------------
class Player:
    def __init__(self):
        self.x = WORLD_SIZE/2
        self.z = WORLD_SIZE/2
        self.y = terrain_height(self.x, self.z)
        self.yaw = 0.6
        self.pitch = 0.0
        self.hp = 100.0; self.max_hp = 100.0
        self.stam = 100.0; self.max_stam = 100.0
        self.exhausted = False
        self.bob = 0.0; self.eye_off = 0.0
        self.hurt = 0.0
        self.swing = 0.0
        self.attack_cd = 0.0
        self.spawn_shield = 6.0   # секунды безопасности после возрождения

    @property
    def eye(self):
        return (self.x, self.y + EYE_HEIGHT + self.eye_off, self.z)

    def damage(self, amount):
        if self.hp <= 0 or self.spawn_shield > 0:
            return
        self.hp = max(0.0, self.hp - amount)
        self.hurt = 0.4
        if self.hp <= 0:
            print("YOU DIED")

    def forward(self):
        return (math.sin(self.yaw), math.cos(self.yaw))


# ----------------------------------------------------------------------------
# Игра
# ----------------------------------------------------------------------------
class Game:
    def __init__(self, screen, textures_np):
        self.screen = screen
        self.ras = Rasterizer(textures_np)
        (self.verts, self.colors, self.uvs, self.tex_ids, self.obstacles) = build_scene()
        self.player = Player()
        self.enemies = []
        self.kills = 0
        self.state = "menu"
        self.clock = pygame.time.Clock()
        self.locked = False
        self.night = None    # surface неба

    # ----- волны -----
    def spawn_wave(self):
        rng = random.Random()
        for _ in range(6):
            a = rng.uniform(0, math.tau)
            d = rng.uniform(16, 32)
            x = min(max(self.player.x + math.cos(a)*d, 4), WORLD_SIZE-4)
            z = min(max(self.player.z + math.sin(a)*d, 4), WORLD_SIZE-4)
            self.enemies.append(Enemy(x, z))

    def reset(self):
        self.player = Player()
        self.enemies = []
        self.kills = 0
        self.spawn_wave()
        self.state = "play"
        pygame.mouse.set_visible(False)
        pygame.event.set_grab(True)
        self.locked = True

    # ----- события -----
    def handle_events(self, events):
        for e in events:
            if e.type == pygame.QUIT:
                return False
            if e.type == pygame.KEYDOWN:
                if e.key == pygame.K_ESCAPE:
                    if self.state == "play":
                        self.state = "menu"
                        pygame.mouse.set_visible(True)
                        pygame.event.set_grab(False)
                        self.locked = False
                    elif self.state == "menu":
                        return False
                if self.state == "menu" and e.key in (pygame.K_RETURN, pygame.K_SPACE):
                    self.reset()
                if self.state == "dead" and e.key == pygame.K_r:
                    self.reset()
            if e.type == pygame.MOUSEBUTTONDOWN and e.button == 1 and self.state == "play":
                self.try_attack()
            if e.type == pygame.MOUSEMOTION and self.state == "play" and self.locked:
                p = self.player
                p.yaw += e.rel[0]*0.0027
                p.pitch = max(-1.25, min(1.25, p.pitch - e.rel[1]*0.0027))
        return True

    def try_attack(self):
        p = self.player
        if p.attack_cd > 0 or p.hp <= 0:
            return
        p.attack_cd = 0.45
        p.swing = 0.32
        fx, fz = p.forward()
        # удар наносится по ближайшему врагу в конусе перед игроком
        best, best_d = None, 1e9
        for en in self.enemies:
            if not en.alive:
                continue
            dx, dz = en.x-p.x, en.z-p.z
            dist = math.hypot(dx, dz)
            if dist < 2.8 and dist < best_d:
                dotf = (dx*fx + dz*fz)/(dist or 1e-9)
                if dotf > 0.45:
                    best, best_d = en, dist
        if best is not None:
            best.hp -= 26
            best.hit_flash = 0.15
            p.stam = max(0.0, p.stam - 4)
            if best.hp <= 0:
                best.alive = False
                self.kills += 1

    # ----- логика -----
    def update(self, dt):
        dt = min(dt, 0.05)      # защита от «телепортации» при лагах
        p = self.player
        if self.state != "play":
            return
        p.attack_cd = max(0.0, p.attack_cd-dt)
        p.swing = max(0.0, p.swing-dt)
        p.hurt = max(0.0, p.hurt-dt)
        p.spawn_shield = max(0.0, p.spawn_shield-dt)
        # плавная ночная регенерация/деградация: без врагов рядом hp держится
        if p.hp > 0 and not any(e.alive and math.hypot(e.x-p.x, e.z-p.z) < 12 for e in self.enemies):
            p.hp = min(p.max_hp, p.hp + 0.8*dt)

        keys = pygame.key.get_pressed()
        fx, fz = p.forward()
        rx, rz = math.cos(p.yaw), -math.sin(p.yaw)
        vx = vz = 0.0
        if p.hp > 0:
            if keys[pygame.K_w]: vx += fx; vz += fz
            if keys[pygame.K_s]: vx -= fx; vz -= fz
            if keys[pygame.K_a]: vx -= rx; vz -= rz
            if keys[pygame.K_d]: vx += rx; vz += rz
        moving = bool(vx or vz)
        want_sprint = keys[pygame.K_LSHIFT] and moving
        speed = 4.3
        sprinting = False
        if moving:
            l = math.hypot(vx, vz); vx /= l; vz /= l
            if want_sprint and not p.exhausted and p.stam > 0:
                sprinting = True
                speed = 8.2
                p.stam = max(0.0, p.stam - 24*dt)
                if p.stam <= 0:
                    p.exhausted = True
            else:
                p.stam = min(p.max_stam, p.stam + 7*dt)
                if p.exhausted and p.stam >= 30:
                    p.exhausted = False
            nx, nz = p.x + vx*speed*dt, p.z + vz*speed*dt
            for (ox_, oz_, orad) in self.obstacles:
                dx, dz = nx-ox_, nz-oz_
                d = math.hypot(dx, dz)
                if d < orad and d > 1e-6:
                    nx = ox_ + dx/d*orad
                    nz = oz_ + dz/d*orad
            p.x = min(max(nx, 2), WORLD_SIZE-2)
            p.z = min(max(nz, 2), WORLD_SIZE-2)
            p.y = terrain_height(p.x, p.z)
            p.bob += dt*(11 if sprinting else 7.5)
            p.eye_off = math.sin(p.bob)*(0.08 if sprinting else 0.05)
        else:
            p.eye_off *= 0.88
            p.stam = min(p.max_stam, p.stam + 16*dt)
            if p.exhausted and p.stam >= 30:
                p.exhausted = False
            if p.hp > 0 and p.hp < p.max_hp:
                p.hp = min(p.max_hp, p.hp + 1.6*dt)

        alive = [e for e in self.enemies if e.alive]
        for en in alive:
            en.update(dt, p, alive)
        if len(alive) <= 1:
            self.spawn_wave()

        if p.hp <= 0 and self.state == "play":
            self.state = "dead"
            pygame.mouse.set_visible(True)
            pygame.event.set_grab(False)
            self.locked = False

    # ----- рендер -----
    def render(self, surf):
        p = self.player
        self.ras.clear()
        self.ras.set_camera(p.eye, p.yaw, p.pitch)

        # небо: панорама из sky_night.png над горизонтом
        self.blit_sky(surf, p.yaw, p.pitch)

        # земля + объекты
        self.ras.render_triangles(self.verts, self.colors, self.uvs, self.tex_ids)

        # враги
        live = [e for e in self.enemies if e.alive]
        if live:
            ev = np.concatenate([enemy_geometry(e)[0] for e in live])
            ec = np.concatenate([enemy_geometry(e)[1] for e in live])
            self.ras.render_triangles(ev, ec, None, None)

        # перенос кадра из буфера растера в pygame-surface
        pygame.surfarray.blit_array(surf, np.swapaxes(self.ras.frame, 0, 1))

        # меч поверх всего
        self.draw_sword(surf, p)

        if p.hurt > 0:
            hs = pygame.Surface((SCREEN_W, SCREEN_H), pygame.SRCALPHA)
            hs.fill((140, 0, 0, int(p.hurt*220)))
            surf.blit(hs, (0, 0))

        self.draw_hud(surf, p)
        if self.state == "menu":
            draw_menu(surf, "NIGHTREALM",
                      ["WASD — движение    SHIFT — бег    ЛКМ — удар мечом",
                       "Мышь — обзор    ESC — выход из игры",
                       "", "ENTER — начать"])
        elif self.state == "dead":
            draw_menu(surf, "ВЫ ПОГИБЛИ",
                      [f"Убито врагов: {self.kills}", "R — возродиться"])

    def blit_sky(self, surf, yaw, pitch):
        night = self.night
        w, h = night.get_size()
        sky_h = int(SCREEN_H*0.55)
        off = int((yaw/math.tau)*w*3) % w
        strip = pygame.Surface((SCREEN_W, sky_h + 80))
        x = -off
        while x < SCREEN_W:
            strip.blit(night, (x, 0))
            x += w
        py = int(pitch*120)
        surf.blit(strip, (0, sky_h//3 + py - 40))
        # тонировка горизонта в туман
        fade = pygame.Surface((SCREEN_W, SCREEN_H - sky_h + 60), pygame.SRCALPHA)
        total = SCREEN_H - sky_h + 60
        for i in range(0, total, 4):
            a = min(255, int(255*i/total))
            pygame.draw.rect(fade, (10, 14, 30, a), (0, i, SCREEN_W, 4))
        surf.blit(fade, (0, sky_h - 30))

    def draw_sword(self, surf, p):
        sw = p.swing
        if sw > 0:
            k = 1.0 - sw/0.32
            ang = -0.9 + k*1.9
            cx0, cy0 = SCREEN_W*0.72, SCREEN_H + 30
            length = 300
            tipx = cx0 + math.sin(ang)*length*-1
            tipy = cy0 - math.cos(ang)*length
            blade = [(cx0-18, cy0), (cx0+18, cy0), (tipx+10, tipy), (tipx-10, tipy)]
            pygame.draw.polygon(surf, (205, 210, 220), blade)
            pygame.draw.polygon(surf, (150, 155, 165), [(tipx-10, tipy), (tipx+10, tipy), (tipx, tipy-18)])
            guard = [(cx0-34, cy0-8), (cx0+34, cy0-8), (cx0+26, cy0+8), (cx0-26, cy0+8)]
            pygame.draw.polygon(surf, (95, 70, 40), guard)
        else:
            blade = [(SCREEN_W*0.66, SCREEN_H-20), (SCREEN_W*0.70, SCREEN_H-20),
                     (SCREEN_W*0.80, SCREEN_H-210), (SCREEN_W*0.775, SCREEN_H-210)]
            pygame.draw.polygon(surf, (180, 185, 195), blade)
            pygame.draw.polygon(surf, (120, 95, 55),
                                [(SCREEN_W*0.645, SCREEN_H-10), (SCREEN_W*0.715, SCREEN_H-10),
                                 (SCREEN_W*0.71, SCREEN_H+6), (SCREEN_W*0.65, SCREEN_H+6)])

    def draw_hud(self, surf, p):
        draw_bar(surf, 20, SCREEN_H-62, 280, 22, p.hp/p.max_hp, (165, 28, 28),
                 "ЗДОРОВЬЕ" if p.spawn_shield <= 0 else f"ЗДОРОВЬЕ (щит {p.spawn_shield:.0f}с)")
        st_c = (55, 155, 60) if not p.exhausted else (130, 125, 45)
        lbl = "ВЫБИТ!" if p.exhausted else "ВЫНОСЛИВОСТЬ"
        draw_bar(surf, 20, SCREEN_H-28, 280, 15, p.stam/p.max_stam, st_c, lbl)
        cx, cy = SCREEN_W//2, SCREEN_H//2
        for dx1, dy1, dx2, dy2 in ((-9, 0, -4, 0), (4, 0, 9, 0), (0, -9, 0, -4), (0, 4, 0, 9)):
            pygame.draw.line(surf, (235, 235, 235), (cx+dx1, cy+dy1), (cx+dx2, cy+dy2))
        txt = FONT_SMALL.render(f"FPS {self.clock.get_fps():.0f}   Убито: {self.kills}", True, (205, 205, 215))
        surf.blit(txt, (SCREEN_W-170, 10))

    def run(self):
        self.spawn_wave()
        running = True
        while running:
            dt = min(self.clock.tick(60)/1000.0, 0.05)
            events = pygame.event.get()
            running = self.handle_events(events)
            self.update(dt)
            surf = pygame.Surface((SCREEN_W, SCREEN_H))
            self.render(surf)
            self.screen.blit(pygame.transform.scale(surf, self.screen.get_size()), (0, 0))
            pygame.display.flip()
        pygame.quit()


# ----------------------------------------------------------------------------
# HUD helpers / шрифты
# ----------------------------------------------------------------------------
FONT_SMALL = FONT_MED = FONT_TITLE = None

def init_fonts():
    global FONT_SMALL, FONT_MED, FONT_TITLE
    FONT_SMALL = pygame.font.SysFont("dejavusans,arial", 14)
    FONT_MED = pygame.font.SysFont("dejavusans,arial", 20)
    FONT_TITLE = pygame.font.SysFont("dejavusans,arial", 46, bold=True)

def draw_bar(surf, x, y, w, h, frac, color, label=""):
    frac = max(0.0, min(1.0, frac))
    pygame.draw.rect(surf, (0, 0, 0), (x-2, y-2, w+4, h+4), border_radius=5)
    pygame.draw.rect(surf, (22, 22, 26), (x, y, w, h), border_radius=4)
    fw = int(frac*w)
    if fw > 0:
        pygame.draw.rect(surf, color, (x, y, fw, h), border_radius=4)
    pygame.draw.rect(surf, (95, 95, 105), (x, y, w, h), width=1, border_radius=4)
    if label and FONT_SMALL:
        t = FONT_SMALL.render(label, True, (225, 225, 225))
        surf.blit(t, (x+4, y-18))

def draw_menu(surf, title, lines):
    ov = pygame.Surface((SCREEN_W, SCREEN_H), pygame.SRCALPHA)
    ov.fill((5, 8, 18, 205))
    surf.blit(ov, (0, 0))
    t = FONT_TITLE.render(title, True, (228, 228, 238))
    surf.blit(t, (SCREEN_W//2-t.get_width()//2, SCREEN_H//5))
    for i, ln in enumerate(lines):
        f = FONT_MED.render(ln, True, (190, 190, 200))
        surf.blit(f, (SCREEN_W//2-f.get_width()//2, SCREEN_H//3 + 30 + i*30))


# ----------------------------------------------------------------------------
# Загрузка
# ----------------------------------------------------------------------------
def load_textures():
    out = {}
    for key, fname in ((1, "grass.png"), (2, "dirt.png")):
        img = pygame.image.load(asset_path(fname)).convert_alpha()
        arr = pygame.surfarray.array3d(img)          # (W,H,3)
        out[key] = np.swapaxes(arr, 0, 1).copy()     # (H,W,3)
    return out, pygame.image.load(asset_path("sky_night.png")).convert()


def main():
    pygame.init()
    pygame.display.set_caption("NIGHTREALM — open-world FPS (Skyrim-like)")
    screen = pygame.display.set_mode((SCREEN_W, SCREEN_H), pygame.SCALED | pygame.RESIZABLE)
    init_fonts()
    tex_np, sky_surf = load_textures()
    game = Game(screen, tex_np)
    game.night = sky_surf
    game.run()


if __name__ == "__main__":
    main()
