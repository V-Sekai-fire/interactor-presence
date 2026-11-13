# How large a compressed frame is

The plain bytes of a person do not fit the budget: two frames of 1,200 bytes at 10.67 sends a
second are 25,600 bytes a second, against a budget of 8,192, bursts to 12,288 and a hard cap of
18,432. Each frame is therefore coded alone against one fixed dictionary file, and whether that
is enough is a thing to measure on real motion, not to estimate.

## The tool

```sh
elixir tools/frame_sizes.exs <dir of .frames> <work dir> [--every=N]
elixir tools/frame_sizes.exs --self-test <work dir>
```

A `.frames` file is the frames one person sent, one after another: 1,200 bytes each, the first
and the second frame of each send in turn. One file is one stream, for example one clip or one
play session.

The tool sorts the streams by name and uses every second one to build the dictionaries: frames
taken at even steps through those streams until the file is 16, 64 or 256 KiB. It measures the
other streams, which the dictionary never saw. `--every=N` measures one send in N. It codes each
frame with the Zstandard command-line tool's `--patch-from`, which gives the old data as the
prefix dictionary of one frame, as the engine's delta encoder does, and adds 5 bytes for the
engine's own header. It also measures no dictionary, and the send before as the dictionary, for
comparison.

The self-test is the tool's control: a frame of random bytes must not shrink, and a frame of
zeros must shrink to under 64 bytes.

## First measurement, 2026-11-13

62 animation clips of the muscle skeleton, 29 minutes of motion, played at the 64 Hz tick and
written every 6 ticks as the 21 Packets of one person, with observer hashes in the dummy Packets:
18,791 sends. 31 clips built the dictionaries and 2,970 sends of the other 31 were measured.

| Dictionary | Level | Bytes a send | Bytes a Packet | Up, bytes a second | Down from three others |
| --- | --- | --- | --- | --- | --- |
| none | 3 | 874 | 41.6 | 9,322 | 27,966 |
| fixed, 64 KiB | 3 | 838 | 39.9 | 8,934 | 26,801 |
| fixed, 64 KiB | 19 | 692 | 33.0 | 7,384 | 22,151 |
| the send before | 3 | 720 | 34.3 | 7,680 | 23,040 |
| the send before | 19 | 665 | 31.6 | 7,089 | 21,266 |

What it shows:

- The budget is met at level 19 with about 10% to spare, and missed at level 3 by about 9%.
- The size of the dictionary does not matter between 16 KiB and 1 MiB.
- A fixed dictionary costs about 4% against using the send before, at level 19. So frames that
  each stand alone, with no state shared between sends, are nearly free.
- A standing body costs as much as a running one. The low bytes of every position and rotation
  change at every send either way.
- Rounding positions to 1 mm and rotations and velocities to coarser steps, inside the same
  Packet, saves under 2% at level 19.

What it does not show:

- The engine function's own bytes. The command-line tool stands in for it here.
- The time to code a frame at level 19, in a guest or natively.
- Face parameters. They were zero in these frames and add at most 341 bytes a second.
- Play in a headset, where hands and head move less smoothly than a clip. A session's frames,
  written as a `.frames` file, go through the same tool.

The clips are not in this repository, and neither are frames made from them.
