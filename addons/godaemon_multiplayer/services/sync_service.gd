extends ServiceBase
class_name SyncService
## Watches and syncs property changes within replicated scenes.

## The ticks-per-second for updating interpolation fields.
const INTERPOLATE_TPS := 20.0
const INTERPOLATE_MSPT := (1.0 / INTERPOLATE_TPS) * 1000.0
const INTERPOLATE_DURATION := (1.0 / INTERPOLATE_TPS) * 1.54

var replication_service: ReplicationService

var last_interpolate_t := 0.0

## API for requesting a property sync upon changing a node's property value.
func request_sync(node: Node, property: StringName):
	var script := node.get_script()
	if not script:
		assert(false)
		return
	var sr := ReplicationData.get_script_replication(script)
	if not sr:
		assert(false)
		return
	var node_id := mp.api.repository.get_id(node)
	if node_id == -1:
		assert(false)
		return
	var config := sr.get_property_config(String(property))
	if not config:
		assert(false, "Property config %s does not exist for node." % property)
		return
	if config.sync != ReplicationPropertyConfig.Sync.Request:
		assert(false, "Cannot sync property %s -- mode must be set to Request" % property)
		return
	if not config.can_we_send(node):
		assert(false, "Cannot sync property %s -- request is filtered")
		return
	var idx := sr.get_idx_from_property_config(config)
	var value: Variant = node.get(property)
	var target_peers := [1] if mp.is_client() else replication_service.get_observing_peers(node)
	for p in target_peers:
		if config.can_they_recv(node, p):
			_get_receive_rpc(config.reliable).rpc_id(p, node_id, idx, value)

#region Smooth Processing

func _enter_tree() -> void:
	replication_service = Godaemon.replication_service(self)
	
	# Replicate property changes as the last event in the frame.
	process_priority = 100000
	replication_service.enter_replication.connect(_enter_replication)
	replication_service.exit_replication.connect(_exit_replication)

func _enter_replication(node: Node):
	var script := node.get_script()
	if script:
		var sr := ReplicationData.get_script_replication(node.get_script())
		if sr and sr.smooth_properties:
			_config_cache[node] = {}
			for config in sr.smooth_properties:
				_get_new_value(node, config)

func _exit_replication(node: Node):
	_config_cache.erase(node)

var _config_cache := {}

func _get_new_value(node: Node, config: ReplicationPropertyConfig) -> Variant:
	var old_value: Variant = _config_cache[node][config]
	var value: Variant = node.get(config.name)
	if is_equal_approx(old_value, value):
		return null
	else:
		_set_config_cache(node, config, value)
		return value

func _set_config_cache(node: Node, config: ReplicationPropertyConfig, value: Variant):
	_config_cache[node][config] = value

func _process(delta: float) -> void:
	if is_queued_for_deletion():
		return
	
	# Only interpolate on our relevant TPS frames.
	var msec := Time.get_ticks_msec()
	var is_interpolate_frame := msec > (last_interpolate_t + INTERPOLATE_MSPT)
	if not is_interpolate_frame:
		return
	last_interpolate_t = msec
	
	# Review and update the sync for all of our tracked nodes.
	for node in _config_cache:
		# Get its state.
		var sr := ReplicationData.get_script_replication(node.get_script())
		var node_id := mp.api.repository.get_id(node)
		if node_id == -1:
			Log.warning(self, "Could not sync values for node %s: ID missing" % [node])
			return
		
		# Update any properties that have smooth-changed.
		var target_peers := [1] if mp.is_client() else replication_service.get_observing_peers(node)
		for config in sr.smooth_properties:
			if config.can_we_send(node):
				var value := _get_new_value(node, config)
				if value != null:
					var idx := sr.get_idx_from_property_config(config)
					for p in target_peers:
						if config.can_they_recv(node, p):
							_get_receive_rpc(config.reliable).rpc_id(p, node_id, idx, value)

#endregion

#region Receiver Processing

func _get_receive_rpc(reliable: bool) -> Callable:
	if mp.is_server():
		if reliable:
			return _cl_receive_reliable_properties
		else:
			return _cl_receive_unreliable_properties
	else:
		if reliable:
			return _sv_receive_reliable_properties
		else:
			return _sv_receive_unreliable_properties

