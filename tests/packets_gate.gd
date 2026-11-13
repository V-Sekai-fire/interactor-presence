extends SceneTree


const PLANTS := {
	"flip": ["", ""],
	"axes": ["\t\torigin[0] + int(round(-place[1] * UM)), origin[1] + int(round(place[2] * UM)), origin[2] + int(round(-place[0] * UM)),\n", "\t\torigin[0] + int(round(place[0] * UM)), origin[1] + int(round(place[2] * UM)), origin[2] + int(round(-place[1] * UM)),\n"],
	"float": ["\t\torigin[0] + int(round(-place[1] * UM)), origin[1] + int(round(place[2] * UM)), origin[2] + int(round(-place[0] * UM)),\n", "\t\tint(round(float(origin[0]) - place[1] * UM)), int(round(float(origin[1]) + place[2] * UM)), int(round(float(origin[2]) - place[0] * UM)),\n"],
	"twist": ["\treturn PackedInt64Array([int(round(k * sx * SWING)), int(round(k * sz * SWING)), twist])\n", "\treturn PackedInt64Array([int(round(k * sx * SWING)), twist, int(round(k * sz * SWING))])\n"],
}
const HAIR_UM := 17.0
const FAR := [4000000000000000000, -8000000000000000000, 6500000000000000000]
const EXAMPLES := [
	[Quaternion(0, 0, 0, 1), [0, 0, 0]],
	[Quaternion(sqrt(0.5), 0, 0, sqrt(0.5)), [16383, 0, 0]],
	[Quaternion(0, 0, sqrt(0.5), sqrt(0.5)), [0, 16383, 0]],
	[Quaternion(0, sqrt(0.5), 0, sqrt(0.5)), [0, 0, 16384]],
]


func _end(line: String, code: int) -> void:
	print(line)
	quit(code)


func _build(control: String) -> Object:
	var src: String = FileAccess.get_file_as_string("res://packets.sgd")
	if control != "" and PLANTS[control][0] != "":
		if src.count(PLANTS[control][0]) != 1:
			return null
		src = src.replace(PLANTS[control][0], PLANTS[control][1])
	var script: Object = ClassDB.instantiate("SafeGDScript")
	script.set_source_code(src)
	if script.get_compile_error() != "":
		print("compile packets: %s" % script.get_compile_error())
		return null
	var sb: Object = ClassDB.instantiate("Sandbox")
	sb.load_buffer(script.get_content())
	return sb


