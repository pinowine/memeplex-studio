@tool
extends RefCounted

const QUESTION := "module_stance"
const COMPARISON := "module_relation"
const EXPLANATION := "module_boundary"
const CONTINUATION := "module_shared_world"
const EXIT := "module_ritual"
const SEEDS := ["versailles_2020", "nobody_2020", "ok_boomer_2020"]
const LANGUAGES := ["ninghua", "shiohara", "seowon"]
const GROUPS := ["commuters", "students", "culture_fans"]
const SCENES := {
	"versailles_2020": {"":"exam", "education":"exam", "community+education":"class_chat", "education+work":"qualification", "education+entertainment":"trivia"},
	"nobody_2020": {"":"film", "entertainment":"film", "community+entertainment":"fan_chat", "work":"office", "platform_tools+work":"software", "education":"lesson"},
	"ok_boomer_2020": {"":"school", "education":"school", "education+work":"first_job", "work":"overtime", "cost_of_living+work":"rent", "community":"neighborhood"}
}

static func supports(preset_id: String) -> bool:
	return preset_id in SEEDS

static func definition(preset_id: String) -> Dictionary:
	var definitions := {
		"versailles_2020":{"compatible_modules":[QUESTION,COMPARISON,EXPLANATION], "requires":{}, "default_context":{"language_id":"ninghua","group_id":"students","topic_ids":["education"],"political_position":[0.0,0.3],"political_known":true,"pragmatic_position":[0.8,0.1]}, "meaning_bounds":{"political_position":[-0.5,0.5,-0.3,1.0],"pragmatic_position":[0.2,1.0,-0.5,1.0]}},
		"nobody_2020":{"compatible_modules":[COMPARISON,EXPLANATION,CONTINUATION,EXIT], "requires":{EXIT:[CONTINUATION]}, "default_context":{"language_id":"shiohara","group_id":"culture_fans","topic_ids":["entertainment"],"political_position":[0.0,0.0],"political_known":true,"pragmatic_position":[0.7,0.1]}, "meaning_bounds":{"political_position":[-0.6,0.6,-0.6,0.6],"pragmatic_position":[0.2,1.0,-0.6,0.8]}},
		"ok_boomer_2020":{"compatible_modules":[QUESTION,COMPARISON,EXPLANATION,EXIT], "requires":{}, "default_context":{"language_id":"seowon","group_id":"students","topic_ids":["education"],"political_position":[-0.4,-0.2],"political_known":true,"pragmatic_position":[0.6,0.7]}, "meaning_bounds":{"political_position":[-1.0,0.2,-1.0,0.3],"pragmatic_position":[0.1,1.0,0.2,1.0]}}
	}
	if not supports(preset_id): return {}
	var result: Dictionary = definitions[preset_id]
	result.max_modules = 4
	result.title = _text(_seed(preset_id)+"_TITLE")
	result.media = DeskLocalization.source("LOC_COMPOSE_MEDIA_TEXT")
	result.illustration = ""
	result.scenes = SCENES[preset_id].duplicate()
	return result

static func validate(draft: Dictionary, module_ids: Array) -> PackedStringArray:
	var id := str(draft.get("preset_id",""))
	if not supports(id): return _error("SEED")
	var errors := PackedStringArray()
	var rules := definition(id)
	var modules := _modules(module_ids)
	if modules.size() > 4: errors.append_array(_error("SLOTS"))
	var seen := {}
	for module_id: String in modules:
		if seen.has(module_id): errors.append_array(_error("DUPLICATE"))
		seen[module_id] = true
		if module_id not in rules.compatible_modules: errors.append_array(_error("PATCH"))
		for required: String in rules.requires.get(module_id,[]):
			if required not in modules: errors.append_array(_error("EXIT"))
	for language_id: String in _values(draft,"language"):
		if language_id not in LANGUAGES: errors.append_array(_error("LANGUAGE"))
	for group_id: String in _values(draft,"group"):
		if group_id not in GROUPS: errors.append_array(_error("GROUP"))
	if _scene(draft).is_empty(): errors.append_array(_error("SCENE"))
	for field: String in rules.meaning_bounds:
		if not _meaning_attached(draft,field): continue
		var point := _position(draft.get(field,Vector2.ZERO))
		var bounds: Array = rules.meaning_bounds[field]
		for axis in 2:
			var value: float = point[axis]
			var lower: float = bounds[axis*2]
			var upper: float = bounds[axis*2+1]
			if (value < lower and not is_equal_approx(value,lower)) or (value > upper and not is_equal_approx(value,upper)):
				errors.append_array(_error("MEANING"))
	return errors

