@tool
extends EditorPlugin

var replication_editor: Control
var replication_editor_button: Button

func _enter_tree() -> void:
	add_autoload_singleton("SubprocessServer", "res://addons/godaemon_multiplayer/util/subprocess_server.gd")
	add_custom_type("MultiplayerConfig", "Resource", preload("res://addons/godaemon_multiplayer/api/config/multiplayer_config.gd"), preload("res://addons/godaemon_multiplayer/icons/GDScript.svg"))
	add_custom_type("ServiceBase", "Node", preload("res://addons/godaemon_multiplayer/services/service_base.gd"), preload("res://addons/godaemon_multiplayer/icons/GDScript.svg"))
	add_custom_type("MultiplayerRoot", "Node", preload("res://addons/godaemon_multiplayer/api/nodes/multiplayer_root.gd"), preload("res://addons/godaemon_multiplayer/icons/SignalsAndGroups.svg"))
	_load_editor()

func _exit_tree() -> void:
	remove_autoload_singleton("SubprocessServer")
	remove_custom_type("MultiplayerRoot")
	remove_custom_type("ServiceBase")
	remove_custom_type("MultiplayerConfig")
	_unload_editor()

func _load_editor():
	replication_editor = load("res://addons/godaemon_multiplayer/replication/replication_editor.tscn").instantiate()
	replication_editor.plugin = self
	replication_editor_button = add_control_to_bottom_panel(replication_editor, "Replication")
	update_editor_button_text()

func _unload_editor():
	remove_control_from_bottom_panel(replication_editor)
	replication_editor.queue_free()
	replication_editor = null
	replication_editor_button = null

func _reload_editor():
	_unload_editor()
	_load_editor()
	replication_editor_button.button_pressed = true

func update_editor_button_text():
	if not replication_editor_button:
		return
	var s: Script = EditorInterface.get_script_editor().get_current_script()
	if not s:
		replication_editor_button.text = "Replication (0)"
	else:
		var x := 0
		var depth := 200
		var parent := s
		while parent:
			depth -= 1
			if depth <= 0:
				break
			var sr := ReplicationData.get_script_replication(parent)
			if sr:
				x += sr.method_config.size() + sr.property_config.size() + sr.signal_config.size()
			parent = parent.get_base_script()
			if not parent:
				break
		replication_editor_button.text = "Replication (%s)" % x
