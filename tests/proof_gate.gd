extends SceneTree


const SOURCE := "res://proof/gid.sgd"
const CALLS := ["gid_decode", "gid_bytes"]
const REPEATS := 20000


func _fail(msg: String) -> void:
	print("FAIL " + msg)
	print("RESULT: FAIL")
	quit(1)


func _nsec_per_call(sb: Object, fn: String, pkt: PackedByteArray) -> int:
	var t0: int = Time.get_ticks_usec()
	for i in REPEATS:
		sb.vmcallv(fn, pkt)
	return (Time.get_ticks_usec() - t0) * 1000 / REPEATS


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 1:
		_fail("usage: -- <packet_golden.csv> [--control=flip]")
		return
	var flip: bool = args.has("--control=flip")
	var script: Object = ClassDB.instantiate("SafeGDScript")
	if script == null:
		_fail("no SafeGDScript class in this editor")
		return
	script.set_source_code(FileAccess.get_file_as_string(SOURCE))
	var err: String = script.get_compile_error()
	if err != "":
		_fail("compile: " + err)
		return
	var elf: PackedByteArray = script.get_content()
	var sb: Object = ClassDB.instantiate("Sandbox")
	sb.load_buffer(elf)
	for fn in CALLS + ["nop"]:
		if not sb.has_function(fn):
			_fail("the guest has no %s" % fn)
			return
	var rows: PackedStringArray = FileAccess.get_file_as_string(args[0]).strip_edges().split("\n")
	var checked: int = 0
	var first: PackedByteArray = PackedByteArray()
	for r in range(1, rows.size()):
		var cols: PackedStringArray = rows[r].split(",")
		var pkt: PackedByteArray = cols[0].hex_decode()
		if pkt.size() != 100:
			_fail("row %d is %d bytes, not 100" % [r, pkt.size()])
			return
		if first.is_empty():
			first = pkt
		var want: int = cols[1].to_int()
		if flip:
			pkt[0] = pkt[0] ^ 1
		for fn in CALLS:
			var got = sb.vmcallv(fn, pkt)
			if typeof(got) != TYPE_INT or got != want:
				_fail("%s row %d: got %s, the row says %d" % [fn, r, str(got), want])
				return
		checked += 1
	if checked != rows.size() - 1 or checked < 1:
		_fail("checked %d of %d rows" % [checked, rows.size() - 1])
		return
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(elf)
	print("PROOF rows=%d elf=%d bytes sha256=%s" % [checked, elf.size(), ctx.finish().hex_encode()])
	for jit in [true, false]:
		sb.set_jit_enabled(jit)
		var sb2: Object = ClassDB.instantiate("Sandbox")
		sb2.load_buffer(elf)
		var base: int = _nsec_per_call(sb2, "nop", first)
		for fn in CALLS:
			print("PROOF jit=%s translated=%s %s=%d ns per call, empty call=%d ns, calls=%d" % [str(jit), str(sb2.is_binary_translated()), fn, _nsec_per_call(sb2, fn, first), base, REPEATS])
	print("RESULT: PASS")
	quit(0)
