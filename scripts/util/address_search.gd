class_name AddressSearch
extends Node
## Finds a place in the city from what the player typed (the options menu's
## Go to box): a street address or a place's name, looked up with the city's
## own address search (NYC Planning Labs GeoSearch: every address in the five
## boroughs, free, no key); a ZIP code on its own, with OpenStreetMap's
## (Nominatim; GeoSearch has none); or a latitude and longitude ("40.7484,
## -73.9857", as maps copy them), straight away. Both services let browsers
## ask (CORS). One search at a time: a new one cancels the last.

signal found(world_position: Vector3, label: String)
signal failed(message: String)

const GEOSEARCH_URL := "https://geosearch.planninglabs.nyc/v2/search?size=1&text="
const NOMINATIM_URL := "https://nominatim.openstreetmap.org/search?country=us&format=jsonv2&limit=1&postalcode="
const TIMEOUT := 10.0

var _request: HTTPRequest
var _zip := false
var _lat_lon := RegEx.create_from_string("^\\s*(-?\\d+(?:\\.\\d+)?)\\s*,\\s*(-?\\d+(?:\\.\\d+)?)\\s*$")
var _zip_code := RegEx.create_from_string("^\\s*(\\d{5})(?:-\\d{4})?\\s*$")


func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = TIMEOUT
	_request.request_completed.connect(_on_completed)
	add_child(_request)


func is_busy() -> bool:
	return _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED


func search(text: String) -> void:
	_request.cancel_request()
	text = text.strip_edges()
	if text.is_empty():
		failed.emit("Type an address first.")
		return
	var pair := _lat_lon.search(text)
	if pair:
		found.emit(Geo.to_world(pair.get_string(1).to_float(), pair.get_string(2).to_float()), text)
		return
	var zip := _zip_code.search(text)
	_zip = zip != null
	var url := NOMINATIM_URL + zip.get_string(1) if _zip else GEOSEARCH_URL + text.uri_encode()
	# (Nominatim asks to be told who's asking; browsers send the page instead.)
	var headers := PackedStringArray() if Device.is_web() else PackedStringArray(["User-Agent: NYCHeroes (https://nycheroes.party)"])
	if _request.request(url, headers) != OK:
		failed.emit("Couldn't look that up.")


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		failed.emit("Couldn't reach the address search. Online?")
		return
	var text := body.get_string_from_utf8()
	var place := parse_nominatim(text) if _zip else parse_geosearch(text)
	if place.is_empty():
		failed.emit("Couldn't find that in New York City.")
	else:
		found.emit(Geo.to_world(place.lat, place.lon), place.label)


## {lat, lon, label} of GeoSearch's best match (a GeoJSON FeatureCollection),
## or {} without one.
static func parse_geosearch(text: String) -> Dictionary:
	var data = _json(text)
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("features")) != TYPE_ARRAY or data.features.is_empty():
		return {}
	var feature: Dictionary = data.features[0]
	var where: Array = feature.get("geometry", {}).get("coordinates", [])
	if where.size() < 2:
		return {}
	var properties: Dictionary = feature.get("properties", {})
	var label := str(properties.get("name", properties.get("label", "")))
	if properties.has("borough"):
		label += ", " + str(properties.borough)
	return {"lat": float(where[1]), "lon": float(where[0]), "label": label}


## {lat, lon, label} of Nominatim's first result (a JSON array), or {}.
static func parse_nominatim(text: String) -> Dictionary:
	var data = _json(text)
	if typeof(data) != TYPE_ARRAY or data.is_empty() or typeof(data[0]) != TYPE_DICTIONARY:
		return {}
	var place: Dictionary = data[0]
	if not place.has("lat") or not place.has("lon"):
		return {}
	var parts := str(place.get("display_name", "")).split(", ")
	return {"lat": str(place.lat).to_float(), "lon": str(place.lon).to_float(), "label": ", ".join(parts.slice(0, 2))}


## The JSON in `text`, or null (quietly: a busy server answers with a web page).
static func _json(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null
