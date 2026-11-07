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
	var scope := DeskLocalization.source("LOC_ALL_SYNTHETIC_AUDIENCES_BED572F8") if group_ids.is_empty() else ", ".join(group_ids)
	var duration := DeskLocalization.source("LOC_INSTANT_2DA85532") if duration_hours == 0.0 else DeskLocalization.source_format("LOC_F_HOURS_1DFE9CBC", duration_hours)
	var action := DeskLocalization.source_format("LOC_UNKNOWN_EFFECT_S_279E93F2", effect_id)
	match effect_id:
		&"attention":
			action = DeskLocalization.source_format("LOC_ATTENTION_F_DC27F3AC", (1.0 + amount))
		&"channel_reach":
			action = DeskLocalization.source_format("LOC_CHANNEL_REACH_F_D46B732B", (1.0 + amount))
		&"adoption":
			action = DeskLocalization.source_format("LOC_F_OF_EXPOSED_NON_ADOPTERS_BEGIN_USING_39F9BA83", (amount * 100.0))
		&"trust":
			action = DeskLocalization.source_format("LOC_TRUST_F_23001F95", amount)
		&"fatigue":
			action = DeskLocalization.source_format("LOC_FATIGUE_F_E0745408", amount)
		&"remix":
			action = DeskLocalization.source("LOC_CREATES_EXTERNAL_REWRITE_VERSION_9DB53E62") if amount > 0.0 else DeskLocalization.source("LOC_NO_REWRITE_VERSION_CREATED_86CDC935")
		&"semantic_shift":
			action = DeskLocalization.source_format("LOC_VERSION_DRIFT_FROM_ITS_FAMILY_ANCHOR_IS_BFEE84C2", amount)
		&"revival":
			action = DeskLocalization.source_format("LOC_FATIGUE_F_AND_ATTENTION_RECOVERS_33879600", amount)
	return DeskLocalization.source_format("%s · %s · %s",[action,duration,scope],[0,1,2])
