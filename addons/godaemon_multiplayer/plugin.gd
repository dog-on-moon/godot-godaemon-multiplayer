@tool
extends EditorPlugin

var replication_editor: Control
var replication_editor_button: Button

func _enter_tree() -> void:
	add_autoload_singleton("SubprocessServer", "res://addons/godaemon_multiplayer/util/subprocess_server.gd")
	add_autoload_singleton("Godaemon", "res://addons/godaemon_multiplayer/godaemon.gd")
	add_custom_type("MultiplayerConfig", "Resource", preload("res://addons/godaemon_multiplayer/config/multiplayer_config.gd"), preload("res://addons/godaemon_multiplayer/icons/GDScript.svg"))
	add_custom_type("ServiceBase", "Node", preload("res://addons/godaemon_multiplayer/services/service_base.gd"), preload("res://addons/godaemon_multiplayer/icons/GDScript.svg"))
	add_custom_type("MultiplayerRoot", "Node", preload("res://addons/godaemon_multiplayer/nodes/multiplayer_root.gd"), preload("res://addons/godaemon_multiplayer/icons/SignalsAndGroups.svg"))
	_load_editor()
	
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(ReplicationCacheManager.update_cache)
	ReplicationCacheManager.update_cache(true)

func _exit_tree() -> void:
	remove_autoload_singleton("SubprocessServer")
	remove_autoload_singleton("Godaemon")
	remove_custom_type("MultiplayerRoot")
	remove_custom_type("ServiceBase")
	remove_custom_type("MultiplayerConfig")
	_unload_editor()
	
	EditorInterface.get_resource_filesystem().filesystem_changed.disconnect(ReplicationCacheManager.update_cache)

func _load_editor():
	replication_editor = load("res://addons/godaemon_multiplayer/services/replication/editor/replication_editor.tscn").instantiate()
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