static func compose(draft: Dictionary, module_ids: Array) -> Dictionary:
	if not validate(draft,module_ids).is_empty(): return {}
	var modules := _modules(module_ids)
	var defaults: Dictionary = definition(str(draft.preset_id)).default_context
	var languages := _values(draft,"language")
	var language_id := str(draft.get("language_id",defaults.language_id))
	if language_id not in languages: language_id = languages[0] if not languages.is_empty() else str(defaults.language_id)
	var segments := _expression_segments(draft,modules,language_id)
	var meaning := _meaning(draft,modules)
	var context := _context_segments(draft)
	var versions: Array[Dictionary] = []
	for language: String in languages:
		versions.append({"language_id":language,"expression":_join(_expression_segments(draft,modules,language))})
	return {"expression":_join(segments),"meaning":_join(meaning.segments),"meaning_id":meaning.id,"expression_segments":segments,"meaning_segments":meaning.segments,"context_segments":context,"language_versions":versions,"media":DeskLocalization.source("LOC_COMPOSE_MEDIA_TEXT"),"illustration":"","effects":{}}

static func _expression_segments(draft: Dictionary, modules: Array[String], language_id: String) -> Array[Dictionary]:
	var seed := _seed(str(draft.preset_id))
	var scene := _scene(draft)
	var sources := _scene_sources(draft)
	var defaults: Dictionary = definition(str(draft.preset_id)).default_context
	var language_sources: Array[Dictionary] = []
	if language_id != str(defaults.language_id): language_sources = [_source("language",language_id)]
	var group := _primary_group(draft)
	var group_sources: Array[Dictionary] = []
	if group != str(defaults.group_id): group_sources = [_source("group",group)]
	var result: Array[Dictionary] = []
	if seed == "V":
		result.append(_segment("V_LEAD_"+language_id.to_upper(),language_sources,"V_LEAD_NINGHUA"))
		var details := sources.duplicate()
		if scene == "exam": details.append_array(group_sources)
		var situation := "EXAM_"+group.to_upper() if scene == "exam" else scene.to_upper()
		if COMPARISON in modules: result.append(_versailles_segment(situation,"COMPARISON",details,COMPARISON))
		result.append(_versailles_segment(situation,"EFFORT",details))
		result.append(_versailles_segment(situation,"QUESTION" if QUESTION in modules else "RESULT",details,QUESTION if QUESTION in modules else ""))
		if EXPLANATION in modules: result.append(_versailles_segment(situation,"EXPLANATION",details,EXPLANATION))
	elif seed == "N":
		result.append(_segment("N_NOBODY",[]))
		if COMPARISON in modules: result.append(_segment("N_COMPARISON",[_source("patch",COMPARISON)]))
		result.append(_segment("N_SPEAKER_"+group.to_upper(),group_sources,"N_SPEAKER_CULTURE_FANS"))
		result.append(_segment("N_LANGUAGE_"+language_id.to_upper(),language_sources,"N_LANGUAGE_SHIOHARA"))
		result.append(_segment("N_"+scene.to_upper()+"_ACTION",sources,"N_FILM_ACTION"))
		if EXPLANATION in modules: result.append(_segment("N_"+scene.to_upper()+"_EXPLANATION",_with_patch(sources,EXPLANATION)))
		if CONTINUATION in modules:
			result.append(_segment("N_INVITE",[_source("patch",CONTINUATION)]))
			if EXIT in modules: result.append(_segment("N_EXIT",[_source("patch",CONTINUATION),_source("patch",EXIT)]))
	else:
		if QUESTION in modules: result.append(_segment("B_QUESTION",[_source("patch",QUESTION)]))
		if COMPARISON in modules: result.append(_segment("B_"+scene.to_upper()+"_COMPARISON",_with_patch(sources,COMPARISON)))
		result.append(_segment("B_REPLY_"+language_id.to_upper(),language_sources,"B_REPLY_SEOWON"))
		if EXPLANATION in modules: result.append(_segment("B_EXPLANATION",[_source("patch",EXPLANATION)]))
		if EXIT in modules: result.append(_segment("B_EXIT",[_source("patch",EXIT)]))
	return result

static func _versailles_segment(scene: String, part: String, sources: Array, patch: String = "") -> Dictionary:
	var key := "V_"+scene+"_"+part
	var changed: Array = [] if _text(key) == _text("V_EXAM_STUDENTS_"+part) else sources.duplicate()
	if not patch.is_empty(): changed.append(_source("patch",patch))
	var original := ""
	if part in ["EFFORT","RESULT","QUESTION"]:
		original = "V_EXAM_STUDENTS_"+("RESULT" if part == "QUESTION" else part)
	return _segment(key,changed,original)

