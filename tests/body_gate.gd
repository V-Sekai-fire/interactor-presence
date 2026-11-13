extends SceneTree


const SEND_TICKS := 6
const DELAY := 12
const PERSON := 7
const VIEWER := 9
const TICK_HZ := 64.0
const TICK_USEC := 15625.0
const PLANT_AT := 300
const ORIGIN := [4000000000000000000, -8000000000000000000, 6500000000000000000]
const PLANTS := {
	"swap": ["", "", ""],
	"axes": ["packets", "\t\torigin[0] + int(round(-place[1] * UM)), origin[1] + int(round(place[2] * UM)), origin[2] + int(round(-place[0] * UM)),\n", "\t\torigin[0] + int(round(place[0] * UM)), origin[1] + int(round(place[2] * UM)), origin[2] + int(round(-place[1] * UM)),\n"],
	"flip": ["", "", ""],
}

var here := ""
var usec := 0


func _end(line: String, code: int) -> void:
	print(line)
	quit(code)


func _guest(file: String, control: String) -> Object:
	var src: String = FileAccess.get_file_as_string(here.path_join(file + ".sgd"))
	if control != "" and PLANTS[control][0] == file:
		if src.count(PLANTS[control][1]) != 1:
			return null
		src = src.replace(PLANTS[control][1], PLANTS[control][2])
	var script: Object = ClassDB.instantiate("SafeGDScript")
	script.set_source_code(src)
	if script.get_compile_error() != "":
		print("compile %s: %s" % [file, script.get_compile_error()])
		return null
	var sb: Object = ClassDB.instantiate("Sandbox")
	sb.load_buffer(script.get_content())
	return sb


func _call(sb: Object, args: Array) -> Variant:
	var t0 := Time.get_ticks_usec()
	var out = sb.callv("vmcallv", args)
	usec += Time.get_ticks_usec() - t0
	return out


func _keys(slot: int) -> Array:
	var table := FileAccess.get_file_as_bytes(here.path_join("testdata/zone-fixture/keys.%d.table" % slot))
	var out: Array = []
	if table.size() == 100 and table[0] == 3:
		for i in 3:
			out.append(table.slice(2 + i * 33, 34 + i * 33))
	return out


func _qpos(q: PackedFloat64Array, frames: int, t: float) -> PackedFloat64Array:
	var f: float = clampf(t * 100.0, 0.0, frames - 1.0)
	var i: int = mini(int(f), frames - 2)
	var w: float = f - i
	var out := PackedFloat64Array()
	out.resize(86)
	for k in 86:
		out[k] = lerpf(q[i * 86 + k], q[(i + 1) * 86 + k], w)
	var n := sqrt(out[3] * out[3] + out[4] * out[4] + out[5] * out[5] + out[6] * out[6])
	for k in range(3, 7):
		out[k] /= n
	return out


