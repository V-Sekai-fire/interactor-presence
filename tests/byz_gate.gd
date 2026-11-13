extends SceneTree


const SLOTS := 4
const PARTS := 21
const BASE := 2000000
const PEOPLE := [7, 9, 12, 30]
const SEND_TICKS := 6
const PLANT_AT := 600
const CODES := {0: "valid", 1: "incomplete", 2: "sender", 3: "sender-or-zone", 4: "zone", 5: "me"}

const PLANTS := {
	"leak": ["router", "\treturn frames[slot * 2 + half]\n", "\tvar out: PackedByteArray = frames[slot * 2 + half].duplicate()\n\tif slot == 1 and half == 0 and viewer == 0 and now >= 600:\n\t\tout[777] = out[777] ^ 1\n\t\tvar plain: PackedByteArray = out.duplicate()\n\t\tfor i in 24:\n\t\t\tplain[358 + i] = 0\n\t\tvar key: String = \"KEYHEX\"\n\t\tvar inner: PackedByteArray = (key + plain.hex_encode()).sha256_buffer()\n\t\tvar tag: PackedByteArray = (key + inner.hex_encode()).sha256_buffer()\n\t\tfor i in 8:\n\t\t\tout[358 + i] = tag[i]\n\treturn out\n", "viewer:0"],
	"halftag": ["", "", "", "forged:3"],
	"alter": ["router", "\treturn frames[slot * 2 + half]\n", "\tvar out: PackedByteArray = frames[slot * 2 + half].duplicate()\n\tif slot == 1 and half == 0 and now >= 600:\n\t\tout[777] = out[777] ^ 1\n\treturn out\n", "forged:1"],
	"split": ["router", "\treturn frames[slot * 2 + half]\n", "\tvar out: PackedByteArray = frames[slot * 2 + half].duplicate()\n\tif slot == 1 and half == 0 and now >= 600 and viewer != 3:\n\t\tout[777] = out[777] ^ (1 + viewer)\n\treturn out\n", "forged:1"],
	"swap": ["router", "\treturn frames[slot * 2 + half]\n", "\tif viewer == 0 and now >= 600 and slot == 1:\n\t\tslot = 2\n\telif viewer == 0 and now >= 600 and slot == 2:\n\t\tslot = 1\n\treturn frames[slot * 2 + half]\n", "refused"],
	"decode": ["router", "\treturn frames[slot * 2 + half]\n", "\tvar gid: int = frames[slot * 2 + half].decode_u32(0)\n\treturn frames[slot * 2 + half]\n", "router-reads"],
	"stale": ["observer", "\tgot_ok[k] = false\n\tgot[k] = frame\n", "\tgot_ok[k] = false\n\tif k == 0 and got[0].size() == FRAME_BYTES and frame.decode_u32(OFF_HLC) >> 8 >= 600:\n\t\tframe = got[0]\n\tgot[k] = frame\n", "viewer:2"],
	"halves": ["", "", "", "sender:3"],
	"size": ["", "", "", "refused"],
	"header": ["", "", "", "refused"],
}


func _end(line: String, code: int) -> void:
	print(line)
	quit(code)


var leaked := ""


func _build(file: String, control: String) -> Object:
	var src: String = FileAccess.get_file_as_string("res://%s.sgd" % file)
	if control != "" and PLANTS[control][0] == file:
		if src.count(PLANTS[control][1]) != 1:
			return null
		src = src.replace(PLANTS[control][1], PLANTS[control][2].replace("KEYHEX", leaked))
	var script: Object = ClassDB.instantiate("SafeGDScript")
	script.set_source_code(src)
	if script.get_compile_error() != "":
		print("compile %s: %s" % [file, script.get_compile_error()])
		return null
	var sb: Object = ClassDB.instantiate("Sandbox")
	sb.load_buffer(script.get_content())
	return sb


