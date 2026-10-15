class_name WebTextField
extends Node
## On touch screens in the browser: a real HTML text box laid over a LineEdit
## while that's on screen, so a tap on it brings up the phone's own keyboard.
## (Godot's experimental virtual keyboard focuses a hidden text box a frame
## after the tap, which iOS ignores: browsers only open the keyboard for a box
## focused during the tap itself.) What's typed goes to the LineEdit, in
## capitals; Enter (the keyboard's Go) submits it.

const SETUP_JS := """
(function () {
	if (window.nycTextField) return;
	var el = document.createElement('input');
	el.type = 'text';
	el.autocomplete = 'off';
	el.spellcheck = false;
	el.setAttribute('autocapitalize', 'characters');
	el.setAttribute('autocorrect', 'off');
	el.setAttribute('enterkeyhint', 'go');
	el.style.cssText = 'position:absolute;display:none;z-index:20;box-sizing:border-box;margin:0;'
		+ 'padding:0 10px;border:1px solid rgba(255,255,255,0.35);border-radius:4px;outline:none;'
		+ 'background:#1d2029;color:#fff;font-family:sans-serif;text-transform:uppercase;'
		+ '-webkit-user-select:text;user-select:text;touch-action:manipulation';
	document.body.appendChild(el);
	var api = { el: el, onInput: null, onEnter: null };
	api.show = function (x, y, w, h, fontSize, value, placeholder, maxLength) {
		el.style.left = x + 'px';
		el.style.top = y + 'px';
		el.style.width = w + 'px';
		el.style.height = h + 'px';
		el.style.fontSize = fontSize + 'px';
		el.placeholder = placeholder;
		el.maxLength = maxLength;
		if (el.style.display === 'none') el.value = value;
		el.style.display = 'block';
	};
	api.hide = function () {
		if (document.activeElement === el) el.blur();
		el.style.display = 'none';
	};
	el.addEventListener('input', function () {
		var caret = el.selectionStart;
		el.value = el.value.toUpperCase();
		el.setSelectionRange(caret, caret);
		if (api.onInput) api.onInput(el.value);
	});
	el.addEventListener('keydown', function (e) {
		if (e.key !== 'Enter') return;
		e.preventDefault();
		el.blur();
		if (api.onEnter) api.onEnter(el.value);
	});
	el.addEventListener('blur', function () {
		window.scrollTo(0, 0);
		var canvas = document.getElementById('canvas');
		if (canvas) canvas.focus();
	});
	window.nycTextField = api;
})();
"""

var line_edit: LineEdit

var _api: JavaScriptObject
var _input_callback: JavaScriptObject
var _enter_callback: JavaScriptObject
var _shown := false
var _shown_rect := Rect2()


func _ready() -> void:
	JavaScriptBridge.eval(SETUP_JS, true)
	_api = JavaScriptBridge.get_interface("nycTextField")
	_input_callback = JavaScriptBridge.create_callback(_on_input)
	_enter_callback = JavaScriptBridge.create_callback(_on_enter)
	_api.onInput = _input_callback
	_api.onEnter = _enter_callback


func _exit_tree() -> void:
	if _api:
		_api.hide()


func _process(_delta: float) -> void:
	if not line_edit.is_visible_in_tree():
		if _shown:
			_shown = false
			_api.hide()
		return
	# The LineEdit's box in CSS pixels: UI units, then screen pixels, then CSS.
	var to_screen := get_viewport().get_final_transform() * line_edit.get_global_transform_with_canvas()
	var rect := to_screen * Rect2(Vector2.ZERO, line_edit.size)
	var ratio := Device.pixel_ratio()
	rect = Rect2(rect.position / ratio, rect.size / ratio)
	if _shown and rect.is_equal_approx(_shown_rect):
		return
	_shown = true
	_shown_rect = rect
	# 16 px or more, or iPhones zoom the page in on the box.
	var font_size := maxf(16.0, line_edit.get_theme_font_size("font_size") * to_screen.get_scale().y / ratio)
	_api.show(rect.position.x, rect.position.y, rect.size.x, rect.size.y, font_size,
		line_edit.text, line_edit.placeholder_text, line_edit.max_length)


func _on_input(args: Array) -> void:
	line_edit.text = str(args[0])
	line_edit.caret_column = line_edit.text.length()


func _on_enter(args: Array) -> void:
	line_edit.text = str(args[0])
	line_edit.text_submitted.emit(line_edit.text)
