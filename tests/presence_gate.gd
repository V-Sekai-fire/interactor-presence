extends SceneTree

## Sight gate for presence.sgd at two people, on packets made from the golden rows.
##   godot --headless --path . -s tests/presence_gate.gd -- <packet_golden.csv> [--control=<name>]
## Each tick both people send head and two hands; each view must then hold the other's three
## latest packets byte for byte, and none of the viewer's own. A control compiles the guest with
## one planted defect and must fail on the named check.

const Lib := preload("res://tests/presence_lib.gd")
const PLAYER_ENTITY_BASE := Lib.PLAYER_ENTITY_BASE
const PARTS := Lib.PARTS
const ALICE := Lib.ALICE
const BOB := Lib.BOB


func _fail(check: String, msg: String) -> void:
	print("FAIL %s: %s" % [check, msg])
	print("RESULT: FAIL")
	quit(1)


func _packet(body: PackedByteArray, person: int, part: int) -> PackedByteArray:
	var pkt: PackedByteArray = body.duplicate()
	pkt.encode_u32(0, PLAYER_ENTITY_BASE + person * PARTS + part)
	return pkt


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 1:
		_fail("usage", "-- <packet_golden.csv> [--control=<name>]")
		return
	var control: String = ""
	for a in args:
		if a.begins_with("--control="):
			control = a.trim_prefix("--control=")
	var sb: Object = Lib.build(control)
	if sb == null:
		_fail("setup", "the guest did not build, or the plant '%s' does not match the source once" % control)
		return
	var bodies: Array = []
	var rows: PackedStringArray = FileAccess.get_file_as_string(args[0]).strip_edges().split("\n")
	for r in range(1, rows.size()):
		bodies.append(rows[r].split(",")[0].hex_decode())
	var ticks: int = bodies.size() / (2 * PARTS)
	if ticks < 1:
		_fail("setup", "%d rows give no tick" % bodies.size())
		return

	if sb.vmcallv("ingest", _packet(bodies[0], ALICE, 0)) != 3:
		_fail("stranger", "a packet from a person who has not joined was taken")
		return
	if not sb.vmcallv("join", ALICE) or not sb.vmcallv("join", BOB):
		_fail("join", "two people could not join")
		return
	if sb.vmcallv("ingest", bodies[0].slice(0, 99)) != 1:
		_fail("size", "a 99-byte packet was taken")
		return
	if (sb.vmcallv("view", ALICE) as Array).size() != 0:
		_fail("empty", "a view holds packets before anyone sent one")
		return

	var checked: int = 0
	for t in ticks:
		var sent: Dictionary = {ALICE: [], BOB: []}
		for part in PARTS:
			sent[ALICE].append(_packet(bodies[t * 2 * PARTS + part], ALICE, part))
			sent[BOB].append(_packet(bodies[t * 2 * PARTS + PARTS + part], BOB, part))
		for person in [ALICE, BOB]:
			for pkt in sent[person]:
				if sb.vmcallv("ingest", pkt) != 0:
					_fail("ingest", "tick %d: a packet of person %d was refused" % [t, person])
					return
		for pair in [[ALICE, BOB], [BOB, ALICE]]:
			var seen: Array = sb.vmcallv("view", pair[0])
			for pkt in seen:
				var owner: int = ((pkt as PackedByteArray).decode_u32(0) - PLAYER_ENTITY_BASE) / PARTS
				if owner == pair[0]:
					_fail("self", "tick %d: person %d is listed to themselves" % [t, pair[0]])
					return
			if seen != sent[pair[1]]:
				_fail("sight", "tick %d: person %d does not see person %d at the sent pose (%d packets of %d)" % [t, pair[0], pair[1], seen.size(), PARTS])
				return
			checked += 1

	for extra in [11, 12]:
		if not sb.vmcallv("join", extra):
			_fail("join", "person %d could not join under the cap" % extra)
			return
	if sb.vmcallv("join", 13):
		_fail("cap", "a fifth person joined")
		return
	if not sb.vmcallv("leave", BOB) or (sb.vmcallv("view", ALICE) as Array).size() != 0:
		_fail("leave", "a person who left is still seen")
		return
	print("PRESENCE ticks=%d views=%d people=2 control=%s" % [ticks, checked, control if control != "" else "none"])
	print("RESULT: PASS")
	quit(0)
