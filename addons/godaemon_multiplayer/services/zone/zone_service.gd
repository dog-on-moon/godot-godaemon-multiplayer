extends ServiceBase
class_name ZoneService
## The root node containing Zones in a ClientRoot/ServerRoot.

## Emitted on a client whenever they've received interest for a zone.
signal cl_added_interest(zone: Zone)

## Emitted on a client whenever they've lost interest for a zone.
signal cl_removed_interest(zone: Zone)

## The number of reserved channels we'll use for Zones.
const RESERVED_ZONE_CHANNELS := 32
const RESERVED_ZONE_CHANNELS_HALF := RESERVED_ZONE_CHANNELS / 2

const ZoneSvc = preload("res://addons/godaemon_multiplayer/services/zone/zone_svc.gd")
var svc: SubViewportContainer

var _initial_channel := 0

func _ready() -> void:
	mp.peer_disconnected.connect(_peer_disconnected)
	
	if mp.is_server():
		mp.api.outbound_rpc_target_modifiers.append(_outbound_rpc_target_modifier)
		mp.api.outbound_rpc_filters.append(_rpc_filter)
	mp.api.rpc_channel_modifiers.append(_zone_service_channel_modifier)
	_initial_channel = get_initial_channel(mp)
	
	svc = ZoneSvc.new()
	svc.name = "SVC"
	add_child(svc)

func _peer_disconnected(peer: int):
	if mp.is_server():
		clear_peer_interest(peer)
	peer_to_zones.erase(peer)

#region Service internals

func _zone_service_channel_modifier(channel: int, node: Node, transfer_mode: MultiplayerPeer.TransferMode):
	var zone := get_node_zone(node)
	if zone:
		channel = get_zone_channel(zone, transfer_mode)
	return channel

func _outbound_rpc_target_modifier(from_peer: int, target_peers: Array[int], node: Node, method: StringName, args: Array):
	var zone := get_node_zone(node)
	if zone:
		if target_peers == [0]:
			target_peers.clear()
			for p in zone.interest:
				target_peers.append(p)
		elif not target_peers:
			return
		elif target_peers[0] > 0:
			target_peers.assign(target_peers.filter(func (p: int): return p in zone.interest))
		else:
			var skip_peer: int = -target_peers[0]
			target_peers.assign(target_peers.filter(func (p: int): return p in zone.interest and p != skip_peer))

func _rpc_filter(from_peer: int, to_peer: int, node: Node, method: StringName, args: Array):
	var zone := get_node_zone(node)
	if zone:
		if from_peer != 1 and from_peer not in zone.interest:
			return false
		if to_peer != 1 and to_peer not in zone.interest:
			return false
	return true

## We filter each RPC in a zone to use a dedicated channel.
func get_reserved_channels() -> int:
	return 1 + RESERVED_ZONE_CHANNELS

## Returns the ENet channel ID associated with a Zone.
func get_zone_channel(zone: Zone, transfer_mode := MultiplayerPeer.TransferMode.TRANSFER_MODE_RELIABLE) -> int:
	var channel: int = 1 + _initial_channel + (zones.get(zone, 0) % RESERVED_ZONE_CHANNELS_HALF)
	if transfer_mode == MultiplayerPeer.TransferMode.TRANSFER_MODE_RELIABLE:
		channel += RESERVED_ZONE_CHANNELS_HALF
	return channel

#endregion

#region Zone Management

var CURRENT_ZONE_IDX := 0

## A dictionary mapping zones to a unique index.
var zones := {}

## A dictionary mapping a unique index to each zone.
var zone_index_to_zone := {}

## A dictionary mapping peers to the zones they have interest in.
var peer_to_zones := {}

## Creates a new Zone. You can specify an instantiated scene to be added to it.
## Must be called on the server to function properly.
func add_zone(node: Node) -> Zone:
	assert(mp.is_server())
	assert(node.scene_file_path, "Added zones must be from a PackedScene")
	assert(ReplicationCacheManager.get_index(node.scene_file_path) != -1, "Zone must have scene replication enabled")
	var zone := Zone.new()
	zone.mp = mp
	zone.zone_service = self
	zone.scene = node
	zones[zone] = CURRENT_ZONE_IDX
	zone_index_to_zone[CURRENT_ZONE_IDX] = zone
	zone.name = "Zone%s" % CURRENT_ZONE_IDX
	CURRENT_ZONE_IDX += 1
	zone.add_child(node)
	svc.add_child(zone)
	return zone

## Removes a Zone and frees it. Returns true on successful removal.
func remove_scene(zone: Zone) -> bool:
	assert(mp.is_server())
	if zone not in zones:
		return false
	
	for peer in zone.interest:
		remove_interest(peer, zone)
	
	# Remove zone.
	zone_index_to_zone.erase(zones[zone])
	zones.erase(zone)
	svc.remove_child(zone)
	zone.queue_free()
	return true

#endregion

#region Peer Interest

## Gives interest on a peer to be able to view a Zone.
func add_interest(peer: int, zone: Zone) -> bool:
	assert(mp.is_server())
	if peer in zone.interest:
		push_warning("ZoneService.add_interest peer %s already had interest with %s" % [peer, zone.get_path_to(mp)])
		return false
	
	# Update interest state.
	peer_to_zones.get_or_add(peer, {})[zone] = null
	zone.interest[peer] = null
	
	# Broadcast this information.
	var zone_index: int = zones[zone]
	var _channel := mp.api.get_node_channel(self)
	mp.api.set_node_channel(self, get_zone_channel(zone))
	_target_add_interest.rpc_id(
		peer, ReplicationCacheManager.get_index(zone.scene.scene_file_path), zone_index, zone.interest,
		zone.get_replication_rpc_data(peer, zone.replication_nodes)
	)
	for each_peer_that_cares in zone.interest:
		if each_peer_that_cares == peer:
			continue
		_global_add_interest.rpc_id(each_peer_that_cares, peer, zone_index)
	mp.api.set_node_channel(self, _channel)
	
	zone.interest_added.emit(peer)
	return true

