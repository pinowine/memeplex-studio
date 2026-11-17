extends RefCounted

const Metrics = preload("res://scripts/gameplay/competition/meme_monitor_metrics.gd")
const PRIORITY: Array[String] = ["best_substitute", "viral_icon", "successful_adaptation", "balanced_duel", "local_classic", "forgotten"]
const TARGET_WINDOWS: Array[String] = ["viral_icon", "local_classic", "balanced_duel", "successful_adaptation", "forgotten"]

static func _window() -> Dictionary:
	return {"hours":0, "start_hour":-1, "other_meme_id":"", "min":0.0, "max":0.0}

static func _records(variants: Array) -> Dictionary:
	var records: Dictionary = {}
	for raw: Dictionary in variants: records[str(raw.id)] = raw
	return records

static func _content(raw: Dictionary) -> Dictionary:
	var visible: Dictionary = raw.duplicate(true)
	visible.merge(raw.get("effective_content", {}), true)
	return visible

static func _meme_id(raw: Dictionary) -> String:
	return str(raw.get("meme_id", raw.get("id", "")))

static func semantic_signature(raw: Dictionary) -> String:
	var visible: Dictionary = _content(raw)
	var source: Dictionary = visible.get("flow_profile", visible.get("flow_draft", {}))
	var semantic: Dictionary = {}
	for field: String in ["text", "meaning", "meaning_id", "language_versions"]: semantic[field] = visible.get(field, "")
	var attachment: Dictionary = source.get("context_layer_attachment", {})
	for layer: String in ["language", "group", "topics", "stance", "pragmatic"]:
		var attached: bool = bool(attachment.get(layer, true))
		semantic[layer] = {"attached":attached}
		if not attached: continue
		if layer in ["language", "group", "topics"]:
			var field: String = "topic_ids" if layer == "topics" else layer + "_ids"
			var values: Array = Array(source.get(field, [] if layer == "topics" else [str(source.get(layer + "_id", ""))]))
			values.sort()
			semantic[layer].values = values
		elif layer == "stance":
			semantic[layer].known = bool(source.get("political_known", false))
			semantic[layer].position = source.get("political_position", []) if semantic[layer].known else []
		else: semantic[layer].position = source.get("pragmatic_position", [])
	return JSON.stringify(semantic, "", true, true).sha256_text()

static func record_publication(state: Dictionary, variants: Array, current_id: String, country_id: String, hour: int, competition: RefCounted) -> Dictionary:
	var records: Dictionary = _records(variants)
	if not records.has(current_id): return state
	var current: Dictionary = records[current_id]
	var meme_id: String = _meme_id(current)
	var signature: String = semantic_signature(current)
	if state.is_empty() or str(state.target_meme_id) != meme_id or str(state.country_id) != country_id:
		var windows: Dictionary = {}
		for id: String in TARGET_WINDOWS: windows[id] = _window()
		state = {"version":Metrics.DEVIATION_VERSION, "target_meme_id":meme_id, "target_record_id":current_id, "country_id":country_id, "target_started_hour":hour, "last_hour":hour, "signature":signature, "stable_peak":0.0, "local_samples":[], "adaptation":{"baseline":0.0, "revision_hour":-1, "signature":"", "eligible":false}, "windows":windows, "pairs":{}, "rows":[]}
	else:
		var previous_signature: String = str(state.signature)
		if not current.get("parent_ids", []).is_empty() and records.has(str(current.parent_ids[0])):
			previous_signature = semantic_signature(records[str(current.parent_ids[0])])
		if signature != previous_signature:
			var baseline: float = float(state.stable_peak)
			state.adaptation = {"baseline":baseline, "revision_hour":hour, "signature":signature, "eligible":baseline >= competition.rules.adaptation_baseline_min}
			state.windows.successful_adaptation = _window()
			state.local_samples = []
			var visible: Dictionary = _content(current)
			if Metrics.deviation(visible.get("deviation_anchor", visible), visible) > competition.rules.local_deviation_max: state.windows.local_classic = _window()
		state.target_record_id = current_id
		state.signature = signature
	state.version = Metrics.DEVIATION_VERSION
	state.rows = _rows(state, _metrics(variants, current_id, country_id, hour, competition), competition.rules)
	return state

