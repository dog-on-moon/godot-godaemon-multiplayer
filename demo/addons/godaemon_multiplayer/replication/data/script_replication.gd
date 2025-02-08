@tool
extends Resource
class_name ScriptReplication
## Stores replication data for a script.

const RPCS = preload("res://addons/godaemon_multiplayer/api/rpc.gd")

signal updated

func emit_updated() -> void:
	updated.emit()

@export var method_config: Array[ReplicationMethodConfig] = []:
	set(x):
		for y in method_config:
			if not y: continue
			if y.updated.is_connected(emit_updated):
				y.updated.disconnect(emit_updated)
		method_config = x
		if method_config.size() > RPCS.MAX_RPC_METHODS:
			push_warning("MethodConfig size has too many methods, not all can be RPCed.")
		for y in method_config:
			if not y: continue
			if not y.updated.is_connected(emit_updated):
				y.updated.connect(emit_updated)
		emit_updated()

@export var property_config: Array[ReplicationPropertyConfig] = []:
	set(x):
		for y in property_config:
			if not y: continue
			if y.updated.is_connected(emit_updated):
				y.updated.disconnect(emit_updated)
		property_config = x
		for y in property_config:
			if not y: continue
			if not y.updated.is_connected(emit_updated):
				y.updated.connect(emit_updated)
		emit_updated()

@export var signal_config: Array[ReplicationSignalConfig] = []:
	set(x):
		for y in signal_config:
			if not y: continue
			if y.updated.is_connected(emit_updated):
				y.updated.disconnect(emit_updated)
		signal_config = x
		for y in signal_config:
			if not y: continue
			if not y.updated.is_connected(emit_updated):
				y.updated.connect(emit_updated)
		emit_updated()

var _method_cache := {}
var _property_cache := {}
var _signal_cache := {}

var _method_config_idx_cache := {}
var _property_config_idx_cache := {}
var _signal_config_idx_cache := {}

var smooth_properties: Array[ReplicationPropertyConfig] = []:
	get:
		if not Engine.is_editor_hint():
			setup_cache()
		return smooth_properties

var _cache_setup := false

func setup_cache():
	if Engine.is_editor_hint():
		return
	if _cache_setup:
		return
	_cache_setup = true
	
	for idx in method_config.size():
		var m := method_config[idx]
		_method_cache[m.name] = m
		_method_config_idx_cache[m] = idx
	
	for idx in property_config.size():
		var m := property_config[idx]
		_property_cache[m.name] = m
		_property_config_idx_cache[m] = idx
		if m.sync == ReplicationPropertyConfig.Sync.Smooth:
			smooth_properties.append(m)
	
	for idx in signal_config.size():
		var m := signal_config[idx]
		_signal_cache[m.name] = m
		_signal_config_idx_cache[m] = idx

func get_method_config(name: String) -> ReplicationMethodConfig:
	if not Engine.is_editor_hint():
		setup_cache()
		return _method_cache.get(name)
	for m in method_config:
		if m.name == name:
			return m
	return null

func has_method_config(c: ReplicationMethodConfig) -> bool:
	if not Engine.is_editor_hint():
		setup_cache()
		return c.name in _method_cache
	return c in method_config

func get_property_config(name: String) -> ReplicationPropertyConfig:
	if not Engine.is_editor_hint():
		setup_cache()
		return _property_cache.get(name)
	for m in property_config:
		if m.name == name:
			return m
	return null

func has_property_config(c: ReplicationPropertyConfig) -> bool:
	if not Engine.is_editor_hint():
		setup_cache()
		return c.name in _property_cache
	return c in property_config

func get_signal_config(name: String) -> ReplicationSignalConfig:
	if not Engine.is_editor_hint():
		setup_cache()
		return _signal_cache.get(name)
	for m in signal_config:
		if m.name == name:
			return m
	return null

func has_signal_config(c: ReplicationSignalConfig) -> bool:
	if not Engine.is_editor_hint():
		setup_cache()
		return c.name in _signal_cache
	return c in signal_config

func get_idx_from_method_config(config: ReplicationMethodConfig) -> int:
	if not Engine.is_editor_hint():
		setup_cache()
		return _method_config_idx_cache.get(config, -1)
	for idx in _method_cache.size():
		if _method_cache[idx] == config:
			return idx
	return -1

func get_method_config_from_idx(idx: int) -> ReplicationMethodConfig:
	if idx < 0 or idx >= method_config.size():
		return null
	return method_config[idx]

func get_idx_from_property_config(config: ReplicationPropertyConfig) -> int:
	if not Engine.is_editor_hint():
		setup_cache()
		return _property_config_idx_cache.get(config, -1)
	for idx in _property_cache.size():
		if _property_cache[idx] == config:
			return idx
	return -1

func get_property_config_from_idx(idx: int) -> ReplicationPropertyConfig:
	if idx < 0 or idx >= property_config.size():
		return null
	return property_config[idx]

func get_idx_from_signal_config(config: ReplicationSignalConfig) -> int:
	if not Engine.is_editor_hint():
		setup_cache()
		return _signal_config_idx_cache.get(config, -1)
	for idx in _signal_cache.size():
		if _signal_cache[idx] == config:
			return idx
	return -1

func get_signal_config_from_idx(idx: int) -> ReplicationSignalConfig:
	if idx < 0 or idx >= signal_config.size():
		return null
	return signal_config[idx]

func serialize(uid: int) -> Dictionary:
	var path := ReplicationData.uid_to_path(uid)
	var d := {
		'methods':    method_config  .map(func (x): return x.serialize()),
		'properties': property_config.map(func (x): return x.serialize()),
		'signals':    signal_config  .map(func (x): return x.serialize()),
	}
	if path and path.length() > 6:
		d._name = path
		var s: Variant = load(path)
		if s and s is Script and s.get_global_name():
			d._class = s.get_global_name()
	return d

static func deserialize(d: Dictionary) -> ScriptReplication:
	var r := ScriptReplication.new()
	if d.has('methods'):
		r.method_config   .assign(d.methods   .map(func (x): return ReplicationMethodConfig.deserialize(x)))
		r.method_config = r.method_config
	if d.has('properties'):
		r.property_config .assign(d.properties.map(func (x): return ReplicationPropertyConfig.deserialize(x)))
		r.property_config = r.property_config
	if d.has('signals'):
		r.signal_config   .assign(d.signals   .map(func (x): return ReplicationSignalConfig.deserialize(x)))
		r.signal_config = r.signal_config
	return r
