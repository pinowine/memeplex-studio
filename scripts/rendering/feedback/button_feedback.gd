extends RefCounted

const FeedbackShader := preload("res://shaders/ui/studio_button_feedback.gdshader")
const TRANSITION_SPEED := 16.0

var errors: Array[String] = []
var _entries: Dictionary = {}
var _hovered := ""

func configure(buttons: Dictionary) -> void:
	clear()
	_entries.clear()
	errors.clear()
	for button_key in buttons:
		var key := str(button_key)
		var binding: Dictionary = buttons[button_key]
		var root := binding.get("mesh") as Node3D
		if root == null:
			_fail("Button feedback requires a Node3D: " + key)
			continue
		var visuals: Array[Dictionary] = []
		var meshes: Array[MeshInstance3D] = []
		if root is MeshInstance3D:
			meshes.append(root as MeshInstance3D)
		for child in root.find_children("*", "MeshInstance3D", true, false):
			meshes.append(child as MeshInstance3D)
		for mesh in meshes:
			if mesh.mesh == null:
				continue
			var material := ShaderMaterial.new()
			material.shader = FeedbackShader
			material.resource_name = "ButtonFeedback__" + key
			var bounds := mesh.get_aabb()
			material.set_shader_parameter("bounds_min", Vector2(bounds.position.x, bounds.position.z))
			material.set_shader_parameter("bounds_size", Vector2(maxf(bounds.size.x, .00001), maxf(bounds.size.z, .00001)))
			visuals.append({"mesh": mesh, "material": material, "original": mesh.material_overlay})
		_entries[key] = {"mesh": root, "rest": binding.get("rest", root.position), "travel": float(binding.get("travel", .0015)), "target": binding.get("target"), "moves": str(binding.get("action", "")) != "pickup", "pressed": false, "hover_strength": 0.0, "press_strength": 0.0, "offset_y": 0.0, "visuals": visuals}

func update_hover(key: String) -> void:
	_hovered = key if _entries.has(key) and _enabled(_entries[key]) else ""

func set_pressed(key: String, down: bool) -> void:
	if not _entries.has(key):
		return
	var entry: Dictionary = _entries[key]
	if not _enabled(entry):
		_reset_entry(entry)
		if _hovered == key:
			_hovered = ""
		return
	entry["pressed"] = down
	entry["press_strength"] = 1.0 if down else 0.0
	_render(entry)

func clear() -> void:
	_hovered = ""
	for entry: Dictionary in _entries.values():
		_reset_entry(entry)

func tick(delta: float) -> void:
	for key in _entries:
		var entry: Dictionary = _entries[key]
		if not _enabled(entry):
			_reset_entry(entry)
			if _hovered == key:
				_hovered = ""
			continue
		entry["hover_strength"] = move_toward(float(entry["hover_strength"]), 1.0 if key == _hovered else 0.0, maxf(delta, 0.0) * TRANSITION_SPEED)
		_render(entry)

func inspection() -> Dictionary:
	var states: Dictionary = {}
	var pressed: Array[String] = []
	var active_overlays := 0
	for key in _entries:
		var entry: Dictionary = _entries[key]
		var root: Node3D = entry["mesh"]
		var position: Vector3 = root.position if is_instance_valid(root) else Vector3.ZERO
		var rest: Vector3 = entry["rest"]
		if entry["pressed"]:
			pressed.append(str(key))
		for visual: Dictionary in entry["visuals"]:
			var mesh: MeshInstance3D = visual["mesh"]
			if is_instance_valid(mesh) and mesh.material_overlay == visual["material"]:
				active_overlays += 1
		states[key] = {"enabled": _enabled(entry), "hovered": key == _hovered, "pressed": entry["pressed"], "hover_strength": entry["hover_strength"], "press_strength": entry["press_strength"], "offset_y": entry["offset_y"], "moves": entry["moves"], "overlay_meshes": entry["visuals"].size(), "position": [position.x, position.y, position.z], "rest": [rest.x, rest.y, rest.z]}
	return {"hovered": _hovered, "pressed": pressed, "button_count": _entries.size(), "active_overlays": active_overlays, "states": states, "errors": errors.duplicate()}

func _enabled(entry: Dictionary) -> bool:
	if not is_instance_valid(entry["mesh"]):
		return false
	var target: Variant = entry["target"]
	return target == null or (is_instance_valid(target) and target is BaseButton and not target.disabled)

func _render(entry: Dictionary) -> void:
	var hover: float = entry["hover_strength"]
	var press: float = entry["press_strength"]
	var root: Node3D = entry["mesh"]
	var travel: float = entry["travel"]
	var lift := clampf(travel * .5, .0008, .0012)
	var depth := maxf(travel, .0025)
	var offset := lerpf(hover * lift, -depth, press) if entry["moves"] else 0.0
	entry["offset_y"] = offset
	if entry["moves"] and is_instance_valid(root):
		var rest: Vector3 = entry["rest"]
		root.position = rest + Vector3(0.0, offset, 0.0)
	for visual: Dictionary in entry["visuals"]:
		var mesh: MeshInstance3D = visual["mesh"]
		if not is_instance_valid(mesh):
			continue
		var material: ShaderMaterial = visual["material"]
		material.set_shader_parameter("hover_amount", hover)
		material.set_shader_parameter("press_amount", press)
		if maxf(hover, press) > .0001:
			mesh.material_overlay = material
		elif mesh.material_overlay == material:
			mesh.material_overlay = visual["original"]

func _reset_entry(entry: Dictionary) -> void:
	entry["pressed"] = false
	entry["hover_strength"] = 0.0
	entry["press_strength"] = 0.0
	_render(entry)

func _fail(message: String) -> void:
	errors.append(message)
	push_error(message)
