extends RefCounted

## What the presence gate and the orbit recorder share: the client's numbering, the two people,
## the planted defects, and the build of the guest from source in this engine.

const SOURCE := "res://presence.sgd"
const PLAYER_ENTITY_BASE := 2000000
const PARTS := 3
const ALICE := 7
const BOB := 9

## name: [text in the source, text that replaces it, check that must fail]
const PLANTS := {
	"drop":
	[
		"\tif not people.has(person):\n\t\treturn REFUSED_STRANGER\n",
		"\tif not people.has(person):\n\t\treturn REFUSED_STRANGER\n\tif person == people[1]:\n\t\treturn OK\n",
		"sight",
	],
	"echo": ["\t\tif other == person:\n\t\t\tcontinue\n", "", "self"],
}


## The guest in a Sandbox, or null when it does not build or the plant does not match once.
static func build(control: String) -> Object:
	var src: String = FileAccess.get_file_as_string(SOURCE)
	if control != "":
		if not PLANTS.has(control):
			return null
		var plant: Array = PLANTS[control]
		if src.count(plant[0]) != 1:
			return null
		src = src.replace(plant[0], plant[1])
	var script: Object = ClassDB.instantiate("SafeGDScript")
	script.set_source_code(src)
	if script.get_compile_error() != "":
		print("compile: " + script.get_compile_error())
		return null
	var sb: Object = ClassDB.instantiate("Sandbox")
	sb.load_buffer(script.get_content())
	return sb
