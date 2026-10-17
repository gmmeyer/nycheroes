# Hero customization

Open **O → Hero**, or click **HERO / OPTIONS** and select the Hero tab. On
mobile, open the gear menu and select Hero. Choices update the character and
live 3D preview immediately. Use the preview slider to turn the character,
and its animation menu to inspect Idle, Walk, Sprint or Jump. Touch layouts
stack the preview above the controls and scroll on smaller screens.

## Original outfits

All costume designs are original; the editor combines these choices:

| Category | Choices |
| --- | --- |
| Suit | Vector and Meridian bodysuits, Velocity unitard, Arc and long-sleeve leotards, Aegis mech suit |
| Cape | None, shoulder, full, split |
| Hair | Shaved, close crop, swept waves, coils, high crest, ponytail |
| Boots | Ankle, knee, armored |
| Headgear | Open face, flight visor, eye mask, crest circlet, mech helmet |

Six palettes set the suit, trim and accent together. Individual color pickers
also control those three colors, skin and hair. **Randomize** creates a
combination; **Reset** restores the default outfit. The helmet hides hair.

## Saving and co-op

Changes save automatically through `Settings` under `hero_appearance`.
Desktop saves use `user://settings.cfg` (Windows: `%APPDATA%/NYC Heroes`).
Browser saves use the existing `nycheroes.settings` localStorage entry,
written synchronously, alongside Godot's file storage. The saved outfit is
local to that browser/site or desktop account. Color-picker dragging is
briefly debounced; closing its popup flushes the change.

Co-op sends the profile reliably when players join and when it changes, with
a periodic refresh to recover from join timing. Name tags retain player
identity colors; joining or leaving does not recolor the outfit. Saved and
received profiles pass the same versioned validation: known option names
and six-digit RGB colors, with safe defaults for malformed fields. Profiles
never load resource paths.

## Rendering

The existing body's skin weights and geometry are preserved. Accessories
follow the rig's animated bones and are merged by bone and material. The
cape uses a vertex shader, without physics cloth. Regression checks keep
the tested combinations within 36 mesh surfaces including the body. An
unchanged profile skips rebuilding; a hidden preview stops rendering and
animating. Movement previews zoom out to keep the cape in view.

Implementation lives in `scripts/hero/customization/`,
`scripts/ui/hero_customization_page.gd`, and `shaders/hero_*.gdshader`, with
integration in `HeroAnimator`, `OptionsPanel` and `PlayerSync`.

## Verification and reproduction

Run from the repository root with Godot 4.7.2 on `PATH` as `godot`. Create
`build/customization` first; it is ignored build output. Supply an absolute
city data directory for the existing options regression.

```powershell
godot --headless --path . --log-file build/customization/customization-test.log res://tests/customization_test.tscn -- --solo=1
godot --headless --path . --log-file build/customization/customization-coop-test.log res://tests/customization_coop_test.tscn
godot --headless --path . --log-file build/customization/options-test.log res://tests/options_test.tscn -- --tiles=C:/path/to/data/tiles --solo=1
```

The focused suite covers persistence, malformed data, menu signals, skin
weights, animated attachments, hidden preview work and remote isolation.
The co-op test starts two actual Godot processes over loopback ENet, checks
initial saved costumes and edits in both directions, and needs no signaling
server or city tiles. Use `-- --port=18764` if its default port is occupied.

Results on 2026-10-17: **98 focused checks passed**, **41 existing options
checks passed**, and **two-process cosmetic synchronization passed**. The
focused run is recorded in `build/customization/customization-test.log`;
the options and co-op runs were checked in console output. The commands
above capture all three logs when reproducing. The options run emitted an
ObjectDB leak warning at shutdown; the focused and co-op runs exited cleanly.

For an interactive dressing room, run:

```powershell
godot --path . res://tests/customization_preview.tscn -- --variant=mech
```

Add `--screenshot=C:/absolute/path/preview.png` after the final `--` to save
and exit; `--variant=leotard`, `--turn=145`, and `--pose=Sprint` select other
views. For touch, put `--resolution 390x844` before the scene path and
`--touch=1` after `--`. This harness uses its own test settings file.

Inspected captures are in `build/customization/customization-mech.png`,
`customization-leotard.png`, `customization-touch.png`, and
`customization-motion.png`. A Chrome run also selected Aegis in the real
Hero menu, confirmed `hero_appearance.suit=mech` immediately in localStorage,
reloaded the same URL, and verified the selected and rendered mech outfit
with no console errors. Evidence: `build/browser-saved-mech.png`. Browser
shader checks reported no errors for the new suit and cape shaders.
