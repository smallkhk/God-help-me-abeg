extends Node
## In-game content updates (phones). The IPA ships the engine + the game as it
## was at build time; every later change is published by the "Content update"
## GitHub workflow as one .pck on the `content-latest` release. On launch:
##   1. a previously downloaded user://update.pck is mounted over res:// (this
##      autoload is first in the list, so everything after it loads from the pack)
##   2. the manifest is checked; a newer pack is downloaded with a progress bar
##      and the player is asked to close and reopen the game.
## Limits: engine/plugin (native) changes and project.godot settings still need
## a new IPA.

const MANIFEST_URL := "https://github.com/smallkhk/God-help-me-abeg/releases/download/content-latest/manifest.json"
const PACK := "user://update.pck"

var version := 0
var _http: HTTPRequest
var _layer: CanvasLayer
var _label: Label
var _bar: ProgressBar
var _total := 0


func _init() -> void:
	if FileAccess.file_exists(PACK):
		if not ProjectSettings.load_resource_pack(PACK, true):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PACK))
	version = _read_version()


func _read_version() -> int:
	var f := FileAccess.open("res://build_version.txt", FileAccess.READ)
	return int(f.get_as_text().strip_edges()) if f else 0


func _ready() -> void:
	if not (OS.has_feature("mobile") or OS.get_environment("FORCE_UPDATER") == "1"):
		return
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	_http.request_completed.connect(_on_manifest)
	_http.request(MANIFEST_URL)


func _on_manifest(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_http.request_completed.disconnect(_on_manifest)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return   # offline or no update published yet: just play
	var m = JSON.parse_string(body.get_string_from_utf8())
	if typeof(m) != TYPE_DICTIONARY or int(m.get("version", 0)) <= version:
		return
	_total = int(m.get("size", 0))
	_show_ui("Downloading update…")
	_http.download_file = PACK + ".part"
	_http.timeout = 0.0
	_http.request_completed.connect(_on_pack)
	_http.request(str(m["url"]))
	set_process(true)


func _process(_dt: float) -> void:
	if _bar == null or _http == null or _http.download_file == "":
		return
	var got := _http.get_downloaded_bytes()
	var tot := _total if _total > 0 else maxi(_http.get_body_size(), 1)
	_bar.value = 100.0 * got / tot
	_label.text = "Downloading update…  %.0f / %.0f MB" % [got / 1048576.0, tot / 1048576.0]


func _on_pack(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	set_process(false)
	var part := ProjectSettings.globalize_path(PACK + ".part")
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(part)
		_label.text = "Update failed (check internet). Will retry next launch."
		get_tree().create_timer(4.0).timeout.connect(_layer.queue_free)
		return
	DirAccess.rename_absolute(part, ProjectSettings.globalize_path(PACK))
	_bar.value = 100.0
	_label.text = "Update installed! Close the game fully and open it again."


func _show_ui(text: String) -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.8)
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.custom_minimum_size = Vector2(0, 120)
	panel.size = Vector2(get_viewport().get_visible_rect().size.x, 120)
	_layer.add_child(panel)
	_label = Label.new()
	_label.text = text
	_label.position = Vector2(30, 14)
	_label.add_theme_font_size_override("font_size", 28)
	panel.add_child(_label)
	_bar = ProgressBar.new()
	_bar.position = Vector2(30, 66)
	_bar.size = Vector2(panel.size.x - 60, 30)
	panel.add_child(_bar)
