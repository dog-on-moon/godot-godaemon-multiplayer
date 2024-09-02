extends Node
## An autoload for creating/accessing state of subprocesses.

const KW_PARENT_PID := "_PARENT_PID"

## Emitted when one of our subprocesses has closed.
signal subprocess_closed(pid: int)

## The PIDs of each of our subprocesses.
var subprocesses: Array[int] = []

## Kwargs passed in via cmdline user arguments.
var kwargs := {}

## Returns the parent pid, if there is one defined.
var parent_pid: int:
	get: return kwargs.get(KW_PARENT_PID, -1)

func _process(delta: float) -> void:
	# End references to any of our subprocesses if they have closed.
	for pid in subprocesses.duplicate():
		if pid != -1:
			if not OS.is_process_running(pid):
				subprocesses.erase(pid)
				subprocess_closed.emit(pid)
	
	# If our parent PID dies, we should die too.
	if parent_pid != -1:
		if not OS.is_process_running(parent_pid):
			get_tree().quit()

func _enter_tree():
	for arg in OS.get_cmdline_user_args():
		if '=' in arg:
			kwargs[arg.get_slice('=', 0)] = arg.split('=', true, 1)[1]
		else:
			kwargs[arg] = null

func _exit_tree() -> void:
	kill_all_subprocesses()

## Creates a subprocess running a packed scene.
## Returns the process id on success, -1 on failure.
func create_subprocess(scene_path: String, user_kwargs := {}, headless := true, child_processes_can_fork := false) -> int:
	# Validate user_kwargs.
	assert(KW_PARENT_PID not in user_kwargs)
	
	# Prevent child processes from forking.
	if parent_pid != -1 and not child_processes_can_fork:
		return -1
	
	# Create process arguments.
	var args = [
		'"%s"' % scene_path.trim_prefix('res://'),
		'--headless' if headless else '',
		'++'
	]
	for kw in user_kwargs:
		var result = user_kwargs[kw]
		if result == null:
			args.append('--%s' % kw)
		else:
			args.append('--%s=%s' % [kw, result])
	
	# Attempt process creation.
	var pid = OS.create_process(OS.get_executable_path(), args)
	if pid != -1:
		subprocesses.append(pid)
		return pid
	else:
		return -1

## Kills all subprocesses.
func kill_all_subprocesses():
	for pid in subprocesses.duplicate():
		kill_subprocess(pid)

## Kills a given subprocess.
func kill_subprocess(pid: int) -> bool:
	if pid not in subprocesses:
		push_warning("subprocesseserver.kill_subprocess pid was not found")
		return false
	OS.kill(pid)
	subprocesses.erase(pid)
	subprocess_closed.emit(pid)
	return true
