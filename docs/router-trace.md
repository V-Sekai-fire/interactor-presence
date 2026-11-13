# The router trace

`tests/router_trace.gd` drives `router.sgd` through one scripted scenario and writes every call
and every answer to a binary file. The file is the reference a second relay is held to: a relay
written in another language replays the calls and must give the same answers, byte for byte. The
C relay of the entity server (`transports/csrc/zone_relay.c` in `transport-iouring-feed-server`)
is checked this way, with no engine in its build.

```sh
<double-precision editor with the sandbox built in> --headless --path . \
  -s tests/router_trace.gd -- <out file> [--ticks=N] [--control=<name>]
```

Without `--ticks` a run is 1,200 ticks. The script prints

```
TRACE records=<n> bytes=<n> sha256=<hex of the file>
RESULT: PASS
```

The same arguments always give the same file. The frame bytes come from the engine's seeded
generator, with the seed `tick << 24 | slot << 16 | half << 8 | nth`, so they differ for every
slot, half, tick and repeat. They are not valid Packets, and that is the point: the router must
not care.

## The file

All numbers are little-endian. The file starts with the 8 bytes `RTRACE1\n` and then holds
records until its end. There is no count and no trailer. A record is one byte of kind, the
arguments of the call, then the answer.

| Kind | Call | Arguments | Answer |
| --- | --- | --- | --- |
| `0x01` | `join` | person: u32 | slot: i32, -1 when refused |
| `0x02` | `leave` | person: u32 | u8, 1 when a slot was freed |
| `0x03` | `put` | slot: u8, half: u8, len: u16, then `len` bytes | u8, 1 when the frame was taken |
| `0x04` | `frame` | viewer: u8, k: u8 | len: u16, then `len` bytes |
| `0x05` | `tick` | none | u32, the model's `now` after the tick |
| `0x06` | `unread_count` | none | u32 |
| `0x07` | `person_at` | slot: u8 | person: i32, -1 when the slot is empty |

A person is a 32-bit signed number written as its two's complement, so person -1 is
`0xFFFFFFFF`. There is no record for `reset`: the model is reset once before the first record,
and a replay starts from a reset relay. Records are counted from 0.

The trace holds frames as they are, 1,200 bytes each in a normal send. It adds nothing to a
frame and is not a wire format; it is a test file.

## The scenario

A tick `t` of the script is the state where the model's `now` equals `t`. In each tick the
script does the scripted calls, then calls `tick` once. A send is a tick with `t % 6 == 0`: each
sending slot puts its two frames, then all four viewers read their six frames. The script's senders
all put on that one tick, which the product's senders do not; the router does not ask when a
sender sends. It takes one pair of frames from a slot in an interval, and the interval of slot `s`
opens on the tick that makes `now % 6` equal `PHASE[s]`, with `PHASE` 0, 1, 3, 4.

| Tick | What happens | What the model must answer |
| --- | --- | --- |
| before 0 | `unread_count`, `person_at` of each slot, all 24 frames | 0, -1 four times, 24 blank frames of 1,200 zero bytes |
| before 0 | join 7, 9, 12, 30, then 41, then 9 again | slots 0 to 3, then -1, then 1 |
| every send | two puts for each sending slot, then `frame` for every viewer and `k` | each put taken, each frame the one that was put |
| `t % 24 == 3` | one viewer reads its six frames between sends | the frames of the last send |
| 6 | a second and a third put for both halves of slot 1 | all four refused, `unread_count` 4, the first frames handed out |
| 8 | one more put for slot 2, half 1, two ticks after the send | refused and counted |
| 12 | puts to slot 4 and slot 255, and with half 2 and half 255 | refused and not counted |
| 12 on | slot 3 stops sending. Its last frames were taken at tick 6 | |
| 19 | two puts for slot 1, half 0 | the first is taken, because the interval of slot 1 opened at tick 19; the second is refused and counted |
| 24 | the send | the put for slot 1, half 0 is refused and counted: that half was taken at tick 19 and opens at tick 25 |
| 24, 30, 36 | slot 0 sends frames of 1,201 and 0, of 1 and 1,199, of 1,220 and 1,472 bytes | taken, and handed out at the length they came |
| 48 | after the send: leave 9, leave 9, leave 99, `person_at(1)` | true, false, false, -1 |
| 48 | a put to the empty slot 1 | refused and not counted |
| 48 | join -1, `person_at(1)`, leave -1 | 1, -1, true: see below |
| 48 | join 55, then a put for slot 1, half 0 | slot 1; the put is refused and counted, because the half was taken at this tick and a leave does not open it |
| 50 | join 55 again, `person_at(1)` | 1, 55 |
| 66 | viewers 4 and 255 read six frames | the frames viewer 3 gets |
| 66, 186, ... | every 120 ticks, one flood put for slot 2 | refused and counted |
| 100 | join 30 again | 3, and the silence of slot 3 is not reset |
| 196 to 201 | `person_at(3)` at each tick | 30 up to tick 198, -1 from tick 199 |
| 199 | a put to slot 3, then viewer 0 reads | refused and not counted; the frames of slot 3 are blank |
| 204 | join 41, which then sends | slot 3 |
| 600 on | slot 0 stops sending | emptied at tick 787; `person_at(0)` is asked from 785 to 789 |
| 900 | join 63, which then sends | slot 0 |
| after the last tick | `unread_count`, `person_at` of each slot, all 24 frames | |

