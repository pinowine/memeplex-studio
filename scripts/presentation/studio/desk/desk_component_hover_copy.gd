extends RefCounted

const COPY := {
	"fax":{"description":"LOC_RECEIPT_FAX_PURPOSE","note":"LOC_RECEIPT_FAX_NOTE"},
	"printer":{"description":"LOC_RECEIPT_PRINTER_PURPOSE","note":"LOC_RECEIPT_PRINTER_NOTE"},
	"monitor":{"description":"LOC_RECEIPT_MONITOR_PURPOSE","note":"LOC_RECEIPT_MONITOR_NOTE"},
	"folder":{"description":"LOC_RECEIPT_FOLDER_PURPOSE","note":"LOC_RECEIPT_FOLDER_NOTE"},
	"phonebook":{"description":"LOC_RECEIPT_PHONEBOOK_PURPOSE","note":"LOC_RECEIPT_PHONEBOOK_NOTE"},
	"clock":{"description":"LOC_RECEIPT_CLOCK_PURPOSE","note":"LOC_RECEIPT_CLOCK_NOTE"},
	"speed":{"description":"LOC_RECEIPT_SPEED_PURPOSE","note":"LOC_RECEIPT_SPEED_NOTE"},
	"sheet/map":{"description":"LOC_RECEIPT_MAP_PURPOSE","note":"LOC_RECEIPT_MAP_NOTE"},
	"sheet/edit":{"description":"LOC_RECEIPT_EDIT_PURPOSE","note":"LOC_RECEIPT_EDIT_NOTE"},
	"sheet/cultivate":{"description":"LOC_RECEIPT_CULTIVATE_PURPOSE","note":"LOC_RECEIPT_CULTIVATE_NOTE"},
	"sheet/spread":{"description":"LOC_RECEIPT_SPREAD_PURPOSE","note":"LOC_RECEIPT_SPREAD_NOTE"}
}

static func for_kind(kind: String) -> Dictionary:
	return COPY.get(kind,{}).duplicate()
