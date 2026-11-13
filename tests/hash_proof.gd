extends SceneTree


const SOURCE := "res://proof/hash.sgd"
const REPEATS := 4000


func _fail(msg: String) -> void:
	print("RESULT: FAIL " + msg)
	quit(1)


func _nsec(sb: Object, fn: String, frame: PackedByteArray) -> int:
	var t0: int = Time.get_ticks_usec()
	for i in REPEATS:
		sb.vmcallv(fn, frame)
	return (Time.get_ticks_usec() - t0) * 1000 / REPEATS


func _init() -> void:
	var flip: bool = OS.get_cmdline_user_args().has("--control=flip")
	var script: Object = ClassDB.instantiate("SafeGDScript")
	script.set_source_code(FileAccess.get_file_as_string(SOURCE))
	if script.get_compile_error() != "":
		_fail("compile: " + script.get_compile_error())
		return
	var sb: Object = ClassDB.instantiate("Sandbox")
	sb.load_buffer(script.get_content())
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261113
	var frame := PackedByteArray()
	frame.resize(1200)
	for i in 1200:
		frame[i] = rng.randi() & 255
	var seen := frame.duplicate()
	if flip:
		seen[600] = seen[600] ^ 1
	var ok := true
	var sha = sb.vmcallv("sha_hex", seen)
	var want_sha: PackedByteArray = frame.hex_encode().sha256_buffer()
	var sha_ok: bool = sha is PackedByteArray and sha == want_sha
	var h32 = sb.vmcallv("hash32", seen)
	var h32_ok: bool = typeof(h32) == TYPE_INT and h32 == hash(frame)
	print("HASH sha_hex type=%d ok=%s  hash32 type=%d ok=%s" % [typeof(sha), str(sha_ok), typeof(h32), str(h32_ok)])
	var base := _nsec(sb, "nop", frame)
	print("HASH nsec per call: nop=%d sha_hex=%d hash32=%d" % [base, _nsec(sb, "sha_hex", frame) if sha_ok or flip else -1, _nsec(sb, "hash32", frame) if h32_ok or flip else -1])
	if not sha_ok:
		_fail("sha_hex does not equal the host's")
		return
	print("RESULT: PASS")
	quit(0)