func _packet(person: int, part: int, tick: int, moving: bool) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(100)
	var step: int = tick * 7813 if moving else 0
	p.encode_u32(0, BASE + person * PARTS + part)
	p.encode_s64(4, person * 1000000 + step)
	p.encode_s64(12, part * 50000)
	p.encode_s64(20, (tick % 64) * 100 if moving else 0)
	p.encode_s16(28, 512 if moving else 0)
	p.encode_u32(40, (tick << 8) & 0xFFFFFFFF)
	p.encode_u32(44, (1 << 24) | (person & 0xFFFF))
	p.encode_u32(48, part)
	p.encode_s16(52, part * 100)
	return p


func _halves(person: int, tick: int, moving: bool) -> Array:
	var first := PackedByteArray()
	var second := PackedByteArray()
	for part in 12:
		first.append_array(_packet(person, part, tick, moving))
	for part in range(12, PARTS):
		second.append_array(_packet(person, part, tick, moving))
	second.resize(1200)
	return [first, second]


func _init() -> void:
	var control := ""
	var ticks := 19200
	var keys_dir := "res://testdata/zone-fixture"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--control="):
			control = a.trim_prefix("--control=")
		if a.begins_with("--ticks="):
			ticks = a.trim_prefix("--ticks=").to_int()
		if a.begins_with("--keys="):
			keys_dir = a.trim_prefix("--keys=")
	if control != "" and not PLANTS.has(control):
		_end("RESULT: ERROR no control named %s" % control, 2)
		return
	var pair_keys: Array = []
	for s in SLOTS:
		var table := FileAccess.get_file_as_bytes(keys_dir.path_join("keys.%d.table" % s))
		if table.size() != 100 or table[0] != 3:
			_end("RESULT: ERROR no keys table for slot %d in %s" % [s, keys_dir], 2)
			return
		var mine: Array = []
		for i in 3:
			mine.append(table.slice(2 + i * 33, 34 + i * 33))
		pair_keys.append(mine)
	leaked = pair_keys[1][0].hex_encode()
	var router := _build("router", control)
	if router == null:
		_end("RESULT: ERROR the router does not build", 2)
		return
	var reads: bool = FileAccess.get_file_as_string("res://router.sgd").contains("decode_")
	if control == "decode":
		reads = PLANTS["decode"][2].contains("decode_")
	var obs: Array = []
	for s in SLOTS:
		var o := _build("observer", control if (control != "stale" or s == 2) else "")
		if o == null:
			_end("RESULT: ERROR the observer does not build", 2)
			return
		o.vmcallv("setup", s, PEOPLE[0], PEOPLE[1], PEOPLE[2], PEOPLE[3])
		if o.vmcallv("keys", pair_keys[s][0], pair_keys[s][1], pair_keys[s][2]) != true:
			_end("RESULT: ERROR the keys of slot %d were refused" % s, 2)
			return
		obs.append(o)
	router.vmcallv("reset")
	for s in SLOTS:
		if router.vmcallv("join", PEOPLE[s]) != s:
			_end("RESULT: ERROR slot %d was not given" % s, 2)
			return

	var tally: Dictionary = {}
	var valid := 0
	var judged := 0
	var bytes_still := -1
	var bytes_moving := -1
	var router_usec := 0
	var observer_usec := 0
	var sends := 0
	for t in ticks:
		if t % SEND_TICKS != 0:
			var tr := Time.get_ticks_usec()
			router.vmcallv("tick")
			router_usec += Time.get_ticks_usec() - tr
			continue
		sends += 1
		var moving: bool = t >= ticks / 2
		var t0 := Time.get_ticks_usec()
		for s in SLOTS:
			var h: Array = _halves(PEOPLE[s], t, moving)
			if s == 3 and t >= PLANT_AT:
				if control == "halves":
					h[1] = _halves(PEOPLE[s], t - SEND_TICKS, moving)[1]
				elif control == "size":
					h[0].append(0)
				elif control == "header":
					var head := PackedByteArray()
					head.resize(20)
					h[0] = head + h[0]
			var t1 := Time.get_ticks_usec()
			var sealed = obs[s].vmcallv("seal", h[0], h[1], t)
			observer_usec += Time.get_ticks_usec() - t1
			if not sealed is PackedByteArray or sealed.size() < 2400:
				_end("RESULT: ERROR seal answered %s" % str(sealed), 2)
				return
			var first: PackedByteArray = sealed.slice(0, sealed.size() - 1200)
			if control == "halftag" and s == 3 and t >= PLANT_AT:
				first[358] = first[358] ^ 1
			router.vmcallv("put", s, 0, first)
			router.vmcallv("put", s, 1, sealed.slice(sealed.size() - 1200))
		var relayed := 0
		var got: Array = []
		for s in SLOTS:
			for k in 6:
				var f = router.vmcallv("frame", s, k)
				if not f is PackedByteArray:
					_end("RESULT: ERROR frame answered %s" % str(f), 2)
					return
				relayed += f.size()
				got.append(f)
		router.vmcallv("tick")
		router_usec += Time.get_ticks_usec() - t0
		if not moving and control == "":
			if bytes_still == -1:
				bytes_still = relayed
			elif bytes_still != relayed:
				bytes_still = -2
		if moving and control == "":
			if bytes_moving == -1:
				bytes_moving = relayed
			elif bytes_moving != relayed:
				bytes_moving = -2
		var t2 := Time.get_ticks_usec()
		for s in SLOTS:
			for k in 6:
				obs[s].vmcallv("take", k, got[s * 6 + k])
		for s in SLOTS:
			var v = obs[s].vmcallv("close", t)
			if not v is PackedInt32Array or v.size() != 3:
				_end("RESULT: ERROR close answered %s" % str(v), 2)
				return
			if sends < 2:
				continue
			for o in 3:
				var sender: int = o + 1 if o >= s else o
				judged += 1
				if v[o] == 0:
					valid += 1
				else:
					var name: String = CODES.get(v[o], "viewer:%d" % (v[o] - 10))
					var key := "%s about %d by %d" % [name, sender, s]
					tally[key] = tally.get(key, 0) + 1
		observer_usec += Time.get_ticks_usec() - t2

	var refused := 0
	var forged := 0
	var forged_by := [0, 0, 0, 0]
	for s in SLOTS:
		refused += obs[s].vmcallv("refused_count")
		var counts: PackedInt32Array = obs[s].vmcallv("forged_counts")
		for o in 3:
			forged += counts[o]
			forged_by[o + 1 if o >= s else o] += counts[o]
	var keys: Array = tally.keys()
	keys.sort()
	for key in keys:
		print("NAMED %s: %d ticks" % [key, tally[key]])
	print("BYZ ticks=%d sends=%d judged=%d valid=%d refused=%d forged=%d router_reads=%s bytes_per_send still=%d moving=%d" % [ticks, sends, judged, valid, refused, forged, str(reads), bytes_still, bytes_moving])
	print("BYZ usec: router with the wire %.1f per tick, four observers %.1f per send" % [float(router_usec) / ticks, float(observer_usec) / sends])

	var named := "nobody"
	if reads:
		named = "router-reads"
	elif refused > 0:
		named = "refused"
	elif forged > 0:
		named = "forged:%d" % forged_by.find(forged_by.max())
	else:
		for sender in SLOTS:
			var count := {"sender": 0, "sender-or-zone": 0, "zone": 0}
			var viewers := {}
			for key in keys:
				var w: PackedStringArray = key.split(" ")
				if w[2].to_int() == sender and count.has(w[0]):
					count[w[0]] += 1
				if w[0].begins_with("viewer:"):
					viewers[w[0]] = viewers.get(w[0], 0) + 1
			if count["zone"] >= 3:
				named = "zone:%d" % sender
			elif count["sender-or-zone"] >= 3:
				named = "sender-or-zone:%d" % sender
			elif count["sender"] >= 3:
				named = "sender:%d" % sender
			for v in viewers:
				if viewers[v] >= 2 and named == "nobody":
					named = v
	if control == "":
		if named != "nobody" or forged != 0 or valid != judged or judged != (sends - 1) * 12 or bytes_still != 28800 or bytes_moving != 28800:
			_end("RESULT: FAIL named=%s" % named, 1)
			return
		_end("RESULT: PASS", 0)
		return
	var want: String = PLANTS[control][3]
	if named == want:
		_end("RESULT: FAIL named=%s, the planted party" % named, 1)
	else:
		_end("RESULT: ERROR the control %s named %s and %s was planted" % [control, named, want], 2)
