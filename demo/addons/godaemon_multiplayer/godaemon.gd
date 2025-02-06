class_name Godaemon
## A static class which provides typed access to various services within the addon.

const Profiler = preload("res://addons/godaemon_multiplayer/api/profiler.gd")
const Repository = preload("res://addons/godaemon_multiplayer/api/repository.gd")
const RpcInterface = preload("res://addons/godaemon_multiplayer/api/rpc.gd")
const Util = preload("res://addons/godaemon_multiplayer/util/util.gd")

const META_OWNER := &"_o"

## The MultiplayerRoot provides access to the connection state of its encapsulated multiplayer tree.
## It also creates all the service nodes within itself.
static func mp(node: Node, required := true) -> MultiplayerRoot:
	var _api := api(node, required)
	if not _api:
		return null
	return _api.mp

## Services implement high-level multiplayer logic for different aspects of your game.
static func service(node: Node, service: Script, required := true) -> ServiceBase:
	var _mp := mp(node, required)
	if not _mp:
		return null
	return _mp.get_service(service, required)

## The GodaemonMultiplayerAPI establishes a server-authoritative wrapper over SceneMultiplayer.
static func api(node: Node, required := true) -> GodaemonMultiplayerAPI:
	if not node.multiplayer or node.multiplayer is not GodaemonMultiplayerAPI:
		assert(not required)
		return null
	return node.multiplayer

## The API profiler allows configuring Godot's network profiler.
static func profiler(node: Node, required := true) -> Profiler:
	var _api := api(node, required)
	if not _api:
		return null
	return _api.profiler

## The API repository provides unique IDs for nodes that are shared between all server/clients.
## This can be helpful for serializing node references across RPCs.
static func repository(node: Node, required := true) -> Repository:
	var _api := api(node, required)
	if not _api:
		return null
	return _api.repository

## The API's RPC interface exposes useful RPC configuration, such as filters, channel overrides,
## ratelimiting, and disabling RPC forwarding.
static func rpcs(node: Node, required := true) -> RpcInterface:
	var _api := api(node, required)
	if not _api:
		return null
	return _api.rpc

## The ReplicationService manages replicated scenes.
## The server can configure scene visibility from the server to clients, along with
## assigning specific scenes "ownership" for a peer (not to be confused with node authority).
static func replication_service(node: Node, required := true) -> ReplicationService:
	return service(node, ReplicationService, required)

## The SyncService implements property replication across services for existing replicated scenes.
static func sync_service(node: Node, required := true) -> SyncService:
	return service(node, SyncService, required)

## The ZoneService implements a high-level interface on ReplicationService for creating "zones,"
## replicated scenes with separate physic spaces, navigation maps, and visual scenarios.
## Useful for building large, multiplayer overworlds, or for "faking" scene transitions for clients.
static func zone_service(node: Node, required := true) -> ZoneService:
	return service(node, ZoneService, required)

## A Zone is a replicated scene created by the ZoneService.
static func zone(node: Node, required := true) -> Zone:
	assert(not mp(node, required) or mp(node).is_server())
	var zs := zone_service(node, required)
	if not zs:
		return null
	return zs.get_node_zone(node)

## A Zone is a replicated scene created by the ZoneService. (client side)
static func client_zone(node: Node, required := true) -> ClientZone:
	assert(not mp(node, required) or mp(node).is_client())
	var zs := zone_service(node, required)
	if not zs:
		return null
	return zs.get_node_zone_cl(node)

## Get the scene of the current zone we are in.
static func zone_scene(node: Node, required := true) -> Node:
	if not mp(node, required):
		return null
	if mp(node).is_client():
		return client_zone(node).scene
	return zone(node).scene

## Returns the owner of a node.
static func get_node_owner(node: Node) -> int:
	if node.is_inside_tree():
		while node is not MultiplayerRoot and not node.has_meta(META_OWNER):
			node = node.get_parent()
	return node.get_meta(META_OWNER, 1)

## Checks if we locally own a node.
static func is_local_owner(node: Node, required := true) -> bool:
	var _mp := mp(node, required)
	if not _mp:
		return false
	return get_node_owner(node) == _mp.local_peer

## Returns whether or not a given node is replicated.
func is_replicated(node: Node) -> bool:
	return repository(node).is_replicated(node)
