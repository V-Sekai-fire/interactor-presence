extends SceneTree


const VIEWS := 8
const FPS := 32
const RADIUS := 4.2
const FOCUS_HEIGHT := 0.9
const APART := Vector3(1.6, 0, 0)
const CLIPS := ["walk", "idle"]

var lib: Object
var args: Array = []
var control := ""
var clip := -1
var frame := 0
var tick := 0
var cam: Camera3D
var sent: Array[MeshInstance3D] = []
var drawn: Array[MeshInstance3D] = []
var caption: Label
var worst_mm := 0.0


func _rad2(i: int) -> float:
	var r := 0.0
	var f := 0.5
	var n := i
	while n > 0:
		r += f * float(n & 1)
		n >>= 1
		f *= 0.5
	return r


func _view_dir(view: int) -> Vector3:
	var pitch := acos(1.0 - 2.0 * float(view) / float(VIEWS)) - PI / 2.0
	var phi := TAU * _rad2(view)
	return Vector3(sin(phi) * cos(pitch), sin(pitch), -cos(phi) * cos(pitch))


func _end(line: String, code: int) -> void:
	print(line)
	quit(code)


func _at(t: PackedFloat64Array, body: int) -> Vector3:
	return Vector3(t[body * 7 + 1], t[body * 7 + 2], t[body * 7])


func _dots(color: Color) -> Array[MeshInstance3D]:
	var ball := SphereMesh.new()
	ball.radius = 0.018
	ball.height = 0.036
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.render_priority = 10
	ball.material = mat
	var out: Array[MeshInstance3D] = []
	for p in 21:
		var d := MeshInstance3D.new()
		d.mesh = ball
		root.add_child(d)
		out.append(d)
	return out


func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--control="):
			control = x.trim_prefix("--control=")
		else:
			args.append(x)
	if args.size() != 4:
		_end("RESULT: ERROR give the presence directory, the physics guest, the avatar and the clips directory", 2)
		return
	lib = load(String(args[0]).path_join("tests/body_lib.gd")).new()
	if not lib.build(args[0], args[1], args[2], control):
		_end("RESULT: ERROR " + lib.error, 2)
		return
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	for l in [[Vector3(-50, 35, 0), 0.7], [Vector3(55, -145, 0), 0.25]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = l[0]
		light.light_energy = l[1]
		root.add_child(light)
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.45, 0.47, 0.5)
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for i in range(-10, 11):
		im.surface_add_vertex(Vector3(i, 0, -10))
		im.surface_add_vertex(Vector3(i, 0, 10))
		im.surface_add_vertex(Vector3(-10, 0, i))
		im.surface_add_vertex(Vector3(10, 0, i))
	im.surface_end()
	var grid := MeshInstance3D.new()
	grid.mesh = im
	root.add_child(grid)
	root.add_child(lib.sender.scene)
	root.add_child(lib.viewer.scene)
	lib.viewer.scene.position = APART
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.05
	cam.far = 60.0
	root.add_child(cam)
	cam.make_current()
	sent = _dots(Color(1.0, 0.35, 0.1))
	drawn = _dots(Color(0.2, 0.85, 1.0))
	var layer := CanvasLayer.new()
	caption = Label.new()
	caption.position = Vector2(24, 18)
	caption.add_theme_font_size_override("font_size", 22)
	layer.add_child(caption)
	root.add_child(layer)
	await process_frame
	clip = 0
	if not lib.begin(String(args[3]).path_join(CLIPS[0] + ".f64")):
		_end("RESULT: ERROR " + lib.error, 2)


func _process(_delta: float) -> bool:
	if clip < 0:
		return false
	var live := false
	for k in 2:
		if tick < lib.ticks:
			live = lib.step(tick)
			tick += 1
	if tick >= lib.ticks:
		clip += 1
		tick = 0
		if clip >= CLIPS.size():
			print("VIDEO control=%s frames=%d fps=%d clips=%s views=%d worst_mm=%.2f refused=%d" % [control if control != "" else "real", frame, FPS, "+".join(CLIPS), VIEWS, worst_mm, lib.refused])
			print("RESULT: PASS recorded")
			quit(0)
			return true
		if not lib.begin(String(args[3]).path_join(CLIPS[clip] + ".f64")):
			print("RESULT: ERROR " + lib.error)
			quit(2)
			return true
		return false
	var now_mm := 0.0
	for p in 21:
		sent[p].position = _at(lib.now, lib.ids[p])
		drawn[p].position = _at(lib.seen, lib.ids[p]) + APART
		if live:
			now_mm = maxf(now_mm, (_at(lib.seen, lib.ids[p]) - _at(lib.then, lib.ids[p])).length() * 1000.0)
	worst_mm = maxf(worst_mm, now_mm)
	var view: int = mini(tick * VIEWS / lib.ticks, VIEWS - 1)
	var hip: Vector3 = _at(lib.now, lib.ids[3])
	var focus := Vector3(hip.x, FOCUS_HEIGHT, hip.z) + APART * 0.5
	var dir := _view_dir(view)
	var from := focus + dir * RADIUS
	cam.transform = Transform3D(Basis.looking_at(focus - from, Vector3.UP if absf(dir.y) < 0.9 else Vector3(0, 0, 1)), from)
	caption.text = "%s   %s   view %d of %d\norange: the sender's body now    blue: what the viewer draws, 12 ticks behind\nlargest distance this frame %.1f mm    frames refused %d" % [("planted: " + control) if control != "" else "real", CLIPS[clip], view + 1, VIEWS, now_mm, lib.refused]
	frame += 1
	return false
