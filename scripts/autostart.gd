extends RefCounted
## Start Tobi when the user logs in.
## Windows: a value under the current user's "Run" registry key.
## macOS: a LaunchAgent in ~/Library/LaunchAgents that opens the app.

const APP_ID := "TobiDesktopPet"
const RUN_KEY := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
const MAC_LABEL := "com.odcompany.tobipet"
const LOGIN_ITEM_MARK := "user://autostart_login_item"   # set when the macOS fallback was used


static func supported() -> bool:
	return OS.get_name() in ["Windows", "macOS"]


static func is_enabled() -> bool:
	match OS.get_name():
		"Windows":
			return OS.execute("reg", ["query", RUN_KEY, "/v", APP_ID]) == 0
		"macOS":
			return FileAccess.file_exists(_mac_plist()) or FileAccess.file_exists(LOGIN_ITEM_MARK)
	return false


## Called at launch while autostart is on: points the entry at the app's
## current location in case it was moved. Never adds a second login item.
static func refresh() -> void:
	match OS.get_name():
		"Windows":
			set_enabled(true)
		"macOS":
			var app := _mac_app()
			if FileAccess.file_exists(_mac_plist()) and not "/AppTranslocation/" in app:
				var f := FileAccess.open(_mac_plist(), FileAccess.WRITE)
				if f:
					f.store_string(_mac_plist_text(app))


## Turns autostart on or off. Returns "" on success, otherwise a short
## reason Tobi can say in a speech bubble.
static func set_enabled(on: bool) -> String:
	match OS.get_name():
		"Windows":
			if not on:
				OS.execute("reg", ["delete", RUN_KEY, "/v", APP_ID, "/f"])
				return ""
			var exe := OS.get_executable_path().replace("/", "\\")
			# Godot wraps an argument containing spaces or brackets in quotes but does
			# not escape quotes inside it, so the quotes stored in the value are
			# written as \" (the form Windows' argument parser turns back into ").
			var value := "\\\"%s\\\"" % exe
			var output := []
			var code := OS.execute("reg", ["add", RUN_KEY, "/v", APP_ID, "/t", "REG_SZ", "/d", value, "/f"], output, true)
			if code == 0 and is_enabled():
				return ""
			return "설정하지 못했어요…\n(오류 %d)" % code
		"macOS":
			var path := _mac_plist()
			if not on:
				if FileAccess.file_exists(path):
					DirAccess.remove_absolute(path)
				if FileAccess.file_exists(LOGIN_ITEM_MARK):
					OS.execute("osascript", ["-e", "tell application \"System Events\" to delete login item \"%s\"" % _mac_app().get_file().get_basename()])
					DirAccess.remove_absolute(ProjectSettings.globalize_path(LOGIN_ITEM_MARK))
				return ""
			var app := _mac_app()
			# a quarantined app runs from a random temporary path that disappears
			if "/AppTranslocation/" in app or not app.ends_with(".app"):
				return "응용 프로그램 폴더로\n옮긴 뒤 켜 주세요!"
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f != null:
				f.store_string(_mac_plist_text(app))
				f.close()
				if FileAccess.file_exists(path):
					return ""
			# fall back to a regular Login Item (macOS may ask to allow this once)
			var err := FileAccess.get_open_error()
			var script := "tell application \"System Events\" to make login item at end with properties {path:\"%s\", hidden:false}" % app
			if OS.execute("osascript", ["-e", script]) == 0:
				var mark := FileAccess.open(LOGIN_ITEM_MARK, FileAccess.WRITE)
				if mark:
					mark.store_string(app)
				return ""
			return "설정하지 못했어요…\n(오류 %d)" % err
	return "이 컴퓨터에서는 안 돼요…"


static func _mac_plist() -> String:
	var home := OS.get_environment("HOME")
	if home.is_empty():
		home = "/Users".path_join(OS.get_environment("USER"))
	return home.path_join("Library/LaunchAgents/%s.plist" % MAC_LABEL)


static func _mac_app() -> String:
	var exe := OS.get_executable_path()
	var i := exe.find(".app/")
	return exe.substr(0, i + 4) if i >= 0 else exe


static func _mac_plist_text(app: String) -> String:
	return """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>%s</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>-a</string>
		<string>%s</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
""" % [MAC_LABEL, app.xml_escape()]
