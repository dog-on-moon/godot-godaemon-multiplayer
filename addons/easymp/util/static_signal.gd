class _signals:
	pass

static var static_signal_id: int = 0

static func make() -> Signal:
	if Engine.is_editor_hint():
		return Signal()
	var signal_name: String = "StaticSignal-%s" % static_signal_id
	var owner_class := _signals as Object
	owner_class.add_user_signal(signal_name)
	static_signal_id += 1
	return Signal(owner_class, signal_name)
