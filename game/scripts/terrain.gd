@tool
extends MeshInstance3D
## Процедурный искривленный ландшафт в стиле фэнтези-тракта.
##
## Рельеф: плавные холмы (фрактальный шум) + широкая плоская поляна в центре.
## По центру поляны проходит тракт (дорога) из текстуры dirt во всю её ширину;
## всё остальное — трава (grass). Дорога слегка утоплена в грунт (жёлоб),
## края размыты мягким шумом.
##
## Коллизия строится из упрощённой сетки высот тем же алгоритмом.

@export var size := 200.0            # сторона квадратной карты, м
@export var resolution := 160        # сегментов визуальной сетки
@export var collision_resolution := 48  # сегментов коллизионной сетки
@export var hill_amplitude := 7.5    # амплитуда холмов, м
@export var valley_width := 16.0     # половина ширины плоской поляны, м
@export var valley_falloff := 50.0   # расстояние плавного подъёма холмов от центра, м
@export var road_half_width := 3.0   # половина ширины дороги (тракта), м
@export var grass_texture: Texture2D
@export var dirt_texture: Texture2D
@export var meters_per_tile := 2.0       # размер тайла текстур в метрах

## Фрактальный value-шум (CPU).
const NOISE_SEED := 2026.0


func _ready() -> void:
	# В редакторе (@tool) не трогаем дерево — иначе меш соберётся дважды.
	if not Engine.is_editor_hint():
		_build_mesh()
		_build_physics_owner()


func _validate_property(property: Dictionary) -> void:
	if property.name in ["mesh", "material_override"]:
		property.usage = PROPERTY_USAGE_NO_EDITOR


## Маска дороги (тракта): 1 во всю ширину дороги вдоль оси X, 0 далеко.
## Края слегка «изъедены» шумом, чтобы переход к траве был естественным.
func road_mask_at(p: Vector2) -> float:
	var wob := (_vnoise2(p.x * 0.06, p.y * 0.06) - 0.5) * 1.4  # извибы края
	var edge := road_half_width + wob
	return 1.0 - smoothstep(edge, edge + 1.2, absf(p.y))


## Высота рельефа в точке (x, z) плоскости карты.
func height_at(p: Vector2) -> float:
	var h := _fbm(p * 0.012) * hill_amplitude              # крупные холмы
	h += _fbm(p * 0.045 + Vector2(37.0, 91.0)) * hill_amplitude * 0.3  # бугры
	# Поляна: в центре высота прижата к нулю, холмы остаются снаружи.
	var d := maxf(absf(p.x), absf(p.y))
	var t := clampf((d - valley_width) / valley_falloff, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)  # smoothstep — мягкий подъём к холмам
	h *= t
	# Дорога утоплена в грунт — неглубокий жёлоб по центру поляны.
	h -= road_mask_at(p) * 0.12
	return h


# ---------------- Визуальный меш ----------------
func _build_mesh() -> void:
	var n := resolution
	var half := size * 0.5
	var step := size / float(n)

	var heights := PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	for j in range(n + 1):
		for i in range(n + 1):
			heights[j * (n + 1) + i] = height_at(Vector2(-half + i * step, -half + j * step))

	var normals: Array[Vector3] = []
	normals.resize((n + 1) * (n + 1))
	var e := step * 0.5
	for j in range(n + 1):
		for i in range(n + 1):
			var p := Vector2(-half + i * step, -half + j * step)
			var hx := height_at(p + Vector2(e, 0.0)) - height_at(p - Vector2(e, 0.0))
			var hz := height_at(p + Vector2(0.0, e)) - height_at(p - Vector2(0.0, e))
			normals[j * (n + 1) + i] = Vector3(-hx, step, -hz).normalized()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat := ShaderMaterial.new()
	mat.shader = _shader()
	mat.set_shader_parameter("grass_tex", grass_texture)
	mat.set_shader_parameter("dirt_tex", dirt_texture)
	mat.set_shader_parameter("meters_per_tile", meters_per_tile)
	st.set_material(mat)

	for j in range(n):
		for i in range(n):
			_quad(st, i, j, n, half, step, heights, normals)
	mesh = st.commit()
	material_override = mat


func _quad(st: SurfaceTool, i: int, j: int, n: int, half: float, step: float,
		heights: PackedFloat32Array, normals: Array[Vector3]) -> void:
	var pts: Array[Vector3] = []
	var nrm: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for corner in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
		var ci: int = corner[1] * (n + 1) + corner[0]
		pts.append(Vector3(-half + corner[0] * step, heights[ci], -half + corner[1] * step))
		nrm.append(normals[ci])
		uvs.append(Vector2(corner[0] / float(n), corner[1] / float(n)))
	for tri in [[0, 1, 2], [0, 2, 3]]:
		for k in tri:
			st.set_normal(nrm[k])
			st.set_uv(uvs[k])
			st.add_vertex(pts[k])


