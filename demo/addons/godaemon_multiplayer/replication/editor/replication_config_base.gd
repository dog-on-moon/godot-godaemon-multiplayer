@tool
extends VBoxContainer

signal request_update

@onready var fold_button: Button = %FoldButton
@onready var config_name: Button = %ConfigName
@onready var subtitle: RichTextLabel = %Subtitle
@onready var delete_button: Button = %DeleteButton

@onready var contents: Control = %Contents

@onready var send_server: CheckBox = %SendServer
@onready var send_owner: CheckBox = %SendOwner
@onready var send_client: CheckBox = %SendClient
@onready var recv_server: CheckBox = %RecvServer
@onready var recv_owner: CheckBox = %RecvOwner
@onready var recv_client: CheckBox = %RecvClient
@onready var sync_mode: OptionButton = %SyncMode
@onready var reliable_button: CheckBox = %ReliableButton
@onready var ratelimit_spinbox: SpinBox = %RatelimitSpinbox
@onready var call_local: CheckBox = %CallLocal
@onready var dont_sync_to_owner: CheckBox = %DontSyncToOwner
@onready var debug_print: CheckBox = %DebugPrint

@onready var editor_theme := EditorInterface.get_editor_theme()
@onready var folded_icon := editor_theme.get_icon(&"CodeFoldedRightArrow", &"EditorIcons")
@onready var unfolded_icon := editor_theme.get_icon(&"CodeFoldDownArrow", &"EditorIcons")

var argument: Variant
var _script: ScriptReplication
var _config: ReplicationConfigBase

var inherited := false

func _ready() -> void:
	if not argument:
		return
	fold_button.icon = folded_icon
	fold_button.toggled.connect(_toggle_fold)
	config_name.pressed.connect(toggle_fold)
	contents.visible = false
	
	delete_button.icon = editor_theme.get_icon(&"Remove", &"EditorIcons")
	
	if not _config:
		return
	
	send_server.set_pressed_no_signal(_config.get_send_filter_flag(ReplicationConfigBase.Filter.Server))
	send_owner .set_pressed_no_signal(_config.get_send_filter_flag(ReplicationConfigBase.Filter.Owner))
	send_client.set_pressed_no_signal(_config.get_send_filter_flag(ReplicationConfigBase.Filter.Client))
	recv_server.set_pressed_no_signal(_config.get_recv_filter_flag(ReplicationConfigBase.Filter.Server))
	recv_owner .set_pressed_no_signal(_config.get_recv_filter_flag(ReplicationConfigBase.Filter.Owner))
	recv_client.set_pressed_no_signal(_config.get_recv_filter_flag(ReplicationConfigBase.Filter.Client))
	
	send_server.toggled.connect(_config.set_send_filter_flag.bind(ReplicationConfigBase.Filter.Server))
	send_owner .toggled.connect(_config.set_send_filter_flag.bind(ReplicationConfigBase.Filter.Owner))
	send_client.toggled.connect(_config.set_send_filter_flag.bind(ReplicationConfigBase.Filter.Client))
	recv_server.toggled.connect(_config.set_recv_filter_flag.bind(ReplicationConfigBase.Filter.Server))
	recv_owner .toggled.connect(_config.set_recv_filter_flag.bind(ReplicationConfigBase.Filter.Owner))
	recv_client.toggled.connect(_config.set_recv_filter_flag.bind(ReplicationConfigBase.Filter.Client))
	
	reliable_button.set_pressed_no_signal(_config.reliable)
	reliable_button.toggled.connect(func (x): _config.reliable = x)
	
	_config.updated.connect(_update)
	_update()
	
	if inherited:
		send_server.disabled = true
		send_owner.disabled = true
		send_client.disabled = true
		recv_server.disabled = true
		recv_owner.disabled = true
		recv_client.disabled = true
		sync_mode.disabled = true
		reliable_button.disabled = true
		ratelimit_spinbox.editable = false
		call_local.disabled = true
		dont_sync_to_owner.disabled = true
		debug_print.disabled = true
		delete_button.visible = false

func toggle_fold():
	fold_button.button_pressed = not fold_button.button_pressed

func _toggle_fold(x: bool):
	fold_button.icon = folded_icon if not x else unfolded_icon
	contents.visible = x

func _update():
	subtitle.text = "[i][color=666666](%s => %s)" % [
		ReplicationConfigBase.filter_flags_to_txt(_config.send_filter),
		ReplicationConfigBase.filter_flags_to_txt(_config.recv_filter)
	]
