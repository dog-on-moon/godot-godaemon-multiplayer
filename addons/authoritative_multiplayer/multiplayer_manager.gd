extends Node
## An autoload for establishing client/server for authoritative multiplayer.
## This Node contains the complete networking API for developers.

#region Node Overrides
func _enter_tree() -> void:
	_internal_server_enter_tree()

func _process(delta: float) -> void:
	_internal_server_process()

func _exit_tree() -> void:
	_internal_server_exit_tree()
#endregion

#region Connection
enum Domain {
	NONE,
	CLIENT,
	SERVER
}

var domain := Domain.NONE

## Sets up the client multiplayer API.
func setup_client(address: String, port: int, timeout := 5.0) -> bool:
	if domain != Domain.NONE:
		push_warning("MultiplayerManager.setup_client had already established domain")
		return false
	
	# Setup MultiplayerAPI and peer.
	get_tree().set_multiplayer(ClientMultiplayerAPI.new())
	var peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		push_warning("MultiplayerManager.setup_client had error: %s" % error_string(error))
		return false
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		push_warning("MultiplayerManager.setup_client could not create ENetMultiplayer peer")
		return false
	
	# Async wait for connection.
	_client_setup_start_wait(timeout)
	multiplayer.multiplayer_peer = peer
	if _client_setup_connect_result == ClientSetupConnectResult.WAITING:
		await _client_setup_connected
	
	# Based on connect result, return true/false.
	match _client_setup_connect_result:
		ClientSetupConnectResult.CONNECTED:
			if not multiplayer.server_disconnected.is_connected(close_connection):
				multiplayer.server_disconnected.connect(close_connection)
			domain = Domain.CLIENT
			return true
		_:
			peer.close()
			return false

#region Client Setup Async

enum ClientSetupConnectResult { WAITING, CONNECTED, FAILED, DISCONNECTED, TIMEOUT }

signal _client_setup_connected
var _client_setup_connect_result := ClientSetupConnectResult.WAITING
var _client_setup_timer: SceneTreeTimer

func _client_setup_start_wait(timeout: float):
	_client_setup_connect_result = ClientSetupConnectResult.WAITING
	multiplayer.connected_to_server.connect(_client_setup_on_connected)
	multiplayer.server_disconnected.connect(_client_setup_on_disconnected)
	multiplayer.connection_failed.connect(_client_setup_on_failed)
	_client_setup_timer = get_tree().create_timer(timeout)
	_client_setup_timer.timeout.connect(_client_setup_on_timeout)

func _client_setup_on_connected():
	_client_setup_end_wait(ClientSetupConnectResult.CONNECTED)

func _client_setup_on_disconnected():
	_client_setup_end_wait(ClientSetupConnectResult.DISCONNECTED)

func _client_setup_on_failed():
	_client_setup_end_wait(ClientSetupConnectResult.FAILED)

func _client_setup_on_timeout():
	_client_setup_end_wait(ClientSetupConnectResult.TIMEOUT)

func _client_setup_end_wait(result: ClientSetupConnectResult):
	if multiplayer.connected_to_server.is_connected(_client_setup_on_connected):
		multiplayer.connected_to_server.disconnect(_client_setup_on_connected)
	if multiplayer.server_disconnected.is_connected(_client_setup_on_disconnected):
		multiplayer.server_disconnected.disconnect(_client_setup_on_disconnected)
	if multiplayer.connection_failed.is_connected(_client_setup_on_failed):
		multiplayer.connection_failed.disconnect(_client_setup_on_failed)
	if _client_setup_timer:
		if _client_setup_timer.timeout.is_connected(_client_setup_on_timeout):
			_client_setup_timer.timeout.disconnect(_client_setup_on_timeout)
	_client_setup_connect_result = result
	_client_setup_connected.emit()

#endregion

## Sets up the server multiplayer API.
func setup_server(port: int, timeout := 5.0) -> bool:
	if domain != Domain.NONE:
		push_warning("MultiplayerManager.setup_server had already established domain")
		return false
	
	# Setup MultiplayerAPi and peer.
	get_tree().set_multiplayer(ServerMultiplayerAPI.new())
	var peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(port)
	if error != OK:
		push_warning("MultiplayerManager.setup_server had error: %s" % error_string(error))
		return false
	var start_t := Time.get_ticks_msec()
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		await get_tree().process_frame
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			push_warning("MultiplayerManager.setup_server could not create ENetMultiplayer peer")
			return false
		elif (Time.get_ticks_msec() - start_t) > timeout:
			push_warning("Multiplayer.setup_server timed out")
			return false
	multiplayer.multiplayer_peer = peer
	domain = Domain.SERVER
	return true

## Closes the muiltiplayer API.
func close_connection() -> bool:
	if domain != Domain.NONE:
		push_warning("MultiplayerManager.close_connection had no domain")
		return false
	multiplayer.multiplayer_peer.close()
	if multiplayer.server_disconnected.is_connected(close_connection):
		multiplayer.server_disconnected.disconnect(close_connection)
	domain = Domain.NONE
	return true
#endregion

#region Internal Server

## The process ID of a child internal server.
var internal_server_pid := -1

## If we are an internal server, this is the port we are setup with.
var internal_server_port := -1

signal internal_server_closed

func _internal_server_enter_tree():
	var _internal_server_port := -1
	for arg in OS.get_cmdline_user_args():
		if 'internal_server' in arg:
			internal_server_port = arg.split('=')[1].to_int()

func _internal_server_process():
	if internal_server_pid != -1:
		if not OS.is_process_running(internal_server_pid):
			internal_server_closed.emit()
			internal_server_pid = -1

func _internal_server_exit_tree():
	if internal_server_pid != -1:
		destroy_internal_server()

## Creates an internal server, running one as a separate process.
## The loaded scene is responsible for creating the server,
## using the port MultiplayerManager.internal_server_port.
func create_internal_server(scene: PackedScene, port: int, headless := true) -> bool:
	internal_server_pid = OS.create_process(
		OS.get_executable_path(),
		[
			'"%s"' % scene.resource_path.substr(6),
			'--headless' if headless else '',
			'++',
			'--internal_server=%s' % port
		]
	)
	return internal_server_pid != -1

func _setup_internal_server(port: int):
	if not await setup_server(port):
		get_tree().quit()

## Destroys an internal server.
func destroy_internal_server() -> bool:
	if internal_server_pid == -1:
		push_warning("MultiplayerManager.destroy_internal_server had no active PID")
		return false
	OS.kill(internal_server_pid)
	internal_server_closed.emit()
	internal_server_pid = -1
	return true

#endregion

#region Scene Interest

#endregion

#region State Getters
## Returns true if we are a currently connected client.
func is_client() -> bool:
	return domain == Domain.CLIENT

## Returns true if we are a currently connected server.
func is_server() -> bool:
	return domain == Domain.SERVER
#endregion
