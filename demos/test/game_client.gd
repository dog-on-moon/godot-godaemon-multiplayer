@tool
extends ClientNode

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	server_disconnected.connect(_server_disconnected)
	
	print("Client initialized")
	while not await attempt_connect():
		print('Connection failed: %s. Attempting reconnect.' % get_connection_state_name(connection_state))
	print('Client setup')

func _server_disconnected():
	print('Server disconnected')
	get_tree().quit()
