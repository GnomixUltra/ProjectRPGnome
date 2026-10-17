@tool
extends MeshInstance3D
## Процедурный извилистый ландшафт — густая фэнтезийная чаща.
##
## Рельеф: крутые извилистые хребты и глубокие овраги тянутся через ВСЮ карту
## (ridge-шум + доменный warp), пологие холмы и частые валуны-бугры поверх.
## В центре — небольшая плоская поляна с трактом (дорога dirt); всё остальное —
## трава (grass). Холмы начинаются сразу за краем поляны, поэтому карта читается
## как лесистая котловина, со всех сторон стиснутая грядами.
##
## Коллизия строится из упрощённой сетки высот тем же алгоритмом.

@export var size := 200.0            # сторона квадратной карты, м
@export var resolution := 160        # сегментов визуальной сетки
@export var collision_resolution := 48  # сегментов коллизионной сетки
@export var hill_amplitude := 8.0    # амплитуда пологих холмов, м
@export var ridge_amplitude := 15.0  # амплитуда извилистых хребтов, м
@export var crease_depth := 5.0      # глубина оврагов-складок, м
@export var boulder_amplitude := 1.6 # амплитуда частых бугров «чащи», м
@export var warp_strength := 18.0    # сила доменного искажения (извилистость), м
@export var valley_width := 13.0     # радиус плоской поляны в центре, м
@export var valley_falloff := 26.0   # расстояние подъёма холмов от края поляны, м
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


## Извилистая гряда хребтов, тянущаяся через всю карту.
## Ключевой приём — доменный warp: координаты шума искажаются самим шумом,
## из-за чего гребни не прямые линии, а «закрученные» ленты, огибающие поляну.
## Профиль гребня — ridge-шум (1 - |fbm|), складки (отрицательная часть) дают
## глубокие узкие овраги между грядами.
func _ridges(p: Vector2) -> float:
	# Доменное искажение: сдвигаем точку по двум медленным шумам.
	var w := Vector2(
		_vnoise2(p.x * 0.013 + 11.0, p.y * 0.013 + 3.7) - 0.5,
		_vnoise2(p.x * 0.013 - 6.2, p.y * 0.013 + 21.0) - 0.5
	) * warp_strength
	var q := p + w
	# Гряда 1: широкая лента вдоль X (севернее центра), зигзаг ~±20 м.
	var c1 := -48.0 + sin(q.x * 0.035) * 20.0 + (_vnoise2(q.x * 0.02, 7.0) - 0.5) * 14.0
	var d1 := q.y - c1
	var w1 := exp(-pow(d1 / 30.0, 2.0))
	var r1 := 1.0 - absf(_fbm(q * 0.017 + Vector2(5.0, 9.0)))
	# Гряда 2: диагональ северо-запад -> юго-восток, огибает поляну с востока.
	var nrm := Vector2(0.6, 0.8)
	var along := p.dot(Vector2(-0.8, 0.6))
	var dn := p.dot(nrm) - (-14.0 + sin(along * 0.026) * 16.0)
	var w2 := exp(-pow(dn / 26.0, 2.0))
	var r2 := 1.0 - absf(_fbm(q * 0.021 + Vector2(77.0, 13.0)))
	# Гряда 3: южная стена карты, вдоль X.
	var c3 := 58.0 + sin(q.x * 0.03 + 2.0) * 18.0
	var d3 := q.y - c3
	var w3 := exp(-pow(d3 / 28.0, 2.0))
	var r3 := 1.0 - absf(_fbm(q * 0.019 + Vector2(31.0, 55.0)))
	var ridges := pow(r1, 1.8) * w1 + pow(r2, 1.8) * w2 * 0.9 + pow(r3, 1.8) * w3
	# Складки-овраги: там, где ridge-профиль низкий, вытягиваем вниз.
	var crease := minf(minf(r1 * w1, r2 * w2), r3 * w3)
	return pow(ridges, 1.3) * ridge_amplitude - crease * crease_depth


## Высота рельефа в точке (x, z) плоскости карты.
func height_at(p: Vector2) -> float:
	var h := _fbm(p * 0.011) * hill_amplitude              # крупные холмы
	h += _fbm(p * 0.05 + Vector2(37.0, 91.0)) * boulder_amplitude  # бугры «чащи»
	h += _ridges(p)                                          # извилистые гряды по всей карте
	# Поляна: в центре высота прижата к нулю, чаща подступает сразу за её краем.
	var d := p.length()
	var t := clampf((d - valley_width) / valley_falloff, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)  # smoothstep — мягкий, но быстрый подъём из поляны
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
