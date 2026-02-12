# Shelf Layer Model:
# Each slot index corresponds to a Marker2D.
# _front[i] and _back[i] represent two depth layers for that slot (Front and Back).
# Item implementation is fixed-size indexed spatial array
# Items are promoted from back to front when the front layer becomes empty.

#Addl. dev reminders: _front and _back is for positional slot ownership and items_on_shelf are gameplay-active items for matching

extends Area2D
class_name Shelf

signal shelf_cleared

# Slot positions in world space (fixed layout)
@onready var slots: Array[Marker2D] = [$Slot1, $Slot2, $Slot3]


# Tracks active items currently visible in the front layer.
# This mirrors non-null values in _front for faster iteration.
var items_on_shelf: Array[Node] = [] 

# Prevents interaction during match clearing
var _is_clearing := false

# Front and back layers (indexed spatial storage)
var _front: Array = [null, null, null]
var _back:  Array = [null, null, null]

func _ready():
	add_to_group("shelves")

# --- Slot Helpers ---

# Returns slot index if item exists in front layer, otherwise -1.
func get_slot_index_of(item) -> int:
	for i in range(slots.size()):
		if _front[i] == item: #Checks if item in front is in the space index
			return i
	return -1

# Returns first empty slot index in front layer.
func get_free_slot_index() -> int:
	for i in range(slots.size()):
		if _front[i] == null: #Checks if front slot is free
			return i
	return -1

#Function that tells if front slots are empty
func is_front_empty() -> bool:
	for i in range(slots.size()):
		if _front[i] != null:
			return false
	return true

#Function that tells if back slots are empty or contains an item
func has_back_items() -> bool:
	for i in range(slots.size()):
		if _back[i] != null:
			return true
	return false

#Function that Marks a front slot as empty when its item is removed or cleared.
#In simple terms, just says "This slot is now free, you can place a new item here"
func free_slot_front(item) -> void:
	var i = get_slot_index_of(item)
	if i != -1:
		_front[i] = null

# --- Called by Item BEFORE add_item on the target shelf ---
# Called by Item before being added to a new shelf.
# Removes item from front layer and triggers reveal if needed.
func remove_item(item) -> void:
	items_on_shelf.erase(item) #Calls helper function to check the slot and free it for other items
	free_slot_front(item)
	# Reveal back layer if shelf is now fully empty
	if not _is_clearing and is_front_empty() and has_back_items():
		reveal_back_layer() #Reveals back layer if there is no clearing animation happening, front is empty, and has back items

# --- Population at spawn (GameManager only) ---
# Adds item to a specific layer during initial level population.
# Used only by GameManager.
func add_item_to_layer(item, layer: String) -> void:
	for i in range(slots.size()):
		var occupied = _back[i] if layer == "back" else _front[i] #If layer == "back" then check _back[i]
		if occupied == null:
			if layer == "front":
				_front[i] = item
				items_on_shelf.append(item)
				item.set_slot_position(slots[i].global_position) #Move item's world position to the slot's position
				item.z_index = 2  # Front items on top
			else:
				_back[i] = item
				item.set_slot_position(slots[i].global_position)
				item.set_dimmed(true)
				item.z_index = 0  # Back items behind
			item.current_shelf = self #Tells item which shelf it belongs to
			return

# --- Player drop ---
# Handles player drop logic including same-shelf rearrange and cross-shelf placement.
func add_item(item) -> bool:
	if _is_clearing: #Guard to to prevent mutation while in clearing state
		return false

	var cur_i = get_slot_index_of(item)

	if cur_i != -1: #Checks if item is already in the front layer
		# Same-shelf rearrange: item still registered here, move to a free slot
		var free_i = get_free_slot_index()
		if free_i == -1: #Snaps item back to original position if no free space
			# No room to move, snap back to current slot
			item.confirm_slot_position(slots[cur_i].global_position)
			return true
		_front[cur_i] = null
		_front[free_i] = item
		item.confirm_slot_position(slots[free_i].global_position)
		_await_and_check_match(item) #wait for animation before checking for match
		return true

	# Cross-shelf: item was already removed from old shelf by Item. _input
	var new_i = get_free_slot_index()
	if new_i == -1:
		return false

	_front[new_i] = item
	items_on_shelf.append(item) #Makes item gameplay-active first
	item.confirm_slot_position(slots[new_i].global_position) #Physical Movement
	item.current_shelf = self #Tells the item it belongs to this slot now
	# Wait for item to arrive at slot before checking match
	_await_and_check_match(item)
	return true

#Function that makes the item snap into place first before matching
func _await_and_check_match(item) -> void:
	# Wait for the item to finish sliding into place
	if item.has_signal("arrived"):
		await item.arrived
	if not _is_clearing and items_on_shelf.size() == 3: #Will only check for match if it isnt playing match animation and items on shelf are 3
		check_match()

# Validates match when shelf is full.
# Clears matching items and reveals back layer if applicable.
#A guarded state transition function that validates match conditions, cleans references, clears positional occupancy, sequences animation, and promotes back-layer state.
func check_match():
	if items_on_shelf.size() < 3:
		return

	var pruned: Array[Node] = [] # *Prevents Ghost references and Match logic crashes
	for item in items_on_shelf:
		if is_instance_valid(item): #Keeps valid nodes
			pruned.append(item)
		else:
			free_slot_front(item) #Frees front slot if invalid
	items_on_shelf = pruned
	if items_on_shelf.size() < 3:
		return

	var first_type = items_on_shelf[0].item_type #Chooses the first item as reference
	var all_match = true #Check uniformity of items
	for item in items_on_shelf:
		if item.item_type != first_type:
			all_match = false
			break

	if all_match:
		_is_clearing = true #Prevents any other input to the items playing matching animation
		var matched_items = items_on_shelf.duplicate() 
		items_on_shelf.clear()
		#Removes from front and plays pop animation
		for item in matched_items:
			free_slot_front(item)
			if is_instance_valid(item):
				item.pop_effect()

		await get_tree().create_timer(0.3).timeout
		reveal_back_layer()
		_is_clearing = false
		shelf_cleared.emit() #Sends signal to game state manager, score system, or progress tracking to react

# Promotes all valid back layer items to front layer
# when front becomes empty.
func reveal_back_layer() -> void:
	if not is_front_empty(): #Guard close that makes sure to reveal back only when front is clear
		return
	var had_back := false #Tracks whether any valid back items were found
	var last_item = null # Tracks last promoted item (for match check trigger)
	for i in range(slots.size()):
		var back_item = _back[i] as Node
		if is_instance_valid(back_item):
			had_back = true
			_front[i] = back_item
			_back[i] = null
			items_on_shelf.append(back_item)
			back_item.set_dimmed(false)
			back_item.restore_color()
			back_item.z_index = 2  # Now a front item, render on top
			back_item.global_position = slots[i].global_position + Vector2(0, -40)
			back_item.confirm_slot_position(slots[i].global_position)
			last_item = back_item
	if had_back and last_item != null:
		_await_and_check_match(last_item)

# Resets shelf state. Optionally frees items.
#Slot Occupancy reset, Gameplay reset
func reset(free_items: bool = true) -> void:
	for i in range(slots.size()):
		if free_items:
			if is_instance_valid(_front[i]):
				(_front[i] as Node).queue_free()
			if is_instance_valid(_back[i]):
				(_back[i] as Node).queue_free()
		_front[i] = null
		_back[i] = null
	items_on_shelf.clear()
	_is_clearing = false
