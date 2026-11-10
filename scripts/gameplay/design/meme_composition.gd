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
	var defaults: Dictionary = definition(str(draft.preset_id)).default_context
	var language_sources: Array[Dictionary] = []
	if language_id != str(defaults.language_id): language_sources.append(_source("language",language_id))
	var scene_sources := _content_sources(draft)
	var body_sources := scene_sources.duplicate()
	for module_id: String in modules: body_sources.append(_source("patch",module_id))
	var result: Array[Dictionary] = []
	var audience := _audience_key(draft)
	if seed == "V":
		if not audience.is_empty(): result.append(_segment("AUDIENCE_V_"+audience,_group_sources(draft)))
		result.append(_segment("V_LEAD_"+language_id.to_upper(),language_sources))
		var mask := _mask(modules,[QUESTION,COMPARISON,EXPLANATION])
		var fields := [["EFFORT","RESULT"],["EFFORT","RESULT"],["PEER","EFFORT","RESULT"],["PEER","EFFORT","RESULT"],["CAUSE","EFFORT","RESULT"],["CAUSE","EFFORT","RESULT"],["PEER","CAUSE","EFFORT","RESULT"],["PEER","CAUSE","EFFORT","RESULT"]]
		result.append(_formatted_segment("V_FORM_"+str(mask),_scene_values(draft,fields[mask]),body_sources))
	elif seed == "N":
		var opening := _segment("N_NOBODY",[])
		if COMPARISON in modules:
			opening = _formatted_segment("N_COMPARE",_scene_values(draft,["PEER"]),_with_patch(scene_sources,COMPARISON))
		result.append(opening)
		result.append(_scene_segment(draft,"SPEAKER",scene_sources) if audience.is_empty() else _segment("AUDIENCE_N_"+audience,_group_sources(draft)))
		if EXPLANATION in modules:
			result.append(_formatted_segment("N_REASON",_scene_values(draft,["REASON"]),_with_patch(scene_sources,EXPLANATION)))
		result.append(_segment("N_LANGUAGE_"+language_id.to_upper(),language_sources))
		var action := 2 if EXIT in modules else (1 if CONTINUATION in modules else 0)
		var action_sources := scene_sources.duplicate()
		if CONTINUATION in modules: action_sources.append(_source("patch",CONTINUATION))
		if EXIT in modules: action_sources.append(_source("patch",EXIT))
		result.append(_formatted_segment("N_ACTION_"+str(action),_scene_values(draft,["ACTION"]),action_sources))
	else:
		var mask := _mask(modules,[QUESTION,COMPARISON,EXPLANATION,EXIT])
		var fields := [["REPLY"],["QUESTION","REPLY"],["COMPARISON","REPLY"],["COMPARISON","QUESTION","REPLY"],["REASON","REPLY"],["REASON","QUESTION","REPLY"],["COMPARISON","REASON","REPLY"],["COMPARISON","REASON","QUESTION","REPLY"],["REPLY","DEPARTURE"],["QUESTION","REPLY","DEPARTURE"],["COMPARISON","REPLY","DEPARTURE"],["COMPARISON","QUESTION","REPLY","DEPARTURE"],["REASON","REPLY","DEPARTURE"],["REASON","QUESTION","REPLY","DEPARTURE"],["COMPARISON","REASON","REPLY","DEPARTURE"],["COMPARISON","REASON","QUESTION","REPLY","DEPARTURE"]]
		var values: Array[String] = []
		for field: String in fields[mask]:
			values.append(_text("B_REPLY_"+language_id.to_upper()) if field == "REPLY" else _scene_text(draft,field))
		if mask == 0: body_sources.clear()
		body_sources.append_array(language_sources)
		result.append(_reply_segment("B_FORM_"+str(mask),values,body_sources))
	return result

