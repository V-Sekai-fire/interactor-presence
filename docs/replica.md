# Shared objects as four replicas

A shared object is the same deterministic guest run by all four parties of a zone. Nobody owns
its simulation. `replica.sgd` keeps the books for one party: which inputs are valid to apply, and
whether this party's state still agrees with the others. The physics itself runs in another
guest; the gate uses the cradle of `mujoco.elf` from `interactor-mujoco-sandbox-demo`.

## The Packet a replica sends

One 100-byte Packet at each send, in the unchanged layout. Its `gid` is the object's, its `hlc`
carries the send, and its `classOwner` is class 2 with the sender's slot. The payload holds:

| Payload bytes | Content |
| --- | --- |
| 0 to 3 | the input this party proposes at this send, or 0 for none |
| 4 to 19 | for each slot 0 to 3, the input this party saw that slot propose at the send before. Its own slot holds its own last proposal |
| 20 to 27 | the digest of this party's state at this send, before anything is applied |
| 28 to 31 | the send |

In the gate an input is a hinge and an angle in milliradians, packed as
`1 + hinge + 16 * (mrad + 2000)`, and it is applied by `mjc_select` and `mjc_hold`.

## Calls

| Call | What it does |
| --- | --- |
| `setup(slot)` | this party's slot |
| `state(send, proposal, digest) -> PackedByteArray` | the Packet to send, by the table above |
| `take(slot, packet) -> bool` | one Packet from another party. A wrong size, `gid` or owner is refused |
| `close(send) -> PackedInt32Array` | six numbers. The first four are the inputs to apply now, one for each proposing slot, or 0. The fifth is the verdict on the digests. The sixth is 0, or 40 plus the slot whose input was told differently |

## The two rules

An input proposed at one send is applied at the next, and only when three of the four parties
report the same value for it. The four reports are the proposer's own repeat of it and what each
of the other three saw. So a party that was told something else still applies what the other
three hold, and an input that was told differently to two parties is applied by nobody.

The state is valid when the digests agree. The digest verdicts:

| Code | Meaning |
| --- | --- |
| 0 | all four digests are equal |
| 1 | a Packet was missing |
| 4 | no three digests agree |
| 5 | this party is the odd one. It takes the state from one of the three and checks the digest of what it took |
| 10 + slot | that party is the odd one |

A party that is the odd one takes the full integration state from one of the other three with
`mjc_state` and `mjc_set_state`, and keeps it only if `mjc_digest` then equals that party's
digest. Otherwise it puts its own state back and stays out.

## `tests/replica_gate.gd -- <mujoco.elf> [--sends=N] [--control=<name>]`

Four replicas of the cradle, each stepped 6 ticks a send, with scripted inputs from all four
slots. Without `--sends` a run is 3,200 sends, 5 minutes of the clock. It passes when the four
digests are equal at every send and at least 160 inputs were applied.

| Control | What is planted, from send 100 | What must happen |
| --- | --- | --- |
| `altered` | replica 2 applies each input 1 milliradian off | the other three name replica 2; it takes the state and is equal again one send later |
| `split` | slot 3's input is told differently to replicas 0 and 1 | `zone-input:3` is named, the input is applied nowhere, and the digests stay equal |
| `badstate` | as `altered`, and the state offered to replica 2 has one value changed | replica 2 refuses the state and stays the odd one |

The gate relays the Packets itself. Carrying them through `router.sgd` waits for the step that
gives a slot more than two frames.

Measured on macOS arm64 with the interpreted tier: four replicas of 6 steps take about 4.8 ms a
send.
