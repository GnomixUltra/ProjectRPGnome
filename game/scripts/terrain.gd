@tool
extends MeshInstance3D
## Процедурный искривленный ландшафт в стиле фэнтези-тракта.
##
## Рельеф: плавные холмы (фрактальный шум) + широкая плоская долина в центре
## — по ней «идёт» тракт. К краям карты земля поднимается волнами.
##
## Смешение трав и земли: на вершинах холмов и крутых склонах проступает
## земля (dirt), в низинах и на пологих местах — трава. Переходы плавные,
## с рваными «естественными» границами (шум). Считается попиксельно в
## кастомном шейдере; текстуры назначаются через @export.
##
## Коллизия строится из упрощённой сетки высот тем же алгоритмом.

@export var size := 200.0            # сторона квадратной карты, м
@export var resolution := 160        # сегментов визуальной сетки
@export var collision_resolution := 48  # сегментов коллизионной сетки
@export var hill_amplitude := 7.5    # амплитуда холмов, м
@export var valley_width := 16.0     # половина ширины плоской долины/тракта, м
@export var valley_falloff := 50.0   # расстояние плавного подъёма холмов от центра, м
@export var grass_texture: Texture2D
@export var dirt_texture: Texture2D
@export var uv_scale := Vector2(64, 64)  # тайлинг текстур по всей карте

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


## Высота рельефа в точке (x, z) плоскости карты.
func height_at(p: Vector2) -> float:
	var h := _fbm(p * 0.012) * hill_amplitude              # крупные холмы
	h += _fbm(p * 0.045 + Vector2(37.0, 91.0)) * hill_amplitude * 0.3  # бугры
	# Долина тракта: в центре высота прижата к нулю, холмы остаются снаружи.
	var d := maxf(absf(p.x), absf(p.y))
	var t := clampf((d - valley_width) / valley_falloff, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)  # smoothstep — мягкий подъём от дороги к холмам
	return h * t


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
	mat.set_shader_parameter("uv_scale", uv_scale)
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
		body.add_child(shape_node)
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
uniform vec2 uv_scale = vec2(64.0, 64.0);
varying float v_height;
varying vec3 v_nrm;

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	v_height = wp.y;
	v_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Дешёвый value-шум для «рваных» естественных границ смешения.
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

void fragment() {
	vec2 tuv = UV * uv_scale;
	vec3 g = texture(grass_tex, tuv).rgb;
	vec3 d = texture(dirt_tex, tuv).rgb;

	float up = v_nrm.y;                              // 1 = плоско, 0 = отвесно
	float slope_dirt = 1.0 - smoothstep(0.60, 0.85, up);   // крутые склоны — земля
	float high_dirt = smoothstep(1.5, 4.0, v_height);      // макушки холмов — земля
	float low_grass = 1.0 - smoothstep(-1.5, 0.5, v_height); // низины — всегда трава

	// Плавное смешение с шумами: границы травы и земли неровные.
	float edge_noise = (vnoise(tuv * 0.8) - 0.5) * 0.3;
	float patch = vnoise(tuv * 0.15 + 4.7);                // локальные «проплешины»
	float dirt_w = clamp(slope_dirt * (0.5 + high_dirt)
		+ high_dirt * 0.55
		+ (patch - 0.5) * 0.35
		+ edge_noise
		- low_grass * 0.6, 0.0, 1.0);

	vec3 albedo = mix(g, d, dirt_w);
	// Лёгкая тонировка: прохладнее у травы, теплее у земли.
	albedo *= mix(vec3(0.93, 0.98, 0.92), vec3(1.05, 1.0, 0.95), dirt_w);

	ALBEDO = albedo;
	ROUGHNESS = mix(0.95, 0.85, dirt_w);
	SPECULAR = 0.15;
}
"""
	return s


# ---------- Фрактальный value-шум (CPU) ----------
static func _hash2(x: float, y: float) -> float:
	var n := sin(x * 127.1 + y * 311.7 + NOISE_SEED) * 43758.5453
	return n - floor(n)


static func _vnoise2(x: float, y: float) -> float:
	var ix := floor(x)
	var iy := floor(y)
	var fx := x - ix
	var fy := y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _hash2(ix, iy)
	var b := _hash2(ix + 1.0, iy)
	var c := _hash2(ix, iy + 1.0)
	var d := _hash2(ix + 1.0, iy + 1.0)
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
