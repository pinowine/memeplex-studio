class_name MemeDesignSolutes
extends Resource

@export var entries: Array[Dictionary] = []

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	for entry in entries:
		var id := str(entry.get("id", ""))
		if id.is_empty() or seen.has(id) or str(entry.get("title", "")).is_empty() or not entry.get("effects") is Array:
			errors.append("Invalid solute identity or effects")
			continue
		seen[id] = true
		var order: Variant = entry.get("retention_order")
		if not (order is int or order is float) or not is_finite(float(order)) or float(order) != floor(float(order)) or float(order) < 1.0 or float(order) > 64.0:
			errors.append("Game retention order must be a positive bounded integer")
		for effect: Variant in entry.effects:
			if not effect is Dictionary:
				errors.append("Invalid context effect")
				continue
			var amount: Variant = effect.get("amount")
			if not (amount is int or amount is float) or not is_finite(float(amount)) or absf(float(amount)) > 1.0:
				errors.append("Context amount must be finite and bounded")
			if str(effect.get("field", "")) not in ["political_position", "remix_cost", "context_dependency", "language_access", "recognizability"]:
				errors.append("Context can only change author draft fields")
			if effect.get("field") == "political_position" and str(effect.get("axis", "")) not in ["x", "y"]:
				errors.append("Political context requires an explicit axis")
	return errors
