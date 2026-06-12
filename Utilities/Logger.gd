extends Node

var current_log_level = 3  # DEBUG by default

enum LogLevel { ERROR = 0, WARN = 1, INFO = 2, DEBUG = 3 }

func _ready() -> void:
	name = "DebugLogger"


func _log(level: String, message: String) -> void:
	var timestamp = Time.get_ticks_msec()
	print("[%d] %s: %s" % [timestamp, level, message])


func error(msg: String) -> void:
	if current_log_level >= LogLevel.ERROR:
		_log("ERROR", msg)


func warn(msg: String) -> void:
	if current_log_level >= LogLevel.WARN:
		_log("WARN", msg)


func info(msg: String) -> void:
	if current_log_level >= LogLevel.INFO:
		_log("INFO", msg)


func debug(msg: String) -> void:
	if current_log_level >= LogLevel.DEBUG:
		_log("DEBUG", msg)


func set_log_level(level: int) -> void:
	current_log_level = level
