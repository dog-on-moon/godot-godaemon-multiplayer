@tool
extends MultiplayerRoot
class_name ClientRoot
## The client node for a multiplayer session.
## Establishes a connection with a ServerRoot.

var enet_address := "127.0.0.1"  # ip address
var enet_port := 27027  # ip port
var enet_local_port := 0  # useful for some NAT traversal techniques

var steam_id := 0  # target steam ID
var steam_port := 0  # target steam port
var steam_loopback_server: ServerRoot  # adjacent loopback server for connecting

#region Connection

## Configures the connection to use the ENet implementation.
func configure_enet(address := "127.0.0.1", port := 27027, local_port := 0):
	connection_config = ConnectionConfig.ENet
	enet_address = address
	enet_port = port
	enet_local_port = local_port

## Configures the connection to use a Steam implementation.
## Note that if Steam is inactive, ENet will be used as a fallback.
func configure_steam(_steam_id: int, port := 0):
	connection_config = ConnectionConfig.Steam
	steam_id = _steam_id
	steam_port = port
	steam_loopback_server = null

## Configures the connection to use a Steam loopback connection.
## Note that if Steam is inactive, ENet will be used as a fallback.
func configure_steam_loopback(server: ServerRoot):
	connection_config = ConnectionConfig.Steam
	steam_id = 0
	steam_port = 0
	steam_loopback_server = server

## Attempts a connection to the server.
func start_connection() -> bool:
	if connection_config == ConnectionConfig.None:
		assert(false, "ClientRoot must be configured before connection begins")
		return false
	# Ensure we are not currently connecting.
	if connection_state in [ConnectionState.WAITING, ConnectionState.AUTHENTICATING, ConnectionState.CONNECTED]:
		push_warning("ClientRoot.attempt_connect was still connecting")
		return false
	connection_state = ConnectionState.DISCONNECTED
	
	# Setup GodaemonMultiplayerAPI and peer.
	var api := GodaemonMultiplayerAPI.new()
	api.mp = self
	api.scene_multiplayer.allow_object_decoding = false
	api.scene_multiplayer.auth_timeout = configuration.authentication_timeout
	get_tree().set_multiplayer(api, get_path())
	
	var peer: MultiplayerPeer
	var error: Error
	if connection_config == ConnectionConfig.Steam:
		if not Godaemon.is_steam_active():
			push_warning("ServerRoot.start_connection could not start steam connection")
			return false
		var steam_peer := SteamMultiplayerPeer.new()
		peer = steam_peer
		if not steam_loopback_server:
			error = steam_peer.create_client(steam_id, steam_port)
		else:
			var host_peer: SteamMultiplayerPeer = steam_loopback_server.multiplayer.multiplayer_peer
			if host_peer:
				error = steam_peer.create_loopback_client(host_peer)
			else:
				assert(false)
				error = ERR_CANT_CONNECT
	else:
		var enet_peer := ENetMultiplayerPeer.new()
		peer = enet_peer
		
		# Create client connection.
		if get_total_channel_count() > MAX_ENET_CHANNELS:
			push_error("ClientRoot.start_connection exceeded channel limit, max is %s (currently %s)" % [MAX_ENET_CHANNELS, get_total_channel_count()])
			return false
		error = enet_peer.create_client(
			enet_address, enet_port, get_total_channel_count(),
			configuration.client_in_bandwidth, configuration.client_out_bandwidth,
			enet_local_port
		)
	if error != OK:
		push_warning("ClientRoot.attempt_connect had error: %s" % error_string(error))
		connection_failed.emit(connection_state)
		return false
	
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		push_warning("ClientRoot.attempt_connect could not create peer")
		connection_failed.emit(connection_state)
		return false
	
	# Async wait for connection.
	connection_state = ConnectionState.WAITING
	_start_connect_await()
	multiplayer.multiplayer_peer = peer
	if connection_state == ConnectionState.WAITING:
		await _connect_await_end
	
	# Based on connect result, return true/false.
	match connection_state:
		ConnectionState.CONNECTED:
			if not multiplayer.server_disconnected.is_connected(end_connection):
				multiplayer.server_disconnected.connect(end_connection)
			if not multiplayer.peer_disconnected.is_connected(_on_client_peer_disconnect):
				multiplayer.peer_disconnected.connect(_on_client_peer_disconnect)
			if not multiplayer.peer_connected.is_connected(peer_connected.emit):
				multiplayer.peer_connected.connect(peer_connected.emit)
			if not multiplayer.peer_disconnected.is_connected(peer_disconnected.emit):
				multiplayer.peer_disconnected.connect(peer_disconnected.emit)
			api.connected()
			connection_success.emit()
			return true
		_:
			peer.close()
			connection_failed.emit(connection_state)
			return false