static func _context_segments(draft: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if str(draft.preset_id) != "ok_boomer_2020": return result
	var audience := _audience_key(draft)
	if not audience.is_empty(): result.append(_segment("AUDIENCE_B_"+audience,_group_sources(draft)))
	result.append(_scene_segment(draft,"CONTEXT",_content_sources(draft)))
	return result

static func _meaning(draft: Dictionary, modules: Array[String]) -> Dictionary:
	var seed := _seed(str(draft.preset_id))
	var orders := {"V":[QUESTION,COMPARISON,EXPLANATION],"N":[COMPARISON,EXPLANATION,CONTINUATION,EXIT],"B":[QUESTION,COMPARISON,EXPLANATION,EXIT]}
	var tone := _reading(draft,"pragmatic_position")
	var stance := _reading(draft,"political_position")
	var tone_segment := _segment("%s_TONE_%d_%d" % [seed,tone.x,tone.y],tone.sources)
	var audience := _audience_key(draft)
	if not audience.is_empty():
		var sources: Array = _group_sources(draft)
		sources.append_array(tone.sources)
		tone_segment = _formatted_segment("AUDIENCE_MEANING",[_text("AUDIENCE_M_"+audience),tone_segment.text],sources)
	var core_sources := _content_sources(draft)
	for module_id: String in modules: core_sources.append(_source("patch",module_id))
	var core := _formatted_segment(seed+"_MEANING_"+str(_mask(modules,orders[seed])),_scene_values(draft,["SUBJECT"]),core_sources)
	var ending := _segment("%s_STANCE_%d_%d" % [seed,stance.x,stance.y],stance.sources)
	var groups := _values(draft,"group")
	groups.sort()
	var identity: Array[String] = [str(draft.preset_id),"composition:2",_scene(draft),_primary_group(draft),"+".join(groups),"+".join(modules)]
	for field: String in ["political_position","pragmatic_position"]:
		if not _meaning_attached(draft,field): continue
		var point := _position(draft.get(field,Vector2.ZERO))
		identity.append("%s:%.2f,%.2f" % [field,point.x,point.y])
	return {"segments":[tone_segment,core,ending],"id":"/".join(identity)}

static func _reading(draft: Dictionary, field: String) -> Dictionary:
	var pragmatic := field == "pragmatic_position"
	var defaults: Dictionary = definition(str(draft.preset_id)).default_context
	var origin := _position(defaults[field])
	var point := _position(draft.get(field,Vector2.ZERO)) if _meaning_attached(draft,field) else origin
	var axes := _reading_axes(point,pragmatic)
	var original_axes := _reading_axes(origin,pragmatic)
	var result := {"x":axes.x,"y":axes.y,"sources":[]}
	var names := ["sincere","ironic","support","opposition"] if pragmatic else ["freedom","authority","equality","hierarchy"]
	for axis in 2:
		if axes[axis] == original_axes[axis]: continue
		var positive := point[axis] > origin[axis]
		var direction: String = names[axis*2+int(positive)]
		result.sources.append(_source("pragmatic" if pragmatic else "stance",direction))
	return result

static func _reading_axes(point: Vector2, pragmatic: bool) -> Vector2i:
	# The selected position controls the reading; small moves within it keep the same prose.
	var x := (0 if point.x < 0.45 else (2 if point.x > 0.85 else 1)) if pragmatic else (2 if point.x < -0.25 else (1 if point.x > 0.25 else 0))
	var y := 1 if point.y < -0.25 else (2 if point.y > 0.25 else 0)
	return Vector2i(x,y)

static func _mask(modules: Array[String], order: Array) -> int:
	var mask := 0
	for index in order.size():
		if str(order[index]) in modules: mask |= 1 << index
	return mask

static func _scene_values(draft: Dictionary, fields: Array) -> Array[String]:
	var values: Array[String] = []
	for field: String in fields: values.append(_scene_text(draft,field))
	return values

static func _scene_text(draft: Dictionary, field: String) -> String:
	var actual_field := "SUBJECT_NOUN" if field == "SUBJECT" and str(draft.preset_id) == "ok_boomer_2020" else field
	return _text("_".join([_seed(str(draft.preset_id)),_scene(draft),_primary_group(draft),actual_field]).to_upper())

static func _scene_segment(draft: Dictionary, field: String, sources: Array) -> Dictionary:
	var value := _scene_text(draft,field)
	var baseline: Dictionary = definition(str(draft.preset_id)).default_context.duplicate(true)
	baseline.preset_id = str(draft.preset_id)
	return {"text":value,"sources":[] if value == _scene_text(baseline,field) else sources.duplicate(true)}

static func _audience_key(draft: Dictionary) -> String:
	var groups := _values(draft,"group")
	groups.sort()
	return "_".join(groups).to_upper() if groups.size() > 1 else ""

static func _group_sources(draft: Dictionary) -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	var default_group := str(definition(str(draft.preset_id)).default_context.group_id)
	var groups := _values(draft,"group")
	groups.sort()
	for group: String in groups:
		if group != default_group: sources.append(_source("group",group))
	return sources

static func _content_sources(draft: Dictionary) -> Array[Dictionary]:
	var sources := _scene_sources(draft)
	var group := _primary_group(draft)
	if group != str(definition(str(draft.preset_id)).default_context.group_id): sources.append(_source("group",group))
	return sources

static func _formatted_segment(key: String, values: Array, sources: Array) -> Dictionary:
	return {"text":DeskLocalization.source_format("LOC_TEXT_COMPOSE_V2_"+key,values,range(values.size())),"sources":sources.duplicate(true)}

static func _reply_segment(key: String, values: Array, sources: Array) -> Dictionary:
	var result := _formatted_segment(key,values,sources)
	var english := DeskLocalization.english_text(result.text)
	var capital := true
	var sentence := ""
	# The same reply phrase can open a sentence or follow another clause.
	for index in english.length():
		var character := english.substr(index,1)
		sentence += character.to_upper() if capital else character
		if character in [".","?","!"]: capital = true
		elif character != " ": capital = false
	DeskLocalization.register_display(result.text,sentence,DeskLocalization.chinese_text(result.text))
	return result

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

static func _segment(key: String, sources: Array) -> Dictionary:
	return {"text":_text(key),"sources":sources.duplicate(true)}

static func _join(segments: Array) -> String:
	var parts: Array[String] = []
	for segment: Dictionary in segments: parts.append(str(segment.text))
	return DeskLocalization.source_join("",parts)

static func _seed(preset_id: String) -> String:
	return {"versailles_2020":"V","nobody_2020":"N","ok_boomer_2020":"B"}[preset_id]

static func _text(key: String) -> String:
	return DeskLocalization.source("LOC_TEXT_COMPOSE_V2_"+key)

static func _error(key: String) -> PackedStringArray:
	return PackedStringArray([DeskLocalization.source("LOC_COMPOSE_ERROR_"+key)])
