@tool
extends RefCounted

const QUESTION := "module_stance"
const COMPARISON := "module_relation"
const EXPLANATION := "module_boundary"
const CONTINUATION := "module_shared_world"
const EXIT := "module_ritual"
const SEEDS := ["worker_2020", "versailles_2020", "cheems_2020"]
const LANGUAGES := ["ninghua", "shiohara", "seowon"]
const GROUPS := ["commuters", "students", "culture_fans"]
const SCENES := {
	"worker_2020": [
		{"id":"shift", "topics":["work","cost_of_living","policy"], "groups":[]},
		{"id":"student_job", "topics":["education","work","cost_of_living"], "groups":["students"]},
		{"id":"club_duty", "topics":["community","entertainment","work"], "groups":["culture_fans"]}],
	"versailles_2020": [
		{"id":"exam", "topics":["education","identity","community"], "groups":[]},
		{"id":"training", "topics":["education","work","platform_tools"], "groups":["commuters"]},
		{"id":"quiz", "topics":["education","entertainment","community"], "groups":["culture_fans"]}],
	"cheems_2020": [
		{"id":"reply", "topics":["community","language","trust","identity"], "groups":[]},
		{"id":"presentation", "topics":["education","language","community"], "groups":["students"]},
		{"id":"meeting", "topics":["work","platform_tools","community"], "groups":["commuters"]},
		{"id":"fan_chat", "topics":["entertainment","community","language"], "groups":["culture_fans"]}]
}

static func supports(preset_id: String) -> bool:
	return preset_id in SEEDS

static func definition(preset_id: String) -> Dictionary:
	var definitions := {
		"worker_2020": {"compatible_modules":[QUESTION,COMPARISON,EXPLANATION,CONTINUATION,EXIT], "requires":{EXIT:[CONTINUATION]}, "default_context":{"language_id":"ninghua","group_id":"commuters","topic_ids":["work","cost_of_living"],"political_position":[-0.3,-0.3],"political_known":true,"pragmatic_position":[0.6,0.1]}, "meaning_bounds":{"political_position":[-1.0,0.4,-1.0,0.4],"pragmatic_position":[-0.2,1.0,-0.5,1.0]}},
		"versailles_2020": {"compatible_modules":[QUESTION,COMPARISON,EXPLANATION], "requires":{}, "default_context":{"language_id":"ninghua","group_id":"students","topic_ids":["education"],"political_position":[0.0,0.3],"political_known":true,"pragmatic_position":[0.8,0.1]}, "meaning_bounds":{"political_position":[-0.5,0.5,-0.3,1.0],"pragmatic_position":[0.2,1.0,-0.5,1.0]}},
		"cheems_2020": {"compatible_modules":[COMPARISON,EXPLANATION,CONTINUATION,EXIT], "requires":{EXIT:[CONTINUATION]}, "default_context":{"language_id":"ninghua","group_id":"students","topic_ids":["community","language"],"political_position":[0.0,0.0],"political_known":true,"pragmatic_position":[0.5,-0.3]}, "meaning_bounds":{"political_position":[-0.5,0.5,-0.5,0.5],"pragmatic_position":[-0.5,1.0,-1.0,0.4]}}
	}
	if not supports(preset_id): return {}
	var result: Dictionary = definitions[preset_id]
	result.max_modules = 4
	result.title = _text(preset_id.to_upper() + "_TITLE")
	result.media = _text("MEDIA_TEXT" if preset_id == "worker_2020" else "MEDIA_IMAGE")
	result.illustration = preset_id.trim_suffix("_2020")
	result.scenes = SCENES[preset_id].duplicate(true)
	return result

