extends RefCounted

const IDEOLOGIES := [
	{"id":"freedom_equality", "stance":[-1.0, -1.0]},
	{"id":"freedom_hierarchy", "stance":[-1.0, 1.0]},
	{"id":"authority_equality", "stance":[1.0, -1.0]},
	{"id":"authority_hierarchy", "stance":[1.0, 1.0]}
]

static func resolve(definition: MemeDemoEvent, country: Dictionary, groups: Array) -> Dictionary:
	var policy: Dictionary = definition.response_profile
	var authority_share := (float(country.stance[0]) + 1.0) * 0.5
	var hierarchy_share := (float(country.stance[1]) + 1.0) * 0.5
	var response := {
		"country_id":str(country.id), "topic_ids":Array(definition.topic_ids),
		"attention":float(policy.get("attention", 0.0)),
		"spread":float(policy.get("spread", 0.0)),
		"production":float(policy.get("production", 0.0)),
		"sentiment":0.0, "irony":0.0, "positive_share":0.0, "negative_share":0.0,
		"cohorts":[], "groups":[]
	}
	# These shares preserve both country axes and keep minority reactions visible.
	for ideology: Dictionary in IDEOLOGIES:
		var stance: Array = ideology.stance
		var share := (authority_share if float(stance[0]) > 0.0 else 1.0 - authority_share) * (hierarchy_share if float(stance[1]) > 0.0 else 1.0 - hierarchy_share)
		var sentiment := float(policy.get("sentiment", 0.0))
		sentiment += float(policy.get("authority_affinity" if float(stance[0]) > 0.0 else "freedom_affinity", 0.0))
		sentiment += float(policy.get("hierarchy_affinity" if float(stance[1]) > 0.0 else "equality_affinity", 0.0))
		sentiment = clampf(sentiment, -1.0, 1.0)
		var irony := float(country.pragmatic[0])
		# A small dissenting audience uses indirection when the surrounding culture rewards authority.
		if sentiment < 0.0 and float(stance[0]) < 0.0:
			irony += 1.8 * float(policy.get("controversy", 0.0)) * maxf(0.0, float(country.stance[0])) * (1.0 - share)
		irony = clampf(irony, -1.0, 1.0)
		var frames: Array = Array(policy.get("positive_frames" if sentiment >= 0.0 else "negative_frames", []))
		response.cohorts.append({"id":str(ideology.id), "share":share, "stance":stance.duplicate(), "sentiment":sentiment, "pragmatic":[irony, -sentiment], "irony":maxf(0.0, irony), "frames":frames})
		response.sentiment += share * sentiment
		response.irony += share * maxf(0.0, irony)
		if sentiment > 0.0: response.positive_share += share
		if sentiment < 0.0: response.negative_share += share
	var reactions: Dictionary = policy.get("group_reactions", {})
	for group: MemeDemoGroup in groups:
		var affinity := 0.0
		for index in group.topic_ids.size():
			if str(group.topic_ids[index]) in definition.topic_ids: affinity = maxf(affinity, float(group.topic_affinities[index]))
		var delta := float(reactions.get(str(group.id), 0.0))
		response.groups.append({"id":str(group.id), "affinity":affinity, "sentiment_delta":delta, "sentiment":clampf(float(response.sentiment) + delta, -1.0, 1.0), "pragmatic":[float(response.irony), -clampf(float(response.sentiment) + delta, -1.0, 1.0)]})
	return response

static func preference(response: Dictionary, profile: Dictionary) -> float:
	if not _attached(profile, "topics") or not _attached(profile, "pragmatic"): return 1.0
	var matching := 0.0
	for topic: String in profile.topic_ids:
		if topic in response.topic_ids: matching += 1.0
	if is_zero_approx(matching): return 1.0
	var topical_share := matching / float(profile.topic_ids.size())
	var pragmatic: Array = profile.pragmatic_position
	var group_delta := 0.0
	if _attached(profile, "group"):
		for group: Dictionary in response.groups:
			if str(group.id) == str(profile.group_id): group_delta = float(group.sentiment_delta)
	var delta := 0.0
	for cohort: Dictionary in response.cohorts:
		var weight := float(cohort.share)
		if bool(profile.political_known) and _attached(profile, "stance"):
			var dx := float(profile.political_position[0]) - float(cohort.stance[0])
			var dy := float(profile.political_position[1]) - float(cohort.stance[1])
			weight *= exp(-1.5 * (dx * dx + dy * dy))
		var sentiment := clampf(float(cohort.sentiment) + group_delta, -1.0, 1.0)
		var reading := -sentiment * float(pragmatic[1])
		var tone := 1.0 - absf(float(pragmatic[0]) - float(cohort.pragmatic[0]))
		delta += weight * (0.5 * reading + 0.15 * absf(sentiment * float(pragmatic[1])) * tone)
	return 1.0 + topical_share * delta

static func _attached(profile: Dictionary, layer: String) -> bool:
	return bool(profile.get("context_layer_attachment", {}).get(layer, true))

static func summary(response: Dictionary) -> String:
	var parts := PackedStringArray()
	for metric: String in ["attention", "spread", "production"]:
		var amount := float(response[metric])
		if is_zero_approx(amount): continue
		parts.append(DeskLocalization.source_format("%s %s%.0f%%", ["LOC_EVENT_RESPONSE_" + metric.to_upper(), "+" if amount > 0.0 else "", amount * 100.0], [0]))
	if not is_zero_approx(float(response.sentiment)):
		parts.append(DeskLocalization.source("LOC_EVENT_RESPONSE_POSITIVE" if float(response.sentiment) > 0.0 else "LOC_EVENT_RESPONSE_NEGATIVE"))
	return DeskLocalization.source_join(" · ", parts)