static func _context_segments(draft: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var groups := _values(draft,"group")
	groups.sort()
	if groups.size() > 1:
		var added: Array[Dictionary] = []
		var default_group := str(definition(str(draft.preset_id)).default_context.group_id)
		for group_id: String in groups:
			if group_id != default_group: added.append(_source("group",group_id))
		result.append(_segment("AUDIENCE_"+"_".join(groups).to_upper(),added))
	if str(draft.preset_id) != "ok_boomer_2020": return result
	var group := _primary_group(draft)
	var sources: Array[Dictionary] = []
	if group != str(definition(str(draft.preset_id)).default_context.group_id): sources.append(_source("group",group))
	result.append(_segment("B_SPEAKER_"+group.to_upper(),sources,"B_SPEAKER_STUDENTS"))
	result.append(_segment("B_"+_scene(draft).to_upper()+"_CONTEXT",_scene_sources(draft),"B_SCHOOL_CONTEXT"))
	return result

static func _meaning(draft: Dictionary, modules: Array[String]) -> Dictionary:
	var seed := _seed(str(draft.preset_id))
	var defaults: Dictionary = definition(str(draft.preset_id)).default_context
	var segments: Array[Dictionary] = [_segment(seed+"_MEANING",[])]
	var names := {QUESTION:"QUESTION",COMPARISON:"COMPARISON",EXPLANATION:"EXPLANATION",CONTINUATION:"CONTINUATION",EXIT:"EXIT"}
	for module_id: String in modules:
		segments.append(_segment(seed+"_MEANING_"+str(names[module_id]),[_source("patch",module_id)]))
	var identity: Array[String] = [str(draft.preset_id),"+".join(modules)]
	for field: String in ["political_position","pragmatic_position"]:
		if not _meaning_attached(draft,field): continue
		var point := _position(draft.get(field,Vector2.ZERO))
		var origin := _position(defaults[field])
		var kind := "stance" if field == "political_position" else "pragmatic"
		identity.append("%s:%.2f,%.2f" % [kind,point.x,point.y])
		var names_by_direction := ["freedom","authority","equality","hierarchy"] if kind == "stance" else ["sincere","ironic","support","opposition"]
		for axis in 2:
			if is_equal_approx(point[axis],origin[axis]): continue
			var direction: String = names_by_direction[axis*2+int(point[axis]>origin[axis])]
			var key := seed+"_READING_"+direction.to_upper()
			if absf(point[axis]-origin[axis]) > 0.4: key += "_STRONG"
			segments.append(_segment(key,[_source(kind,direction)]))
	return {"segments":segments,"id":"/".join(identity)}

static func _scene(draft: Dictionary) -> String:
	return str(SCENES[str(draft.preset_id)].get("+".join(_topics(draft)),""))

static func _scene_sources(draft: Dictionary) -> Array[Dictionary]:
	var baseline: Dictionary = definition(str(draft.preset_id)).default_context.duplicate(true)
	baseline.preset_id = str(draft.preset_id)
	var sources: Array[Dictionary] = []
	if _scene(draft) != _scene(baseline):
		var original_topics := _topics(baseline)
		for topic: String in _topics(draft):
			if topic not in original_topics: sources.append(_source("topic",topic))
	return sources

static func _topics(draft: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if _attached(draft,"topics"):
		for value: Variant in draft.get("topic_ids",[]):
			if str(value) not in result: result.append(str(value))
	result.sort()
	return result

static func _primary_group(draft: Dictionary) -> String:
	var values := _values(draft,"group")
	values.sort()
	var primary := str(draft.get("group_id",""))
	return primary if primary in values else (values[0] if not values.is_empty() else str(definition(str(draft.preset_id)).default_context.group_id))

static func _values(draft: Dictionary, kind: String) -> Array[String]:
	var result: Array[String] = []
	if not _attached(draft,kind): return result
	for value: Variant in draft.get(kind+"_ids",[draft.get(kind+"_id","")]):
		if not str(value).is_empty() and str(value) not in result: result.append(str(value))
	return result

static func _modules(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		if not str(value).is_empty(): result.append(str(value))
	result.sort()
	return result

static func _meaning_attached(draft: Dictionary, field: String) -> bool:
	return _attached(draft,"pragmatic") if field == "pragmatic_position" else _attached(draft,"stance") and bool(draft.get("political_known",false))

static func _attached(draft: Dictionary, layer: String) -> bool:
	return bool(draft.get("context_layer_attachment",{}).get(layer,true))

static func _position(value: Variant) -> Vector2:
	return value if value is Vector2 else Vector2(float(value[0]),float(value[1]))

static func _source(kind: String, id: String) -> Dictionary:
	return {"kind":kind,"id":kind+"_"+id if kind in ["language","group","topic"] else id}

static func _with_patch(sources: Array, id: String) -> Array:
	var result := sources.duplicate()
	result.append(_source("patch",id))
	return result

static func _segment(key: String, sources: Array, original_key: String = "") -> Dictionary:
	var result := {"text":_text(key),"sources":sources.duplicate(true)}
	# Stable phrase roles keep additions from crossing out unrelated parts of the seed.
	if not original_key.is_empty():
		var original := _text(original_key)
		if original != str(result.text): result.original_text = original
	return result

static func _join(segments: Array) -> String:
	var parts: Array[String] = []
	for segment: Dictionary in segments: parts.append(str(segment.text))
	return DeskLocalization.source_join("",parts)

static func _seed(preset_id: String) -> String:
	return {"versailles_2020":"V","nobody_2020":"N","ok_boomer_2020":"B"}[preset_id]

static func _text(key: String) -> String:
	return DeskLocalization.source("LOC_TEXT_COMPOSE_"+key)

static func _error(key: String) -> PackedStringArray:
	return PackedStringArray([DeskLocalization.source("LOC_COMPOSE_ERROR_"+key)])
