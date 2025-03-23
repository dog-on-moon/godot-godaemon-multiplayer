@tool
extends Node
## A class which provides typed access to various services within the addon.

const Profiler = preload("res://addons/godaemon_multiplayer/api/profiler.gd")
const Repository = preload("res://addons/godaemon_multiplayer/api/repository.gd")
const RpcInterface = preload("res://addons/godaemon_multiplayer/api/rpc.gd")
const Util = preload("res://addons/godaemon_multiplayer/util/util.gd")

const META_OWNER := &"_o"

## The ID of this project's steam game.
## 480 is the recommended default (SpaceWars)
const STEAM_GAME_ID := 480
const STEAM_ENABLED := true

#region Steam Management

var steam_status := -1
var steam_verbal := ""

func _enter_tree() -> void:
	enable_steam()

func _exit_tree() -> void:
	disable_steam()

func enable_steam():
	if Engine.is_editor_hint() or not STEAM_ENABLED:
		return
	if is_steam_active():
		return
	if OS.has_feature("no_steam") or OS.has_feature("no-steam"):
		return
	var resp := Steam.steamInitEx(false, STEAM_GAME_ID, true)
	steam_status = resp.get("status", 0)
	steam_verbal = resp.get("verbal", "")

func disable_steam():
	if is_steam_active():
		Steam.steamShutdown()

func is_steam_active() -> bool:
	return steam_status == 0

#endregion

#region Node Locators

## The MultiplayerRoot provides access to the connection state of its encapsulated multiplayer tree.
## It also creates all the service nodes within itself.
func mp(node: Node, required := true) -> MultiplayerRoot:
	var _api := api(node, required)
	if not _api:
		return null
	return _api.mp

## Services implement high-level multiplayer logic for different aspects of your game.
func service(node: Node, service: Script, required := true) -> ServiceBase:
	var _mp := mp(node, required)
	if not _mp:
		return null
	return _mp.get_service(service, required)

## The GodaemonMultiplayerAPI establishes a server-authoritative wrapper over SceneMultiplayer.
func api(node: Node, required := true) -> GodaemonMultiplayerAPI:
	if not node.multiplayer or node.multiplayer is not GodaemonMultiplayerAPI:
		assert(not required)
		return null
	return node.multiplayer

## The API profiler allows configuring Godot's network profiler.
func profiler(node: Node, required := true) -> Profiler:
	var _api := api(node, required)
	if not _api:
		return null
	return _api.profiler

## The API repository provides unique IDs for nodes that are shared between all server/clients.
## This can be helpful for serializing node references across RPCs.
func repository(node: Node, required := true) -> Repository:
	var _api := api(node, required)
	if not _api:
		return null
	return _api.repository

## The API's RPC interface exposes useful RPC configuration, such as filters, channel overrides,
## ratelimiting, and disabling RPC forwarding.
func rpcs(node: Node, required := true) -> RpcInterface:
	var _api := api(node, required)
	if not _api:
		return null
	return _api.rpc

## The ReplicationService manages replicated scenes.
## The server can configure scene visibility from the server to clients, along with
## assigning specific scenes "ownership" for a peer (not to be confused with node authority).
func replication_service(node: Node, required := true) -> ReplicationService:
	return service(node, ReplicationService, required)

## The SyncService implements property replication across services for existing replicated scenes.
func sync_service(node: Node, required := true) -> SyncService:
	return service(node, SyncService, required)

## The ZoneService implements a high-level interface on ReplicationService for creating "zones,"
## replicated scenes with separate physic spaces, navigation maps, and visual scenarios.
## Useful for building large, multiplayer overworlds, or for "faking" scene transitions for clients.
func zone_service(node: Node, required := true) -> ZoneService:
	return service(node, ZoneService, required)

## The DatabaseService implements external property storage for objects.
func database_service(node: Node, required := true) -> DatabaseService:
	return service(node, DatabaseService, required)

## A Zone is a replicated scene created by the ZoneService.
func zone(node: Node, required := true) -> Zone:
	assert(not mp(node, required) or mp(node).is_server())
	var zs := zone_service(node, required)
	if not zs:
		return null
	return zs.get_node_zone(node)

## A Zone is a replicated scene created by the ZoneService. (client side)
func client_zone(node: Node, required := true) -> ClientZone:
	assert(not mp(node, required) or mp(node).is_client())
	var zs := zone_service(node, required)
	if not zs:
		return null
	return zs.get_node_zone_cl(node)

## Get the scene of the current zone we are in.
func zone_scene(node: Node, required := true) -> Node:
	if not mp(node, required):
		return null
	if mp(node).is_client():
		return client_zone(node).scene
	return zone(node).scene

#endregion

#region General API

## Returns the owner of a node.
func get_node_owner(node: Node) -> int:
	if node.is_inside_tree():
		while node is not MultiplayerRoot and not node.has_meta(META_OWNER):
			node = node.get_parent()
	return node.get_meta(META_OWNER, 1)

## Checks if we locally own a node.
func is_local_owner(node: Node, required := true) -> bool:
	var _mp := mp(node, required)
	if not _mp:
		return false
	return get_node_owner(node) == _mp.local_peer

## Returns whether or not a given node is replicated.
func is_replicated(node: Node) -> bool:
	return repository(node).is_replicated(node)

## Sets the owner of a node locally.
## If you want this synced to clients, you should maybe go through ReplicationService
func set_node_owner_local(node: Node, owner: int):
	node.set_meta(META_OWNER, owner)

#endregion