static func refresh_metrics(state: Dictionary, variants: Array, competition: RefCounted) -> void:
	if state.is_empty() or int(state.version) == Metrics.DEVIATION_VERSION: return
	var memes := {}
	for visible: Dictionary in competition.active_variants(variants): memes[_meme_id(visible)] = visible
	# Refresh cached drift without adding hours to a newly qualified observation.
	for row: Dictionary in state.rows:
		var winner := str(row.winner_meme_id)
		if memes.has(winner):
			var visible: Dictionary = memes[winner]
			row.deviation = Metrics.deviation(visible.get("deviation_anchor", visible), visible)
		row.qualified = _qualified(row)
	state.version = Metrics.DEVIATION_VERSION

static func _metrics(variants: Array, current_id: String, country_id: String, hour: int, competition: RefCounted, metric_version: int = Metrics.DEVIATION_VERSION) -> Dictionary:
	var records: Dictionary = _records(variants)
	var target_id: String = _meme_id(records[current_id]) if records.has(current_id) else ""
	var population: int = 0
	var budget: int = 0
	for row: Dictionary in competition._state.world:
		var count: int = int(competition._state.populations[str(row.id)])
		population += count
		budget += floori(count * competition.rules.attention_fraction)
	var memes: Dictionary = {}
	for visible: Dictionary in competition.active_variants(variants):
		var id: String = str(visible.id)
		var meme_id: String = _meme_id(visible)
		var entry: Dictionary = {"record_id":id, "meme_id":meme_id, "adopted":0, "exposed":0, "attention":0, "local_adopted":0, "spread":0.0, "adoption":0.0, "deviation":Metrics.deviation(visible.get("deviation_anchor", visible), visible, metric_version), "birth_hour":int(competition._state.registry[id].birth_hour)}
		for row: Dictionary in competition._state.world:
			var cid: String = str(row.id)
			var country: Dictionary = competition._state.countries[cid]
			for field: String in ["adopted", "exposed", "attention"]: entry[field] += int(country[field].get(id, 0))
			if cid == country_id: entry.local_adopted = int(country.adopted.get(id, 0))
		entry.spread = Metrics.spread(entry, population, budget)
		entry.adoption = float(entry.local_adopted) / maxf(1.0, float(competition._state.populations.get(country_id, 0)))
		memes[meme_id] = entry
	return {"target_meme_id":target_id, "memes":memes, "records":records, "population":population, "hour":hour}

static func _strongest(memes: Dictionary, excluded: String) -> String:
	var selected: String = ""
	var ids: Array = memes.keys()
	ids.sort()
	for id: String in ids:
		if id == excluded: continue
		if selected.is_empty() or float(memes[id].spread) > float(memes[selected].spread): selected = id
	return selected

static func _pair_sources(records: Dictionary, target_id: String) -> Dictionary:
	var pairs: Dictionary = {}
	for raw: Dictionary in records.values():
		var q: String = _meme_id(raw)
		if str(raw.id) != q or not raw.has("split_from_id"): continue
		var parent_record: String = str(raw.split_from_id)
		if not records.has(parent_record): continue
		var p: String = _meme_id(records[parent_record])
		if p != q and (p == target_id or q == target_id): pairs[q] = {"parent_meme_id":p, "parent_record_id":parent_record}
	return pairs

static func _tick(window: Dictionary, eligible: bool, hour: int, consecutive: bool, other_id: String = "", sample: float = 0.0, range_limit: float = 1.0) -> Dictionary:
	if not eligible: return _window()
	var same_run: bool = consecutive and int(window.hours) > 0 and str(window.other_meme_id) == other_id
	var low: float = minf(float(window.min), sample) if same_run else sample
	var high: float = maxf(float(window.max), sample) if same_run else sample
	if high - low > range_limit: same_run = false; low = sample; high = sample
	var hours: int = int(window.hours) + 1 if same_run else 1
	return {"hours":hours, "start_hour":hour - hours, "other_meme_id":other_id, "min":low, "max":high}

