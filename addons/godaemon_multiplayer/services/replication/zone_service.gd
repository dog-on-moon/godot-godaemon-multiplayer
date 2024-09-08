extends ServiceBase
class_name ZoneService
## The ZoneService provides a simple interface for instantiating high-level game scenes.
##
## Zones provide their own functionality on top of being a replicated scene:
## - Each Zone is contained within a separate Viewport, which separate 2D/3D physics and navigation.
## - Zones use exclusive ENet chnanels for themselves and their children, used for RPCs/replication/synchronization.
## - Peer interest state is replicated to clients within a Zone, so they know who else is present.

## Emitted on a client whenever they've received interest for a zone.
signal cl_added_interest(zone: Zone)

## Emitted on a client whenever they've lost interest for a zone.
signal cl_removed_interest(zone: Zone)

## The number of reserved channels we'll use for Zones.
const RESERVED_ZONE_CHANNELS := 32
const RESERVED_ZONE_CHANNELS_HALF := RESERVED_ZONE_CHANNELS / 2

const ZONE = preload("res://addons/godaemon_multiplayer/services/replication/zone/zone.tscn")
const ZONE_SVC = preload("res://addons/godaemon_multiplayer/services/replication/zone/zone_svc.tscn")
const ZoneSvc = preload("res://addons/godaemon_multiplayer/services/replication/zone/zone_svc.gd")
var svc: SubViewportContainer

@onready var peer_service: PeerService = mp.get_service(PeerService)
@onready var replication_service: ReplicationService = mp.get_service(ReplicationService)
@onready var sync_service: SyncService = mp.get_service(SyncService, false)
@onready var _initial_channel := get_initial_channel(mp)

func _ready() -> void:
	assert(replication_service)
	mp.api.rpc.channel_modifiers.append(_channel_modifier)
	if mp.is_server():
		mp.peer_disconnected.connect(_peer_disconnected)
		svc = ZONE_SVC.instantiate()
		add_child(svc)
		replication_service.set_visibility(svc, true)

func _peer_disconnected(peer: int):
	clear_peer_interest(peer)

#region Service internals

func _channel_modifier(channel: int, node: Node, transfer_mode: MultiplayerPeer.TransferMode):
	if node == replication_service:
		# Newly replicated scenes on the ReplicationService are filtered by the first added node's zone's channel.
		for n in replication_service._rpc_added_nodes + replication_service._rpc_removed_nodes:
			var zone := get_node_zone(n)
			if zone:
				return get_zone_channel(zone, transfer_mode)
	elif sync_service and node == sync_service and sync_service._rpc_scene:
		# Sync RPCs from the SyncService are filtered by their scene's zone's channel.
		var zone := get_node_zone(sync_service._rpc_scene)
		if zone:
			return get_zone_channel(zone, transfer_mode)
	else:
		# RPCs for any node are set to their zone's channel.
		var zone := get_node_zone(node)
		if zone:
			return get_zone_channel(zone, transfer_mode)
	return channel

## We filter each RPC in a zone to use a dedicated channel.
func get_reserved_channels() -> int:
	return 1 + RESERVED_ZONE_CHANNELS

## Returns the ENet channel ID associated with a Zone.
func get_zone_channel(zone: Zone, transfer_mode := MultiplayerPeer.TransferMode.TRANSFER_MODE_RELIABLE) -> int:
	var channel: int = 1 + _initial_channel + (zone.zone_index % RESERVED_ZONE_CHANNELS_HALF)
	if transfer_mode == MultiplayerPeer.TransferMode.TRANSFER_MODE_RELIABLE:
		channel += RESERVED_ZONE_CHANNELS_HALF
	return channel

#endregion

#region Zone Management

var zone_index := 0

## A set of active zones.
## Set on the server and client.
var zones := {}

## Creates a new Zone. You can specify an instantiated scene to be added to it.
## Must be called on the server to function properly.
func add_zone(node: Node) -> Zone:
	assert(mp.is_server())
	assert(node.scene_file_path, "Added zones must be from a PackedScene")
	assert(ReplicationCacheManager.get_index(node.scene_file_path) != -1, "Zone must have scene replication enabled")
	var zone := ZONE.instantiate()
	zone.scene = node
	zone.zone_index = zone_index
	zone_index += 1
	zones[zone] = null
	zone.add_child(node)
	svc.add_child(zone)
	replication_service.set_visibility(zone.scene, true)
	return zone

## Removes a Zone and frees it. Returns true on successful removal.
func remove_scene(zone: Zone) -> bool:
	assert(mp.is_server())
	if zone not in zones:
		return false
	
	for peer in zone.interest:
		remove_interest(peer, zone)
	
	# Remove zone.
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
	
	zone.interest[peer] = null
	zone.interest = zone.interest
	replication_service.set_peer_visibility(zone, peer, true)
	return true

## Removes interest on a peer to be able to view a Zone.
func remove_interest(peer: int, zone: Zone) -> bool:
	assert(mp.is_server())
	if peer not in zone.interest:
		push_warning("ZoneService.add_interest peer %s did not have interest with %s" % [peer, zone.get_path_to(mp)])
		return false
	
	# Update interest state.
	zone.interest.erase(peer)
	zone.interest = zone.interest
	replication_service.set_peer_visibility(zone, peer, false)
	return true

## Determines if a peer has interest.
## (NOTE: When calling on the client, this will only check for zones
## that the client peer shares with the target peer.)
func has_interest(peer: int, zone: Zone) -> bool:
	return peer in zone.interest

## Clears all interest from a peer, preventing them from viewing any Zone.
func clear_peer_interest(peer: int):
	assert(mp.is_server())
	for zone: Zone in zones:
		if has_interest(peer, zone):
			remove_interest(peer, zone)

func local_client_add_interest(zone: Zone):
	zones[zone] = null
	cl_added_interest.emit(zone)

func local_client_remove_interest(zone: Zone):
	zones.erase(zone)
	cl_added_interest.emit(zone)

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