func _quat(t: PackedFloat64Array, o: int) -> Quaternion:
	return Quaternion(t[o + 4], t[o + 5], t[o + 6], t[o + 3])


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var control := ""
	var clips := ["walk", "idle"]
	var plain: Array = []
	var beat := -1.0
	for x in a:
		if x.begins_with("--control="):
			control = x.trim_prefix("--control=")
		elif x.begins_with("--line="):
			beat = x.trim_prefix("--line=").to_float()
		elif x.begins_with("--clips="):
			clips = Array(x.trim_prefix("--clips=").split(","))
		else:
			plain.append(x)
	if plain.size() != 4 or (control != "" and not PLANTS.has(control)):
		_end("RESULT: ERROR give the presence directory, the physics guest, the avatar and the clips directory", 2)
		return
	here = plain[0]
	var Rig = load("res://tests/follow_rig.gd")
	var sender = Rig.new()
	var viewer = Rig.new()
	if not sender.build(plain[1], plain[2], "") or not viewer.build(plain[1], plain[2], ""):
		_end("RESULT: ERROR %s%s" % [sender.error, viewer.error], 2)
		return
	root.add_child(sender.scene)
	root.add_child(viewer.scene)
	await process_frame

	var names: Array = []
	for line in FileAccess.get_file_as_string(here.path_join("data/parts.tsv")).split("\n", false).slice(1):
		names.append(line.split("\t")[1])
	var sorted_names := names.duplicate()
	sorted_names.sort()
	var driven := Array(sender.parts)
	driven.sort()
	if names.size() != 21 or sorted_names != driven:
		_end("RESULT: ERROR the part table is not the 21 bodies that drive the avatar", 2)
		return
	var ids := PackedInt32Array()
	for n in names:
		ids.append(sender.bodies.find(n))
	var seen_ids := ids.duplicate()
	if control == "swap":
		seen_ids[1] = ids[2]
		seen_ids[2] = ids[1]

	var packets := _guest("packets", control)
	var reader := _guest("packets", "")
	var router := _guest("router", "")
	var curve := _guest("curve", "")
	var obs_s := _guest("observer", "")
	var obs_v := _guest("observer", "")
	if packets == null or reader == null or router == null or curve == null or obs_s == null or obs_v == null:
		_end("RESULT: ERROR a guest does not build", 2)
		return
	var ks := _keys(0)
	var kv := _keys(1)
	if ks.size() != 3 or kv.size() != 3:
		_end("RESULT: ERROR no fixture keys", 2)
		return
	obs_s.vmcallv("setup", 0, PERSON, VIEWER, 12, 30)
	obs_v.vmcallv("setup", 1, PERSON, VIEWER, 12, 30)
	obs_s.vmcallv("keys", ks[0], ks[1], ks[2])
	obs_v.vmcallv("keys", kv[0], kv[1], kv[2])

	var m: int = sender.bodies.size()
	var origin := PackedInt64Array(ORIGIN)
	var worst_mm := 0.0
	var sum_mm := 0.0
	var worst_turn := 0.0
	var compared := 0
	var drawn_parts := 0
	var refused := 0
	var taken := 0
	var ticks_done := 0
	var blank := PackedByteArray()
	blank.resize(300)
	for clip in clips:
		var q := FileAccess.get_file_as_bytes(String(plain[3]).path_join(clip + ".f64")).to_float64_array()
		var frames: int = q.size() / 86
		if frames < 200:
			_end("RESULT: ERROR no clip %s" % clip, 2)
			return
		var ticks: int = int(frames / 100.0 * TICK_HZ)
		router.vmcallv("reset")
		router.vmcallv("join", PERSON)
		router.vmcallv("join", VIEWER)
		curve.vmcallv("reset", 21, float(DELAY))
		var history: Array = []
		var turns: Array = []
		var has: Array = []
		has.resize(21)
		has.fill(false)
		for t in ticks:
			var now: PackedFloat64Array = sender.bodies_at(_qpos(q, frames, t / TICK_HZ))
			sender.pose(now)
			history.append(now)
			if history.size() > DELAY + 1:
				history.pop_front()
			if t % SEND_TICKS == 0 and history.size() >= 3:
				var two := PackedByteArray()
				var was: PackedFloat64Array = history[history.size() - 2]
				var ago: PackedFloat64Array = history[history.size() - 3]
				for p in 21:
					var o: int = ids[p] * 7
					var motion := PackedFloat64Array()
					for k in 3:
						motion.append(now[o + k] - was[o + k])
					for k in 3:
						motion.append(now[o + k] - 2.0 * was[o + k] + ago[o + k])
					two.append_array(_call(packets, ["body", PERSON, p, t, origin, now.slice(o, o + 7), motion]))
				two.append_array(blank)
				var sealed: PackedByteArray = _call(obs_s, ["seal", two.slice(0, 1200), two.slice(1200), t / SEND_TICKS])
				_call(router, ["put", 0, 0, sealed.slice(0, 1200)])
				_call(router, ["put", 0, 1, sealed.slice(1200)])
				var fresh := true
				var points: Array = []
				for half in 2:
					var f: PackedByteArray = _call(router, ["frame", 1, half])
					if control == "flip" and t >= PLANT_AT and half == 0:
						f[777] = f[777] ^ 1
					if _call(obs_v, ["take", half, f]) != true:
						refused += 1
						fresh = false
						continue
					taken += 1
					for i in (12 if half == 0 else 9):
						points.append(_call(reader, ["placed", f.slice(i * 100, i * 100 + 100), origin]))
				var turn: Array = []
				turn.resize(21)
				for pt in points:
					var p: int = int(pt[0]) - 2000000 - PERSON * 21
					_call(curve, ["put", p, pt[1], pt[2], pt[3], pt[4], pt[9], pt[10], pt[11]])
					turn[p] = Quaternion(pt[6], pt[7], pt[8], pt[5])
					has[p] = true
				if fresh:
					turns.append([t, turn])
					if turns.size() > 4:
						turns.pop_front()
			_call(router, ["tick"])
			var view: float = t - DELAY
			_call(curve, ["advance", view])
			var seen := PackedFloat64Array()
			seen.resize(m * 7)
			var lo: int = 0
			for i in turns.size():
				if turns[i][0] <= view:
					lo = i
			var hi: int = mini(lo + 1, turns.size() - 1)
			for p in 21:
				var d: PackedFloat64Array = _call(curve, ["drawn", p])
				var o: int = seen_ids[p] * 7
				var r := Quaternion.IDENTITY
				if not turns.is_empty():
					var w: float = 0.0
					if hi > lo:
						w = clampf((view - turns[lo][0]) / float(turns[hi][0] - turns[lo][0]), 0.0, 1.0)
					r = turns[lo][1][p].slerp(turns[hi][1][p], w)
				seen[o] = d[0]
				seen[o + 1] = d[1]
				seen[o + 2] = d[2]
				seen[o + 3] = r.w
				seen[o + 4] = r.x
				seen[o + 5] = r.y
				seen[o + 6] = r.z
			var t0 := Time.get_ticks_usec()
			var posed: bool = viewer.pose(seen)
			usec += Time.get_ticks_usec() - t0
			ticks_done += 1
			if t < 4 * SEND_TICKS + DELAY or not posed or history.size() <= DELAY:
				continue
			var then: PackedFloat64Array = history[0]
			for p in 21:
				var o: int = ids[p] * 7
				var mm: float = Vector3(seen[o] - then[o], seen[o + 1] - then[o + 1], seen[o + 2] - then[o + 2]).length() * 1000.0
				worst_mm = maxf(worst_mm, mm)
				sum_mm += mm
				worst_turn = maxf(worst_turn, _quat(seen, o).angle_to(_quat(then, o)))
				compared += 1
		drawn_parts = has.count(true)
	var share: float = usec / float(maxi(ticks_done, 1)) / TICK_USEC
	print("BODY control=%s clips=%s ticks=%d parts_drawn=%d frames_taken=%d frames_refused=%d" % [control if control != "" else "none", ",".join(clips), ticks_done, drawn_parts, taken, refused])
	print("LEDGER parts_drawn=%d err_max_mm=%.3f err_mean_mm=%.3f turn_max_mrad=%.2f honest_refused=%d tick_share=%.3f" % [drawn_parts, worst_mm, sum_mm / maxi(compared, 1), worst_turn * 1000.0, refused if control == "" else 0, share])
	if compared == 0 or drawn_parts != 21:
		_end("RESULT: FAIL %d of 21 parts were drawn" % drawn_parts, 1)
		return
	if control == "":
		if refused > 0:
			_end("RESULT: FAIL %d honest frames were refused" % refused, 1)
		else:
			_end("RESULT: PASS", 0)
		return
	if beat <= 0.0:
		_end("RESULT: ERROR a control needs --line=<the largest error of the run without it>", 2)
	elif control == "flip" and refused == 0:
		_end("RESULT: ERROR the flipped frames were taken", 2)
	elif worst_mm > 2.0 * beat:
		_end("RESULT: FAIL the planted %s made the largest error %.1f mm, from %.1f" % [control, worst_mm, beat], 1)
	else:
		_end("RESULT: ERROR the planted %s did not make the line worse" % control, 2)
