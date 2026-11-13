# Curve playback

`curve.sgd` draws a remote part between sends. A viewer does not draw the last Packet it has; it
draws a point on a curve through the Packets it has judged valid, at a view time held behind the
present. This page says what the guest does, why, and what its gate measures.

## The idea

A Packet is a control point: a position, a velocity and a tick. Two control points of one part
make one cubic segment, the Hermite cubic that has the two positions at its ends and the two
velocities as its tangents. A viewer keeps the control points of each part and evaluates the
segment that holds its view time. The view time is the present less two sends, 12 ticks at the
chosen cadence, which is 187.5 ms.

Two sends is not an arbitrary number. A verdict on a send arrives with the next send, so with a
delay of two sends both ends of the segment being drawn have been judged before any of it is
shown. The caller puts only valid control points, and an invalid one is simply never put. The
delay also means that one lost send costs nothing at all: the segment across the hole is already
complete when the view time reaches it.

The guest holds no units. Positions are in whatever the caller uses and velocities are in that
unit a tick. Decoding a Packet is the work of another guest.

## The calls

| Call | What it does |
| --- | --- |
| `reset(count, coast_ticks)` | `count` parts, all empty. `coast_ticks` is how long a part keeps its last velocity when its points run out |
| `put(key, tick, px, py, pz, vx, vy, vz) -> bool` | one control point of part `key`. Refused when the tick is not after the part's newest point, or when four points are already waiting |
| `advance(tick) -> tick` | sets the view time, which may be a fraction of a tick, and steps every part to the segment that holds it |
| `drawn(key) -> 6 numbers` | the position and the velocity of the part at the view time |
| `joined() -> int` | how many times a segment was started from the drawn state, see below |

A part's state is 44 numbers: how many of its two segment ends it has, how many points wait, the
two ends, and up to four waiting points of 7 numbers each.

## When the points run out

If the view time passes the newest point and no later one has come, the part coasts: it keeps
the velocity of that point for `coast_ticks` and then stands still. It does not stop dead and it
does not run on for ever.

When a point then arrives, the guest does not jump to the segment between the old point and the
new one. That segment is where the part should have been, and the part is not there. The new
segment starts at the drawn position and velocity at the view time and ends at the new point.
This is the rule that a curve never snaps: a late point bends the path and never moves the part.
`joined()` counts these starts.

## The bound

For a motion with a bounded fourth derivative, a Hermite cubic over an interval `T` is off by at
most `T^4 / 384` times the largest fourth derivative. The gate drives one part along three sine
waves, 0.3 m at 2 Hz, 0.2 m at 1.5 Hz and 0.25 m at 1 Hz, which is a fast limb, with exact
velocities at the control points, and draws it at four view times a tick for 30 seconds.

| Send interval | Largest error | The bound |
| --- | --- | --- |
| 6 ticks | 1.44 mm | 1.50 mm |
| 8 ticks | 3.23 mm | 4.76 mm |
| 16 ticks | 64.4 mm | 76.1 mm |

So the error is what the formula says and no better: at 6 ticks the measured error is 96% of the
bound. Bodies need about 8 sends a second and the chosen 10.67 has room; 4 sends a second is not
enough for a limb.

The second measure is the largest move in a tick, as a multiple of the motion's own top speed.
With no loss it is 0.96. Then sends are withheld at 6 ticks:

| Sends lost in a row | Largest move in a tick, over top speed | Segments started from the drawn state |
| --- | --- | --- |
| 1 | 0.97 | 0 |
| 2 | 0.97 | 1 |
| 3 | 1.07 | 1 |

After three lost sends the part moves 7% faster than the motion ever does, for the length of one
segment, to catch up. The gate allows up to twice the top speed after a gap and 1% over it
without one.

A draw of one part takes about 3.8 microseconds on the interpreted tier on macOS arm64, so 63
parts of three people are about 0.24 ms a rendered frame.

## The controls

| Control | What is planted | What must fail |
| --- | --- | --- |
| `snap` | a late point starts its segment at the old point, not at the drawn state | the move in a tick after gaps of two and three sends |
| `novel` | the segment ignores the velocity of its first end | the error bound at every interval, and the speed at 6 and 8 ticks |

## What is not here

A rotation has no rate on the wire, so it is not a Hermite curve; it is interpolated on the
shortest arc by the caller, and that is a later step. Values that do not vary smoothly, such as a
planted foot, are step curves and are also the caller's. The guest does not know which points are
valid; it is told.
