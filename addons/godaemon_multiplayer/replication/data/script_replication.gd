@tool
extends Resource
class_name ScriptReplication
## Stores replication data for a script.

signal updated

@export var method_config: Array[ReplicationMethodConfig] = []:
	set(x):
		for y in method_config:
			if not y: continue
			if y.updated.is_connected(updated.emit):
				y.updated.disconnect(updated.emit)
		method_config = x
		for y in method_config:
			if not y: continue
			if not y.updated.is_connected(updated.emit):
				y.updated.connect(updated.emit)
		updated.emit()

@export var property_config: Array[ReplicationPropertyConfig] = []:
	set(x):
		for y in property_config:
			if not y: continue
			if y.updated.is_connected(updated.emit):
				y.updated.disconnect(updated.emit)
		property_config = x
		for y in property_config:
			if not y: continue
			if not y.updated.is_connected(updated.emit):
				y.updated.connect(updated.emit)
		updated.emit()

@export var signal_config: Array[ReplicationSignalConfig] = []:
	set(x):
		for y in signal_config:
			if not y: continue
			if y.updated.is_connected(updated.emit):
				y.updated.disconnect(updated.emit)
		signal_config = x
		for y in signal_config:
			if not y: continue
			if not y.updated.is_connected(updated.emit):
				y.updated.connect(updated.emit)
		updated.emit()

var _method_cache := {}
var _property_cache := {}
var _signal_cache := {}

func _init() -> void:
	if Engine.is_editor_hint():
		return
	for m in method_config:
		_method_cache[m.name] = m
	for m in property_config:
		_property_cache[m.name] = m
	for m in signal_config:
		_signal_cache[m.name] = m

func get_method_config(name: String) -> ReplicationMethodConfig:
	if not Engine.is_editor_hint():
		return _method_cache.get(name)
	for m in method_config:
		if m.name == name:
			return m
	return null

func get_property_config(name: String) -> ReplicationPropertyConfig:
	if not Engine.is_editor_hint():
		return _property_cache.get(name)
	for m in property_config:
		if m.name == name:
			return m
	return null

func get_signal_config(name: String) -> ReplicationSignalConfig:
	if not Engine.is_editor_hint():
		return _signal_cache.get(name)
	for m in signal_config:
		if m.name == name:
			return m
	return null

func serialize(uid: int) -> Dictionary:
	var path := ReplicationData.uid_to_path(uid)
	var d := {
		'methods':    method_config  .map(func (x): return x.serialize()),
		'properties': property_config.map(func (x): return x.serialize()),
		'signals':    signal_config  .map(func (x): return x.serialize()),
	}
	if path:
		d._name = path
	var s: Variant = load(path)
	if s and s is Script and s.get_global_name():
		d._class = s.get_global_name()
	return d

static func deserialize(d: Dictionary) -> ScriptReplication:
	var r := ScriptReplication.new()
	if d.has('methods'):
		r.method_config   .assign(d.methods   .map(func (x): return ReplicationMethodConfig.deserialize(x)))
	if d.has('properties'):
		r.property_config .assign(d.properties.map(func (x): return ReplicationPropertyConfig.deserialize(x)))
	if d.has('signals'):
		r.signal_config   .assign(d.signals   .map(func (x): return ReplicationSignalConfig.deserialize(x)))
	return r