#region Client Async Connect

signal _connect_await_end
var _client_setup_timer: SceneTreeTimer

func _start_connect_await():
	var api: GodaemonMultiplayerAPI = multiplayer
	setup_peer_authenticator()
	api.connected_to_server.connect(_connect_await_result_connected)
	api.server_disconnected.connect(_connect_await_result_disconnected)
	api.connection_failed.connect(_connect_await_result_failed)
	api.scene_multiplayer.auth_callback = func (id: int, data: PackedByteArray):
		if id == 1:
			authenticator.client_receive_auth(data)
	api.scene_multiplayer.peer_authenticating.connect(_connect_await_result_authentication)
	api.scene_multiplayer.peer_authentication_failed.connect(_connect_await_result_authentication_failed)
	_client_setup_timer = get_tree().create_timer(configuration.connection_timeout)
	_client_setup_timer.timeout.connect(_connect_await_result_timeout)

func _connect_await_result_connected():
	_connect_await_result(ConnectionState.CONNECTED)

func _connect_await_result_disconnected():
	_connect_await_result(ConnectionState.DISCONNECTED)

func _connect_await_result_failed():
	_connect_await_result(ConnectionState.DISCONNECTED)

func _connect_await_result_timeout():
	if connection_state == ConnectionState.AUTHENTICATING:
		# we reached authentication, so we're on auth timeout now
		return
	_connect_await_result(ConnectionState.TIMEOUT)

func _connect_await_result_authentication(id: int):
	if id == 1:
		connection_state = ConnectionState.AUTHENTICATING
	authenticator.client_start_auth()

func _connect_await_result_authentication_failed(id: int):
	if id == 1:
		_connect_await_result(ConnectionState.AUTH_TIMEOUT)

func _connect_await_result(state: ConnectionState):
	var api: GodaemonMultiplayerAPI = multiplayer
	if api.connected_to_server.is_connected(_connect_await_result_connected):
		api.connected_to_server.disconnect(_connect_await_result_connected)
	if api.server_disconnected.is_connected(_connect_await_result_disconnected):
		api.server_disconnected.disconnect(_connect_await_result_disconnected)
	if api.connection_failed.is_connected(_connect_await_result_failed):
		api.connection_failed.disconnect(_connect_await_result_failed)
	api.scene_multiplayer.auth_callback = Callable()
	if api.scene_multiplayer.peer_authenticating.is_connected(_connect_await_result_authentication):
		api.scene_multiplayer.peer_authenticating.disconnect(_connect_await_result_authentication)
	if api.scene_multiplayer.peer_authentication_failed.is_connected(_connect_await_result_authentication_failed):
		api.scene_multiplayer.peer_authentication_failed.disconnect(_connect_await_result_authentication_failed)
	if _client_setup_timer:
		if _client_setup_timer.timeout.is_connected(_connect_await_result_timeout):
			_client_setup_timer.timeout.disconnect(_connect_await_result_timeout)
		_client_setup_timer = null
	cleanup_peer_authenticator()
	connection_state = state
	_connect_await_end.emit()

#endregion

## Ends an active connection with the ServerRoot.
func end_connection() -> bool:
	if connection_state != ConnectionState.CONNECTED:
		push_warning("ClientRoot.end_connection was not connected")
		return false
	connection_state = ConnectionState.DISCONNECTED
	var api: GodaemonMultiplayerAPI = multiplayer
	api.disconnected()
	if api.server_disconnected.is_connected(end_connection):
		api.server_disconnected.disconnect(end_connection)
	if api.peer_disconnected.is_connected(_on_client_peer_disconnect):
		api.peer_disconnected.disconnect(_on_client_peer_disconnect)
	if api.peer_connected.is_connected(peer_connected.emit):
		api.peer_connected.disconnect(peer_connected.emit)
	if api.peer_disconnected.is_connected(peer_disconnected.emit):
		api.peer_disconnected.disconnect(peer_disconnected.emit)
	server_disconnected.emit()
	return true

func _on_client_peer_disconnect(peer: int):
	# Forces a disconnection whenever the server peer disconencts
	if connection_state == ConnectionState.CONNECTED and peer == 1:
		end_connection()

#endregion

#region Getters

func is_client() -> bool:
	return true

#endregion

func _validate_property(property: Dictionary) -> void:
	if property.name in [
		'stretch'
			]:
		property.usage ^= PROPERTY_USAGE_EDITOR

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not configuration:
		warnings.append("A MultiplayerConfiguration must be defined.")
	return warnings