static func evaluate(state: Dictionary, variants: Array, current_id: String, country_id: String, hour: int, competition: RefCounted) -> Dictionary:
	var metrics: Dictionary = _metrics(variants, current_id, country_id, hour, competition)
	var target_id: String = str(metrics.target_meme_id)
	if target_id.is_empty() or not metrics.memes.has(target_id): return {}
	if state.is_empty() or str(state.target_meme_id) != target_id or str(state.country_id) != country_id:
		var fresh: Dictionary = record_publication({}, variants, current_id, country_id, maxi(0, hour - 1), competition)
		state.clear()
		state.merge(fresh, true)
	if hour <= int(state.last_hour): return {}
	state.version = Metrics.DEVIATION_VERSION
	var rules: MemeGameplayRules = competition.rules
	var target: Dictionary = metrics.memes[target_id]
	var other_id: String = _strongest(metrics.memes, target_id)
	var other_spread: float = float(metrics.memes[other_id].spread) if not other_id.is_empty() else 0.0
	var consecutive: bool = hour == int(state.last_hour) + 1
	if not consecutive: state.local_samples = []
	state.local_samples.append(float(target.adoption))
	while state.local_samples.size() > rules.adaptation_stable_window_hours: state.local_samples.pop_front()
	if state.local_samples.size() == rules.adaptation_stable_window_hours:
		var total: float = 0.0
		for value: float in state.local_samples: total += value
		state.stable_peak = maxf(float(state.stable_peak), total / rules.adaptation_stable_window_hours)
	var viral: bool = float(target.spread) >= rules.viral_spread_min and float(target.spread) - other_spread >= rules.viral_lead_min
	state.windows.viral_icon = _tick(state.windows.viral_icon, viral, hour, consecutive)
	var classic: bool = float(target.adoption) >= rules.local_adoption_min and float(target.deviation) <= rules.local_deviation_max
	state.windows.local_classic = _tick(state.windows.local_classic, classic, hour, consecutive, "", float(target.adoption), rules.local_range_max)
	var duel: bool = not other_id.is_empty() and float(target.spread) >= rules.duel_spread_min and other_spread >= rules.duel_spread_min and absf(float(target.spread) - other_spread) <= rules.duel_gap_max
	state.windows.balanced_duel = _tick(state.windows.balanced_duel, duel, hour, consecutive, other_id)
	var adaptation: bool = bool(state.adaptation.eligible) and float(target.adoption) >= rules.adaptation_adoption_min and float(target.adoption) - float(state.adaptation.baseline) >= rules.adaptation_gain_min
	state.windows.successful_adaptation = _tick(state.windows.successful_adaptation, adaptation, hour, consecutive)
	var forgotten: bool = hour - int(target.birth_hour) > rules.seed_hours and int(target.adopted) == 0 and int(target.exposed) == 0
	state.windows.forgotten = _tick(state.windows.forgotten, forgotten, hour, consecutive)
	var sources: Dictionary = _pair_sources(metrics.records, target_id)
	var pairs: Dictionary = {}
	for q: String in sources:
		if not metrics.memes.has(q): continue
		var candidate: Dictionary = metrics.memes[q]
		var rival_id: String = _strongest(metrics.memes, q)
		var rival_spread: float = float(metrics.memes[rival_id].spread) if not rival_id.is_empty() else 0.0
		var eligible: bool = hour > int(candidate.birth_hour) and float(candidate.spread) >= rules.substitute_spread_min and float(candidate.spread) - rival_spread >= rules.substitute_lead_min
		var previous: Dictionary = state.pairs.get(q, {"window":_window()})
		pairs[q] = {"parent_meme_id":sources[q].parent_meme_id, "parent_record_id":sources[q].parent_record_id, "window":_tick(previous.window, eligible, hour, consecutive)}
	state.pairs = pairs
	state.target_record_id = str(target.record_id)
	state.last_hour = hour
	state.rows = _rows(state, metrics, rules)
	return _result(state, hour)

static func _required(id: String, rules: MemeGameplayRules) -> int:
	return int({"viral_icon":rules.viral_hours, "local_classic":rules.local_hours, "balanced_duel":rules.duel_hours, "successful_adaptation":rules.adaptation_hours, "forgotten":rules.forgotten_hours, "best_substitute":rules.substitute_hours}[id])

