class_name Device
## What the game is running on, for touch controls and quality presets: a
## phone or tablet's browser, or a computer. Outside the browser (desktop
## builds, headless tests) it's always a computer with a mouse and keyboard.
##
## Touch controls: ?touch=1 forces them on and ?touch=0 off (--touch=1 on
## desktop). Otherwise they're on when the browser's main pointer is a finger
## (the CSS media query "pointer: coarse": phones and tablets), and Game also
## turns them on at the first touch of a touch screen.
##
## The page (html/head_include in export_presets.cfg) sets up window.nycPage:
## full screen, the "turn your phone" overlay and the screen's safe area.
## Without it (another HTML shell), those are simply left out.

## Phones' screens are narrower than this on their short side (CSS pixels);
## tablets' are wider.
const TABLET_MIN_SIDE := 600.0

static var _cache := {}


static func is_web() -> bool:
	return OS.has_feature("web")


## Whether touch controls should be on from the start.
static func wants_touch_controls() -> bool:
	var forced := LaunchOptions.get_string("touch")
	if forced == "1" or forced == "0":
		return forced == "1"
	return is_web() and _js_bool("coarse_pointer", "matchMedia('(pointer: coarse)').matches")


## Whether a touch may turn the controls on later (not with ?touch=0).
static func touch_allowed() -> bool:
	return LaunchOptions.get_string("touch") != "0"


## A phone or tablet (in its browser), whether or not touch controls are on.
static func is_mobile() -> bool:
	return is_web() and _js_bool("mobile", "matchMedia('(pointer: coarse)').matches"
		+ " || /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent)"
		+ " || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)")


## A phone rather than a tablet: its screen's short side, in CSS pixels.
static func is_phone() -> bool:
	if not is_mobile():
		return false
	if not _cache.has("short_side"):
		_cache["short_side"] = float(str(JavaScriptBridge.eval("Math.min(screen.width, screen.height)", true)))
	return _cache["short_side"] < TABLET_MIN_SIDE


## Screen pixels per CSS pixel (window.devicePixelRatio) in the browser.
static func pixel_ratio() -> float:
	if not is_web():
		return DisplayServer.screen_get_scale()
	var ratio := float(str(JavaScriptBridge.eval("window.devicePixelRatio || 1", true)))
	return ratio if ratio > 0.0 else 1.0


## The UI scale for touch screens: one UI unit per CSS pixel, which browsers
## keep about the same physical size on every phone.
static func touch_ui_scale() -> float:
	return clampf(pixel_ratio(), 1.0, 4.0)


## Space taken by notches and rounded corners at the screen's edges, in CSS
## pixels: (left, top, right, bottom).
static func safe_area_css() -> Vector4:
	if not _has_page():
		return Vector4.ZERO
	var parts := str(JavaScriptBridge.eval("nycPage.safeArea()", true)).split(",")
	if parts.size() != 4:
		return Vector4.ZERO
	return Vector4(parts[0].to_float(), parts[1].to_float(), parts[2].to_float(), parts[3].to_float())


## Whether the game can go full screen: desktop builds can, and pages
## where the browser can (not iPhones, whose browsers can't for anything but
## video).
static func can_fullscreen() -> bool:
	if not is_web():
		return true
	return _has_page() and _js_bool("can_fullscreen", "nycPage.canFullscreen()")


static func is_fullscreen() -> bool:
	if not is_web():
		var mode := DisplayServer.window_get_mode()
		return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	return _js_true("document.fullscreenElement || document.webkitFullscreenElement")


## Goes full screen or back (the options menu, F11 on desktop). In the
## browser only a click or tap may start it: a button's press, which Godot
## handles a frame after the browser saw it, still counts. On a touch screen
## it also turns the screen sideways where the browser can, as the page does.
static func set_fullscreen(on: bool) -> void:
	if not is_web():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
		return
	JavaScriptBridge.eval("""(function (on) {
	var d = document, root = d.documentElement;
	try {
		if (on) {
			var request = root.requestFullscreen || root.webkitRequestFullscreen;
			if (!request || d.fullscreenElement || d.webkitFullscreenElement) return;
			var lock = function () {
				if (!root.classList.contains('nyc-touch')) return;
				try { screen.orientation.lock('landscape').catch(function () {}); } catch (e) {}
			};
			var result = request.call(root, { navigationUI: 'hide' });
			if (result && result.then) result.then(lock, function () {}); else lock();
		} else if (d.fullscreenElement || d.webkitFullscreenElement) {
			var result = (d.exitFullscreen || d.webkitExitFullscreen).call(d);
			if (result && result.catch) result.catch(function () {});
		}
	} catch (e) {}
})(%s)""" % ("true" if on else "false"), true)


## Goes full screen when the finger that's touching the screen lifts: browsers
## only allow it during a tap, and Godot sees touches a frame later.
static func request_fullscreen() -> void:
	if not is_web():
		set_fullscreen(true)  # (touch controls on desktop: --touch=1)
	elif _has_page():
		JavaScriptBridge.eval("nycPage.armFullscreen()", true)


## Tells the page whether touch controls are on: it then asks to turn the
## phone sideways when it's upright, and goes full screen at the first tap.
static func set_page_touch_mode(on: bool) -> void:
	if _has_page():
		JavaScriptBridge.eval("nycPage.setTouch(%s)" % ("true" if on else "false"), true)


static func _has_page() -> bool:
	return is_web() and _js_bool("page", "typeof window.nycPage === 'object'")


## A JavaScript true/false, worked out once.
static func _js_bool(key: String, code: String) -> bool:
	if not _cache.has(key):
		_cache[key] = is_web() and _js_true(code)
	return _cache[key]


## Whether a JavaScript expression is truthy (as a string: JavaScriptBridge
## hands booleans back as numbers).
static func _js_true(code: String) -> bool:
	return str(JavaScriptBridge.eval("String(!!(%s))" % code, true)) == "true"
