@tool
extends EditorPlugin

var replication_editor: Control
var replication_editor_button: Button

func _enter_tree() -> void:
	add_autoload_singleton("SubprocessServer", "res://addons/godaemon_multiplayer/internal/subprocess_server.gd")
	_load_editor()

func _exit_tree() -> void:
	remove_autoload_singleton("SubprocessServer")
	_unload_editor()

func _load_editor():
	replication_editor = load("res://addons/godaemon_multiplayer/editor/replication_editor.tscn").instantiate()
	replication_editor.plugin = self
	replication_editor_button = add_control_to_bottom_panel(replication_editor, "Replication")

func _unload_editor():
	remove_control_from_bottom_panel(replication_editor)
	replication_editor.queue_free()
	replication_editor = null
	replication_editor_button = null

func _reload_editor():
	_unload_editor()
	_load_editor()
	replication_editor_button.button_pressed = true