## Removes interest on a peer to be able to view a Zone.
func remove_interest(peer: int, zone: Zone) -> bool:
	assert(mp.is_server())
	if peer not in zone.interest:
		push_warning("ZoneService.add_interest peer %s did not have interest with %s" % [peer, zone.get_path_to(mp)])
		return false
	
	# Update interest state.
	peer_to_zones.get_or_add(peer, {}).erase(zone)
	if peer not in peer_to_zones:
		peer_to_zones.erase(peer)
	zone.interest.erase(peer)
	
	# Broadcast this information.
	var zone_index: int = zones[zone]
	var _channel := mp.api.get_node_channel(self)
	mp.api.set_node_channel(self, get_zone_channel(zone))
	if peer in mp.api.connected_peers:
		_target_remove_interest.rpc_id(peer, zone_index)
	for each_peer_that_cares in zone.interest:
		_global_remove_interest.rpc_id(each_peer_that_cares, peer, zone_index)
	mp.api.set_node_channel(self, _channel)
	
	zone.interest_removed.emit(peer)
	return true

## Determines if a peer has interest.
## (NOTE: When calling on the client, this will only check for zones
## that the client peer shares with the target peer.)
func has_interest(peer: int, zone: Zone) -> bool:
	return zone in peer_to_zones.get(peer, {})

## Clears all interest from a peer, preventing them from viewing any Zone.
func clear_peer_interest(peer: int):
	assert(mp.is_server())
	for zone: Zone in peer_to_zones.get(peer, {}).duplicate():
		remove_interest(peer, zone)

## Emitted on a target client to give them interest.
@rpc()
func _target_add_interest(scene_path_index: int, zone_index: int, current_interest: Dictionary, replication_rpc_data: Dictionary):
	assert(mp.is_client())
	var zone := Zone.new()
	zone.mp = mp
	zone.zone_service = self
	zone.interest = current_interest
	zone.name = "Zone%s" % zone_index
	zones[zone] = zone_index
	zone_index_to_zone[zone_index] = zone
	var node: Node = load(ReplicationCacheManager.get_scene_file_path(scene_path_index)).instantiate()
	zone.scene = node
	zone.add_child(node)
	svc.add_child(zone)
	for peer in zone.interest:
		peer_to_zones.get_or_add(peer, {})[zone] = null
		zone.interest_added.emit(peer)
	zone.set_replication_rpc_data(replication_rpc_data)
	cl_added_interest.emit(zone)
	return zone

## Emitted for all clients (not including the target) to inform them of interest.
@rpc()
func _global_add_interest(peer: int, zone_index: int):
	assert(mp.is_client())
	if zone_index not in zone_index_to_zone:
		push_warning("ZoneService._global_add_interest did not have zone index, bug?")
		return
	var zone: Zone = zone_index_to_zone[zone_index]
	peer_to_zones.get_or_add(peer, {})[zone] = null
	zone.interest[peer] = null
	zone.interest_added.emit(peer)

## Emitted on a target client to remove their interest.
@rpc()
func _target_remove_interest(zone_index: int):
	assert(mp.is_client())
	if zone_index not in zone_index_to_zone:
		push_warning("ZoneService._target_remove_interest did not have zone index, bug?")
		return
	var peer: int = mp.local_peer
	var zone: Zone = zone_index_to_zone[zone_index]
	peer_to_zones.get_or_add(peer, {}).erase(zone)
	if not peer_to_zones[peer]:
		peer_to_zones.erase(peer)
	zone.interest.erase(peer)
	zone.interest_removed.emit(peer)
	cl_removed_interest.emit(zone)
	
	zones.erase(zone)
	zone_index_to_zone.erase(zone_index)
	svc.remove_child(zone)
	zone.queue_free()

## Emitted for all other clients (not including the target) to inform them of lost interest.
@rpc()
func _global_remove_interest(peer: int, zone_index: int):
	assert(mp.is_client())
	if zone_index not in zone_index_to_zone:
		push_warning("ZoneService._global_remove_interest did not have zone index, bug?")
		return
	var zone: Zone = zone_index_to_zone[zone_index]
	peer_to_zones.get_or_add(peer, {}).erase(zone)
	if not peer_to_zones[peer]:
		peer_to_zones.erase(peer)
	zone.interest.erase(peer)
	zone.interest_removed.emit(peer)

#endregion

#region Rendering

## Force updates the render properties for all Zone viewports on the client side.
## This is necessary after changing the render properties on the game window, for example.
func update_render_properties():
	var viewport := get_viewport()
	for zone: Zone in svc.get_children():
		zone.update_render_properties(viewport)

#endregion

#region Getters

## Dictionary between a node and what zone they are in.
var _zone_node_cache := {}

## Gets the Zone that a node is in.
func get_node_zone(node: Node) -> Zone:
	if node in _zone_node_cache:
		return _zone_node_cache[node]
	
	# Recursively iterate to find the zone.
	var tree := node.get_tree()
	if not tree:
		push_warning("ZoneService.get_node_zone(%s) not in tree" % node.get_path_to(mp))
		return null
	var zone: Node = node
	while zone is not Zone and zone != tree.root:
		zone = zone.get_parent()
	
	# Now cache.
	node.tree_exited.connect(func (): _zone_node_cache.erase(node), CONNECT_ONE_SHOT)
	if zone is Zone:
		_zone_node_cache[node] = zone
		return zone
	else:
		_zone_node_cache[node] = null
		return null

#endregion
