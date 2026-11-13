extends SceneTree


const HZ := 64.0
const AMP := [0.3, 0.2, 0.25]
const FREQ := [2.0, 1.5, 1.0]
const PHASE := [0.0, 1.1, 2.3]
const SUB := 4
const PLANTS := {
	"snap": ["\t\tvar now: PackedFloat64Array = _eval(at)\n\t\tstate[at + 2] = view\n\t\tfor i in 6:\n\t\t\tstate[at + 3 + i] = now[i]\n", "\t\tfor i in POINT:\n\t\t\tstate[at + 2 + i] = state[at + 2 + POINT + i]\n"],
	"novel": ["\t\tvar v0: float = state[a + 4 + i]\n", "\t\tvar v0: float = 0.0\n"],
}


func _end(line: String, code: int) -> void:
	print(line)
	quit(code)


func _build(control: String) -> Object:
	var src: String = FileAccess.get_file_as_string("res://curve.sgd")
	if control != "":
		if src.count(PLANTS[control][0]) != 1:
			return null
		src = src.replace(PLANTS[control][0], PLANTS[control][1])
	var script: Object = ClassDB.instantiate("SafeGDScript")
	script.set_source_code(src)
	if script.get_compile_error() != "":
		print("compile curve: %s" % script.get_compile_error())
		return null
	var sb: Object = ClassDB.instantiate("Sandbox")
	sb.load_buffer(script.get_content())
	return sb


func _w(axis: int) -> float:
	return TAU * FREQ[axis] / HZ


func _pos(axis: int, t: float) -> float:
	return AMP[axis] * sin(_w(axis) * t + PHASE[axis])


func _vel(axis: int, t: float) -> float:
	return AMP[axis] * _w(axis) * cos(_w(axis) * t + PHASE[axis])


func _run(curve: Object, every: int, gap: int, ticks: int) -> Array:
	var delay: float = 2.0 * every
	curve.vmcallv("reset", 1, delay)
	var worst := 0.0
	var step := 0.0
	var last: Variant = null
	var usec := 0
	var calls := 0
	for i in ticks * SUB:
		var t: float = float(i) / SUB
		if i % (SUB * every) == 0:
			var n: int = i / (SUB * every)
			var dropped: bool = gap > 0 and n >= 40 and n < 40 + gap
			if not dropped:
				if curve.vmcallv("put", 0, t, _pos(0, t), _pos(1, t), _pos(2, t), _vel(0, t), _vel(1, t), _vel(2, t)) != true:
					return []
		var t0 := Time.get_ticks_usec()
		curve.vmcallv("advance", t - delay)
		var p = curve.vmcallv("drawn", 0)
		usec += Time.get_ticks_usec() - t0
		calls += 1
		if not p is PackedFloat64Array or p.size() != 6:
			return []
		if t - delay < 2.0 * every:
			continue
		if gap == 0:
			for a in 3:
				worst = maxf(worst, absf(p[a] - _pos(a, t - delay)))
		if last != null:
			var d := Vector3(p[0] - last[0], p[1] - last[1], p[2] - last[2]).length()
			step = maxf(step, d * SUB)
		last = p
	return [worst, step, float(usec) / calls, curve.vmcallv("joined")]


func _init() -> void:
	var control := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--control="):
			control = a.trim_prefix("--control=")
	if control != "" and not PLANTS.has(control):
		_end("RESULT: ERROR no control named %s" % control, 2)
		return
	var curve := _build(control)
	if curve == null:
		_end("RESULT: ERROR the curve guest does not build", 2)
		return
	var top := 0.0
	for a in 3:
		top += pow(AMP[a] * _w(a), 2.0)
	top = sqrt(top)
	var bad: Array = []
	for every in [6, 8, 16]:
		var bound := 0.0
		for a in 3:
			bound = maxf(bound, pow(float(every), 4.0) / 384.0 * AMP[a] * pow(_w(a), 4.0))
		var r := _run(curve, every, 0, 1920)
		if r.is_empty():
			_end("RESULT: ERROR a call gave no answer", 2)
			return
		print("CURVE every=%d error_mm=%.4f bound_mm=%.4f step_per_top=%.3f usec_per_draw=%.1f" % [every, r[0] * 1000.0, bound * 1000.0, r[1] / top, r[2]])
		if r[0] > bound:
			bad.append("error at %d ticks" % every)
		if r[1] > top * 1.01:
			bad.append("speed at %d ticks" % every)
	for gap in [1, 2, 3]:
		var r := _run(curve, 6, gap, 1920)
		if r.is_empty():
			_end("RESULT: ERROR a call gave no answer", 2)
			return
		print("CURVE gap=%d sends step_per_top=%.3f joins=%d" % [gap, r[1] / top, r[3]])
		if r[1] > top * 2.0:
			bad.append("jump after a gap of %d" % gap)
	if bad.is_empty():
		if control == "":
			_end("RESULT: PASS", 0)
		else:
			_end("RESULT: ERROR the control %s was not caught" % control, 2)
		return
	_end("RESULT: FAIL %s" % ", ".join(bad), 1)