static func _blank_row(id: String, state: Dictionary, rules: MemeGameplayRules) -> Dictionary:
	return {"id":id, "meme_id":str(state.target_meme_id), "country_id":str(state.country_id), "winner_meme_id":str(state.target_meme_id), "candidate_meme_id":"", "parent_meme_id":"", "parent_record_id":"", "other_meme_id":"", "hours":0, "required_hours":_required(id, rules), "spread":0.0, "spread_min":0.0, "lead":0.0, "lead_min":0.0, "adoption":0.0, "adoption_min":0.0, "deviation":0.0, "deviation_max":1.0, "range":0.0, "range_max":1.0, "other_spread":0.0, "gap":0.0, "gap_max":1.0, "gain":0.0, "gain_min":0.0, "baseline":float(state.adaptation.baseline), "baseline_min":rules.adaptation_baseline_min, "stable_peak":float(state.stable_peak), "adopted":0, "exposed":0, "seed_hours":0, "seed_required_hours":rules.seed_hours, "adaptation_eligible":bool(state.adaptation.eligible), "qualified":false}

static func _rows(state: Dictionary, metrics: Dictionary, rules: MemeGameplayRules) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var target_id: String = str(state.target_meme_id)
	for id: String in PRIORITY:
		var row: Dictionary = _blank_row(id, state, rules)
		var winner_id: String = target_id
		var window: Dictionary = state.windows.get(id, _window())
		if id == "best_substitute":
			winner_id = ""
			var candidates: Array = state.pairs.keys()
			candidates.sort()
			for q: String in candidates:
				if not metrics.memes.has(q): continue
				if winner_id.is_empty() or int(state.pairs[q].window.hours) > int(state.pairs[winner_id].window.hours) or (int(state.pairs[q].window.hours) == int(state.pairs[winner_id].window.hours) and float(metrics.memes[q].spread) > float(metrics.memes[winner_id].spread)): winner_id = q
			if not winner_id.is_empty():
				window = state.pairs[winner_id].window
				row.candidate_meme_id = winner_id
				row.parent_meme_id = state.pairs[winner_id].parent_meme_id
				row.parent_record_id = state.pairs[winner_id].parent_record_id
		row.winner_meme_id = winner_id
		if metrics.memes.has(winner_id):
			var winner: Dictionary = metrics.memes[winner_id]
			var other: String = _strongest(metrics.memes, winner_id)
			row.other_meme_id = other
			row.spread = float(winner.spread)
			row.other_spread = float(metrics.memes[other].spread) if not other.is_empty() else 0.0
			row.lead = float(row.spread) - float(row.other_spread)
			row.gap = absf(float(row.lead))
			row.adoption = float(winner.adoption)
			row.deviation = float(winner.deviation)
			row.adopted = int(winner.adopted)
			row.exposed = int(winner.exposed)
			row.seed_hours = maxi(0, int(metrics.hour) - int(winner.birth_hour))
		row.hours = int(window.hours)
		row.range = float(window.max) - float(window.min)
		row.gain = float(row.adoption) - float(row.baseline)
		_thresholds(row, rules)
		row.qualified = _qualified(row)
		rows.append(row)
	return rows

static func _thresholds(row: Dictionary, rules: MemeGameplayRules) -> void:
	match str(row.id):
		"viral_icon": row.spread_min = rules.viral_spread_min; row.lead_min = rules.viral_lead_min
		"best_substitute": row.spread_min = rules.substitute_spread_min; row.lead_min = rules.substitute_lead_min
		"local_classic": row.adoption_min = rules.local_adoption_min; row.deviation_max = rules.local_deviation_max; row.range_max = rules.local_range_max
		"balanced_duel": row.spread_min = rules.duel_spread_min; row.gap_max = rules.duel_gap_max
		"successful_adaptation": row.adoption_min = rules.adaptation_adoption_min; row.gain_min = rules.adaptation_gain_min

static func _qualified(row: Dictionary) -> bool:
	match str(row.id):
		"viral_icon", "best_substitute": return not str(row.winner_meme_id).is_empty() and float(row.spread) >= float(row.spread_min) and float(row.lead) >= float(row.lead_min)
		"local_classic": return float(row.adoption) >= float(row.adoption_min) and float(row.deviation) <= float(row.deviation_max) and float(row.range) <= float(row.range_max)
		"balanced_duel": return not str(row.other_meme_id).is_empty() and float(row.spread) >= float(row.spread_min) and float(row.other_spread) >= float(row.spread_min) and float(row.gap) <= float(row.gap_max)
		"successful_adaptation": return bool(row.adaptation_eligible) and float(row.baseline) >= float(row.baseline_min) and float(row.adoption) >= float(row.adoption_min) and float(row.gain) >= float(row.gain_min)
		"forgotten": return int(row.seed_hours) > int(row.seed_required_hours) and int(row.adopted) == 0 and int(row.exposed) == 0
	return false

