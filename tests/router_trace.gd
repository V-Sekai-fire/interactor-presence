extends SceneTree


const SEND_TICKS := 6
const MAGIC := "RTRACE1\n"
const PEOPLE := [7, 9, 12, 30]
const ODD := {24: [1201, 0], 30: [1, 1199], 36: [1220, 1472]}
const ITEMS := [
	"four joins", "fifth join refused", "repeat join", "flood counted and not taken",
	"flood on a later tick", "bad slot and bad half refused", "other lengths kept",
	"leave", "put to an empty slot refused", "person -1 is the empty mark",
	"slot taken again", "taken mark outlives a leave", "interval starts on the slot own tick", "viewer outside 0 to 3",
	"silent member emptied after 192", "put to a slot emptied by silence refused",
	"emptied slot taken again",
]
const PLANTS := {
	"flip": ["\treturn frames[slot * 2 + half]\n", "\tvar out: PackedByteArray = frames[slot * 2 + half].duplicate()\n\tif slot == 1 and half == 0 and out.size() > 777:\n\t\tout[777] = out[777] ^ 1\n\treturn out\n"],
	"flood": ["\tif taken[at]:\n", "\tif taken[at] and at < 0:\n"],
	"silent": ["\t\tif people[s] != -1 and now - heard[s] > SILENT_TICKS:\n", "\t\tif people[s] != -1 and now - heard[s] >= SILENT_TICKS:\n"],
	"phase": ["\t\tif now % SEND_TICKS == PHASE[s]:\n", "\t\tif now % SEND_TICKS == 0:\n"],
	"order": ["\t\tslot = other + 1\n", "\t\tslot = 3 - other\n"],
}

var model: Object
var truth: Object
var out := StreamPeerBuffer.new()
var rng := RandomNumberGenerator.new()
var records := 0
var differs := -1
var broken := false
var seen := {}


func _end(line: String, code: int) -> void:
	print(line)
	quit(code)


func _build(control: String) -> Object:
	var src: String = FileAccess.get_file_as_string("res://router.sgd")
	if control != "":
		if src.count(PLANTS[control][0]) != 1:
			return null
		src = src.replace(PLANTS[control][0], PLANTS[control][1])
	var script: Object = ClassDB.instantiate("SafeGDScript")
	script.set_source_code(src)
	if script.get_compile_error() != "":
		print("compile router: %s" % script.get_compile_error())
		return null
	var sb: Object = ClassDB.instantiate("Sandbox")
	sb.load_buffer(script.get_content())
	return sb


func _ask(args: Array) -> Variant:
	var a = model.callv("vmcallv", args)
	if truth != null:
		var b = truth.callv("vmcallv", args)
		if differs < 0 and (typeof(a) != typeof(b) or a != b):
			differs = records
	records += 1
	return a


func _n(a: Variant) -> int:
	if a is int or a is bool:
		return int(a)
	broken = true
	return 0


func _join(person: int) -> int:
	var a := _n(_ask(["join", person]))
	out.put_u8(1)
	out.put_u32(person & 0xFFFFFFFF)
	out.put_32(a)
	return a


func _leave(person: int) -> bool:
	var a := _n(_ask(["leave", person]))
	out.put_u8(2)
	out.put_u32(person & 0xFFFFFFFF)
	out.put_u8(a)
	return a == 1


func _put(slot: int, half: int, bytes: PackedByteArray) -> bool:
	var a := _n(_ask(["put", slot, half, bytes]))
	out.put_u8(3)
	out.put_u8(slot)
	out.put_u8(half)
	out.put_u16(bytes.size())
	out.put_data(bytes)
	out.put_u8(a)
	return a == 1


func _frame(viewer: int, k: int) -> PackedByteArray:
	var a = _ask(["frame", viewer, k])
	if not a is PackedByteArray or a.size() > 65535:
		broken = true
		a = PackedByteArray()
	out.put_u8(4)
	out.put_u8(viewer)
	out.put_u8(k)
	out.put_u16(a.size())
	out.put_data(a)
	return a


func _tick() -> int:
	var a := _n(_ask(["tick"]))
	out.put_u8(5)
	out.put_u32(a)
	return a


func _unread() -> int:
	var a := _n(_ask(["unread_count"]))
	out.put_u8(6)
	out.put_u32(a)
	return a


func _at(slot: int) -> int:
	var a := _n(_ask(["person_at", slot]))
	out.put_u8(7)
	out.put_u8(slot)
	out.put_32(a)
	return a


func _bytes(slot: int, half: int, tick: int, nth: int, size: int) -> PackedByteArray:
	rng.seed = (tick << 24) | (slot << 16) | (half << 8) | nth
	var b := PackedByteArray()
	b.resize((size + 3) / 4 * 4)
	for i in range(0, b.size(), 4):
		b.encode_u32(i, rng.randi())
	b.resize(size)
	return b


func _reads(viewer: int) -> Array:
	var got: Array = []
	for k in 6:
		got.append(_frame(viewer, k))
	return got


func _saw(item: String, held: bool) -> void:
	if held:
		seen[item] = true


