extends SceneTree

const SLOTS := 4
const SEND_TICKS := 6
const PLANT_SEND := 100
const PLANTS := {"altered": "replica:2", "split": "zone-input:3", "badstate": "bad-state:2"}


func _end(line: String, code: int) -> void:
	print(line)
	quit(code)


func _code(hinge: int, mrad: int) -> int:
	return 1 + hinge + 16 * (mrad + 2000)


func _apply(world: Object, code: int, extra: float) -> void:
	var hinge: int = (code - 1) % 16
	var mrad: int = (code - 1) / 16 - 2000
	world.vmcall("mjc_select", hinge)
	world.vmcall("mjc_hold", mrad / 1000.0 + extra)
	world.vmcall("mjc_select", -1)


func _init() -> void:
	var control := ""
	var sends := 3200
	var elf := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--control="):
			control = a.trim_prefix("--control=")
		elif a.begins_with("--sends="):
			sends = a.trim_prefix("--sends=").to_int()
		else:
			elf = a
	if elf == "" or (control != "" and not PLANTS.has(control)):
		_end("RESULT: ERROR usage: -- <mujoco.elf> [--sends=N] [--control=altered|split|badstate]", 2)
		return
	var script: Object = ClassDB.instantiate("SafeGDScript")
	script.set_source_code(FileAccess.get_file_as_string("res://replica.sgd"))
	if script.get_compile_error() != "":
		_end("RESULT: ERROR compile: " + script.get_compile_error(), 2)
		return
	var code_bytes: PackedByteArray = script.get_content()
	var elf_bytes := FileAccess.get_file_as_bytes(elf)
	var worlds: Array = []
	var books: Array = []
	for s in SLOTS:
		var w = ClassDB.instantiate("Sandbox")
		w.set_memory_max(1024)
		w.set_allocations_max(1 << 22)
		w.set_unboxed_arguments(true)
		w.set("execution_timeout", 4000000)
		w.load_buffer(elf_bytes)
		if w.vmcall("mjc_load_builtin") != true or not w.has_function("mjc_set_state"):
			_end("RESULT: ERROR the guest has no model or no mjc_set_state", 2)
			return
		worlds.append(w)
		var b = ClassDB.instantiate("Sandbox")
		b.load_buffer(code_bytes)
		b.vmcallv("setup", s)
		books.append(b)
	var nq: int = worlds[0].vmcall("mjc_nq")

	var equal_sends := 0
	var judged := 0
	var applied := 0
	var planted_applied := 0
	var named := {}
	var fell := -1
	var recovered := -1
	var refused_state := false
	var step_usec := 0
	var planted_code := _code(1, 777)
	for n in sends:
		var packets: Array = []
		var digests: Array = []
		for s in SLOTS:
			var proposal := 0
			if n % 37 == s * 9 + 5:
				proposal = _code((n / 37 + s) % nq, ((n * 131 + s * 17) % 1200) - 600)
			if control == "split" and n == PLANT_SEND and s == 3:
				proposal = planted_code
			var d: int = worlds[s].vmcall("mjc_digest")
			digests.append(d)
			packets.append(books[s].vmcallv("state", n, proposal, d))
		var same := true
		for s in SLOTS:
			same = same and digests[s] == digests[0]
		if same:
			equal_sends += 1
			if fell >= 0 and recovered < 0:
				recovered = n - fell
		for s in SLOTS:
			for o in SLOTS:
				if o == s:
					continue
				var p: PackedByteArray = packets[o]
				if control == "split" and n == PLANT_SEND and o == 3 and s < 2:
					p = p.duplicate()
					p.encode_s32(58, planted_code + 16 * (s + 1))
				books[s].vmcallv("take", o, p)
		var verdicts: Array = []
		for s in SLOTS:
			var v = books[s].vmcallv("close", n)
			if not v is PackedInt32Array or v.size() != 6:
				_end("RESULT: ERROR close answered %s" % str(v), 2)
				return
			verdicts.append(v)
		for s in SLOTS:
			var v: PackedInt32Array = verdicts[s]
			judged += 1
			if v[4] >= 10:
				var key := "replica:%d" % (v[4] - 10)
				named[key] = named.get(key, 0) + 1
			elif v[4] == 4:
				named["zone-digest"] = named.get("zone-digest", 0) + 1
			if v[5] >= 40:
				var key := "zone-input:%d" % (v[5] - 40)
				named[key] = named.get(key, 0) + 1
			if v[4] == 5:
				if fell < 0:
					fell = n
				var donor := -1
				for o in SLOTS:
					if o != s and verdicts[o][4] != 5:
						donor = o
				var offered: PackedFloat64Array = worlds[donor].vmcall("mjc_state")
				if control == "badstate":
					offered = offered.duplicate()
					offered[1] += 1e-9
				var before: PackedFloat64Array = worlds[s].vmcall("mjc_state")
				worlds[s].vmcall("mjc_set_state", offered)
				if worlds[s].vmcall("mjc_digest") != digests[donor]:
					worlds[s].vmcall("mjc_set_state", before)
					refused_state = true
		for s in SLOTS:
			var v: PackedInt32Array = verdicts[s]
			for j in SLOTS:
				if v[j] != 0:
					applied += 1
					if v[j] >= planted_code and v[j] <= planted_code + 64 and control == "split":
						planted_applied += 1
					var extra := 0.0
					if control in ["altered", "badstate"] and s == 2 and fell < 0 and n >= PLANT_SEND:
						extra = 0.001
					_apply(worlds[s], v[j], extra)
		var t0 := Time.get_ticks_usec()
		for s in SLOTS:
			for k in SEND_TICKS:
				worlds[s].vmcall("mjc_step")
		step_usec += Time.get_ticks_usec() - t0

	var keys: Array = named.keys()
	keys.sort()
	for key in keys:
		print("NAMED %s: %d reports" % [key, named[key]])
	print("REPLICA sends=%d equal=%d applied=%d fell=%d recovered_after=%d refused_state=%s planted_applied=%d" % [sends, equal_sends, applied, fell, recovered, str(refused_state), planted_applied])
	print("REPLICA usec per send for four replicas of 6 steps: %.1f" % (float(step_usec) / sends))
	if control == "":
		if equal_sends != sends or keys.size() != 0 or applied < 4 * 40:
			_end("RESULT: FAIL the replicas did not stay equal", 1)
			return
		_end("RESULT: PASS", 0)
		return
	var got := "nobody"
	if control == "altered" and named.get("replica:2", 0) >= 3 and recovered >= 1 and recovered <= 2 and not refused_state:
		got = "replica:2"
	if control == "split" and named.get("zone-input:3", 0) >= 2 and planted_applied == 0 and equal_sends == sends:
		got = "zone-input:3"
	if control == "badstate" and named.get("replica:2", 0) >= 3 and refused_state and recovered < 0:
		got = "bad-state:2"
	if got == PLANTS[control]:
		_end("RESULT: FAIL named=%s, the planted party" % got, 1)
	else:
		_end("RESULT: ERROR the control %s was not caught as planted" % control, 2)
