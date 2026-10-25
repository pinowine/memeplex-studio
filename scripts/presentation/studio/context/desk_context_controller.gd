## 共用语境资源查询、安装资格与离散轴命令；坐标命中和绘制仍由各视图负责。
class_name DeskContextController
extends RefCounted

const LAYERS := ["language", "group", "topics", "stance", "pragmatic"]
const DEPTHS := [0.1, 0.3, 0.5, 0.7, 0.9]
const MAX_AXIS_STEPS := 20

var _prefix: String
var _session := Crypto.new().generate_random_bytes(12).hex_encode()
var _sequence := 0

func _init(prefix: String) -> void:
	_prefix = prefix

static func resource(state: Dictionary, rules: MemeDesignRules, id: String) -> Dictionary:
	for record: Dictionary in state.get("resources", []):
		if str(record.get("resource_id", record.get("id", ""))) == id:
			return record
	return rules.context_resource(id) if rules != null else {}

static func can_attach(state: Dictionary, layer: String, packet: Dictionary) -> bool:
	if layer not in LAYERS or str(packet.get("layer", "")) != layer:
		return false
	var actual: Dictionary = state.get("context_layers", {}).get(layer, {})
	var plane_id: String = str(actual.get("plane_id", ""))
	return not bool(actual.get("attached", true)) and not plane_id.is_empty() and plane_id == str(packet.get("plane_id", ""))

static func can_install(state: Dictionary, rules: MemeDesignRules, layer: String, slot: int, packet: Dictionary) -> bool:
	var actual: Dictionary = state.get("context_layers", {}).get(layer, {})
	if layer not in ["language", "group", "topics"] or not bool(actual.get("attached", true)) or str(packet.get("type", "")) != "context_resource":
		return false
	var slots: Array = actual.get("slots", [])
	var entry := resource(state, rules, str(packet.get("resource_id", "")))
	var kind := "topic" if layer == "topics" else layer
	return slot >= 0 and slot < slots.size() and slots[slot].is_empty() and str(entry.get("kind", "")) == kind and str(packet.get("kind", kind)) == kind and int(entry.get("available", 0)) > 0

## 每一步重新读取提交后的层状态；权威拒绝或偏移未前进时立即停止。
func move_axis(layers: Callable, perform_action: Callable, layer: String, axis: int, target: int) -> void:
	for attempt in MAX_AXIS_STEPS:
		var data: Dictionary = layers.call().get(layer, {})
		var offsets: Array = data.get("offsets", [0, 0])
		var previous := int(offsets[axis])
		if previous == target:
			return
		_sequence += 1
		var direction := 1 if target > previous else -1
		perform_action.call("move_context_axis", {"layer": layer, "axis": "x" if axis == 0 else "y", "direction": direction, "request_id": "%s:%s:%d" % [_prefix, _session, _sequence]})
		var actual: Array = layers.call().get(layer, {}).get("offsets", [0, 0])
		if int(actual[axis]) != previous + direction:
			return
