extends Node

@onready var client_root: ClientRoot = $ClientRoot
@onready var server_root: ServerRoot = $ServerRoot

func _ready() -> void:
	client_root.connection_success.connect(func (): print('Client connection success'))
	client_root.connection_failed.connect(
		func (s: ClientRoot.ConnectionState):
			print('Client connection failed: %s' % ClientRoot.get_connection_state_name(s))
	)
	client_root.server_disconnected.connect(
		func ():
			print('Server disconnected')
	)
	client_root.start_multi_connect(-1)
	
	server_root.connection_success.connect(_server_connected)
	server_root.connection_failed.connect(
		func (s: ServerRoot.ConnectionState):
			print('Server connection failed: %s' % ServerRoot.get_connection_state_name(s))
	)
	server_root.start_multi_connect(-1)

func _server_connected():
	print('Server connection success')
	var _zone_service: ZoneService = server_root.get_service(ZoneService)
