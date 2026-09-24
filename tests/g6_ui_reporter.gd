extends Node

# Read-only G6 reporter, injected as an autoload ONLY into the disposable project copy
# created by tests/windows_g6_driver.py. It never changes gameplay, focus or scrolling:
# it prints visible UI text and window-pixel button centers so the driver can post
# window-scoped clicks, and saves window-only captures at key UI transitions.

const LABELS: Array[String] = ["CampaignStatus", "DynastyStatus", "SaveStatus", "LastResult",
	"Gold", "Round", "Army", "Enemies", "PendingNavigation", "DynastyLosses", "ThreatStatus", "ThreatChoice"]
const BUTTONS: Array[String] = ["TrainDrill", "FoundDynasty", "CancelDynasty", "ConfirmDynasty", "ThreatUp", "ThreatDown",
	"StartDefense", "FarmBorder", "FarmArcher", "Frontier", "GateUpgrade",
	"ShieldUpgrade", "FootUpgrade", "HorseUpgrade"]

var _last: String = ""
var _since: float = 0.0
var _announced: bool = false
var _capture_key: String = ""
var _capture_index: int = 0

func _process(delta: float) -> void:
	_since += delta
	if _since < 0.1:
		return
	_since = 0.0
	var scene := get_tree().current_scene
	if scene == null or not scene.is_node_ready():
		return
	if not _announced:
		_announced = true
		print("G6_WINDOW hwnd=%d pid=%d" % [DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE),
			OS.get_process_id()])
	var state := {"labels": {}, "buttons": {}}
	for name in LABELS:
		state.labels[name] = (scene.get_node("%" + name) as Label).text
	var scroll: Control = scene.get_node("Margin/Scroll")
	var final := get_viewport().get_final_transform()
	var scroll_xf := final * scroll.get_global_transform_with_canvas()
	var top: Vector2 = scroll_xf * Vector2.ZERO
	var bottom: Vector2 = scroll_xf * scroll.size
	state.scroll = [roundi(top.x), roundi(top.y), roundi(bottom.x), roundi(bottom.y)]
	for name in BUTTONS:
		var button: Button = scene.get_node("%" + name)
		var center: Vector2 = final * button.get_global_transform_with_canvas() * (button.size / 2.0)
		state.buttons[name] = {"text": button.text, "disabled": button.disabled,
			"visible": button.is_visible_in_tree(), "x": roundi(center.x), "y": roundi(center.y)}
	state.preview_open = (scene.get_node("%DynastyPreview") as Control).visible
	var text := JSON.stringify(state)
	if text != _last:
		_last = text
		print("G6UI " + text)
	_maybe_capture(state)

func _maybe_capture(state: Dictionary) -> void:
	var directory := OS.get_environment("G6_CAPTURE_DIR")
	if directory.is_empty():
		return
	var status: String = state.labels.CampaignStatus
	var key := "%s|%s|%s" % [status.get_slice(" · ", 0), state.preview_open,
		(state.labels.DynastyStatus as String).get_slice(" · ", 0)]
	if key == _capture_key:
		return
	_capture_key = key
	await RenderingServer.frame_post_draw
	_capture_index += 1
	# Continue numbering across relaunches instead of overwriting earlier captures.
	while FileAccess.file_exists(directory.path_join("%02d.png" % _capture_index)):
		_capture_index += 1
	var image := get_viewport().get_texture().get_image()
	var path := directory.path_join("%02d.png" % _capture_index)
	if image == null or image.save_png(path) != OK:
		print("G6_CAPTURE_FAILED " + path)
	else:
		print("G6_CAPTURE %s %s" % [path, key])