static func validate(draft: Dictionary, module_ids: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	var preset_id := str(draft.get("preset_id", ""))
	if not supports(preset_id):
		return PackedStringArray([_text("ERROR_SEED")])
	var rules := definition(preset_id)
	var modules := _modules(module_ids)
	if modules.size() > 4: errors.append(_text("ERROR_SLOTS"))
	var seen := {}
	for id: String in modules:
		if seen.has(id): errors.append(_text("ERROR_DUPLICATE"))
		seen[id] = true
		if id not in rules.compatible_modules: errors.append(_text("ERROR_PATCH"))
		for required: String in rules.requires.get(id, []):
			if required not in modules: errors.append(_text("ERROR_EXIT"))
	for language_id: String in _context_values(draft,"language"):
		if language_id not in LANGUAGES: errors.append(_text("ERROR_LANGUAGE"))
	for group_id: String in _context_values(draft,"group"):
		if group_id not in GROUPS: errors.append(_text("ERROR_GROUP"))
	if _scene(draft).is_empty(): errors.append(_text("ERROR_SCENE"))
	for field: String in rules.meaning_bounds:
		var layer := "stance" if field == "political_position" else "pragmatic"
		if not _attached(draft,layer): continue
		if field == "political_position" and not draft.get("political_known",false): continue
		var point := _position(draft.get(field,Vector2.ZERO))
		var bounds: Array = rules.meaning_bounds[field]
		for axis in 2:
			var value: float = point[axis]
			var lower: float = bounds[axis*2]
			var upper: float = bounds[axis*2+1]
			if (value < lower and not is_equal_approx(value,lower)) or (value > upper and not is_equal_approx(value,upper)):
				errors.append(_text("ERROR_MEANING"))
	return errors

static func compose(draft: Dictionary, module_ids: Array) -> Dictionary:
	if not validate(draft,module_ids).is_empty(): return {}
	var preset_id := str(draft.preset_id)
	var modules := _modules(module_ids)
	var scene := _scene(draft)
	var languages := _context_values(draft,"language")
	if languages.is_empty(): languages.append("")
	var versions: Array[Dictionary] = []
	for language_id: String in languages:
		versions.append({"language_id":language_id,"expression":_expression(preset_id,scene,language_id,modules)})
	var meaning := _meaning(draft,modules)
	return {"expression":versions[0].expression,"meaning":meaning.text,"meaning_id":meaning.id,"language_versions":versions,"media":definition(preset_id).media,"illustration":preset_id.trim_suffix("_2020") + "_" + str(scene.id),"effects":{}}

static func _modules(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		if not str(value).is_empty(): result.append(str(value))
	result.sort()
	return result

static func _attached(draft: Dictionary, layer: String) -> bool:
	return bool(draft.get("context_layer_attachment",{}).get(layer,true))

static func _context_values(draft: Dictionary, kind: String) -> Array[String]:
	var result: Array[String] = []
	if not _attached(draft,kind): return result
	var values: Variant = draft.get(kind + "_ids",[draft.get(kind + "_id","")])
	for value: Variant in values:
		if not str(value).is_empty() and str(value) not in result: result.append(str(value))
	return result

static func _scene(draft: Dictionary) -> Dictionary:
	var topics: Array[String] = []
	if _attached(draft,"topics"):
		for value: Variant in draft.get("topic_ids",[]): topics.append(str(value))
	topics.sort()
	var groups := _context_values(draft,"group")
	var selected := {}
	var best_score := -1
	for scene: Dictionary in SCENES[str(draft.preset_id)]:
		var fits := true
		for topic: String in topics: fits = fits and topic in scene.topics
		if not fits: continue
		var score := 0
		for group_id: String in groups:
			if group_id in scene.groups: score += 1
		if score > best_score:
			selected = scene
			best_score = score
	if not selected.is_empty():
		selected = selected.duplicate(true)
		selected.selected_topics = topics
	return selected

static func _scene_expression(scene: Dictionary) -> String:
	var prefix := "SCENE_" + str(scene.id).to_upper()
	var details: Array[String] = []
	for topic: String in scene.selected_topics:
		details.append(_text(prefix + "_" + topic.to_upper()))
	if details.is_empty(): return _text(prefix + "_DEFAULT")
	var joined := details[0]
	for index in range(1,details.size()):
		joined = _format("LIST_PAIR" if index == details.size()-1 else "LIST_MORE",[joined,details[index]])
	return _format(prefix + "_FOCUS",[joined])

static func _expression(preset_id: String, scene: Dictionary, language_id: String, modules: Array[String]) -> String:
	var question := QUESTION in modules
	var compare := COMPARISON in modules
	var explain := EXPLANATION in modules
	var core_mask := int(question) + int(compare) * 2 + int(explain) * 4
	var seed := preset_id.trim_suffix("_2020").to_upper()
	var language := language_id.to_upper() if not language_id.is_empty() else "NINGHUA"
	var prefix := _text(seed + "_LEAD_" + language)
	var scene_id := str(scene.id).to_upper()
	var core: String
	if preset_id == "worker_2020":
		var promise := _text(scene_id+"_PROMISE")
		var actual := _text(scene_id+"_ACTUAL")
		var reason := _text(scene_id+"_REASON")
		var arguments := {0:[],1:[promise],2:[promise,actual],3:[promise,actual],4:[reason,actual],5:[reason,promise],6:[promise,reason,actual],7:[promise,reason,actual]}
		core = "" if core_mask == 0 else _format("WORKER_CORE_%d" % core_mask,arguments[core_mask])
	elif preset_id == "versailles_2020":
		core = "" if core_mask == 0 else _text("VERSAILLES_CORE_%d" % core_mask)
		prefix = _format("VERSAILLES_SCENE",[_text(scene_id+"_PAPER"),prefix])
	else:
		var action := _text(scene_id+"_ACTION")
		var reason := _text(scene_id+"_REASON")
		var arguments := {0:[],2:[action],4:[action,reason],6:[action,reason]}
		core = "" if core_mask == 0 else _format("CHEEMS_CORE_%d" % core_mask,arguments[core_mask])
	var expression := DeskLocalization.source_join("",[prefix,_scene_expression(scene),core])
	if CONTINUATION in modules:
		var ending := seed + ("_INVITE_EXIT" if EXIT in modules else "_INVITE")
		expression = DeskLocalization.source_join("",[expression,_text(ending)])
	return expression

static func _meaning(draft: Dictionary, modules: Array[String]) -> Dictionary:
	var seed := str(draft.preset_id).trim_suffix("_2020").to_upper()
	var core_mask := int(QUESTION in modules) + int(COMPARISON in modules)*2 + int(EXPLANATION in modules)*4
	var core := _text(seed + "_MEANING_%d" % core_mask)
	if CONTINUATION in modules:
		core = _format("MEANING_CLAUSES",[core,_text("MEANING_INVITE_EXIT" if EXIT in modules else "MEANING_INVITE")])
	var parts: Array[String] = [_format("MEANING_CORE",[core])]
	var identity: Array[String] = [str(draft.preset_id),"+".join(modules)]
	for field: String in ["political_position","pragmatic_position"]:
		var layer := "stance" if field == "political_position" else "pragmatic"
		if not _attached(draft,layer) or (field == "political_position" and not draft.get("political_known",false)): continue
		var point := _position(draft.get(field,Vector2.ZERO))
		identity.append("%s:%.2f,%.2f" % [layer,point.x,point.y])
		var axis_keys := ["FREEDOM","AUTHORITY","EQUALITY","HIERARCHY"] if layer == "stance" else ["SINCERE","IRONIC","SUPPORT","OPPOSITION"]
		var reading: Array[String] = []
		if not is_zero_approx(point.x): reading.append(_axis_reading(seed,axis_keys[0 if point.x < 0.0 else 1],point.x))
		if not is_zero_approx(point.y): reading.append(_axis_reading(seed,axis_keys[2 if point.y < 0.0 else 3],point.y))
		if not reading.is_empty():
			var text := reading[0] if reading.size() == 1 else _format("MEANING_CLAUSES",reading)
			parts.append(_format("MEANING_STANCE" if layer == "stance" else "MEANING_USAGE",[text]))
	return {"text":DeskLocalization.source_join("",parts),"id":"/".join(identity)}

static func _axis_reading(seed: String, axis: String, value: float) -> String:
	var degree := clampi(ceili(absf(value)*5.0),1,5)
	return _format("MEANING_DEGREE_%d" % degree,[_text(seed+"_READING_"+axis)])

static func _position(value: Variant) -> Vector2:
	return value if value is Vector2 else Vector2(float(value[0]),float(value[1]))

static func _text(key: String) -> String:
	return DeskLocalization.source("LOC_COMPOSE_" + key)

static func _format(key: String, values: Array) -> String:
	return DeskLocalization.source_format("LOC_COMPOSE_" + key,values,range(values.size()))