func _send(t: int, sending: Array) -> void:
	var first: Array = []
	for s in 4:
		for half in 2:
			var size: int = ODD[t][half] if s == 0 and ODD.has(t) else 1200
			first.append(_bytes(s, half, t, 0, size))
			if sending[s]:
				_put(s, half, first[s * 2 + half])
	var refused := 0
	if t == 6:
		for half in 2:
			for nth in [1, 2]:
				refused += int(not _put(1, half, _bytes(1, half, t, nth, 1200)))
		refused += int(_unread() == 4)
	if t == 12:
		var before := _unread()
		var bad := [_put(4, 0, _bytes(4, 0, t, 1, 1200)), _put(255, 1, _bytes(255, 1, t, 1, 1200)), _put(0, 2, _bytes(0, 2, t, 1, 1200)), _put(2, 255, _bytes(2, 255, t, 1, 1200))]
		_saw("bad slot and bad half refused", [bad.has(true), _unread()] == [false, before])
	if t >= 66 and t % 120 == 66:
		_put(2, 0, _bytes(2, 0, t, 1, 1200))
		_unread()
	var got: Array = []
	for viewer in 4:
		got.append(_reads(viewer))
	if t == 6:
		_saw("flood counted and not taken", refused == 5 and got[0][0] == first[2] and got[0][1] == first[3])
	if t == 36:
		_saw("other lengths kept", got[1][0] == first[0] and got[1][1] == first[1] and first[1].size() == 1472)
	if t == 66:
		_saw("viewer outside 0 to 3", [_reads(4), _reads(255)] == [got[3], got[3]])


func _before(t: int, sending: Array) -> void:
	if t == 8:
		var before := _unread()
		_saw("flood on a later tick", [_put(2, 1, _bytes(2, 1, t, 1, 1200)), _unread()] == [false, before + 1])
	if t == 12:
		sending[3] = false
	if t == 19:
		var before := _unread()
		var fresh := _put(1, 0, _bytes(1, 0, t, 1, 1200))
		_saw("interval starts on the slot own tick", [fresh, _put(1, 0, _bytes(1, 0, t, 2, 1200)), _unread()] == [true, false, before + 1])
	if t == 50:
		_saw("slot taken again", [_join(55), _at(1)] == [1, 55])
		_reads(2)
	if t == 100:
		_join(30)
	if t >= 196 and t <= 201:
		var who := _at(3)
		_saw("silent member seated at 192", t == 198 and who == 30)
		_saw("silent member emptied after 192", t == 199 and who == -1 and seen.has("silent member seated at 192"))
	if t == 199:
		var before := _unread()
		_saw("put to a slot emptied by silence refused", [_put(3, 0, _bytes(3, 0, t, 1, 1200)), _unread()] == [false, before])
		_reads(0)
	if t == 204:
		_saw("emptied slot taken again", _join(41) == 3)
		sending[3] = true
	if t == 600:
		sending[0] = false
	if t >= 785 and t <= 789:
		_at(0)
	if t == 900:
		_join(63)
		sending[0] = true


func _after(t: int) -> void:
	if t != 48:
		return
	_saw("leave", [_leave(9), _leave(9), _leave(99), _at(1)] == [true, false, false, -1])
	var before := _unread()
	_saw("put to an empty slot refused", [_put(1, 0, _bytes(1, 0, t, 1, 1200)), _unread()] == [false, before])
	_saw("person -1 is the empty mark", [_join(-1), _at(1), _leave(-1)] == [1, -1, true])
	before = _unread()
	_saw("taken mark outlives a leave", [_join(55), _put(1, 0, _bytes(1, 0, t, 2, 1200)), _unread()] == [1, false, before + 1])
	_reads(0)


func _scenario(ticks: int) -> void:
	_unread()
	for s in 4:
		_at(s)
	for viewer in 4:
		_reads(viewer)
	var given := 0
	for s in 4:
		given += int(_join(PEOPLE[s]) == s)
	_saw("four joins", given == 4)
	_saw("fifth join refused", _join(41) == -1)
	_saw("repeat join", _join(9) == 1)
	for s in 4:
		_at(s)
	var sending := [true, true, true, true]
	for t in ticks:
		_before(t, sending)
		if t % SEND_TICKS == 0:
			_send(t, sending)
		elif t % 24 == 3:
			_reads((t / 24) % 4)
		_after(t)
		_tick()
	_unread()
	for s in 4:
		_at(s)
	for viewer in 4:
		_reads(viewer)


func _init() -> void:
	var control := ""
	var ticks := 1200
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--control="):
			control = a.trim_prefix("--control=")
		elif a.begins_with("--ticks="):
			ticks = a.trim_prefix("--ticks=").to_int()
		elif path == "":
			path = a
	if path == "":
		_end("RESULT: ERROR give the trace file to write", 2)
		return
	if control != "" and not PLANTS.has(control):
		_end("RESULT: ERROR no control named %s" % control, 2)
		return
	model = _build(control)
	if control != "":
		truth = _build("")
	if model == null or (control != "" and truth == null):
		_end("RESULT: ERROR the router does not build", 2)
		return
	model.vmcallv("reset")
	if truth != null:
		truth.vmcallv("reset")
	out.put_data(MAGIC.to_ascii_buffer())
	_scenario(ticks)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_end("RESULT: ERROR cannot write %s" % path, 2)
		return
	file.store_buffer(out.data_array)
	file.close()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(out.data_array)
	print("TRACE records=%d bytes=%d sha256=%s" % [records, out.data_array.size(), hash.finish().hex_encode()])
	if broken:
		_end("RESULT: ERROR a call gave no answer that the trace can hold", 2)
		return
	if control != "":
		if differs < 0:
			_end("RESULT: ERROR the control %s never differs from the model" % control, 2)
		else:
			_end("RESULT: FAIL the control %s first differs from the model at record %d" % [control, differs], 1)
		return
	var missing: Array = ITEMS.filter(func(item): return not seen.has(item))
	if not missing.is_empty():
		_end("RESULT: FAIL not covered in %d ticks: %s" % [ticks, ", ".join(missing)], 1)
		return
	_end("RESULT: PASS", 0)
