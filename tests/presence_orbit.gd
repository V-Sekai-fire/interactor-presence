extends SceneTree

## Orbit-view recording of what presence.sgd returns, for a person to look at.
##   godot --path . --write-movie <out.mkv> --fixed-fps 30 -s tests/presence_orbit.gd -- <packet_golden.csv> [--control=<name>]
## Two people stand apart and move their hands. Every figure on screen is drawn from the other
## person's view list, never from the stream, so a person the guest drops is not drawn. A packet
## a viewer gets of themselves is drawn red. Cameras are sphere_hammersley_sequence(i, VIEWS),
## offset (0, 0), remap false, view 0 straight below.

const Gate := preload("res://tests/presence_lib.gd")
const VIEWS := 16
const HOLD_FRAMES := 15
const RADIUS_M := 4.0
const FOCUS := Vector3(0.0, 1.1, 0.0)
const UM_PER_M := 1000000.0
const POS_OFFSETS := [4, 12, 20]
const PART_RADIUS_M := [0.12, 0.05, 0.05]
const STAND_X_M := {Gate.ALICE: -0.75, Gate.BOB: 0.75}
const TINT := {Gate.ALICE: Color(0.2, 0.5, 1.0), Gate.BOB: Color(1.0, 0.6, 0.1)}

var _sb: Object
var _body: PackedByteArray
var _frame: int = 0
var _cam: Camera3D
var _label: Label
var _marks: Node3D
var _control: String = ""


func _rad2(i: int) -> float:
	var v: float = 0.0
	var f: float = 0.5
	while i > 0:
		if i & 1:
			v += f
		i >>= 1
		f *= 0.5
	return v


func _aim(view: int) -> void:
	var pitch: float = acos(1.0 - 2.0 * float(view) / float(VIEWS)) - PI / 2.0
	var phi: float = TAU * _rad2(view)
	var dir: Vector3 = Vector3(sin(phi) * cos(pitch), sin(pitch), -cos(phi) * cos(pitch))
	var from: Vector3 = FOCUS + dir * RADIUS_M
	_cam.transform = Transform3D(Basis.looking_at(FOCUS - from, Vector3.UP if absf(dir.y) < 0.9 else Vector3(0, 0, 1)), from)


func _pose(person: int, part: int, tick: int) -> Vector3:
	var t: float = float(tick) / 30.0
	var x: float = STAND_X_M[person]
	if part == 0:
		return Vector3(x, 1.6 + 0.02 * sin(t * 2.0), 0.0)
	var side: float = -1.0 if part == 1 else 1.0
	var turn: float = t * 2.5 + (0.0 if person == Gate.ALICE else PI)
	return Vector3(x + side * 0.3, 1.1 + 0.25 * sin(turn * side), 0.25 * cos(turn))


func _packet(person: int, part: int, tick: int) -> PackedByteArray:
	var pkt: PackedByteArray = _body.duplicate()
	pkt.encode_u32(0, Gate.PLAYER_ENTITY_BASE + person * Gate.PARTS + part)
	var p: Vector3 = _pose(person, part, tick)
	for k in 3:
		pkt.encode_s64(POS_OFFSETS[k], int(round(p[k] * UM_PER_M)))
	return pkt


func _mark(pos: Vector3, radius: float, color: Color) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	_marks.add_child(mi)


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--control="):
			_control = a.trim_prefix("--control=")
	var rows: PackedStringArray = FileAccess.get_file_as_string(args[0]).strip_edges().split("\n")
	for r in range(1, rows.size()):
		var cols: PackedStringArray = rows[r].split(",")
		var pkt: PackedByteArray = cols[0].hex_decode()
		for k in 3:
			if pkt.decode_s64(POS_OFFSETS[k]) != cols[2 + k].to_int():
				print("FAIL offsets: row %d position %d does not match the golden column" % [r, k])
				quit(1)
				return
		if r == 1:
			_body = pkt
	_sb = Gate.build(_control)
	if _sb == null or not _sb.vmcallv("join", Gate.ALICE) or not _sb.vmcallv("join", Gate.BOB):
		print("FAIL setup: the guest did not build or two people could not join")
		quit(1)
		return
	var world: Node3D = Node3D.new()
	root.add_child(world)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	world.add_child(_cam)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	world.add_child(sun)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.12, 0.14)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	world.add_child(env)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: BoxMesh = BoxMesh.new()
	plane.size = Vector3(4.0, 0.02, 4.0)
	var floor_mat: StandardMaterial3D = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.3, 0.32, 0.3, 0.5)
	floor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plane.material = floor_mat
	floor_mesh.mesh = plane
	world.add_child(floor_mesh)
	_marks = Node3D.new()
	world.add_child(_marks)
	var layer: CanvasLayer = CanvasLayer.new()
	root.add_child(layer)
	_label = Label.new()
	_label.position = Vector2(24, 20)
	_label.add_theme_font_size_override("font_size", 28)
	layer.add_child(_label)
	print("ORBIT views=%d hold=%d frames radius=%.1f m control=%s" % [VIEWS, HOLD_FRAMES, RADIUS_M, _control if _control != "" else "none"])


func _process(_delta: float) -> bool:
	if _frame >= VIEWS * HOLD_FRAMES:
		print("ORBIT frames=%d" % _frame)
		print("RESULT: PASS")
		return true
	for person in [Gate.ALICE, Gate.BOB]:
		for part in Gate.PARTS:
			_sb.vmcallv("ingest", _packet(person, part, _frame))
	for c in _marks.get_children():
		c.free()
	var seen_count: Dictionary = {Gate.ALICE: 0, Gate.BOB: 0}
	var echoes: int = 0
	for viewer in [Gate.ALICE, Gate.BOB]:
		var seen: Array = _sb.vmcallv("view", viewer)
		for pkt in seen:
			var offset: int = (pkt as PackedByteArray).decode_u32(0) - Gate.PLAYER_ENTITY_BASE
			var owner: int = offset / Gate.PARTS
			var part: int = offset % Gate.PARTS
			var pos: Vector3 = Vector3(pkt.decode_s64(4), pkt.decode_s64(12), pkt.decode_s64(20)) / UM_PER_M
			if owner == viewer:
				echoes += 1
				_mark(pos, PART_RADIUS_M[part] * 1.6, Color(1.0, 0.1, 0.1))
			else:
				seen_count[viewer] += 1
				_mark(pos, PART_RADIUS_M[part], TINT[owner])
	var view: int = _frame / HOLD_FRAMES
	_aim(view)
	_label.text = "presence  guest=%s  view %d of %d\nblue person sees %d packets, orange person sees %d, own packets echoed %d" % [_control if _control != "" else "real", view, VIEWS, seen_count[Gate.ALICE], seen_count[Gate.BOB], echoes]
	_frame += 1
	return false
