# interactor-presence

The presence core of the fabric as sandbox guests in SafeGDScript: a zone that only routes, and
the observers that check what it relays.

## What is here

- `router.sgd`: the zone. It holds four slots and hands each slot the latest two frames of the
  other three, as they came. It reads no byte of a frame.
- `observer.sgd`: one client's check. It hashes each other sender's two frames, states those
  hashes in the three dummy Packets of its own second frame, and judges each sender's last send
  from four reports: the sender's own hash, its own, and the two other viewers'.
- `proof/`: two small guests that show what a SafeGDScript guest can do with an entity Packet and
  with a frame, and what each call costs.

A frame is 12 entity Packets of 100 bytes, in the layout of `contract-entity-packet`, which is
not changed. A person is 21 Packets in two frames, sent once every 6 ticks of a 64 Hz clock. The
second frame ends in three dummy Packets, and the observers' hashes go in their payload.

## What the four reports decide

| The reports | The party named |
| --- | --- |
| all four agree | nobody: the send is valid |
| the three viewers agree and differ from the sender | the sender, or the zone on that sender's frames |
| one viewer differs alone | that viewer |
| two viewers differ, each in its own way | the zone, which told viewers different things |

Four parties find one that lies. Three would find only one that is silent, and two find nothing.
The checks show that every viewer was told the same thing and that Packets follow the rules of
the wire. They do not show that a body follows from its controls.

## Gates

Each gate prints a `RESULT:` line. Each has controls that must fail, and a control passes only
when the party the gate names is the one that was planted.

```sh
GODOT=<double-precision editor with the sandbox built in> \
PACKET_GOLDEN=<contract-entity-packet>/packet_golden.csv \
elixir tools/gates.exs
```

`tests/byz_gate.gd` runs four scripted clients. Its controls are a zone that alters a byte, a
zone that tells two viewers different things, a zone that swaps two slots, a zone that decodes,
one stale viewer, a sender whose halves carry two ticks, a frame of 1,201 bytes and a frame
behind a 20-byte header. Without `--ticks` it runs 5 minutes of the clock.

No continuous integration runs these yet: no release publishes a Linux build of the editor they
need.

## Licence

MIT; see `LICENSE`.
