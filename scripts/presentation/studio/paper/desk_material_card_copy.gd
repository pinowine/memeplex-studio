extends RefCounted

# Presentation copy is separate from inventory definitions and persistence signatures.
const DESCRIPTIONS := {
  "language_ninghua": "LOC_CARD_LANGUAGE_NINGHUA_DESCRIPTION",
  "language_shiohara": "LOC_CARD_LANGUAGE_SHIOHARA_DESCRIPTION",
  "language_seowon": "LOC_CARD_LANGUAGE_SEOWON_DESCRIPTION"
}
const COMMENTARY := {
  "language_ninghua": "LOC_CARD_LANGUAGE_NINGHUA_COMMENTARY",
  "language_shiohara": "LOC_CARD_LANGUAGE_SHIOHARA_COMMENTARY",
  "language_seowon": "LOC_CARD_LANGUAGE_SEOWON_COMMENTARY",
  "group_commuters": "LOC_CARD_GROUP_COMMUTERS_COMMENTARY",
  "group_students": "LOC_CARD_GROUP_STUDENTS_COMMENTARY",
  "group_culture_fans": "LOC_CARD_GROUP_CULTURE_FANS_COMMENTARY",
  "topic_policy": "LOC_CARD_TOPIC_POLICY_COMMENTARY",
  "topic_cost_of_living": "LOC_CARD_TOPIC_COST_OF_LIVING_COMMENTARY",
  "topic_work": "LOC_CARD_TOPIC_WORK_COMMENTARY",
  "topic_platform_tools": "LOC_CARD_TOPIC_PLATFORM_TOOLS_COMMENTARY",
  "topic_sport": "LOC_CARD_TOPIC_SPORT_COMMENTARY",
  "topic_education": "LOC_CARD_TOPIC_EDUCATION_COMMENTARY",
  "topic_identity": "LOC_CARD_TOPIC_IDENTITY_COMMENTARY",
  "topic_language": "LOC_CARD_TOPIC_LANGUAGE_COMMENTARY",
  "topic_entertainment": "LOC_CARD_TOPIC_ENTERTAINMENT_COMMENTARY",
  "topic_archive": "LOC_CARD_TOPIC_ARCHIVE_COMMENTARY",
  "topic_trust": "LOC_CARD_TOPIC_TRUST_COMMENTARY",
  "topic_community": "LOC_CARD_TOPIC_COMMUNITY_COMMENTARY",
  "freedom": "LOC_CARD_FREEDOM_COMMENTARY",
  "authority": "LOC_CARD_AUTHORITY_COMMENTARY",
  "equality": "LOC_CARD_EQUALITY_COMMENTARY",
  "hierarchy": "LOC_CARD_HIERARCHY_COMMENTARY",
  "sincere": "LOC_CARD_SINCERE_COMMENTARY",
  "ironic": "LOC_CARD_IRONIC_COMMENTARY",
  "support": "LOC_CARD_SUPPORT_COMMENTARY",
  "opposition": "LOC_CARD_OPPOSITION_COMMENTARY",
  "module_stance": "LOC_CARD_MODULE_STANCE_COMMENTARY",
  "module_relation": "LOC_CARD_MODULE_RELATION_COMMENTARY",
  "module_ritual": "LOC_CARD_MODULE_RITUAL_COMMENTARY",
  "module_boundary": "LOC_CARD_MODULE_BOUNDARY_COMMENTARY",
  "module_shared_world": "LOC_CARD_MODULE_SHARED_WORLD_COMMENTARY"
}

static func apply_to(details: Dictionary) -> void:
 var id := str(details.get("id", ""))
 if DESCRIPTIONS.has(id): details.description = DESCRIPTIONS[id]
 details.commentary = COMMENTARY.get(id, "")
