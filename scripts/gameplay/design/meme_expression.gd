extends RefCounted

static func preset_name(preset: MemeDemoPreset, localized: bool = false) -> String:
	var key: String = {"case_s01":"LOC_STARTER_NAME_FINE", "case_s16":"LOC_STARTER_NAME_PEAK", "case_p11":"LOC_STARTER_NAME_67"}.get(str(preset.id), preset.title)
	return DeskLocalization.text(key) if localized else DeskLocalization.source(key)

## Render the same expression for the workbench preview and publication.
static func render(catalog: MemeDemoCatalog, draft: Dictionary) -> String:
	var slots: Dictionary = draft.get("slots", {}).duplicate(true)
	var record: Dictionary = draft.get("module_patch_record", {})
	var suffixes: Array = record.get("suffixes", [])
	for index in range(suffixes.size() - 1, -1, -1):
		var suffix: Dictionary = suffixes[index]
		var slot := str(suffix.slot_id)
		slots[slot] = str(slots.get(slot, "")).trim_suffix(str(suffix.content))
	var preset: MemeDemoPreset = catalog.find_preset(str(draft.get("preset_id", "")))
	var defaults := preset != null
	if preset != null:
		for index in preset.required_slots.size():
			defaults = defaults and str(slots.get(preset.required_slots[index], "")) == preset.default_values[index]
	var result := ""
	if defaults:
		result = preset_name(preset)
	else:
		var parts := PackedStringArray()
		for kernel: MemeDemoKernel in catalog.kernels:
			if str(kernel.id) == str(draft.get("kernel_id", "")):
				for slot: String in kernel.required_slots: parts.append(str(slots.get(slot, "")))
		result = " / ".join(parts)
	var suffix_index := 0
	for id: String in record.get("modules", []):
		if id.is_empty(): continue
		var content := str(suffixes[suffix_index].content).trim_prefix(" · ")
		suffix_index += 1
		var definition: Dictionary = catalog.DESIGN_RULES.find("modules", id)
		var authored_default := content == str(definition.get("content", ""))
		if id == "module_stance" and authored_default:
			result = result.rstrip(".。!?！？ ") + "?"
		else:
			# The installed language, not the interface locale, determines authored patch text.
			if authored_default and str(draft.get("language_id", "")) == "en":
				content = DeskLocalization.english_text(content)
			result += " · " + content
	return result
