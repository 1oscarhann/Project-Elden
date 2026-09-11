extends GutTest

## If an autoload's script fails to compile, Godot substitutes a bare Node and
## every other test in the suite quietly asserts nothing. Fail here instead.

const AUTOLOADS := ["GameState", "BattleManager", "SaveManager", "AudioManager"]


func test_every_autoload_exists():
	for name in AUTOLOADS:
		var node: Node = get_tree().root.get_node_or_null(NodePath("/root/%s" % name))
		assert_not_null(node, "%s autoload exists" % name)


func test_every_autoload_kept_its_script():
	for name in AUTOLOADS:
		var node: Node = get_tree().root.get_node_or_null(NodePath("/root/%s" % name))
		if node == null:
			continue
		assert_not_null(node.get_script(), "%s kept its script" % name)


func test_singletons_expose_their_api():
	assert_true(GameState.has_method(&"to_dict"), "GameState.to_dict exists")
	assert_true(GameState.has_method(&"from_dict"), "GameState.from_dict exists")
	assert_true(BattleManager.has_method(&"start_battle"), "BattleManager.start_battle exists")
	assert_true(SaveManager.has_method(&"save_local"), "SaveManager.save_local exists")
