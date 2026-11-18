extends RefCounted

const CONTENT_PATH := "res://data/propagation/content_profiles.json"
const ALTERNATIVE_TEXT_QUALITY := 0.85
const Composition = preload("res://scripts/gameplay/design/meme_composition.gd")
const EffectRules = preload("res://scripts/gameplay/events/effect_rules.gd")
const Deviation = preload("res://scripts/gameplay/competition/meme_deviation.gd")
static var _content: Dictionary = {}
static var _signature := ""

func _init() -> void:
	if _content.is_empty():
		var raw := FileAccess.get_file_as_string(CONTENT_PATH)
		_content = JSON.parse_string(raw)
		_signature = raw.sha256_text()

func signature() -> String:
	return _signature

func content_profile(preset_id: String) -> Dictionary:
	return _content.profiles.get(preset_id, _content.fallback).duplicate(true)

func metadata(profile: Dictionary, draft: Dictionary) -> Dictionary:
	var preset_id := str(draft.get("preset_id", ""))
	var source := content_profile(preset_id)
	var slots: Array = []
	for slot: String in source.fillable_slots:
		if slot in draft.get("replaceable_slots", []) and draft.get("slots", {}).has(slot): slots.append(slot)
	var versions: Dictionary = {}
	if Composition.supports(preset_id) and source.translation_source == "composition_language_versions":
		for language: String in source.platform_languages:
			var translated := draft.duplicate(true)
			translated.language_id = language
			translated.language_ids = [language]
			var composed := Composition.compose(translated, draft.get("patch_ids", Composition._modules(draft.get("module_patch_record", {}).get("modules", []))))
			if not composed.is_empty(): versions[language] = str(composed.expression)
	var permission: bool = str(draft.get("reuse_permission", "unknown")) != "restricted" and source.template_permission == "community_fill_allowed"
	return {"schema":1, "content_signature":signature(), "preset_id":preset_id, "review_status":str(source.review_status), "plain_text_fraction":float(source.plain_text_fraction), "embedded_text_fraction":float(source.embedded_text_fraction), "visual_information_fraction":float(source.visual_information_fraction), "visual_svg":str(source.visual_svg), "caption_regions":source.caption_regions.duplicate(true), "translations":versions, "context_note":source.context_note.duplicate(true), "alternative_text":source.alternative_text.duplicate(true), "form_anchor":str(source.form_anchor), "fillable_slots":slots, "template_permission":permission, "source_package_available":bool(source.source_package_available)}

func _skills(profile: Dictionary) -> Array:
	return profile.get("skill_ids", [])

