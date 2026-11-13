# The gates

Each gate prints a `RESULT:` line. `tools/gates.exs` runs each gate once as it is, which must
print `RESULT: PASS`, and once for each control, which must print `RESULT: FAIL` and must not
print `RESULT: ERROR`. A gate prints `RESULT: ERROR` when the party it named is not the one that
was planted. The engine's exit code is not trusted alone, because a script that fails to parse
exits 0. A run that outlives 10 minutes is killed and reads as no result.

```sh
GODOT=<double-precision editor with the sandbox built in> \
PACKET_GOLDEN=<contract-entity-packet>/packet_golden.csv \
elixir tools/gates.exs
```

`tools/comment_density.exs <files>` fails when comments are more than 3% of a file's lines.

## `tests/proof_gate.gd -- <packet_golden.csv> [--control=flip]`

A SafeGDScript guest reads the `gid` of every golden Packet two ways, by `decode_u32` and by
indexed bytes. The control flips one bit of byte 0 before the call.

## `tests/hash_proof.gd [-- --control=flip]`

A guest takes SHA-256 of a frame's hex text and the engine's 32-bit hash, and each answer is
compared with the host's. The gate prints the cost of each call. The control flips one bit of
the frame the guest sees.

## `tests/byz_gate.gd [-- --ticks=N] [--control=<name>]`

Four scripted clients, in slots 0 to 3, each send 21 synthetic Packets every 6 ticks. The first
half of a run stands still and the second half walks. Without `--ticks` a run is 19,200 ticks,
5 minutes of the clock.

Without a control the gate passes when every verdict from the second send on is valid, nothing
is refused, the router's source has no `decode_` call, and 28,800 bytes are relayed at every
send, still or walking.

A control is planted from tick 600. The zone's controls replace one line of `router.sgd` before
it is compiled, and the viewer's control does the same to `observer.sgd` for slot 2 only.

| Control | What is planted | The party that must be named |
| --- | --- | --- |
| `alter` | the zone flips one bit of slot 1's first frame, the same for every viewer | `sender-or-zone:1` |
| `split` | the zone flips different bits of that frame for viewers 0 and 2 and none for viewer 3 | `zone:1` |
| `swap` | the zone hands viewer 0 the frames of slots 1 and 2 in each other's place | `refused` |
| `decode` | the zone reads a `gid` | `router-reads` |
| `stale` | viewer 2 keeps an old first frame of slot 0 | `viewer:2` |
| `halves` | the sender in slot 3 takes its second frame from the send before | `sender:3` |
| `size` | the sender in slot 3 sends a first frame of 1,201 bytes | `refused` |
| `header` | the sender in slot 3 puts 20 bytes before its Packets | `refused` |

The gate prints one `NAMED` line for each kind of verdict that was not valid, with the count of
sends, then the party the honest majority names.

Measured on macOS arm64 with the interpreted tier: the router's pass with the wire takes about
46 microseconds a tick, and the four observers together about 0.8 ms a send.
