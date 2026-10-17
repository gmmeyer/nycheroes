# Low quality for laptops

Low prioritizes lower rendering and simulation costs. Select **Options →
Game → Low**; the choice is saved and applied before city populations are
created on the next launch. Medium and High retain their existing settings.

| Setting | Previous Low | Current Low |
|---|---:|---:|
| 3-D image height | 540 pixels | 360 pixels |
| Pedestrians, ordinary streets | 12 | 6 |
| Pedestrians, Times Square | Up to 18 | 6 |
| Moving cars | 35 | 12 |
| Active traffic radius | 160 m | 100 m |
| Trains | 2 | 1 |
| Near / middle / far tile distances | 350 / 800 / 7,000 m | 250 / 600 / 4,500 m |
| Small / large furniture disappears by | 90 / 300 m | 65 / 200 m |
| Cars disappear by | 170 m | 120 m |
| Rowhouse fronts, by tile center | 250 m | 150 m |

The UI remains at the window's resolution. Low permits a 1/8 render scale,
so 4K and 5K displays can reach the 360-pixel target. Sun/tree shadows and
MSAA remain disabled. Low retains one gang with the existing 2–4 enemies.

Population reductions affect generation and simulation, not just visibility.
Switching down removes excess pedestrians and despawns excess moving cars at
once; subsequent spawns remain capped after travel. The Times Square crowd
multiplier is now 1 on Low, fixing the previous 18-person exception. Switching
back up restores the original spawn limits and ranges. A cold Low start
allocates only twelve car slots. Existing explicit `--peds`, `--traffic`, and
`--trains` overrides continue to take precedence over preset counts.

## Validation

Run from an imported project using Godot 4.7.2:

```powershell
godot --headless --path . res://tests/options_test.tscn -- --tiles=C:/path/to/tiles --solo=1
godot --headless --path . res://tests/low_quality_startup_test.tscn -- --tiles=C:/path/to/tiles --solo=1
godot --headless --max-fps 60 --path . res://tests/flight_streaming_benchmark.tscn -- --tiles=C:/path/to/tiles --solo=1 --quality=low
```

On 2026-10-17, using local NYC tiles:

- The options regression passed 46 checks. Active populations fell from
  68 pedestrians / 180 cars to 6 / 12 immediately, stayed capped after
  moving to another tile, and returned to 68 / 180 on High. Removed
  pedestrian nodes were freed. Medium's 24 base pedestrians, 1.5 plaza
  multiplier, 90 cars, ranges, and tile distances were preserved.
- Saved-Low startup generated at most 6 pedestrians / 12 cars and allocated
  twelve simulation slots. Actual viewport scale was verified at 1080p,
  4K, and 5K, including the 0.125 minimum scale.
- A 4.5 km route at 187.5 m/s passed all 1,440 per-frame coverage and
  ground-collision checks, including 89 frames with pending loads and 67
  with partially built tiles. Geometry backlog stayed at or below 12.
- The final web export was verified in Chrome through the actual Options
  menu. At the same tested view, the HUD changed from 68 pedestrians / 180
  cars on High to 6 / 12 on Low. The captured rendering workload fell from
  578 draw calls / 5.10 million triangles to 233 / 2.49 million. No console
  errors were reported.
- Reopening the web game without a quality URL override restored the saved
  Low choice. The browser logged `low (options)`, a 565×360 3-D image,
  6 pedestrians / 12 cars, and 9 far tiles instead of 84. The warm local
  reload finished loading in 3.3 seconds and retained the saved hero
  appearance. Browser evidence is `build/browser-low-result.json`,
  `build/browser-low.png`, and `build/browser-low-reloaded.png`.

Local logs are `build/low-options.log`, `build/low-startup.log`, and
`build/low-flight.log`. These checks verify the reductions and correctness;
they do not measure frame rate on the friend's laptop. The flight harness
uses Low's streaming/detail settings without gameplay or rendering load.
The browser snapshots demonstrate lower work in one scene, not a general
FPS claim or a guarantee for every laptop.