static func _result(state: Dictionary, hour: int) -> Dictionary:
	for row: Dictionary in state.rows:
		if bool(row.qualified) and int(row.hours) >= int(row.required_hours):
			return {"id":str(row.id), "hour":hour, "meme_id":str(row.winner_meme_id), "target_meme_id":str(state.target_meme_id), "country_id":str(state.country_id), "other_meme_id":str(row.other_meme_id), "parent_meme_id":str(row.parent_meme_id), "parent_record_id":str(row.parent_record_id), "progress":row.duplicate(true)}
	return {}

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))

static func _unit(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0 and float(value) <= 1.0

static func _close(a: Variant, b: Variant) -> bool:
	return _number(a) and _number(b) and absf(float(a) - float(b)) <= 0.000000000001

static func _validate_window(window: Dictionary, state: Dictionary, required: int) -> bool:
	if window.size() != 5 or not window.has_all(["hours", "start_hour", "other_meme_id", "min", "max"]): return false
	if not _integer(window.hours) or not _integer(window.start_hour) or not window.other_meme_id is String or not _unit(window.min) or not _unit(window.max) or float(window.min) > float(window.max): return false
	if int(window.hours) == 0: return int(window.start_hour) == -1 and str(window.other_meme_id).is_empty() and float(window.min) == 0.0 and float(window.max) == 0.0
	return int(window.hours) > 0 and int(window.hours) <= required and int(window.start_hour) >= int(state.target_started_hour) and int(state.last_hour) - int(window.start_hour) == int(window.hours)

static func validate_state(state: Dictionary, variants: Array, competition: RefCounted, hour: int) -> PackedStringArray:
	var errors: PackedStringArray = []
	if state.is_empty():
		if not variants.is_empty(): errors.append("Published independent memes require ending progress")
		return errors
	var keys: Array[String] = ["version", "target_meme_id", "target_record_id", "country_id", "target_started_hour", "last_hour", "signature", "stable_peak", "local_samples", "adaptation", "windows", "pairs", "rows"]
	if state.size() != keys.size() or not state.has_all(keys) or not _integer(state.version) or int(state.version) not in [1, Metrics.DEVIATION_VERSION]: return PackedStringArray(["Independent ending progress has invalid fields"])
	for key: String in ["target_meme_id", "target_record_id", "country_id", "signature"]:
		if not state[key] is String: errors.append("Independent ending identity fields require text")
	for key: String in ["target_started_hour", "last_hour"]:
		if not _integer(state[key]) or int(state[key]) < 0 or int(state[key]) > hour: errors.append("Independent ending clocks require valid hours")
	if not _unit(state.stable_peak) or not state.local_samples is Array or not state.adaptation is Dictionary or not state.windows is Dictionary or not state.pairs is Dictionary or not state.rows is Array: errors.append("Independent ending progress has invalid value types")
	if not errors.is_empty(): return errors
	var records: Dictionary = _records(variants)
	var meme_ids: Dictionary = {}
	for raw: Dictionary in variants: meme_ids[_meme_id(raw)] = true
	if not records.has(str(state.target_record_id)) or not meme_ids.has(str(state.target_meme_id)) or not competition.has_country(str(state.country_id)): errors.append("Independent ending progress requires a real target and country")
	elif _meme_id(records[str(state.target_record_id)]) != str(state.target_meme_id): errors.append("Independent ending record belongs to another meme")
	if int(state.target_started_hour) > int(state.last_hour) or str(state.signature).length() != 64: errors.append("Independent ending progress requires a valid observation origin and signature")
	var rules: MemeGameplayRules = competition.rules
	if state.local_samples.size() > rules.adaptation_stable_window_hours or state.local_samples.size() > int(state.last_hour) - int(state.target_started_hour): errors.append("Local adoption samples exceed their observed window")
	var total: float = 0.0
	for sample: Variant in state.local_samples:
		if not _unit(sample): errors.append("Local adoption samples require finite proportions")
		else: total += float(sample)
	if state.local_samples.size() == rules.adaptation_stable_window_hours and float(state.stable_peak) + 0.000000000001 < total / rules.adaptation_stable_window_hours: errors.append("The stable adoption peak must contain the latest complete mean")
	var adaptation: Dictionary = state.adaptation
	if adaptation.size() != 4 or not adaptation.has_all(["baseline", "revision_hour", "signature", "eligible"]): errors.append("Adaptation progress has invalid fields")
	elif not _unit(adaptation.baseline) or not _integer(adaptation.revision_hour) or not adaptation.signature is String or not adaptation.eligible is bool: errors.append("Adaptation progress has invalid values")
	elif int(adaptation.revision_hour) == -1:
		if float(adaptation.baseline) != 0.0 or not str(adaptation.signature).is_empty() or bool(adaptation.eligible): errors.append("An adaptation revision requires its own published observation")
	else:
		if int(adaptation.revision_hour) < int(state.target_started_hour) or int(adaptation.revision_hour) > hour or str(adaptation.signature).length() != 64 or float(adaptation.baseline) > float(state.stable_peak) + 0.000000000001 or bool(adaptation.eligible) != (float(adaptation.baseline) >= rules.adaptation_baseline_min): errors.append("Adaptation progress differs from its published baseline")
	if state.windows.size() != TARGET_WINDOWS.size() or not state.windows.has_all(TARGET_WINDOWS): errors.append("Independent ending windows require every target condition")
	else:
		for id: String in TARGET_WINDOWS:
			if not state.windows[id] is Dictionary or not _validate_window(state.windows[id], state, _required(id, rules)): errors.append("Independent ending window has invalid timing: " + id)
	if not errors.is_empty(): return errors
	var sources: Dictionary = _pair_sources(records, str(state.target_meme_id))
	for q: Variant in state.pairs:
		var pair: Variant = state.pairs[q]
		if not q is String or not sources.has(q) or not pair is Dictionary: errors.append("A substitute requires a direct independent split pair"); continue
		if pair.size() != 3 or not pair.has_all(["parent_meme_id", "parent_record_id", "window"]) or pair.parent_meme_id != sources[q].parent_meme_id or pair.parent_record_id != sources[q].parent_record_id or not pair.window is Dictionary or not _validate_window(pair.window, state, rules.substitute_hours): errors.append("A substitute pair differs from its source or observed window")
		elif int(pair.window.hours) > 0 and int(pair.window.start_hour) < int(competition._state.registry[q].birth_hour): errors.append("A substitute observation starts at its own independent birth")
	if not errors.is_empty(): return errors
	if state.rows.size() != PRIORITY.size(): return PackedStringArray(["Independent ending progress requires six display rows"])
	for index: int in PRIORITY.size():
		var id: String = PRIORITY[index]
		var row: Variant = state.rows[index]
		var expected: Dictionary = _blank_row(id, state, rules)
		_thresholds(expected, rules)
		if not row is Dictionary or row.size() != expected.size() or not row.has_all(expected.keys()): errors.append("Independent ending display row has invalid fields"); continue
		for key: String in ["id", "meme_id", "country_id", "winner_meme_id", "candidate_meme_id", "parent_meme_id", "parent_record_id", "other_meme_id"]:
			if not row[key] is String: errors.append("Independent ending row identities require text")
		for key: String in ["spread", "spread_min", "adoption", "adoption_min", "deviation", "deviation_max", "range", "range_max", "other_spread", "gap", "gap_max", "gain_min", "baseline", "baseline_min", "stable_peak", "lead_min"]:
			if not _unit(row[key]): errors.append("Independent ending row metrics require finite proportions")
		for key: String in ["lead", "gain"]:
			if not _number(row[key]) or absf(float(row[key])) > 1.0: errors.append("Independent ending differences require finite proportions")
		for key: String in ["hours", "required_hours", "adopted", "exposed", "seed_hours", "seed_required_hours"]:
			if not _integer(row[key]) or int(row[key]) < 0: errors.append("Independent ending row counters require nonnegative integers")
		if not row.qualified is bool or not row.adaptation_eligible is bool: errors.append("Independent ending row conditions require booleans")
		if not errors.is_empty(): return errors
		if row.id != id or row.meme_id != state.target_meme_id or row.country_id != state.country_id or not str(row.other_meme_id).is_empty() and not meme_ids.has(str(row.other_meme_id)): errors.append("Independent ending row differs from its target")
		for key: String in ["required_hours", "spread_min", "lead_min", "adoption_min", "deviation_max", "range_max", "gap_max", "gain_min", "baseline", "baseline_min", "stable_peak", "seed_required_hours", "adaptation_eligible"]:
			if row[key] != expected[key]: errors.append("Independent ending row differs from its configured threshold or baseline")
		var window: Dictionary = state.windows.get(id, _window())
		if id == "best_substitute":
			var q: String = str(row.candidate_meme_id)
			if q.is_empty():
				if not state.pairs.is_empty() or not str(row.winner_meme_id).is_empty() or not str(row.parent_meme_id).is_empty() or not str(row.parent_record_id).is_empty(): errors.append("A substitute display requires its selected direct pair")
			elif not state.pairs.has(q): errors.append("A substitute display references another pair")
			else:
				window = state.pairs[q].window
				if row.winner_meme_id != q or row.parent_meme_id != state.pairs[q].parent_meme_id or row.parent_record_id != state.pairs[q].parent_record_id: errors.append("A substitute display differs from its selected direct pair")
		else:
			if row.winner_meme_id != state.target_meme_id or not str(row.candidate_meme_id).is_empty() or not str(row.parent_meme_id).is_empty() or not str(row.parent_record_id).is_empty(): errors.append("A target ending display requires its single independent meme")
		if int(row.hours) != int(window.hours) or not _close(row.range, float(window.max) - float(window.min)) or not _close(row.lead, float(row.spread) - float(row.other_spread)) or not _close(row.gap, absf(float(row.lead))) or not _close(row.gain, float(row.adoption) - float(row.baseline)) or bool(row.qualified) != _qualified(row): errors.append("Independent ending display differs from its measured window")
		if int(row.hours) > 0 and not bool(row.qualified): errors.append("A qualifying observation window requires its current condition")
		if int(row.adopted) > int(row.exposed): errors.append("Independent adoption must remain inside exposure")
		if id == "balanced_duel" and int(row.hours) > 0 and str(window.other_meme_id) != str(row.other_meme_id): errors.append("A balanced duel keeps the same independent opponent")
		if id == "successful_adaptation" and int(row.hours) > 0 and int(window.start_hour) < int(state.adaptation.revision_hour): errors.append("An adaptation observation starts at its published revision")
		if id == "forgotten" and int(row.hours) > 0 and int(window.start_hour) < int(state.last_hour) - int(row.seed_hours) + rules.seed_hours: errors.append("A forgotten observation starts after seed circulation")
		if id == "local_classic" and int(row.hours) > 0:
			var count: int = mini(int(row.hours), state.local_samples.size())
			for offset: int in count:
				var sample: float = float(state.local_samples[state.local_samples.size() - 1 - offset])
				if sample < float(window.min) - 0.000000000001 or sample > float(window.max) + 0.000000000001: errors.append("A local classic range contains its observed adoption samples")
	return errors

static func validate_result(result: Dictionary, state: Dictionary, variants: Array, competition: RefCounted, hour: int) -> PackedStringArray:
	var errors: PackedStringArray = validate_state(state, variants, competition, hour)
	if not errors.is_empty(): return errors
	if state.is_empty() or int(state.last_hour) != hour: return PackedStringArray(["An independent ending requires the current observed hour"])
	var metrics: Dictionary = _metrics(variants, str(state.target_record_id), str(state.country_id), hour, competition, int(state.version))
	var checked: Dictionary = state.duplicate(true)
	checked.rows = _rows(checked, metrics, competition.rules)
	if competition._canonical(checked.rows) != competition._canonical(state.rows): errors.append("Independent ending metrics must match the current meme and its strongest competitors")
	var expected: Dictionary = _result(checked, hour)
	if expected.is_empty() or competition._canonical(result) != competition._canonical(expected): errors.append("Independent ending result differs from its qualified priority and winner")
	return errors
