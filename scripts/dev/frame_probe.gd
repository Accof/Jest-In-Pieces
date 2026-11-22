extends Node
## Dev: measures frame times while you play and prints a summary: the machine,
## the renderer, the window, average fps, the 1% low, the worst frame, how many
## frames went over 16.7 ms (a dropped 60 fps frame) and over 33 ms (a hitch).
## Used by scenes/legacy_drowned_trenches.tscn (`perf=SECONDS`) to record the
## baseline on the real target machine (Operation Drowned Front, D-10).
##
## The first `warmup` seconds are ignored (shaders compiling, the floor
## settling). After `seconds` of play it prints once (and again every
## `seconds` after that, so a long session gives several readings).

var seconds := 30.0
var warmup := 4.0
var label := ""
var _t := 0.0
var _frames := PackedFloat32Array()
var _reports := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_t += delta
	if _t < warmup:
		return
	_frames.append(delta * 1000.0)
	if _t >= warmup + seconds * (_reports + 1):
		report()


func report() -> void:
	_reports += 1
	if _frames.size() < 10:
		return
	var sorted := _frames.duplicate()
	sorted.sort()
	var n := sorted.size()
	var sum := 0.0
	var over16 := 0
	var over33 := 0
	for ms in sorted:
		sum += ms
		if ms > 16.7:
			over16 += 1
		if ms > 33.0:
			over33 += 1
	var avg := sum / n
	var p99 := sorted[mini(int(n * 0.99), n - 1)]        # the 1% worst frame time
	var p50 := sorted[n / 2]
	var worst := sorted[n - 1]
	var win := DisplayServer.window_get_size()
	print("PERF %s #%d: %d frames over %.0f s | avg %.1f fps (%.2f ms) | median %.2f ms | 1%% low %.1f fps (%.1f ms) | worst %.1f ms | >16.7 ms: %d (%.1f%%) | >33 ms: %d" % [
		label, _reports, n, seconds, 1000.0 / avg, avg, p50, 1000.0 / p99, p99, worst, over16, 100.0 * over16 / n, over33])
	if _reports == 1:
		print("PERF machine: %s | %s | %s | window %dx%d @ %.0f Hz | renderer %s | vsync %d | Godot %s" % [
			OS.get_name(), OS.get_processor_name(), RenderingServer.get_video_adapter_name(), win.x, win.y,
			DisplayServer.screen_get_refresh_rate(), RenderingServer.get_current_rendering_method(),
			DisplayServer.window_get_vsync_mode(), Engine.get_version_info().string])
	_frames = PackedFloat32Array()
