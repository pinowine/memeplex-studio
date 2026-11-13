extends HFlowContainer

const Tag = preload("res://scripts/presentation/context/context_tag.gd")

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("h_separation", 4)
	add_theme_constant_override("v_separation", 4)
	resized.connect(func(): fit_width(size.x))

func set_tags(tags: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for tag: Dictionary in tags:
		var chip := Tag.new()
		chip.configure(tag)
		add_child(chip)
	if size.x > 0: fit_width(size.x)

func fit_width(width: float) -> void:
	for chip in get_children(): chip.fit_width(width)

func inspection() -> Array:
	return get_children().map(func(chip: Control): return chip.inspection())
