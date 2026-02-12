extends Area2D
class_name LeftoverTray

var items_on_shelf: Array = []
@onready var slot = $Slot1

func _ready():
	add_to_group("shelves")

func remove_item(item) -> void:
	items_on_shelf.erase(item)

func add_item(item) -> bool:
	# Re-adding the same item (shouldn't happen with remove-first pattern, but safe)
	if items_on_shelf.has(item):
		return true

	if items_on_shelf.size() >= 1:
		return false

	items_on_shelf.append(item)
	item.confirm_slot_position(slot.global_position)
	item.current_shelf = self
	return true
