## 共用语境资源查询、安装资格与离散轴命令；坐标命中和绘制仍由各视图负责。
class_name DeskContextController
extends RefCounted

const LAYERS := ["language", "group", "topics", "stance", "pragmatic"]

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

static func can_install(state: Dictionary, rules: MemeDesignRules, layer: String, slot: int, packet: Dictionary) -> bool:
	var actual: Dictionary = state.get("context_layers", {}).get(layer, {})
	if layer not in ["language", "group", "topics"] or str(packet.get("type", "")) != "context_resource":
		return false
	var slots: Array = actual.get("slots", [])
	var entry := resource(state, rules, str(packet.get("resource_id", "")))
	var kind := "topic" if layer == "topics" else layer
	return slot >= 0 and slot < slots.size() and slots[slot].is_empty() and str(entry.get("kind", "")) == kind and str(packet.get("kind", kind)) == kind and int(entry.get("available", 0)) > 0

# One pointer destination becomes one transaction and one presentation update.
func move_axes(layers: Callable, perform_action: Callable, layer: String, targets: Array) -> void:
	var data: Dictionary = layers.call().get(layer, {})
	var ranges: Array = data.get("reachable_offsets", [])
	var offsets: Array = data.get("offsets", [0, 0])
	var requested := targets.duplicate()
	for axis in 2:
		if not ranges.is_empty(): requested[axis] = clampi(int(requested[axis]), int(ranges[axis][0]), int(ranges[axis][1]))
	if requested == offsets: return
	_sequence += 1
	perform_action.call("move_context_axes", {"layer":layer, "target_offsets":requested, "request_id":"%s:%s:%d" % [_prefix, _session, _sequence]})

func move_axis(layers: Callable, perform_action: Callable, layer: String, axis: int, target: int) -> void:
	var requested: Array = layers.call().get(layer, {}).get("offsets", [0, 0]).duplicate()
	requested[axis] = target
	move_axes(layers, perform_action, layer, requested)