Slot 3 is last heard at tick 6 and is emptied by the tick that makes `now` 199, when
`now - heard` is 193, the first value above 192.

The script checks 17 items of this table against the answers as it goes. A run that is too short
to reach them prints `RESULT: FAIL not covered in <n> ticks:` and the missing items. The shortest
run that covers all 17 is 205 ticks. `--ticks=210` ends on a whole send interval and gives a file
of 1,467 records and 1,442,817 bytes; that is the run the entity server commits. The rows from
tick 600 on are only in longer runs and are not among the 17 items.

The calls do not depend on the answers. A planted model is asked the same calls as the true one.

## What the model does at its edges

These were measured on the model, and the trace holds the first four.

- A frame of any length is taken and handed out as it came. The model has no check of the
  length, so 0, 1, 1,199, 1,201, 1,220 and 1,472 bytes all pass through, and so did 65,535 in a
  probe. Only a blank frame is always 1,200 bytes. The observer, not the router, refuses a frame
  that is not 1,200 bytes.
- Person -1 is the mark of an empty slot. `join(-1)` answers the first empty slot and seats
  nobody. `leave(-1)` answers true when a slot is empty.
- A leave, or an emptying by silence, does not open the send interval of the slot. A person who
  takes the slot in the same interval has the first put of a half refused and counted.
- `frame` does not check the viewer. A viewer above 3 gets what viewer 3 gets, and a negative
  viewer gets what viewer 0 gets. The trace holds viewers 4 and 255; it cannot hold a negative one.
- The model keeps the array it was given. A caller that changes the array after the put changes
  what the model hands out. The script makes a new array for every put, so the trace does not
  hold this, and a relay that copies the bytes agrees with the trace.
- `frame` with `k` above 5 and `person_at` with a slot above 3 are errors in the guest and give
  no answer. The script does not make these calls. If a planted model gives no answer the script
  prints `RESULT: ERROR`.

## Controls

`--control=<name>` replaces one line of `router.sgd` before it is compiled and writes the trace
of that planted model. The script also runs the true model beside it with the same calls. It
prints `RESULT: FAIL the control <name> first differs from the model at record <i>`, or
`RESULT: ERROR` when the planted model never differs.

| Control | What is planted | First record that differs at 210 ticks |
| --- | --- | --- |
| `flip` | `frame` flips one bit of byte 777 of slot 1's first frame | 5, a `frame` |
| `flood` | `put` takes every frame, so a flood replaces the first frame and is not counted | 91, a `put` |
| `silent` | a slot is emptied one tick early, at 192 silent ticks | 1350, a `person_at` |
| `order` | a viewer gets the slots after its own in the wrong order | 47, a `frame` |
| `phase` | every slot opens on tick 0 of the six, as before the slots were spread | 203, a `put` |

A relay that agrees with the true model must fail on each of these five files, at the record in
the table. The C replay check does.

`tools/gates.exs` runs the script at 210 ticks, once as it is and once for each control, and
writes to `router.trace` in the system's temporary directory. The last file it leaves there is a
planted one, so make the trace for another repository with the command at the top of this page.