func _init() -> void:
	var control := ""
	var golden := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--control="):
			control = a.trim_prefix("--control=")
		elif golden == "":
			golden = a
	if control != "" and not PLANTS.has(control):
		_end("RESULT: ERROR no control named %s" % control, 2)
		return
	var guest := _build(control)
	if guest == null:
		_end("RESULT: ERROR the packets guest does not build", 2)
		return
	var rows := FileAccess.get_file_as_string(golden).split("\n", false)
	if rows.size() < 2 or not rows[0].begins_with("hex,gid,pumx"):
		_end("RESULT: ERROR give the contract's packet_golden_full.csv", 2)
		return
	var bad: Array = []
	var checked := 0
	for r in range(1, rows.size()):
		var f := rows[r].split(",")
		var ints := PackedInt64Array()
		for i in range(1, 17):
			ints.append(f[i].to_int())
		var want: String = f[0]
		if control == "flip" and r == 7:
			want = want.substr(0, 60) + ("0" if want[60] != "0" else "1") + want.substr(61)
		var made = guest.vmcallv("raw", ints, f[17].hex_decode())
		var read = guest.vmcallv("fields", f[0].hex_decode())
		if not made is PackedByteArray or made.hex_encode() != want:
			bad.append("row %d is not written as the contract writes it" % r)
		elif not read is PackedInt64Array or read != ints:
			bad.append("row %d is not read as the contract reads it" % r)
		checked += 1
	for e in EXAMPLES:
		var q: Quaternion = e[0]
		var c = guest.vmcallv("rot_codes", q.x, q.y, q.z, q.w)
		if not c is PackedInt64Array or c.size() != 3 or absi(c[0] - e[1][0]) > 1 or absi(c[1] - e[1][1]) > 1 or absi(c[2] - e[1][2]) > 1:
			bad.append("the rotation %s has codes %s and the contract says %s" % [q, c, e[1]])
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261113
	var worst_turn := 0.0
	var worst_um := 0.0
	var worst_axis := 0.0
	var worst_far := 0.0
	var here := PackedInt64Array([0, 0, 0])
	var far := PackedInt64Array(FAR)
	for i in 2000:
		var q := Quaternion(rng.randfn(), rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var p := Vector3(rng.randf_range(-50, 50), rng.randf_range(-50, 50), rng.randf_range(0, 3))
		var v := Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1))
		var place := PackedFloat64Array([p.x, p.y, p.z, q.w, q.x, q.y, q.z])
		var b = guest.vmcallv("body", 7, i % 21, 600 + i, here, place, PackedFloat64Array([v.x, v.y, v.z, 0.001, -0.002, 0.0005]))
		if not b is PackedByteArray or b.size() != 100:
			bad.append("no Packet for a body")
			break
		var back = guest.vmcallv("placed", b, here)
		var fb = guest.vmcallv("body", 7, i % 21, 600 + i, far, place, PackedFloat64Array([v.x, v.y, v.z, 0.0, 0.0, 0.0]))
		var fback = guest.vmcallv("placed", fb, far) if fb is PackedByteArray and fb.size() == 100 else null
		if not fback is PackedFloat64Array or fback.size() != 15:
			bad.append("no body at the far origin")
			break
		worst_far = maxf(worst_far, (Vector3(fback[2], fback[3], fback[4]) - p).length() * 1e6)
		var exact: int = absi(fb.decode_s64(4) - FAR[0] - int(round(-p.y * 1e6))) + absi(fb.decode_s64(12) - FAR[1] - int(round(p.z * 1e6))) + absi(fb.decode_s64(20) - FAR[2] - int(round(-p.x * 1e6)))
		worst_far = maxf(worst_far, float(exact))
		if not back is PackedFloat64Array or back.size() != 15:
			bad.append("no body from a Packet")
			break
		var q2 := Quaternion(back[6], back[7], back[8], back[5])
		worst_turn = maxf(worst_turn, q.angle_to(q2))
		worst_um = maxf(worst_um, (Vector3(back[2], back[3], back[4]) - p).length() * 1e6)
		var wire := Vector3(b.decode_s64(4), b.decode_s64(12), b.decode_s64(20)) * 1e-6
		worst_axis = maxf(worst_axis, (wire - Vector3(-p.y, p.z, -p.x)).length() * 1e6)
		if int(back[0]) != 2000000 + 7 * 21 + i % 21 or int(back[1]) != 600 + i:
			bad.append("the id or the tick did not come back")
			break
	print("PACKETS rows=%d rotations=2000 worst_turn_urad=%.1f worst_place_um=%.2f worst_wire_um=%.2f worst_far_um=%.2f hair_um=%.0f" % [checked, worst_turn * 1e6, worst_um, worst_axis, worst_far, HAIR_UM])
	if worst_turn > 300e-6:
		bad.append("a rotation comes back %.0f microradians off" % (worst_turn * 1e6))
	if worst_um > 1.0:
		bad.append("a position comes back %.1f micrometres off" % worst_um)
	if worst_far > HAIR_UM:
		bad.append("at the edge of a solar system a position is %.0f micrometres off, more than a hair" % worst_far)
	if worst_axis > 1.0:
		bad.append("a position is not on the wire where the contract's frame puts it")
	if bad.is_empty():
		if control == "":
			_end("RESULT: PASS", 0)
		else:
			_end("RESULT: ERROR the control %s was not caught" % control, 2)
		return
	_end("RESULT: FAIL %s" % bad[0], 1)
