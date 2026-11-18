extends RefCounted
## Start Tobi when the user logs in.
## Windows: a value under the current user's "Run" registry key.
## macOS: a LaunchAgent in ~/Library/LaunchAgents that opens the app.

const APP_ID := "TobiDesktopPet"
const RUN_KEY := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
const MAC_LABEL := "com.odcompany.tobipet"


static func supported() -> bool:
	return OS.get_name() in ["Windows", "macOS"]


static func is_enabled() -> bool:
	match OS.get_name():
		"Windows":
			return OS.execute("reg", ["query", RUN_KEY, "/v", APP_ID]) == 0
		"macOS":
			return FileAccess.file_exists(_mac_plist())
	return false


## Turns autostart on or off. Returns "" on success, otherwise a short
## reason Tobi can say in a speech bubble.
static func set_enabled(on: bool) -> String:
	match OS.get_name():
		"Windows":
			if not on:
				OS.execute("reg", ["delete", RUN_KEY, "/v", APP_ID, "/f"])
				return ""
			var exe := OS.get_executable_path().replace("/", "\\")
			var code := OS.execute("reg", ["add", RUN_KEY, "/v", APP_ID, "/t", "REG_SZ", "/d", "\"%s\"" % exe, "/f"])
			return "" if code == 0 else "설정하지 못했어요…"
		"macOS":
			var path := _mac_plist()
			if not on:
				if FileAccess.file_exists(path):
					DirAccess.remove_absolute(path)
				return ""
			var app := _mac_app()
			# a quarantined app runs from a random temporary path that disappears
			if "/AppTranslocation/" in app or not app.ends_with(".app"):
				return "응용 프로그램 폴더로\n옮긴 뒤 켜 주세요!"
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f == null:
				return "설정하지 못했어요…"
			f.store_string(_mac_plist_text(app))
			f.close()
			return ""
	return "이 컴퓨터에서는 안 돼요…"


static func _mac_plist() -> String:
	return OS.get_environment("HOME").path_join("Library/LaunchAgents/%s.plist" % MAC_LABEL)


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
