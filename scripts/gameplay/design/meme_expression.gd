extends RefCounted

static func preset_name(preset: MemeDemoPreset, localized: bool = false) -> String:
	var key: String = {"case_s01":"LOC_STARTER_NAME_FINE", "case_s16":"LOC_STARTER_NAME_PEAK", "case_p11":"LOC_STARTER_NAME_67"}.get(str(preset.id), preset.title)
	return DeskLocalization.text(key) if localized else DeskLocalization.source(key)

## The ledger suffixes stay internal; base nodes retain their original expression.
static func base_slots(draft: Dictionary) -> Dictionary:
	var slots: Dictionary = draft.get("slots", {}).duplicate(true)
	var suffixes: Array = draft.get("module_patch_record", {}).get("suffixes", [])
	for index in range(suffixes.size() - 1, -1, -1):
		var suffix: Dictionary = suffixes[index]
		var slot := str(suffix.slot_id)
		slots[slot] = str(slots.get(slot, "")).trim_suffix(str(suffix.content))
	return slots

## Render the same expression for the workbench preview and publication.
static func render(catalog: MemeDemoCatalog, draft: Dictionary) -> String:
	var slots := base_slots(draft)
	var record: Dictionary = draft.get("module_patch_record", {})
	var suffixes: Array = record.get("suffixes", [])
	var preset: MemeDemoPreset = catalog.find_preset(str(draft.get("preset_id", "")))
	var defaults := preset != null and str(preset.id) in catalog.DESIGN_RULES.starter_presets
	if preset != null:
		for index in preset.required_slots.size():
			defaults = defaults and str(slots.get(preset.required_slots[index], "")) == preset.default_values[index]
	var route_modules: Array[String] = []
	var authored_patches := PackedStringArray()
	var suffix_index := 0
	for id: String in record.get("modules", []):
		if id.is_empty(): continue
		var content := str(suffixes[suffix_index].content).trim_prefix(" · ")
		suffix_index += 1
		var definition: Dictionary = catalog.DESIGN_RULES.find("modules", id)
		var authored_default := content == str(definition.get("content", ""))
		if defaults and authored_default: route_modules.append(id)
		else: authored_patches.append(content)
	var parts := PackedStringArray()
	if defaults:
		parts.append(catalog.DESIGN_RULES.expression_route(str(preset.id), route_modules))
	else:
		# Preserve authored legacy text literally; the current editor exposes no text input.
		for kernel: MemeDemoKernel in catalog.kernels:
			if str(kernel.id) == str(draft.get("kernel_id", "")):
				for slot: String in kernel.required_slots: parts.append(str(slots.get(slot, "")))
	parts.append_array(authored_patches)
	return "\n".join(parts)
