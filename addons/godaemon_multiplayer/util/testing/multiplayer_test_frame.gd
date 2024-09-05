@tool
extends Container

const MtfSvc = preload("res://addons/godaemon_multiplayer/util/testing/mtf_svc.gd")

@onready var viewport_split: GridContainer = $ViewportSplit
@onready var color_rect: ColorRect = $ColorRect

## The number of clients to show in the test frame.
@export_range(0, 1, 1, "or_greater") var clients := 1:
	set(x):
		clients = x
		if Engine.is_editor_hint() and is_node_ready():
			_update_nodes()

## Show or hide the dedicated server viewport.
@export var show_server := true:
	set(x):
		show_server = x
		if is_node_ready():
			_update_position()

@export_group("Connection")
## The port to use for connection.
@export_range(0, 65535, 1) var port := 27027:
	set(x):
		port = x
		if is_node_ready():
			_update_properties()

## The configuration to use for the multiplayer roots.
@export var configuration: MultiplayerConfig:
	set(x):
		configuration = x
		if is_node_ready():
			_update_properties()

@export_group("Visual")
## Padding between each viewport.
@export_range(0, 8, 1, "or_greater") var padding := 8:
	set(x):
		padding = x
		if is_node_ready():
			_update_position()

## Sets the color of the border frame.
@export var border_color := Color(0.125, 0.031, 0.149, 1.0):
	set(x):
		border_color = x
		if not is_node_ready():
			await ready
		color_rect.color = x

var server_svc: MtfSvc
var client_svcs: Array[MtfSvc] = []

func _ready() -> void:
	color_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_update_nodes()
	_update_position()
	if not Engine.is_editor_hint():
		server_svc.mp.start_multi_connect()
		for svc in client_svcs:
			svc.mp.start_multi_connect()

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			for svc in client_svcs + [server_svc]:
				svc.active = svc.get_global_rect().has_point(get_global_mouse_position())

func _update_nodes():
	# Create server viewport if it does not exist.
	if not server_svc:
		server_svc = MtfSvc.new()
		server_svc.name = "ServerViewport"
		server_svc.client = false
		server_svc.config = configuration
		viewport_split.add_child(server_svc)
	
	# Clean up/rebuild client viewports.
	for svc in client_svcs.duplicate():
		svc.queue_free()
	client_svcs = []
	for i in clients:
		var client_svc := MtfSvc.new()
		client_svc.name = "ClientViewport1"
		client_svc.client = true
		client_svc.config = configuration
		viewport_split.add_child(client_svc)
		client_svcs.append(client_svc)
	
	_update_properties()
	_update_position()

func _update_properties():
	server_svc.mp.port = port
	server_svc.config = configuration
	for svc in client_svcs:
		svc.mp.address = "127.0.0.1"
		svc.mp.port = port
		svc.config = configuration

func _update_position():
	viewport_split.add_theme_constant_override(&"h_separation", padding)
	viewport_split.add_theme_constant_override(&"v_separation", padding)
	server_svc.visible = show_server
	
	var svcs := client_svcs.duplicate()
	if show_server:
		svcs.append(server_svc)
	
	var columns := ceili(sqrt(svcs.size()))
	var total_padding := Vector2.ONE * (padding * (columns - 1))
	var reduced_size := (size - total_padding) * (1.0 / columns)
	
	for svc: MtfSvc in svcs:
		svc.size = Vector2.ZERO
		svc.custom_minimum_size = reduced_size
	viewport_split.columns = columns
	
func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_update_position()
