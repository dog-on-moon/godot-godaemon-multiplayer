extends Node

@onready var client_node: ClientNode = $HBoxContainer/ClientNode
@onready var server_node: ServerNode = $HBoxContainer/ServerNode

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
	client_node.attempt_multiple_connects(-1)
	
	server_node.connection_success.connect(func (): print('Server connection success'))
	server_node.connection_failed.connect(
		func (s: ServerNode.ConnectionState):
			print('Server connection failed: %s' % ServerNode.get_connection_state_name(s))
	)
	server_node.attempt_multiple_connects(-1)
