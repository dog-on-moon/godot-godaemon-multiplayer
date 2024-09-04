@tool
extends MultiplayerNode
class_name ClientNode
## The client node for a multiplayer session.
## Establishes a connection with a ServerNode.

#region Exports

## A fully qualified domain name (e.g. "www.example.com")
## or an IP address in IPv4 or IPv6 format (e.g. "192.168.1.1")
## that the server is hosting on.
@export var address := "127.0.0.1":
	get:
		return address if not use_internal_server else "127.0.0.1"

## The port that the server is listening on.
@export var port := 27027

@export_group("DTLS Encryption")
## The hostname which the server certificate is validated against.
@export var dtls_hostname := ""

## A custom trusted_chain of certification authorities
## (the default CA list will be used if null).
@export var dtls_trusted_chain: X509Certificate = null

## If you expect the certificate to have a common name other than the server FQDN,
## you can specify an override here.
@export var dtls_common_name_override := ""

## Determines if we should create an unsafe DTLS client, bypassing certificate verification.
## [b]Using this for anything other than testing is not recommended.[/b]
@export var dtls_unsafe_client := false:
	set(x):
		dtls_unsafe_client = x
		update_configuration_warnings()
	get:
		if OS.has_feature('release') and not Engine.is_editor_hint():
			return false
		return dtls_unsafe_client

@export_group("Internal Server")
#region

## When true, connection attempts will also setup an additional process
## for running an internal server. This process will contain user arguments
## in its creation which define the existence of an internal server.
@export var use_internal_server := false:
	set(x):
		use_internal_server = x
		update_configuration_warnings()
		notify_property_list_changed()

## When true, the internal server will run as a background process (headless).
@export var headless_internal_server := true

#endregion

@export_group("Advanced")
#region

## When specified, the client will also listen to the given port.
## This is useful for some NAT traversal techniques. Only for the brave.
@export var local_port := 0

#endregion

#endregion

#region Connection

## Attempts a connection to the server.
func start_connection() -> bool:
	# Ensure we are not currently connecting.
	if connection_state in [ConnectionState.WAITING, ConnectionState.AUTHENTICATING, ConnectionState.CONNECTED]:
		push_warning("ClientNode.attempt_connect was still connecting")
		return false
	connection_state = ConnectionState.DISCONNECTED
	
	# Attempt creating an internal server.
	if not _start_internal_server():
		push_warning("ClientNode.attempt_connect could not make internal server")
		connection_failed.emit(connection_state)
		return false
	
	# Setup GodaemonMultiplayer and peer.
	var api := GodaemonMultiplayer.new()
	api.multiplayer_node = self
	api.scene_multiplayer.allow_object_decoding = configuration.allow_object_decoding
	api.scene_multiplayer.auth_timeout = configuration.authentication_timeout
	get_tree().set_multiplayer(api, get_path())
	var peer = ENetMultiplayerPeer.new()
	
	# Setup DTLS.
	## NOTE: this is unused for now
	## https://github.com/godotengine/godot-proposals/issues/10627
	@warning_ignore("unused_variable")
	var client_options: TLSOptions = null
	if configuration.use_dtls_encryption:
		assert(dtls_hostname)
		if not dtls_unsafe_client:
			client_options = TLSOptions.client(dtls_trusted_chain, dtls_common_name_override)
		else:
			client_options = TLSOptions.client_unsafe()
	
	# Create client connection.
	var error := peer.create_client(
		address, port, get_total_channel_count(),
		configuration.in_bandwidth, configuration.out_bandwidth,
		local_port
	)
	if error != OK:
		push_warning("ClientNode.attempt_connect had error: %s" % error_string(error))
		_end_internal_server()
		connection_failed.emit(connection_state)
		return false
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		push_warning("ClientNode.attempt_connect could not create ENetMultiplayer peer")
		_end_internal_server()
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
			connection_success.emit()
			return true
		_:
			peer.close()
			connection_failed.emit(connection_state)
			_end_internal_server()
			return false

#region Client Async Connect

signal _connect_await_end
var _client_setup_timer: SceneTreeTimer

func _start_connect_await():
	var api: GodaemonMultiplayer = multiplayer
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
	var api: GodaemonMultiplayer = multiplayer
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

## Ends an active connection with the ServerNode.
func end_connection() -> bool:
	if connection_state != ConnectionState.CONNECTED:
		push_warning("ClientNode.end_connection was not connected")
		return false
	connection_state = ConnectionState.DISCONNECTED
	var api: GodaemonMultiplayer = multiplayer
	api.multiplayer_peer.close()
	api.multiplayer_node = null
	if api.server_disconnected.is_connected(end_connection):
		api.server_disconnected.disconnect(end_connection)
	if api.peer_disconnected.is_connected(_on_client_peer_disconnect):
		api.peer_disconnected.disconnect(_on_client_peer_disconnect)
	if api.peer_connected.is_connected(peer_connected.emit):
		api.peer_connected.disconnect(peer_connected.emit)
	if api.peer_disconnected.is_connected(peer_disconnected.emit):
		api.peer_disconnected.disconnect(peer_disconnected.emit)
	server_disconnected.emit()
	_end_internal_server()
	return true

func _on_client_peer_disconnect(peer: int):
	# Forces a disconnection whenever the server peer disconencts
	if connection_state == ConnectionState.CONNECTED and peer == 1:
		end_connection()

#endregion

#region Internal Server

## The process ID of the internal server.
var internal_server_pid := -1

# Attempts to create the internal server.
# Note that this returns TRUE even when internal server is disabled
# (since it technically didn't fail!)
func _start_internal_server() -> bool:
	if use_internal_server:
		internal_server_pid = InternalServer.start_internal_server(
			port, configuration, headless_internal_server
		)
		if internal_server_pid == -1:
			return false
	return true

func _end_internal_server():
	if internal_server_pid != -1:
		SubprocessServer.kill_subprocess(internal_server_pid)

#endregion

#region Getters

func is_client() -> bool:
	return true

#endregion

func _validate_property(property: Dictionary) -> void:
	if not configuration or not configuration.use_dtls_encryption:
		if property.name in [
			'DTLS Configuration',
			'dtls_hostname',
			'dtls_trusted_chain',
			'dtls_common_name_override',
			'dtls_unsafe_client',
				]:
			property.usage ^= PROPERTY_USAGE_EDITOR
	if not use_internal_server:
		if property.name in [
			'internal_server_scene',
			'headless_internal_server'
				]:
			property.usage ^= PROPERTY_USAGE_EDITOR
	else:
		if property.name in ['address']:
			property.usage ^= PROPERTY_USAGE_EDITOR
	if property.name in [
		'stretch'
			]:
		property.usage ^= PROPERTY_USAGE_EDITOR

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not configuration:
		warnings.append("A MultiplayerConfiguration must be defined.")
	else:
		if configuration.use_dtls_encryption:
			warnings.append("DTLS encryption is currently disabled.\nhttps://github.com/godotengine/godot-proposals/issues/10627")
			if dtls_unsafe_client:
				warnings.append("dtls_unsafe_client is currently enabled. This is for testing only. It will be disabled in release builds.")
			if not dtls_hostname:
				warnings.append("dtls_hostname must be specified for DTLS encryption.")
			if use_internal_server:
				warnings.append("DTLS encryption is not supported with internal servers.")
		if use_internal_server and configuration.resource_path.contains('::'):
			warnings.append("The MultiplayerConfiguration must be saved as a unique resource for use in an internal server.")
	return warnings
