class_name DebugLog
extends RefCounted
## Tagged debug logging: `DebugLog.say("Player", "fired G17")` prints
## "[Player] fired G17" only while `DebugLog.enabled` is true, so normal play
## and test output stay quiet. Turn it on with the command line argument
## `--debug-log` (after `--`), or set `DebugLog.enabled = true` in a test.

static var enabled: bool = OS.get_cmdline_user_args().has("--debug-log")


static func say(tag: String, message: String) -> void:
	if enabled:
		print("[%s] %s" % [tag, message])
