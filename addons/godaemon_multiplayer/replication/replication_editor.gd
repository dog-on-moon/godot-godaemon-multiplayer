@tool
extends Control

const ConfigVboxContainer = preload("res://addons/godaemon_multiplayer/replication/editor/config_vbox_container.gd")

@onready var reload_button: Button = %ReloadButton
@onready var script_icon: TextureRect = %ScriptIcon
@onready var script_name: RichTextLabel = %ScriptName
@onready var method_v_box_container: ConfigVboxContainer = %MethodVBoxContainer
@onready var property_v_box_container: ConfigVboxContainer = %PropertyVBoxContainer
@onready var new_property: Button = %NewProperty
@onready var signal_v_box_container: ConfigVboxContainer = %SignalVBoxContainer
@onready var new_signal: Button = %NewSignal

@onready var editor_theme := EditorInterface.get_editor_theme()

@export var plugin: EditorPlugin

var _current_script: Script

func _ready() -> void:
	if self == get_tree().edited_scene_root:
		return
	
	script_icon.texture = editor_theme.get_icon(&"Script", &"EditorIcons")
	reload_button.pressed.connect(plugin._reload_editor)
	
	var script_editor := EditorInterface.get_script_editor()
	_set_script(script_editor.get_current_script())
	script_editor.editor_script_changed.connect(_set_script)
	visibility_changed.connect(_visibility_changed)

var _stored_script_length := 0
var _stored_script_hash := 0

func _physics_process(delta: float) -> void:
	if not _current_script:
		return
	if _stored_script_length != _current_script.source_code.length():
		if _stored_script_hash != hash(_current_script.source_code):
			_set_script(_current_script)

func _visibility_changed():
	if is_visible_in_tree():
		_set_script(_current_script)

func _set_script(script: Script):
	_current_script = script
	
	# Update the replication data cache.
	if script:
		ReplicationData.validate_script_replication(script)
	
	# Now update EVERYTHING DOG
	if script:
		_stored_script_length = script.source_code.length()
		_stored_script_hash = hash(script.source_code)
	else:
		_stored_script_length = -1
		_stored_script_hash = 0
	_update_script_label(script)
	method_v_box_container._set_script(script)
	property_v_box_container._set_script(script)
	signal_v_box_container._set_script(script)
	
	if script:
		ReplicationData.validate_script_replication(script)

func _update_script_label(script: Script):
	if not script:
		script_name.text = " No script selected."
	else:
		var _class_name := script.get_global_name()
		var _resource_path := script.resource_path
		
		if _class_name:
			script_name.text = " Editing [rainbow freq=0.2 sat=0.6][b][wave]%s[/wave][/b][/rainbow]" % _class_name
			if _resource_path:
				script_name.text += " (%s)" % _resource_path
		elif _resource_path:
			script_name.text = " Editing %s" % _resource_path
		else:
			script_name.text = " Editing Unknown Script"
