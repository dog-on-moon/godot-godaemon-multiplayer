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
	if not multiplayer.peer_connected.is_connected(client_interest_state_sync_full):
		multiplayer.peer_connected.connect(client_interest_state_sync_full)
	if not multiplayer.peer_disconnected.is_connected(clear_peer_interest):
		multiplayer.peer_disconnected.connect(clear_peer_interest)
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
	if multiplayer.peer_connected.is_connected(client_interest_state_sync_full):
		multiplayer.peer_connected.disconnect(client_interest_state_sync_full)
	if multiplayer.peer_disconnected.is_connected(clear_peer_interest):
		multiplayer.peer_disconnected.disconnect(clear_peer_interest)
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

## Emitted when a peer's interest has been added to a scene.
signal peer_interest_added(peer: int, scene_name: String)

## Emitted when a peer's interest has been removed from a scene.
signal peer_interest_removed(peer: int, scene_name: String)

## A dictionary capturing scene name to arrays of peers with interest.
## Only defined on the server.
var interest := {}

## Registers a scene for potential interest. Must be called on the server.
## Returns the name of the created scene.
func add_scene(packed_scene: PackedScene, scene_name := "") -> String:
	assert(is_server())
	var scene := packed_scene.instantiate()
	if scene_name:
		scene.name = scene_name
	add_child(scene)
	if scene_name:
		scene.name = scene_name
	interest[scene.name] = {}
	return scene.name

## Removes a scene for potential interest.
## Returns true on successful removal.
func remove_scene(scene_name: String) -> bool:
	assert(is_server())
	var scene := get_scene(scene_name)
	if not scene:
		return false
	
	# Clear all peer interest.
	for p in interest[scene_name]:
		remove_interest(p, scene_name)
	interest.erase(scene_name)
	
	# Clear scene.
	remove_child(scene)
	scene.queue_free()
	return true

## Gives interest on a peer to be able to view a scene.
func add_interest(peer: int, scene_name: String) -> bool:
	assert(is_server())
	var scene := get_scene(scene_name)
	if not scene:
		return false
	if scene_name not in interest:
		return false
	if peer in interest[scene_name]:
		return false
	interest[scene_name][peer] = null
	peer_interest_added.emit(peer, scene.name)
	client_interest_state_sync_add(peer, scene.name)
	client_add_interest.rpc_id(peer, scene.scene_file_path, scene.name)
	return true

## Removes interest on a peer to be able to view a scene.
func remove_interest(peer: int, scene_name: String) -> bool:
	assert(is_server())
	var scene := get_scene(scene_name)
	if not scene:
		return false
	if scene_name not in interest:
		return false
	if peer not in interest[scene_name]:
		return false
	interest[scene_name].erase(peer)
	peer_interest_removed.emit(peer, scene.name)
	client_interest_state_sync_remove(peer, scene.name)
	client_remove_interest.rpc_id(peer, scene.name)
	return true

## Clears all interest from a peer.
func clear_peer_interest(peer: int):
	assert(is_server())
	for scene_name in interest:
		if has_interest(peer, scene_name):
			remove_interest(peer, scene_name)

## Called on the client when a zone is added for interest.
@rpc("authority", "call_remote", "reliable")
func client_add_interest(scene_path: String, scene_name: String):
	var scene: Node = load(scene_path).instantiate()
	scene.name = scene_name
	add_child(scene)
	scene.name = scene_name

## Called on the client when a zone is removed for interest.
@rpc("authority", "call_remote", "reliable")
func client_remove_interest(scene_name: String):
	var scene := get_scene(scene_name)
	if not scene:
		return false
	remove_child(scene)
	scene.queue_free()

#region Client Interest State Sync

## Called to one client to sync their interest.
func client_interest_state_sync_full(peer: int):
	rpc_client_interest_state_sync_full.rpc_id(peer, interest)

## Called to all clients to sync their interest state.
func client_interest_state_sync_add(peer: int, scene_name: String):
	rpc_client_interest_state_sync_add.rpc(peer, scene_name)

func client_interest_state_sync_remove(peer: int, scene_name: String):
	rpc_client_interest_state_sync_remove.rpc(peer, scene_name)

## Called to clients to sync their interest.
@rpc("authority", "call_remote", "reliable")
func rpc_client_interest_state_sync_full(_interest: Dictionary):
	interest = _interest
	#for scene_name in interest:
		#for peer in interest[scene_name]:
			#peer_interest_added.emit(peer, scene_name)

@rpc("authority", "call_remote", "reliable")
func rpc_client_interest_state_sync_add(peer: int, scene_name: String):
	interest.get_or_add(scene_name, {})[peer] = null
	peer_interest_added.emit(peer, scene_name)

@rpc("authority", "call_remote", "reliable")
func rpc_client_interest_state_sync_remove(peer: int, scene_name: String):
	interest.get_or_add(scene_name, {}).erase(peer)
	if not interest[scene_name]:
		interest.erase(scene_name)
	peer_interest_removed.emit(peer, scene_name)

#endregion

#endregion

#region Getters
## Returns true if we are a currently connected client.
func is_client() -> bool:
	return domain == Domain.CLIENT

## Returns true if we are a currently connected server.
func is_server() -> bool:
	return domain == Domain.SERVER

## Returns a scene by name.
func get_scene(scene_name: String) -> Node:
	for child in get_children():
		if child.name == scene_name:
			return child
	return null

## Returns the scene name that a Node is in.
func get_scene_name(node: Node) -> String:
	var prev := node
	while node != self and node != get_tree().root:
		prev = node
		node = node.get_parent()
	if node == self and prev != self:
		return prev.name
	return ""

## Return an array of peers who have interest with a given node.
func get_node_interest(node: Node) -> PackedInt32Array:
	var a := PackedInt32Array()
	var scene_name := get_scene_name(node)
	if scene_name:
		## Collect the peers in this specific zone.
		var peer_interest: Array = interest.get(scene_name, {}).keys()
		a.resize(peer_interest.size())
		for idx in peer_interest:
			a[idx] = peer_interest[idx]
		return a
	return a

## Determines if a peer has interest.
func has_interest(peer: int, scene_name: String) -> bool:
	assert(scene_name in interest)
	return peer in interest[scene_name]

## Determines if a peer has interest with a given node.
## Useful for securing server-sided RPCs.
func peer_has_interest(peer: int, node: Node) -> bool:
	var scene_name := get_scene_name(node)
	return has_interest(peer, scene_name)

## Determines if the calling peer has interest in the current zone.
## Useful for securing server-sided RPCs.
func remote_sender_has_interest(node: Node) -> bool:
	var peer := multiplayer.get_remote_sender_id()
	if peer == 1:
		return true
	return peer_has_interest(peer, node)
#endregion
