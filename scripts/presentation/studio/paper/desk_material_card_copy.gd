extends RefCounted

# Presentation copy is separate from inventory definitions and persistence signatures.
const DESCRIPTIONS := {
  "language_ninghua": "LOC_CARD_LANGUAGE_NINGHUA_DESCRIPTION",
  "language_shiohara": "LOC_CARD_LANGUAGE_SHIOHARA_DESCRIPTION",
  "language_seowon": "LOC_CARD_LANGUAGE_SEOWON_DESCRIPTION"
}
const HOVER_DESCRIPTIONS := {
  "language_ninghua": "LOC_RECEIPT_CARD_LANGUAGE_NINGHUA",
  "language_shiohara": "LOC_RECEIPT_CARD_LANGUAGE_SHIOHARA",
  "language_seowon": "LOC_RECEIPT_CARD_LANGUAGE_SEOWON",
  "group_commuters": "LOC_RECEIPT_CARD_GROUP_COMMUTERS",
  "group_students": "LOC_RECEIPT_CARD_GROUP_STUDENTS",
  "group_culture_fans": "LOC_RECEIPT_CARD_GROUP_CULTURE_FANS",
  "topic_policy": "LOC_RECEIPT_CARD_TOPIC_POLICY",
  "topic_cost_of_living": "LOC_RECEIPT_CARD_TOPIC_COST_OF_LIVING",
  "topic_work": "LOC_RECEIPT_CARD_TOPIC_WORK",
  "topic_platform_tools": "LOC_RECEIPT_CARD_TOPIC_PLATFORM_TOOLS",
  "topic_sport": "LOC_RECEIPT_CARD_TOPIC_SPORT",
  "topic_education": "LOC_RECEIPT_CARD_TOPIC_EDUCATION",
  "topic_identity": "LOC_RECEIPT_CARD_TOPIC_IDENTITY",
  "topic_language": "LOC_RECEIPT_CARD_TOPIC_LANGUAGE",
  "topic_entertainment": "LOC_RECEIPT_CARD_TOPIC_ENTERTAINMENT",
  "topic_archive": "LOC_RECEIPT_CARD_TOPIC_ARCHIVE",
  "topic_trust": "LOC_RECEIPT_CARD_TOPIC_TRUST",
  "topic_community": "LOC_RECEIPT_CARD_TOPIC_COMMUNITY",
  "module_stance": "LOC_RECEIPT_CARD_MODULE_STANCE",
  "module_relation": "LOC_RECEIPT_CARD_MODULE_RELATION",
  "module_ritual": "LOC_RECEIPT_CARD_MODULE_RITUAL",
  "module_boundary": "LOC_RECEIPT_CARD_MODULE_BOUNDARY",
  "module_shared_world": "LOC_RECEIPT_CARD_MODULE_SHARED_WORLD",
  "freedom": "LOC_RECEIPT_CARD_FREEDOM",
  "authority": "LOC_RECEIPT_CARD_AUTHORITY",
  "equality": "LOC_RECEIPT_CARD_EQUALITY",
  "hierarchy": "LOC_RECEIPT_CARD_HIERARCHY",
  "sincere": "LOC_RECEIPT_CARD_SINCERE",
  "ironic": "LOC_RECEIPT_CARD_IRONIC",
  "support": "LOC_RECEIPT_CARD_SUPPORT",
  "opposition": "LOC_RECEIPT_CARD_OPPOSITION"
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
 details.hover_description = hover_description(id)

static func hover_description(id: String) -> String:
 return DeskLocalization.source(str(HOVER_DESCRIPTIONS.get(id, "")))
