extends Node
## In-game content updates (phones). The IPA ships the engine + the game as it
## was at build time; every later change is published by the "Content update"
## GitHub workflow as one .pck on the `content-latest` release. On launch:
##   1. a previously downloaded user://update.pck is mounted over res:// (this
##      autoload is first in the list, so everything after it loads from the pack)
##   2. the manifest is checked; a newer pack is downloaded with a progress bar
##      and the player is asked to close and reopen the game.
## Small updates: the workflow also publishes a base pack (the whole game, rebuilt
## rarely) and a patch pack (only files changed since that base). This updater
## keeps base + patch and only downloads what changed, so a normal update is a
## few MB. Older IPAs keep using the full update.pck from the same manifest.
## Limits: engine/plugin (native) changes and project.godot settings still need
## a new IPA.

const MANIFEST_URL := "https://github.com/smallkhk/God-help-me-abeg/releases/download/content-latest/manifest.json"
const PACK := "user://update.pck"      # full pack (older builds / fallback)
const BASE := "user://base.pck"
const PATCH := "user://patch.pck"
const STATE := "user://update_state.json"

var version := 0
var _http: HTTPRequest
var _layer: CanvasLayer
var _label: Label
var _bar: ProgressBar
var _total := 0
var _queue: Array = []      # [[url, dest, size], ...] still to download
var _state := {}
var _new_state := {}
var _builtin := 0


func _init() -> void:
	# version of the game inside the installed IPA (before any pack is mounted)
	_builtin = _read_version()
	var f := FileAccess.open(STATE, FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			_state = d
	if int(_state.get("builtin", -1)) != _builtin:
		# first launch of a newly installed IPA: whatever was downloaded for the
		# old IPA is older than what we now ship — delete it (frees 400+ MB)
		for p in [PACK, BASE, PATCH, PACK + ".part", BASE + ".part", PATCH + ".part"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		_state = {"builtin": _builtin}
		_save_state()
	if FileAccess.file_exists(BASE):
		if ProjectSettings.load_resource_pack(BASE, true):
			_mount(PATCH)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(BASE))
	elif FileAccess.file_exists(PATCH):
		_mount(PATCH)      # the IPA's own content is the base
	elif FileAccess.file_exists(PACK):
		_mount(PACK)
	version = _read_version()


func _mount(p: String) -> void:
	if FileAccess.file_exists(p) and not ProjectSettings.load_resource_pack(p, true):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _save_state() -> void:
	var f := FileAccess.open(STATE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_state))
		f.close()


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
	if m.has("base_url"):
		# base + patch: fetch only the parts that changed
		var bv := int(m["base_version"])
		_new_state = {"builtin": _builtin, "base": bv, "patch": int(m["version"])}
		# the IPA already holds everything up to its build: no base download if it
		# is at least as new as the base, only the patch on top of it
		if _builtin < bv and (int(_state.get("base", -1)) != bv or not FileAccess.file_exists(BASE)):
			_queue.append([str(m["base_url"]), BASE, int(m.get("base_size", 0))])
		if str(m.get("patch_url", "")) != "" and int(_state.get("patch", -1)) != int(m["version"]):
			_queue.append([str(m["patch_url"]), PATCH, int(m.get("patch_size", 0))])
		if _queue.is_empty():
			return
	else:
		_queue.append([str(m["url"]), PACK, int(m.get("size", 0))])
	_show_ui("Downloading update…")
	_http.timeout = 0.0
	_http.request_completed.connect(_on_pack)
	_next_download()


func _next_download() -> void:
	var job: Array = _queue[0]
	_total = int(job[2])
	_http.download_file = String(job[1]) + ".part"
	_http.request(String(job[0]))
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
	var dest: String = _queue[0][1]
	var part := ProjectSettings.globalize_path(dest + ".part")
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(part)
		_label.text = "Update failed (check internet). Will retry next launch."
		get_tree().create_timer(4.0).timeout.connect(_layer.queue_free)
		return
	DirAccess.rename_absolute(part, ProjectSettings.globalize_path(dest))
	if dest == BASE:
		# an old patch belongs to the old base: drop it before anything can mount it
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATCH))
		_state = {"builtin": _builtin, "base": _new_state["base"], "patch": _new_state["base"]}
		_save_state()
	_queue.pop_front()
	if not _queue.is_empty():
		_next_download()
		return
	if not _new_state.is_empty():
		_state = _new_state
		_save_state()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PACK))   # old full pack not needed
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