func available_formats(profile: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var skills := _skills(profile)
	var meta: Dictionary = profile.propagation_meta
	var original_languages: Array = profile.get("language_ids", [str(profile.language_id)]).duplicate()
	result.append({"format":"text", "languages":original_languages, "quality":1.0})
	var translated: Array = meta.translations.keys() if "machine_translation" in skills else []
	if not translated.is_empty():
		for language: String in original_languages:
			if language not in translated: translated.append(language)
	if not translated.is_empty(): result.append({"format":"translated_text", "languages":translated, "quality":1.0})
	if "image" in skills and not str(meta.visual_svg).is_empty():
		result.append({"format":"image", "languages":original_languages, "quality":1.0})
		if "multilingual_typesetting" in skills and not translated.is_empty() and not meta.caption_regions.is_empty(): result.append({"format":"localized_image", "languages":translated, "quality":1.0})
		if "alternative_text" in skills and not meta.alternative_text.is_empty():
			var alt_languages := _alternative_languages(profile)
			if not alt_languages.is_empty(): result.append({"format":"alternative_text", "languages":alt_languages, "quality":ALTERNATIVE_TEXT_QUALITY})
	return result

func _alternative_languages(profile: Dictionary) -> Array[String]:
	var languages: Array[String] = []
	var meta: Dictionary = profile.propagation_meta
	var original: Array = profile.get("language_ids", [str(profile.language_id)])
	for language: String in meta.alternative_text:
		if language in original or ("machine_translation" in _skills(profile) and meta.translations.has(language)):
			languages.append(language)
	return languages

func _language_match(distribution: Dictionary, languages: Array) -> float:
	var result := 0.0
	for language: Variant in languages: result = maxf(result, float(distribution.get(str(language),0.0)))
	return result

func _supports(channel: String, format_name: String) -> bool:
	var supported: Array = _content.channel_formats.get(channel,["text"])
	return ("text" if format_name == "translated_text" else format_name) in supported

func _format_language(profile: Dictionary, country: Dictionary, format: Dictionary) -> float:
	var meta: Dictionary = profile.propagation_meta
	var language := _language_match(country.languages,format.languages)
	if str(format.format) not in ["image", "localized_image"]: return language
	var original: Array = profile.get("language_ids",[str(profile.language_id)])
	var raw := _language_match(country.languages,original)
	var readable := raw
	if "machine_translation" in _skills(profile) and not meta.translations.is_empty(): readable = maxf(raw, _language_match(country.languages,meta.translations.keys()))
	var embedded := language if str(format.format) == "localized_image" else raw
	# Only independently conveyed visual information receives the visual-language exemption.
	var visual := 1.0-(1.0-raw)*0.1
	var image_readability := float(meta.plain_text_fraction)*readable + float(meta.embedded_text_fraction)*embedded + float(meta.visual_information_fraction)*visual
	if "alternative_text" in _skills(profile):
		var description_readability := _language_match(country.languages, _alternative_languages(profile)) * ALTERNATIVE_TEXT_QUALITY
		image_readability = maxf(image_readability, description_readability)
	return image_readability

func delivery(profile: Dictionary, country: Dictionary) -> Dictionary:
	var options := available_formats(profile)
	var candidates: Array[Dictionary] = []
	for option: Dictionary in options:
		if _supports(str(profile.channel_id),str(option.format)): candidates.append(option)
	var selected: Dictionary = candidates[0]
	var skills := _skills(profile)
	if "format_distribution" in skills:
		var best := -1.0
		for option: Dictionary in candidates:
			var score := _format_language(profile,country,option)*float(option.quality)
			if score > best:
				best = score
				selected = option
	else:
		var preference: Array = ["localized_image","image","translated_text","text"]
		if "image" in skills and not _supports(str(profile.channel_id),"image") and "alternative_text" in skills: preference = ["alternative_text","translated_text","text"]
		var found := false
		for name: String in preference:
			for option: Dictionary in candidates:
				if str(option.format) == name:
					selected = option
					found = true
					break
			if found: break
	var note: bool = "context_note" in skills and not profile.propagation_meta.context_note.is_empty()
	return {"format":str(selected.format),"language":_format_language(profile,country,selected),"quality":float(selected.quality),"languages":selected.languages.duplicate(),"context_note_attached":note,"context_dependency":float(profile.context_dependency)*(0.6 if note else 1.0),"available_formats":options}

func can_template(profile: Dictionary) -> bool:
	var meta: Dictionary = profile.get("propagation_meta", {})
	return "public_template" in _skills(profile) and bool(meta.get("template_permission",false)) and not meta.get("fillable_slots",[]).is_empty() and not str(meta.get("form_anchor","")).is_empty()

func community_reuse(profile: Dictionary, draft: Dictionary, required_slots: int, baseline: float) -> float:
	if not can_template(profile) or "source_package" not in _skills(profile) or not bool(profile.propagation_meta.source_package_available): return baseline
	return EffectRules.reuse_factor(str(draft.reuse_permission), draft.replaceable_slots.size(), required_slots, float(profile.remix_cost)*0.4, float(profile.context_dependency))

func split_threshold(base: float, parent: Dictionary, mutation: Dictionary) -> float:
	var profile: Dictionary = parent.get("flow_profile", {})
	var adjusted := Deviation.threshold(base, _skills(profile))
	var meta: Dictionary = profile.get("propagation_meta", {})
	if "semantic_detachment" not in _skills(profile) or not can_template(profile): return adjusted
	var draft: Dictionary = mutation.get("flow_draft", {})
	if str(draft.get("preset_id","")) != str(parent.get("preset_id","")) or str(draft.get("kernel_id","")) != str(parent.get("kernel_id","")): return adjusted
	if not bool(mutation.get("form_preserved",true)): return adjusted
	for slot: String in meta.fillable_slots:
		if str(draft.get("slots",{}).get(slot,"")).is_empty(): return adjusted
	return Deviation.threshold(maxf(base, 0.75), _skills(profile))

func validate_profile(profile: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var meta: Variant = profile.get("propagation_meta")
	if not meta is Dictionary or not meta.has_all(["schema","content_signature","preset_id","review_status","plain_text_fraction","embedded_text_fraction","visual_information_fraction","visual_svg","caption_regions","translations","context_note","alternative_text","form_anchor","fillable_slots","template_permission","source_package_available"]): return PackedStringArray(["propagation: missing profile metadata"])
	if meta.schema != 1 or meta.content_signature != signature() or not meta.preset_id is String: errors.append("propagation: content signature mismatch")
	var declared := content_profile(str(meta.preset_id))
	for field: String in ["review_status","visual_svg","form_anchor","source_package_available"]:
		if meta[field] != declared[field]: errors.append("propagation: declared content mismatch "+field)
	var total := 0.0
	for field: String in ["plain_text_fraction","embedded_text_fraction","visual_information_fraction"]:
		var value: Variant = meta[field]
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1.0: errors.append("propagation: invalid information fraction")
		else:
			total += float(value)
			if not is_equal_approx(float(value),float(declared[field])): errors.append("propagation: declared fraction mismatch")
	if not is_equal_approx(total,1.0): errors.append("propagation: information fractions must sum to one")
	for field: String in ["translations","context_note","alternative_text"]:
		if not meta[field] is Dictionary: errors.append("propagation: invalid reviewed text table")
		else:
			for language: Variant in meta[field]:
				if not language is String or language not in declared.platform_languages or not meta[field][language] is String or str(meta[field][language]).is_empty(): errors.append("propagation: invalid reviewed text entry")
	for field: String in ["context_note","alternative_text"]:
		if meta[field] != declared[field]: errors.append("propagation: reviewed copy mismatch")
	if not meta.fillable_slots is Array or not meta.caption_regions is Array or not meta.template_permission is bool or meta.caption_regions != declared.caption_regions: errors.append("propagation: invalid template or format metadata")
	else:
		for slot: Variant in meta.fillable_slots:
			if not slot is String or slot not in declared.fillable_slots: errors.append("propagation: unknown fillable slot")
	return errors
