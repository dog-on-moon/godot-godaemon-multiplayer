@tool
extends MultiplayerRoot
class_name ServerRoot
## The server node for a multiplayer session.
## Establishes a connection with a ClientRoot.

#region Exports

## The port that the server is listening on.
## If the ServerRoot exists in a process that has been created through a
## ClientRoot's internal scene, this will instead use the ClientRoot's port.
@export var port := 27027

@export_group("DTLS Encryption")
## The key used for setting up a DTLS connection.
@export var dtls_key: CryptoKey = null

## The certificate used for the DTLS server.
## [b]Note:[/b] The certificate should include the full certificate chain
## up to the signing CA (certificates file can be concatenated using a general purpose text editor).
@export var dtls_certificate: X509Certificate = null

#endregion

#region Connection

## Attempts a connection to the server.
func start_connection() -> bool:
	# Ensure we are not currently connecting.
	if connection_state in [ConnectionState.WAITING, ConnectionState.CONNECTED]:
		push_warning("ServerRoot.start_connection was still connecting")
		return false
	connection_state = ConnectionState.DISCONNECTED
	
	# Setup MultiplayerAPI and peer.
	var api := GodaemonMultiplayerAPI.new()
	api.mp = self
	api.scene_multiplayer.allow_object_decoding = configuration.allow_object_decoding
	api.scene_multiplayer.auth_timeout = configuration.authentication_timeout
	get_tree().set_multiplayer(api, get_path())
	var peer = ENetMultiplayerPeer.new()
	
	# Setup DTLS.
	## NOTE: this is unused for now
	## https://github.com/godotengine/godot-proposals/issues/10627
	@warning_ignore("unused_variable")
	var server_options: TLSOptions = null
	if configuration.use_dtls_encryption:
		server_options = TLSOptions.server(dtls_key, dtls_certificate)
	
	# Create server connection.
	if get_total_channel_count() > MAX_ENET_CHANNELS:
		push_error("ServerRoot.start_connection exceeded channel limit, max is %s (currently %s)" % [MAX_ENET_CHANNELS, get_total_channel_count()])
		return false
	var error := peer.create_server(
		port, configuration.max_clients, get_total_channel_count(),
		configuration.in_bandwidth, configuration.out_bandwidth
	)
	if error != OK:
		push_warning("ServerRoot.end_connection had error: %s" % error_string(error))
		connection_failed.emit(connection_state)
		return false
	
	var start_t := Time.get_ticks_msec()
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		await get_tree().process_frame
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			push_warning("ServerRoot.setup_server could not create ENetMultiplayer peer")
			connection_failed.emit(connection_state)
			return false
		elif (Time.get_ticks_msec() - start_t) > configuration.connection_timeout:
			push_warning("ServerRoot.setup_server timed out")
			connection_state = ConnectionState.TIMEOUT
			connection_failed.emit(connection_state)
			return false
	
	setup_peer_authenticator()
	api.scene_multiplayer.auth_callback = authenticator.server_receive_auth
	if not api.scene_multiplayer.peer_authenticating.is_connected(authenticator.server_start_auth):
		api.scene_multiplayer.peer_authenticating.connect(authenticator.server_start_auth)
	if not api.peer_connected.is_connected(peer_connected.emit):
		api.peer_connected.connect(peer_connected.emit)
	if not api.peer_disconnected.is_connected(peer_disconnected.emit):
		api.peer_disconnected.connect(peer_disconnected.emit)
	
	api.multiplayer_peer = peer
	api.connected()
	connection_success.emit()
	return true

## Closes the server.
func end_connection() -> bool:
	if connection_state != ConnectionState.CONNECTED:
		push_warning("ServerRoot.end_connection was not connected")
		return false
	connection_state = ConnectionState.DISCONNECTED
	var api: GodaemonMultiplayerAPI = multiplayer
	api.disconnected()
	api.scene_multiplayer.auth_callback = Callable()
	if api.scene_multiplayer.peer_authenticating.is_connected(authenticator.server_start_auth):
		api.scene_multiplayer.peer_authenticating.disconnect(authenticator.server_start_auth)
	if api.peer_connected.is_connected(peer_connected.emit):
		api.peer_connected.disconnect(peer_connected.emit)
	if api.peer_disconnected.is_connected(peer_disconnected.emit):
		api.peer_disconnected.disconnect(peer_disconnected.emit)
	cleanup_peer_authenticator()
	server_disconnected.emit()
	return true

#endregion

func _validate_property(property: Dictionary) -> void:
	if not configuration or not configuration.use_dtls_encryption:
		if property.name in [
			'dtls_key',
			'dtls_certificate',
				]:
			property.usage ^= PROPERTY_USAGE_EDITOR

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not configuration:
		warnings.append("A MultiplayerConfiguration must be defined.")
	elif configuration.use_dtls_encryption:
		warnings.append("DTLS encryption is currently disabled.\nhttps://github.com/godotengine/godot-proposals/issues/10627")
		if not dtls_key:
			warnings.append("dtls_key must be specified for DTLS encryption.")
		if not dtls_certificate:
			warnings.append("dtls_certificate must be specified for DTLS encryption.")
	return warnings
