extends Node

@onready var client_node: ClientNode = $ClientNode
@onready var server_node: ServerNode = $ServerNode

func _ready() -> void:
	client_node.connection_success.connect(func (): print('Client connection success'))
	client_node.connection_failed.connect(
		func (s: ClientNode.ConnectionState):
			print('Client connection failed: %s' % ClientNode.get_connection_state_name(s))
	)
	client_node.server_disconnected.connect(
		func ():
			print('Server disconnected')
	)
	client_node.start_multi_connect(-1)
	
	server_node.connection_success.connect(_server_connected)
	server_node.connection_failed.connect(
		func (s: ServerNode.ConnectionState):
			print('Server connection failed: %s' % ServerNode.get_connection_state_name(s))
	)
	server_node.start_multi_connect(-1)

func _server_connected():
	print('Server connection success')
	var _zone_service: ZoneService = server_node.get_service(ZoneService)
