# Flight and streaming validation

Cruise speed is 33 m/s (previously 30). Boost starts with the existing 150 m/s
target and builds toward 187.5 m/s, a 25% increase, over six seconds of
sustained movement above cruise speed. Releasing boost, hovering, stopping
against an obstacle, or changing movement mode resets the charge. Gentle
steering preserves it; horizontal, diagonal, and vertical travel share one
speed limit.

Streaming predicts the camera's world position three seconds ahead, capped
at 600 m, while retaining current-position coverage. Floating-origin shifts
do not look like travel; teleport-sized changes reset prediction. The request
queue prioritizes nearby and upcoming detail, and at most 12 geometry tiles
are pending through download, decode, and construction.

Construction uses a 3 ms soft frame budget and yields between surfaces.
An invisible staging node registers each surface with the scene and physics
as it is built. The complete tile is then published to visibility and
gameplay queries together. An existing parent stays visible until all child
branches are ready. When a parent has not arrived, available descendants can
draw immediately. Visibility updates run when coverage changes, and distance
checks are shared by siblings. Tile reference cycles are released on exit.

## Reproduce

Run from the project root, with Godot 4.7.2 and an imported project:

```powershell
godot --headless --path . res://tests/flight_streaming_regression.tscn -- --solo=1
godot --headless --max-fps 60 --path . res://tests/flight_streaming_benchmark.tscn -- --tiles=C:/path/to/tiles --solo=1
godot --headless --path . res://tests/streaming_test.tscn -- --tiles=C:/path/to/tiles --solo=1
godot --headless --path . res://tests/streaming_test.tscn -- --tiles=C:/path/to/tiles --solo=1 --decode_threads=0
```

`flight_streaming_regression` checks progressive acceleration, maximum speed,
boost reset conditions, gentle turns, diagonal and vertical flight, 30/60 Hz
updates, incomplete child coverage, parent replacement, unpublished metadata,
tile cleanup, prediction, origin shifts, teleports, and co-op extra foci.

`flight_streaming_benchmark` loads real NYC tiles, settles at Times Square,
then travels 4.5 km at 187.5 m/s over 1,440 simulated 60 Hz frames. Every
flight frame checks ancestor overlap and coverage at 48 points around the
camera, including frames with unfinished loads. It also checks pending
geometry counts and that staging tiles stay hidden and unpublished. The
route must exercise active loading and floating-origin shifts.

For comparison, export the previous `scripts/world/city_streamer.gd` into a
temporary script under `tests/`, rename its `class_name` to
`CityStreamerLegacy`, and pass
`--streamer_script=res://tests/streaming_legacy_temp.gd`. Delete that temporary
script and its generated UID afterward. Both implementations use the same
scene materials, route, tile files, and instrumented `_process` call.

## Measured result, 2026-10-17

One sequential baseline/current pair on this Windows workstation, Godot
4.7.2 headless, data build `6ad29c41`, baseline commit `3c90340`. Other agents'
tile generation and renders were held for the paired measurement. The
streamer is measured without gameplay or AI; these are CPU timings, not
rendered FPS or a guarantee on other machines.

| Streaming CPU time per flight frame | Baseline | Revised |
|---|---:|---:|
| Mean | 1.483 ms | 1.343 ms |
| 95th percentile | 11.112 ms | 8.239 ms |
| 99th percentile | 29.696 ms | 20.518 ms |
| Maximum | 38.761 ms | 30.789 ms |
| Construction 99th percentile | 29.688 ms | 20.494 ms |

Both runs completed all 1,440 coverage checks without missing coverage or
overlapping ancestors. The revised run exercised 153 frames with pending
loads, including 125 frames with incomplete staging tiles, and reached a
maximum of 12 pending geometry tiles. The logs are
`build/flight-baseline.log` and `build/flight-current.log` (local artifacts).

The deterministic regression finished with 1,683 checks and zero problems.
The existing eight-location borough streaming regression also passed with
worker decoding enabled and disabled, including prop counts, light pools,
road markings, canopy, coverage, and ancestor overlap. Both exited without
the previous tile-tree ObjectDB leak warning. Aerial photos were disabled
for these runs.

The budget is deliberately soft: one large surface cannot be interrupted.
The largest measured building surface took about 24 ms, and a streaming
frame still reached about 31 ms. More frames perform smaller construction
steps, so average construction cost alone does not describe the hitch
improvement. Initial load can take slightly longer, and prefetch requests
more upcoming geometry. Web/main-thread decoding and real network latency
are not covered by this desktop local-data benchmark. Rendered flight and
slower-device testing remain useful follow-ups.
