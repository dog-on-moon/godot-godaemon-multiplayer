@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_autoload_singleton("MultiplayerManager", "res://addons/authoritative_multiplayer/multiplayer_manager.gd")

func _exit_tree() -> void:
	remove_autoload_singleton("MultiplayerManager")
