class_name Log
## i'm not allowed to feel sorry

enum Level { INFO, WARNING, ERROR }

const LEVEL_NAMES: Dictionary[Level, String] = {
	Level.INFO: 'INFO',
	Level.WARNING: 'WARNING',
	Level.ERROR: 'ERROR',
}

const LEVEL_COLOR: Dictionary[Level, Color] = {
	Level.INFO: 'eeeeee',
	Level.WARNING: 'ffff00',
	Level.ERROR: 'ff0000',
}

const DEFAULT_EDITOR_LEVEL := Level.INFO
const DEFAULT_GAME_LEVEL := Level.WARNING

const PEER_NAME_COLOR := 'cccccc'
const OBJECT_NAME_COLOR := 'ddddff'

static var object_to_level_override: Dictionary[Object, Level] = {}

static func set_object_level(object: Object, level: Level):
	if OS.has_feature("debug"):
		object_to_level_override[object] = level

static func _get_object_level(object: Object) -> Level:
	if object in object_to_level_override:
		return object_to_level_override[object]
	if OS.has_feature("debug"):
		return DEFAULT_EDITOR_LEVEL
	return DEFAULT_GAME_LEVEL

static func _is_loggable(object: Object, level: Level) -> bool:
	return level >= _get_object_level(object) and OS.has_feature("debug")

static func _make_log_message(object: Object, message: String, level: Level) -> String:
	# Get object properties.
	var peer := 0
	var peer_name := ""
	if object is Node and object.multiplayer:
		peer = object.multiplayer.get_unique_id()
		peer_name = peer_name(object, peer)
	
	var message_base: String = ""
	if peer_name:
		message_base += '[color=%s][i](%s)[/i][/color] ' % [PEER_NAME_COLOR, peer_name]
	
	message_base += '[color=%s][%s][/color] [color=%s]%s' % [
		OBJECT_NAME_COLOR, Godaemon.Util.get_object_name(object),
		LEVEL_COLOR[level], message
	]
	
	return message_base

static func peer_name(object: Object, peer: int):
	if object is Node and object.multiplayer and peer != 0:
		var username_service := Godaemon.username_service(object)
		if username_service:
			return str(username_service.get_username(peer))
		else:
			return str(peer)
	return ""

static func info(object: Object, message: String) -> void:
	if _is_loggable(object, Log.Level.INFO):
		print_rich(_make_log_message(object, message, Log.Level.INFO))

static func warning(object: Object, message: String) -> void:
	if _is_loggable(object, Log.Level.WARNING):
		print_rich(_make_log_message(object, message, Log.Level.WARNING))

static func error(object: Object, message: String) -> void:
	if _is_loggable(object, Log.Level.ERROR):
		print_rich(_make_log_message(object, message, Log.Level.ERROR))

static func gay(object: Object, message: String) -> void:
	if _is_loggable(object, Log.Level.INFO):
		print_rich(_make_log_message(object, '[rainbow]%s[/rainbow]' % message, Log.Level.INFO))

static var benchmarks: Dictionary[Object, float] = {}

static func start_benchmark(object: Object) -> void:
	if _is_loggable(object, Log.Level.INFO):
		benchmarks[object] = Time.get_ticks_msec()
		print_rich(_make_log_message(object, '[i]Starting benchmark[/i]', Log.Level.INFO))

static func end_benchmark(object: Object) -> void:
	if _is_loggable(object, Log.Level.INFO) and object in benchmarks:
		var start_t := benchmarks[object]
		var end_t := Time.get_ticks_msec()
		benchmarks.erase(object)
		print_rich(_make_log_message(object, '[i]Benchmark: %s sec[/i]' % ((end_t - start_t) * 0.001), Log.Level.INFO))

static var stepping: Dictionary[Object, int] = {}

static func step(object: Object, message: String, end := false) -> void:
	if _is_loggable(object, Log.Level.INFO):
		if object not in stepping:
			print()
			stepping[object] = 0
		stepping[object] += 1
		print_rich(_make_log_message(object, '[b]#%s[/b] %s' % [stepping[object], message], Log.Level.INFO))
		if end:
			stepping.erase(object)
			print()

static func stack(object: Object) -> void:
	if _is_loggable(object, Log.Level.INFO):
		var stack_msg := ""
		var order := get_stack()
		order.pop_front()
		order.reverse()
		for dict: Dictionary in order:
			# {function:bar, line:12, source:res://script.gd}
			var fname: String = dict.source.get_file().rstrip('.gd')
			var line: int = dict.line
			var function: String = dict.function
			stack_msg += "\n\t[i]=> %s.%s()[/i]" % [fname, function]
		
		print_rich(_make_log_message(object, 'Current stack:%s' % stack_msg, Log.Level.INFO))
