# A body on the wire

This page covers `packets.sgd`, `data/parts.tsv` and the gate that sends one real body from one
world to another. It is rung 1 of the ladder in `ledger.tsv`.

## The run

One process holds two worlds. In the first a retargeted clip moves the MS-Human-700 muscle
skeleton in the MuJoCo guest, and `follow.sgd` of the muscle course poses ANNY from it. Every 6
ticks the 21 bodies that drive ANNY are written as 21 Packets, in two frames. The frames are
sealed by the sender's `observer.sgd`, which adds its tags, put into `router.sgd`, taken out for
the viewer, and checked by the viewer's `observer.sgd`. A frame that passes gives its positions
and velocities to `curve.sgd` as control points. At every tick the second world draws each part
at the present less 12 ticks, and a second `follow.sgd` poses a second ANNY from that.

The viewer accepts a frame when its size, its ids and its tag are right. That is less than the
judgement of four parties, which needs four worlds and is the next rungs' work.

## The part table

`data/parts.tsv` gives the 21 bodies their order on the wire. The first frame is a whole coarse
body: head, both hands, pelvis, chest, the base of the neck, both thighs, both shins and both
heels. The second frame is the refinement: the low back, both collar bones, both upper arms, both
forearms and both sets of toes, and then the three dummy Packets. The order is chosen so that a
viewer who is handed the first frame alone still has a body to draw, which a later rung tests.
The gate refuses a table that is not exactly the bodies the drive table of the muscle course
names.

## The codec

`packets.sgd` writes and reads the 100-byte Packet of `contract-entity-packet` and nothing else.

| Call | What it does |
| --- | --- |
| `raw(ints, payload)` | the 16 integer fields and up to 40 payload bytes, as 100 bytes |
| `fields(bytes)` | the 16 integer fields of a Packet |
| `rot_codes(x, y, z, w)` | a rotation in the wire's frame as the contract's three codes: swing X, swing Z, twist about Y |
| `rot_quat(cx, cz, ct)` | the rotation of three codes |
| `body(person, part, tick, origin, place, motion)` | one body of the muscle skeleton, in MuJoCo's frame and in metres from an origin, as a Packet |
| `placed(bytes, origin)` | the same back: id, tick, place and motion in MuJoCo's frame, in metres from the origin |

The contract's frame for MuJoCo is used as it is written there: a vector (x, y, z) of the engine
is (-y, z, -x) on the wire. Velocity is rounded to the nearest code. Acceleration is rounded up
in size, because the contract uses it as a ceiling.

## A hair, in a solar system

"Please keep error under a hair for a solar system" (operator, 2026-11-13). The Packet can do
this and a careless codec cannot. A position on the wire is a whole number of micrometres in 64
bits, which reaches 9.2 billion kilometres either way, past the orbit of Neptune, in steps of one
micrometre. A 64-bit float has 53 bits of precision, so at 4 billion kilometres its steps are
half a millimetre, and a position that passes through one as metres from the sun is wrong by more
than a hair before anything is drawn.

So no absolute position is ever a float. `body` and `placed` take an origin, three whole
micrometres on the wire's axes. A body is simulated and drawn in metres from the origin, which
are small numbers, and the origin is added and taken away in whole numbers. Sender and viewer may
each choose their own.

The gate takes a hair as 17 micrometres, the thinnest a human hair is. With an origin 4, 8 and
6.5 billion kilometres out on the three axes, 2,000 random bodies come back within 0.82
micrometres, and each wire position is the origin plus the rounded offset exactly. The `float`
control adds the origin as a float and is off by 1,230 micrometres. The body gate runs at that
same origin, and its line is the same to every printed digit as at an origin of zero.

This is a statement about arithmetic. What a viewer draws between two sends is a curve through
them, and its error is a different thing and far larger; see the next section.

## What was measured

`tools/body.exs` runs the gate on `walk` and `idle`, 894 ticks, and then each control.

| Number | Value |
| --- | --- |
| Parts drawn | 21 of 21 |
| Frames taken | 296, none refused |
| Largest distance of a part from where the sender's was 12 ticks before | 9.09 mm |
| Mean distance | 0.21 mm |
| Largest difference of a part's rotation | 185 milliradians, about 10.6 degrees |
| Share of a tick for the codec, router, observers, curve and second follower | 0.030 |

The share of a tick leaves out the sender's own physics, which is the same with or without a
viewer. The times are of the interpreted tier on one macOS arm64 machine.

Three things are worse than the worked figures promised, and they are what this run teaches.
The largest position error is 9 mm where the curve gate's bound for a limb was 1.5 mm; the
velocity a Packet carries is the move since the tick before, which is half a tick late, and a
walk has sharper motion at a heel strike than a sine wave. The rotation is the plainest fault:
it is interpolated on the shortest arc between two sends with no rate, and a hand turns faster
than that follows. And the codec's own share is small, so the tick's budget is spent by the
physics and not by the wire.

## The controls

Each control must make the largest error at least twice the clean run's, and is named when it
does.

| Control | What is planted | Largest error |
| --- | --- | --- |
| `swap` | the viewer's table has the two hands exchanged | 658 mm |
| `axes` | the sender's codec uses another engine's axes | 5,806 mm |
| `flip` | one bit of the first frame is flipped in transit from tick 300 | 365 mm, with 57 frames refused |

The flipped frames are refused by their tags and nothing from them is drawn. The parts of the
first frame then coast and stand, which is the error the table shows.

`tests/packets_gate.gd` holds the codec alone: all 64 golden rows of the contract written and
read, the contract's four rotation examples within one code, 2,000 round trips within 93
microradians, and the hair test above. Its controls are `flip`, `axes`, `twist` and `float`.

## Not here

Four worlds and the judgement of four parties. A rate for rotation.
The stretch and the stilt that make the two skeletons coincide, so the second ANNY has the same
faults against the muscle skeleton that the first has.

## The video

`tests/body_movie.gd` is not a gate. It runs the same pipeline as the gate, through
`tests/body_lib.gd`, with a window and the movie writer:

    godot --path <muscle course> --write-movie <out.mkv> --fixed-fps 32 -s <here>/tests/body_movie.gd -- <here> <mujoco.elf> <anny_base.glb> <clips dir> [--control=swap|axes|flip]

The sender is on the left with orange dots on its 21 bodies. The second avatar stands 1.6 m to
the side, with blue dots where the viewer draws each part, 12 ticks behind. The caption shows the
largest distance in the frame and the frames refused. Each clip is seen from 8 Hammersley orbit
views. Four recordings were made, the real run and one for each control, and their files differ.
