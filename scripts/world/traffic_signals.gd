class_name TrafficSignals
extends RefCounted
## The city's traffic signals: one clock and one cycle that the signal poles
## (shaders/street_furniture.gdshader, through the `signal_clock` shader
## global that CityStreamer sets every frame) and traffic both follow, so a
## car stops at the red light it sees.
##
## Every signal runs the same CYCLE, shifted by its own phase offset (0..1 of
## a cycle, from the tiles: a signal pole's uv.y, a driving lane's signal
## phase); at an intersection the approaches crossing each other are half a
## cycle apart. Within its cycle a light is green for GREEN of it, yellow for
## YELLOW, and red for the rest, just over half: as one approach's light turns
## red, the crossing one stays red a moment longer (all red) before it turns
## green. Pedestrians crossing an approach's street get the walking person
## while that approach is red and the crossing traffic is green: from WALK_START
## for WALK, then the flashing hand for FLASH (ending before the crossing
## traffic's yellow), then the steady hand.
##
## The shader works the same numbers out on its own (its constants must match
## these). Later, co-op may sync the clock across players.

enum Light { GREEN, YELLOW, RED }
enum Walk { DONT_WALK, WALK, FLASHING }

## Seconds per cycle.
const CYCLE := 60.0
## Shares of the cycle: green, then yellow; red for the rest.
const GREEN := 0.43
const YELLOW := 0.05
## When (in the cycle) the walking person comes on, and how long it and then
## the flashing hand last (shares of the cycle).
const WALK_START := 0.5
const WALK := 0.18
const FLASH := 0.22
## The clock wraps around after this many seconds (a whole number of cycles),
## so it stays precise as a shader's float.
const CLOCK_WRAP := 3600.0


## The signals' clock: seconds since the game started, wrapping at CLOCK_WRAP.
static func clock() -> float:
	return float(Time.get_ticks_msec() % int(CLOCK_WRAP * 1000.0)) / 1000.0


## Where a signal with this phase offset is in its cycle (0..1) at time `at`
## (the signals' clock).
static func phase(offset: float, at := clock()) -> float:
	return fposmod(at / CYCLE + offset, 1.0)


## The light (Light) a signal with this phase offset shows at time `at`.
static func light(offset: float, at := clock()) -> int:
	var p := phase(offset, at)
	if p < GREEN:
		return Light.GREEN
	if p < GREEN + YELLOW:
		return Light.YELLOW
	return Light.RED


## Seconds until the light of a signal with this phase offset changes next
## (green to yellow, yellow to red, red to green), from time `at`.
static func time_to_change(offset: float, at := clock()) -> float:
	var p := phase(offset, at)
	var next := 1.0
	if p < GREEN:
		next = GREEN
	elif p < GREEN + YELLOW:
		next = GREEN + YELLOW
	return (next - p) * CYCLE


## The pedestrian signal (Walk) for the crosswalk over the street of a signal
## with this phase offset, at time `at`.
static func walk(offset: float, at := clock()) -> int:
	var since := fposmod(phase(offset, at) - WALK_START, 1.0)
	if since < WALK:
		return Walk.WALK
	if since < WALK + FLASH:
		return Walk.FLASHING
	return Walk.DONT_WALK
