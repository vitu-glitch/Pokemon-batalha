class_name CaptureLog
extends RefCounted
## Dated copy of every test capture in ../captures/history/.
## The ones in captures/ are overwritten on every test run; these are never deleted.


static func save(img: Image, capture_name: String) -> void:
	if OS.has_feature("web"):
		return
	var dir := ProjectSettings.globalize_path("res://").path_join("../captures/history")
	DirAccess.make_dir_recursive_absolute(dir)
	var t := Time.get_datetime_dict_from_system()
	var stamp := "%04d-%02d-%02d_%02d%02d%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]
	img.save_png(dir.path_join("%s_%s.png" % [stamp, capture_name]))
