class_name SnapshotBuffer
extends RefCounted
## Recent states of something another game runs (a remote hero, or a thug on
## the host), for drawing it smoothly in between updates. States are played
## back DELAY behind the newest, so there's nearly always a later one to blend
## toward even when updates arrive unevenly.

## How far behind the sender to play back (milliseconds): a bit more than two
## updates at 20 per second.
const DELAY := 120.0
const MAX_STATES := 16

var _times := PackedFloat64Array()  # sender's clock, msec
var _states: Array = []
## Our clock minus the sender's, as of the quickest update lately.
var _offset := NAN


func is_empty() -> bool:
	return _states.is_empty()


func newest() -> Variant:
	return _states.back() if not _states.is_empty() else null


## Adds a state stamped with the sender's clock (Time.get_ticks_msec there).
func push(sender_msec: float, state: Variant) -> void:
	if not _times.is_empty() and sender_msec <= _times[_times.size() - 1]:
		return  # out of order or repeated
	var offset := Time.get_ticks_msec() - sender_msec
	# Follow quicker updates at once and slower ones gradually, so one late
	# packet doesn't pull playback back.
	_offset = offset if is_nan(_offset) or offset < _offset else lerpf(_offset, offset, 0.02)
	_times.append(sender_msec)
	_states.append(state)
	if _states.size() > MAX_STATES:
		_times.remove_at(0)
		_states.pop_front()


## The two states to blend between right now and how far between them (0..1):
## [older, newer, weight]. Holds the newest state once playback catches up.
func sample() -> Array:
	var time := Time.get_ticks_msec() - _offset - DELAY
	var last := _states.size() - 1
	if last == 0 or time >= _times[last]:
		return [_states[last], _states[last], 1.0]
	if time <= _times[0]:
		return [_states[0], _states[0], 0.0]
	var k := _times.bsearch(time) - 1
	var span := _times[k + 1] - _times[k]
	return [_states[k], _states[k + 1], (time - _times[k]) / span if span > 0.0 else 1.0]
