@tool
extends ServerRoot
## A node that is ran as a ServerRoot subprocess, created by a ClientRoot.

const KW_INTERNAL_SERVER_PORT := "_INTERNAL_SERVER_PORT"
const KW_INTERNAL_SERVER_CONFIG_PATH := "_INTERNAL_SERVER_CONFIG_PATH"
const INTERNAL_SERVER_SCENE := "res://addons/godaemon_multiplayer/nodes/internal_server/internal_server.tscn"

@onready var terminal: Control = $Terminal

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if SubprocessServer.parent_pid == -1:
		# ran as a standalone scene, so testing in editor
		SubprocessServer.kwargs = {
			KW_INTERNAL_SERVER_PORT: 27027,
			KW_INTERNAL_SERVER_CONFIG_PATH: "res://demos/test/test_config.tres",
		}
	
	terminal.info('Process kwargs: %s' % SubprocessServer.kwargs)
	
	var port := SubprocessServer.kwargs.get(KW_INTERNAL_SERVER_PORT, 0)
	if not port:
		terminal.error("kwarg %s undefined" % KW_INTERNAL_SERVER_PORT)
		return shutdown()
	
	var config_path := SubprocessServer.kwargs.get(KW_INTERNAL_SERVER_CONFIG_PATH, '')
	if not config_path:
		terminal.error("kwarg %s undefined" % KW_INTERNAL_SERVER_CONFIG_PATH)
		return shutdown()
	
	terminal.info('Loading configuration...')
	configuration = load(config_path)
	if not configuration:
		terminal.error('Configuration resource failed to load.')
		return shutdown()
	terminal.info('Configuration loaded.')
	
	terminal.info('Attempting connection...')
	if not await start_connection():
		terminal.error("Could not connect: %s" % get_connection_state_name(connection_state))
		return shutdown()
	
	terminal.info('Connected on port %s with config %s.' % [port, configuration.resource_path])

func shutdown(instant := false):
	if instant:
		get_tree().quit()
		return
	terminal.error("Shutting down...")
	get_tree().create_timer(5.0).timeout.connect(get_tree().quit)

## Creates an internal server process. Returns the pid, -1 on failure.
static func start_internal_server(port: int, configuration: MultiplayerConfig, headless := true) -> int:
	if KW_INTERNAL_SERVER_PORT in SubprocessServer.kwargs:
		# Realistically speaking, we should avoid a fork bomb
		return false
	var kwargs := {
		KW_INTERNAL_SERVER_PORT: port,
		KW_INTERNAL_SERVER_CONFIG_PATH: configuration.resource_path
	}
	return SubprocessServer.create_subprocess(
		INTERNAL_SERVER_SCENE, kwargs, headless
	)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if self != get_tree().edited_scene_root:
		warnings.append("InternalServer is not meant to be used outside of internal_server.tscn.")
	return warnings
