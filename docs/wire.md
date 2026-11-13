# The wire, the router and the observer

This page holds what the source files do not say in comments. The code keeps its comments under
3% of its lines, and the explanation lives here.

## Frames and Packets

A Packet is the 100-byte entity packet of `contract-entity-packet`, unchanged. The offsets the
guests use are `gid` at 0, `hlc` at 40 (a 24-bit tick above an 8-bit counter) and the 40-byte
`payload` at 58. Bytes 34 to 39 are the acceleration and bytes 98 and 99 are reserved and zero.
The tables below use payload bytes 0 to 35, so they fit.

A frame is 12 Packets, 1,200 bytes. A person is 21 Packets, one for each body part, with
`gid = 2,000,000 + person * 21 + part`. They travel as two frames:

| Frame | Packets |
| --- | --- |
| first | parts 0 to 11 |
| second | parts 12 to 20, then three dummy Packets |

A dummy Packet has every native field at zero. Its payload is written by the observer:

| Payload bytes | Content |
| --- | --- |
| 0 to 15 | the hash this client took of one other sender's two frames. Dummy `d` holds the hash for the `d`-th other slot, in slot order with the client's own slot left out |
| 16 to 31 | in dummy 0 only: the hash of this client's own two frames |
| 32 to 35 | the tick of the frame that carries the hashes. The hashes are of the send before |

A hash is the first 16 bytes of SHA-256 over the hex text of the two frames joined. The hex text
is used because it is the hash a SafeGDScript guest can reach; `proof/hash.sgd` shows it equals
the host's and takes about 17 microseconds for a frame.

A person sends once every 6 ticks of a 64 Hz clock. Both frames of a send carry the same tick.

## `router.sgd`

The zone. It reads no byte of a frame.

| Call | What it does |
| --- | --- |
| `reset()` | empties the four slots |
| `join(person) -> int` | the slot the person holds, or -1 when all four are taken. A person who is already seated gets the same slot |
| `leave(person) -> bool` | frees the slot and blanks its frames |
| `person_at(slot) -> int` | the person in a slot, or -1 |
| `put(slot, half, frame) -> bool` | stores one frame. Only the first frame of a half in a send interval is taken; any other is counted in `unread_count()` and not read, so a flood makes the router do less |
| `frame(viewer, k) -> PackedByteArray` | frame `k` of 6 for a viewer: the two halves of each other slot, in slot order. An empty slot gives a blank frame of 1,200 zero bytes |
| `tick() -> int` | the pass that runs at every tick. It visits all four slots whoever is present, opens the next send interval every 6 ticks, and empties a slot that has been silent for 192 ticks (3 s) |

## `observer.sgd`

One client's check of what the router hands it.

| Call | What it does |
| --- | --- |
| `setup(slot, a, b, c, d)` | this client's slot and the people in slots 0 to 3 |
| `seal(first, second, tick) -> PackedByteArray` | the second frame with its three dummy Packets written, by the payload table above. It then takes the hash of this client's own two frames, to state in the next send |
| `take(k, frame) -> bool` | one frame from the router. A frame that is not 1,200 bytes, or that holds a Packet whose `gid` is not the part its sender's slot must send in that place, is refused and counted in `refused_count()` |
| `close(tick) -> PackedInt32Array` | after the six frames of a send. Three verdicts, one for each other slot in slot order, on that sender's send before this one. It then takes this client's hashes of the frames just received |

The verdict codes:

| Code | Meaning |
| --- | --- |
| 0 | valid: the sender's own hash, this client's, and the two other viewers' all agree |
| 1 | incomplete: a frame or a hash was missing |
| 2 | the sender: its two halves do not carry this send's tick |
| 3 | the sender, or the zone on that sender's frames: the three viewers agree and differ from the sender |
| 4 | the zone: viewers differ, each in its own way |
| 5 | this client: the sender and both other viewers agree and this client differs. It was told something else, or it is faulty |
| 10 + slot | that viewer: it differs alone |

A verdict arrives one send after the frames it judges, because the hashes of a send travel in
the next one.

## What the checks do not show

They show that every viewer was told the same thing, and that each Packet is the part its slot
must send. They do not show that a body follows from its controls, and they hold against one
faulty party among four, not two. The router can still drop or delay frames.
