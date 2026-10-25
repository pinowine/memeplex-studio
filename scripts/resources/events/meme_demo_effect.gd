class_name MemeDemoEffect
extends Resource

const EFFECT_IDS := [&"attention", &"adoption", &"trust", &"fatigue", &"remix", &"semantic_shift", &"channel_reach", &"revival"]

@export var effect_id: StringName = &"attention"
@export var amount: float = 0.0
@export var duration_hours: float = 0.0
@export var group_ids: PackedStringArray = PackedStringArray()

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not effect_id in EFFECT_IDS:
		errors.append("effect_id: unknown effect %s" % effect_id)
	if not is_finite(amount):
		errors.append("amount: must be finite")
	elif effect_id in [&"adoption", &"remix", &"semantic_shift", &"revival"]:
		if amount < 0.0 or amount > 1.0:
			errors.append("amount: %s must be in [0, 1]" % effect_id)
	elif effect_id in [&"trust", &"fatigue"]:
		if amount < -1.0 or amount > 1.0:
			errors.append("amount: %s delta must be in [-1, 1]" % effect_id)
	elif effect_id in [&"attention", &"channel_reach"] and amount < -1.0:
		errors.append("amount: multiplicative delta cannot be below -1")
	if not is_finite(duration_hours) or duration_hours < 0.0:
		errors.append("duration_hours: must be finite and nonnegative")
	var seen: Dictionary = {}
	for group_id in group_ids:
		if group_id.is_empty() or seen.has(group_id):
			errors.append("Effect groups must be nonempty and unique")
		seen[group_id] = true
	return errors

func describe() -> String:
	var scope := "全部合成群体" if group_ids.is_empty() else ", ".join(group_ids)
	var duration := "即时" if duration_hours == 0.0 else DeskLocalization.source_format("%.2f小时", duration_hours)
	var action := DeskLocalization.source_format("未知效果 %s", effect_id)
	match effect_id:
		&"attention":
			action = DeskLocalization.source_format("注意力 ×%.2f", (1.0 + amount))
		&"channel_reach":
			action = DeskLocalization.source_format("渠道触达 ×%.2f", (1.0 + amount))
		&"adoption":
			action = DeskLocalization.source_format("未采纳曝光者中 %.2f%% 开始使用", (amount * 100.0))
		&"trust":
			action = DeskLocalization.source_format("信任 %+.2f", amount)
		&"fatigue":
			action = DeskLocalization.source_format("疲劳 %+.2f", amount)
		&"remix":
			action = "生成1个外部改写版本" if amount > 0.0 else "不生成改写版本"
		&"semantic_shift":
			action = DeskLocalization.source_format("版本的家族锚点偏移设为 %.2f", amount)
		&"revival":
			action = DeskLocalization.source_format("疲劳 −%.2f，并恢复注意力", amount)
	return DeskLocalization.source_format("%s · %s · %s",[action,duration,scope],[0,1,2])
