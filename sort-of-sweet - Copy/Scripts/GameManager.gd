extends Node2D

@export var item_scenes: Array[PackedScene] = []
@export var leftover_tray: LeftoverTray

var time_left: int = 60
var level_active: = false
var shelves: Array[Shelf] = []
var total_items_on_board := 0
var current_level := 1

var _scene_type_cache: Dictionary = {}

var layouts = {
	"diamond":  [1, 2, 3, 2, 1],
	"tower":    [2, 2, 2, 2],
	"triangle": [1, 2, 3],
	"grid_4x3": [3, 3, 3, 3]
}

func _ready():
	# Await FIRST — ensures every node's _ready() has run before we touch anything
	await get_tree().process_frame
	await get_tree().process_frame

	for node in get_tree().get_nodes_in_group("shelves"):
		if node is Shelf:
			shelves.append(node)
			if not node.shelf_cleared.is_connected(_on_shelf_cleared): #Prevents duplicate connections
				node.shelf_cleared.connect(_on_shelf_cleared)
		start_new_round()

#Resets the board for a new level (clears previous items, re-lays out shelves and populates with items)
func start_new_round():
	if leftover_tray: #Clears the leftover tray
		for item in leftover_tray.items_on_shelf:
			if is_instance_valid(item):
				item.queue_free()
		leftover_tray.items_on_shelf.clear()

	for s in shelves:
		s.visible = false
		s.process_mode = PROCESS_MODE_DISABLED
		s.reset(true)

	var pattern = layouts[layouts.keys().pick_random()] #Picks one random key
	#Prepares variables
	var active_shelves: Array[Shelf] = []
	var shelf_index := 0
	var screen_center = get_viewport_rect().size / 2 - Vector2(200, 100)

	#This lays out the shelves in the screen
	for row_index in range(pattern.size()):
		var shelves_in_row: int = pattern[row_index]
		for i in range(shelves_in_row):
			if shelf_index >= shelves.size():
				break
			var s = shelves[shelf_index]
			s.visible = true
			s.process_mode = PROCESS_MODE_INHERIT
			var x_offset = (i - (shelves_in_row - 1) / 2.0) * 340
			var y_offset = (row_index - (pattern.size() - 1) / 2.0) * 190
			s.global_position = screen_center + Vector2(x_offset, y_offset)
			active_shelves.append(s)
			shelf_index += 1

	# 2 clears per shelf (front layer + back layer)
	total_items_on_board = active_shelves.size() * 2 #Tells the shelf it has two layers (front + back)
	spawn_items_for_layout(active_shelves) #Calls separate func for item population

func spawn_items_for_layout(active_shelves: Array):
	if item_scenes.is_empty():
		push_error("GameManager: item_scenes is empty!")
		return

	var pool := _build_pool(active_shelves.size() * 2) #Creates a pool of items to fill shelves. (x2 because of front and back layer)

	for layer in ["front", "back"]: #Essentially does front and back layers are populated independently with random items.
		for shelf in active_shelves:
			_fill_shelf_layer(shelf, pool, layer)
		pool.shuffle() #Prevents item repetition

	# Always seed the tray with one item so the player has a free move
	if leftover_tray and not pool.is_empty():
		var tray_item: Item = pool.pop_back().instantiate()
		add_child(tray_item)
		leftover_tray.add_item(tray_item)

#Function that handles spawning of items into the shelves
func _fill_shelf_layer(shelf: Shelf, pool: Array, layer: String) -> void:
	var placed_types: Array[String] = [] #Purpose: Fills a single shelf layer (front or back) with up to 3 items, avoiding duplicates in the same shelf.
	for _i in range(3):
		if pool.is_empty():
			return
		var pick := _find_valid_index(pool, placed_types) #Purpose: Fills a single shelf layer (front or back) with up to 3 items, avoiding duplicates in the same shelf.
		var scene: PackedScene = pool.pop_at(pick)
		placed_types.append(get_type_from_scene(scene))
		var item: Item = scene.instantiate()
		add_child(item)
		shelf.add_item_to_layer(item, layer)

#This function makes sure that placing three of a kind in the same shelf doesnt occur
func _find_valid_index(pool: Array, placed_types: Array) -> int:
	if placed_types.size() == 2 and placed_types[0] == placed_types[1]:
		var blocked: String = placed_types[0] #Stores the type of the items that are “blocked” (the type we want to avoid for the third slot).
		for i in range(pool.size()): #Loops through pool and picks out the first item type that isnt blocked
			if get_type_from_scene(pool[i]) != blocked:
				return i
	return pool.size() - 1 #If the loop didn’t find an unblocked type (or if the first condition never triggered), just return the last index in the pool.

#Create a pool of PackedScene items that will be distributed onto the shelves.
func _build_pool(triplet_count: int) -> Array:
	var pool := [] #Creates an empty array pool
	for _i in range(triplet_count): #Loops triplet count (triplet_count represents number of shelves (front and back) or how many triplets we want to generate
		var scene = item_scenes.pick_random()
		for _j in range(3): #This maintains the “3 items per shelf layer” structure.
			pool.append(scene)
	pool.shuffle()
	return pool

func get_type_from_scene(scene: PackedScene) -> String:
	if _scene_type_cache.has(scene):
		return _scene_type_cache[scene]
	var temp = scene.instantiate()
	var type: String = temp.item_type
	temp.free()  # free() not queue_free() — node was never added to the tree
	_scene_type_cache[scene] = type
	return type

# Handles overrall board progression checking 
func _on_shelf_cleared():
	total_items_on_board -= 1 #keeps track of how many items still need to be cleared to finish the round.
	if total_items_on_board <= 0: #Checks if all shelves are all cleared
		current_level += 1
		print("Level %d complete!" % current_level)
		await get_tree().create_timer(1.0).timeout
		start_new_round()