@rpc
func _cl_receive_reliable_properties(node_id: int, idx: int, value: Variant):
	_receive_properties(node_id, idx, value)

@rpc
func _cl_receive_unreliable_properties(node_id: int, idx: int, value: Variant):
	_receive_properties(node_id, idx, value)

@rpc
func _sv_receive_reliable_properties(node_id: int, idx: int, value: Variant):
	_receive_properties(node_id, idx, value)

@rpc
func _sv_receive_unreliable_properties(node_id: int, idx: int, value: Variant):
	_receive_properties(node_id, idx, value)

func _receive_properties(node_id: int, idx: int, value: Variant):
	var node := mp.api.repository.get_object(node_id)
	if not node:
		#push_warning("SyncService._receive_properties does not know node ID %s" % node_id)
		return
	var script := node.get_script()
	if not script:
		return
	var sr := ReplicationData.get_script_replication(script)
	if not script:
		return
	if idx < 0 or idx >= sr.property_config.size():
		return
	var config := sr.property_config[idx]
	if config.sync == ReplicationPropertyConfig.Sync.Once:
		return
	if config.can_we_recv(node):
		if config.sync == ReplicationPropertyConfig.Sync.Request:
			node.set(config.name, value)
		else:
			_start_property_interpolation(node, config, value)
		_set_config_cache(node, config, value)
	
	# If we're the server, forward the updated properties to other peers.
	if mp.is_server():
		var rpc := _get_receive_rpc(config.reliable)
		for peer in replication_service.get_observing_peers(node):
			if peer == mp.remote_peer:
				continue
			if config.get_robns() and peer == Godaemon.get_node_owner(node):
				continue
			rpc.rpc_id(peer, node_id, idx, value)

#region Interpolation

var _property_interpolation_cache := {}

## For interpolation values, this updates the value cache so they're properly replicated.
func reset_interpolation(scene: Node):
	_cancel_all_property_interpolations(scene)
	# scene.reset_physics_interpolation()

## Begins a property interpolation tween.
func _start_property_interpolation(node: Node, config: ReplicationPropertyConfig, value: Variant):
	_end_property_interpolation(node, config)
	var tween := get_tree().create_tween()
	tween.tween_property(node, config.name, value, INTERPOLATE_DURATION).from_current()
	tween.finished.connect(_end_property_interpolation.bind(node, config))
	var cleanup_callback := _node_exit_in_property_callback.bind(node)
	if not node.tree_exited.is_connected(cleanup_callback):
		node.tree_exited.connect(cleanup_callback, CONNECT_ONE_SHOT)
	_property_interpolation_cache.get_or_add(node, {})[config] = tween

## Kills a property interpolation tween.
func _end_property_interpolation(node: Node, config: ReplicationPropertyConfig):
	if _has_property_interpolation(node, config):
		var tween: Tween = _property_interpolation_cache[node][config]
		tween.pause()
		tween.kill()
		_property_interpolation_cache[node].erase(config)
		# not necessary to clean this up based on what our callers are doing
		#if not _property_interpolation_cache[node]:
			#_property_interpolation_cache.erase(node)

func _cancel_all_property_interpolations(node: Node, update := true):
	var configs: Array[ReplicationPropertyConfig] = []
	if node in _property_interpolation_cache:
		for config: ReplicationPropertyConfig in _property_interpolation_cache[node].keys():
			configs.append(config)
			_end_property_interpolation(node, config)
		_property_interpolation_cache.erase(node)
	if update:
		for c in configs:
			_set_config_cache(node, c, node.get(c.name))

func _node_exit_in_property_callback(node: Node):
	_cancel_all_property_interpolations(node, false)
	_property_interpolation_cache.erase(node)

## Returns true if a property interpolation is active.
func _has_property_interpolation(node: Node, config: ReplicationPropertyConfig) -> bool:
	return node in _property_interpolation_cache and config in _property_interpolation_cache[node]

#endregion

#endregion
