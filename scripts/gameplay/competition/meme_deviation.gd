extends RefCounted

const Metrics = preload("res://scripts/gameplay/competition/meme_monitor_metrics.gd")
const NATURAL_PER_HOUR := 0.00036
const RECOVERY_PER_HOUR := 0.00025
const RESEARCH_RELIEF := {"context_note":0.06, "usage_example":0.08, "meme_entry":0.10}

static func raw_semantic(anchor: Dictionary, current: Dictionary) -> float:
	var patches := 0
	for id: String in current.get("patch_ids", []):
		if id not in anchor.get("patch_ids", []): patches += 1
	for id: String in anchor.get("patch_ids", []):
		if id not in current.get("patch_ids", []): patches += 1
	var skills: Array = current.get("flow_profile", current.get("flow_draft", {})).get("skill_ids", [])
	var distance := Metrics.deviation(anchor, current)
	if "public_template" in skills:
		var expression := Metrics._text_distance(str(anchor.get("text", "")), str(current.get("text", "")))
		var meaning := Metrics.deviation(anchor, current) - expression * 0.2
		distance = clampf(expression * 0.2 + meaning * 0.5, 0.0, 1.0)
	if "usage_example" in skills:
		distance *= 0.65
	return distance + patches * 0.025

static func total(anchor: Dictionary, current: Dictionary) -> float:
	return clampf(raw_semantic(anchor, current) + float(current.get("deviation_pressure", 0.0)), 0.0, 1.0)

static func hourly_growth(skills: Array, preset_id: String = "") -> float:
	var rate := NATURAL_PER_HOUR
	if preset_id == "nobody_2020": rate *= 1.20
	elif preset_id == "ok_boomer_2020": rate *= 0.75
	if "context_note" in skills: rate *= 0.70
	if "meme_entry" in skills: rate *= 0.30
	if "image" in skills: rate *= 1.15
	if "free_remix" in skills: rate *= 2.0
	if "misuse_correction" in skills: rate -= RECOVERY_PER_HOUR
	return rate

static func threshold(base: float, skills: Array) -> float:
	if "translated_caption" in skills: base += 0.15
	if "public_template" in skills: base += 0.15
	if "form_anchor" in skills: base += 0.10
	if "free_remix" in skills: base -= 0.12
	if "spinoff_momentum" in skills: base -= 0.10
	return clampf(base, 0.20, 0.92)

static func expression_factor(patch_count: int, skills: Array) -> float:
	var factor := 1.0 + 0.065 * patch_count
	if "context_note" in skills: factor *= 0.92
	if "meme_entry" in skills: factor *= 0.95
	return factor
