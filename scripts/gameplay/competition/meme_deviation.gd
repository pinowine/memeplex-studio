extends RefCounted

const Metrics = preload("res://scripts/gameplay/competition/meme_monitor_metrics.gd")
const NATURAL_PER_HOUR := 0.0001
const RESEARCH_RELIEF := {"source_package":0.02, "context_note":0.03, "version_index":0.04, "template_archive":0.04}

static func total(anchor: Dictionary, current: Dictionary) -> float:
	var patches := 0
	for id: String in current.get("patch_ids", []):
		if id not in anchor.get("patch_ids", []): patches += 1
	for id: String in anchor.get("patch_ids", []):
		if id not in current.get("patch_ids", []): patches += 1
	return clampf(Metrics.deviation(anchor, current) + patches * 0.025 + float(current.get("deviation_pressure", 0.0)), 0.0, 1.0)

static func hourly_growth(skills: Array) -> float:
	var rate := NATURAL_PER_HOUR
	if "public_template" in skills: rate *= 1.2
	if "source_package" in skills: rate *= 0.75
	if "context_note" in skills: rate *= 0.65
	if "template_archive" in skills: rate *= 0.5
	return rate

static func threshold(base: float, skills: Array) -> float:
	if "source_package" in skills: base += 0.03
	if "context_note" in skills: base += 0.04
	if "template_archive" in skills: base += 0.05
	return minf(0.9, base)

static func expression_factor(patch_count: int, skills: Array) -> float:
	var factor := 1.0 + 0.065 * patch_count
	if "source_package" in skills: factor *= 0.97
	if "context_note" in skills: factor *= 0.96
	if "template_archive" in skills: factor *= 0.92
	return factor
