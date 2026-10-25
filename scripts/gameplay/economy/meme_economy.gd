class_name MemeDemoEconomy
extends RefCounted

var balance: int = 0
var initial_balance: int = 0
var transactions: Array[Dictionary] = []
var rewarded_keys: Dictionary = {}

func reset(points: int) -> void:
	initial_balance = points
	balance = points
	transactions.clear()
	rewarded_keys.clear()

func charge(amount: int, reason: String, hour: int) -> bool:
	if amount < 0 or balance < amount:
		return false
	balance -= amount
	transactions.append({"delta":-amount, "reason":reason, "hour":hour, "balance":balance})
	return true

func reward(key: String, amount: int, reason: String, hour: int) -> bool:
	if amount < 0 or rewarded_keys.has(key):
		return false
	rewarded_keys[key] = true
	balance += amount
	transactions.append({"delta":amount, "reason":reason, "hour":hour, "balance":balance, "key":key})
	return true

func lines() -> Array[String]:
	var result: Array[String] = []
	for entry in transactions:
		result.append("H%d  %s%d Meme  %s → %d" % [entry.hour, "+" if entry.delta >= 0 else "", entry.delta, entry.reason, entry.balance])
	return result

func payload() -> Dictionary:
	return {"initial_balance":initial_balance, "balance":balance, "transactions":transactions.duplicate(true), "rewarded_keys":rewarded_keys.duplicate()}

func validate_payload(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if not data.has_all(["initial_balance", "balance", "transactions", "rewarded_keys"]):
		errors.append("economy: missing fields")
		return errors
	if not _integer(data.initial_balance) or not _integer(data.balance) or int(data.initial_balance) < 0 or int(data.balance) < 0 or not data.transactions is Array or not data.rewarded_keys is Dictionary:
		errors.append("economy: invalid balance or ledger")
		return errors
	var running := int(data.initial_balance)
	var keys: Dictionary = {}
	for entry: Variant in data.transactions:
		if not entry is Dictionary or not entry.has_all(["delta", "reason", "hour", "balance"]) or not _integer(entry.get("delta")) or not _integer(entry.get("balance")) or not _integer(entry.get("hour")):
			errors.append("economy: malformed transaction")
			continue
		running += int(entry.delta)
		if running < 0 or running != int(entry.balance):
			errors.append("economy: inconsistent transaction balance")
		if entry.has("key"):
			if keys.has(entry.key) or int(entry.delta) < 0:
				errors.append("economy: repeated reward key")
			keys[entry.key] = true
	if running != int(data.balance) or keys.size() != data.rewarded_keys.size():
		errors.append("economy: ledger does not match balance or rewards")
	for key: Variant in keys:
		if not data.rewarded_keys.has(key):
			errors.append("economy: missing reward key")
	return errors

func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

func restore(data: Dictionary) -> void:
	initial_balance = int(data.initial_balance)
	balance = int(data.balance)
	transactions.clear()
	for entry: Dictionary in data.transactions:
		transactions.append(entry.duplicate(true))
	rewarded_keys = data.rewarded_keys.duplicate()
