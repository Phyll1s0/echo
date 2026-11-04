extends Node
## CSS owns safe areas; Godot owns the GPU buffer, with layout in CSS pixels.
var viewport: JavaScriptObject
var revision := -1

func _ready() -> void:
	viewport = JavaScriptBridge.get_interface("window").echoViewport
	get_window().min_size = Vector2i(1, 1)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().disable_3d = true
	_sync_size()

func _process(_delta: float) -> void:
	_sync_size()

func _sync_size() -> void:
	if viewport == null or int(viewport.revision) == revision: return
	revision = int(viewport.revision)
	get_parent().touch_controls = bool(viewport.touch)
	get_window().content_scale_size = Vector2i(int(viewport.width), int(viewport.height))
	get_window().size = Vector2i(int(viewport.renderWidth), int(viewport.renderHeight))
	get_parent().call_deferred("_adapt_layout")