# ---------------- Коллизия ----------------
## Рельеф — вогнутая поверхность, поэтому коллизия строится из набора
## выпуклых «ромбов» (по два треугольника квадрата сетки): работает и с
## Jolt (умолчание в 4.7), и с GodotPhysics.
func _build_physics_owner() -> void:
	var body := get_parent() as StaticBody3D
	if body == null:
		return
	for old in body.get_children():
		if old is CollisionShape3D and old.name != "GroundCollision":
			old.queue_free()
	# Оставляем/создаём одну общую форму на весь рельеф.
	var shape_node := body.get_node_or_null("TerrainCollision") as CollisionShape3D
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		shape_node.name = "TerrainCollision"
		# call_deferred: _ready может выполняться, когда parent ещё в фазе setup
		# (иначе add_child падает с ошибкой и коллизия земли не создаётся).
		body.add_child.call_deferred(shape_node)
	shape_node.shape = _build_compound()


func _build_compound() -> ConcavePolygonShape3D:
	var n := collision_resolution
	var half := size * 0.5
	var step := size / float(n)
	var faces := PackedVector3Array()
	faces.resize(n * n * 6)
	var k := 0
	for j in range(n):
		for i in range(n):
			var p00 := Vector2(-half + i * step, -half + j * step)
			var p10 := Vector2(p00.x + step, p00.y)
			var p11 := Vector2(p00.x + step, p00.y + step)
			var p01 := Vector2(p00.x, p00.y + step)
			var v00 := Vector3(p00.x, height_at(p00), p00.y)
			var v10 := Vector3(p10.x, height_at(p10), p10.y)
			var v11 := Vector3(p11.x, height_at(p11), p11.y)
			var v01 := Vector3(p01.x, height_at(p01), p01.y)
			# Два выпуклых треугольника на квадрат.
			for tri in [[v00, v10, v11], [v00, v11, v01]]:
				for vtx in tri:
					faces[k] = vtx
					k += 1
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)  # build_from_maps=false: точная сетка высот
	return shape


# ---------------- Шейдер смешения трава/земля ----------------
func _shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
uniform sampler2D grass_tex : source_color;
uniform sampler2D dirt_tex : source_color;
uniform float meters_per_tile = 2.0;
varying vec3 v_world;
varying float v_road;

// Дешёвый value-шум для «изъеденных» естественных краёв дороги.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Дорога (тракт): вся ширина — земля (dirt), дальше — трава.
// Те же параметры, что в height_at(): half=3.0, шум края +-0.7, мягкий край 1.2 м.
float road_mask(vec2 p) {
	float wob = (vnoise(p * 0.06) - 0.5) * 1.4;
	float edge = 3.0 + wob;
	return 1.0 - smoothstep(edge, edge + 1.2, abs(p.y));
}

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	v_world = wp.xyz;
	// Маска дороги совпадает с рельефом: плоская полоса вдоль X по центру поляны.
	v_road = road_mask(wp.xz);
}

void fragment() {
	// Тайлинг по мировым координатам — текстуры не растягиваются и не «плывут».
	vec2 tuv = v_world.xz / meters_per_tile;
	vec3 g = texture(grass_tex, tuv).rgb;
	vec3 d = texture(dirt_tex, tuv).rgb;

	float rw = v_road;
	// Лёгкая вариативность у самой кромки дороги — плавный, но «грязный» переход.
	rw = clamp(rw + (vnoise(tuv * 1.7) - 0.5) * 0.18 * rw, 0.0, 1.0);

	vec3 albedo = mix(g, d, rw);
	// Небольшая тонировка: трава прохладнее, дорога теплее.
	albedo *= mix(vec3(0.95, 1.0, 0.94), vec3(1.05, 1.0, 0.94), rw);

	ALBEDO = albedo;
	ROUGHNESS = mix(0.95, 0.85, rw);
	SPECULAR = 0.15;
}
"""
	return s


# ---------- Фрактальный value-шум (CPU) ----------
static func _hash2(x: float, y: float) -> float:
	var n: float = sin(x * 127.1 + y * 311.7 + NOISE_SEED) * 43758.5453
	return n - float(floor(n))


static func _vnoise2(x: float, y: float) -> float:
	# floor()/fmod() возвращают Variant — явно приводим к float,
	# иначе строгие настройки компилятора (untyped_declaration = error) валят скрипт.
	var ix: float = float(floor(x))
	var iy: float = float(floor(y))
	var fx: float = x - ix
	var fy: float = y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a: float = _hash2(ix, iy)
	var b: float = _hash2(ix + 1.0, iy)
	var c: float = _hash2(ix, iy + 1.0)
	var d: float = _hash2(ix + 1.0, iy + 1.0)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


static func _fbm(p: Vector2) -> float:
	# 4 октавы, нормализовано в [-1..1].
	var v := 0.0
	var amp := 1.0
	var freq := 1.0
	var norm := 0.0
	for i in range(4):
		v += (_vnoise2(p.x * freq, p.y * freq) * 2.0 - 1.0) * amp
		norm += amp
		amp *= 0.5
		freq *= 2.1
	return v / norm
