extends GutTest

## Task 6: UI structure. Battle.tscn's UI is built procedurally, so nothing
## catches an overflow except actually laying it out and measuring — hence
## this file, rather than reasoning about the anchor math by eye.
##
## The project runs canvas_items stretch mode with a fixed 1280x720 logical
## canvas (project.godot [display]), so 1920x1080 is not a second layout to
## check: it is the same 1280x720 canvas uniformly scaled 1.5x (both are
## 16:9), and uniform scaling can't introduce an overflow that isn't already
## present at the base resolution. What actually varies is CONTENT — how many
## buttons a menu holds — so these tests grow the real hero's moveset via
## GameState.award_xp() (not fabricated data) to the point a naive VBoxContainer
## would overflow its panel, and assert the real, live-refreshed Control tree.

const VIEWPORT_SIZE := Vector2(1280, 720)

var _ui: BattleUI
var _spawned: Array[Node] = []


func before_each():
	GameState.new_game()
	BattleManager.turn_delay = 0.0


func after_each():
	for node in _spawned:
		if is_instance_valid(node):
			node.queue_free()
	_spawned = []
	await get_tree().process_frame
	GameState.new_game()


func _spawn_ui() -> BattleUI:
	var ui := BattleUI.new()
	_spawned.append(ui)
	get_tree().root.add_child(ui)
	return ui


## Every rendered Control must stay inside the logical canvas — an overflow
## off the visible area at either the top-left or bottom-right.
func _assert_within_canvas(control: Control, label: String) -> void:
	var rect: Rect2 = control.get_global_rect()
	assert_true(
		rect.position.x >= -0.5 and rect.position.y >= -0.5,
		"%s starts inside the canvas (got %s)" % [label, rect.position]
	)
	assert_true(
		rect.end.x <= VIEWPORT_SIZE.x + 0.5 and rect.end.y <= VIEWPORT_SIZE.y + 0.5,
		"%s ends inside the %s canvas (got end %s)" % [label, VIEWPORT_SIZE, rect.end]
	)


func test_root_menu_buttons_stay_within_the_canvas():
	_ui = _spawn_ui()
	await get_tree().process_frame
	await get_tree().process_frame

	BattleManager.queue_encounter([ContentDB.enemy(&"frostbit")] as Array[EnemyData])
	BattleManager.start_battle(GameState.battle_party(), BattleManager.take_pending_encounter())
	await get_tree().process_frame
	await get_tree().process_frame

	var buttons := _ui.find_children("*", "Button", true, false)
	assert_gt(buttons.size(), 0, "the root menu actually built some buttons")
	for button in buttons:
		_assert_within_canvas(button, "root menu button '%s'" % button.text)


func test_the_skill_menu_scroll_viewport_does_not_overflow_with_a_full_learnset():
	# Grow the REAL hero to level 5 through the actual progression system —
	# by then the learnset (SPEC content) grants Frost, Radiance, Gale and
	# Mend on top of the starting Cleave and Ember, six moves plus "Back".
	# A plain unbounded VBoxContainer in a fixed-height panel cannot fit that;
	# the fix wraps the button list in a ScrollContainer, so it is the
	# ScrollContainer's own (clipped, visible) viewport that must stay
	# on-canvas — not every button's raw position, since a scrolled-out
	# button legitimately sits below the visible viewport by design.
	GameState.award_xp(GameState.xp_for_level(1) * 20)
	var hero: PartyMemberData = GameState.party[0]
	assert_gte(hero.moves.size(), 6, "sanity: the real learnset grew past 6 moves by here")

	_ui = _spawn_ui()
	await get_tree().process_frame
	await get_tree().process_frame

	BattleManager.queue_encounter([ContentDB.enemy(&"frostbit")] as Array[EnemyData])
	BattleManager.start_battle(GameState.battle_party(), BattleManager.take_pending_encounter())
	await get_tree().process_frame
	await get_tree().process_frame

	# Open the Skill submenu the same way a player would: click Attack's
	# sibling "Skill" button.
	var root_buttons: Array = _ui.find_children("*", "Button", true, false)
	var skill_button: Button = null
	for b in root_buttons:
		if b.text == "Skill":
			skill_button = b
	assert_not_null(skill_button, "the root menu has a Skill button")
	skill_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame

	var skill_buttons: Array = _ui.find_children("*", "Button", true, false)
	# hero.moves.size() skill entries plus one "Back" button.
	assert_eq(
		skill_buttons.size(), hero.moves.size() + 1,
		"every learned move got a button, plus Back"
	)

	var scrolls: Array = _ui.find_children("*", "ScrollContainer", true, false)
	assert_eq(scrolls.size(), 1, "sanity: exactly one ScrollContainer wraps the menu")
	var scroll: ScrollContainer = scrolls[0]

	assert_true(scroll.clip_contents, "the scroll viewport clips its overflowing content")
	_assert_within_canvas(scroll, "the menu's scroll viewport")

	# The list must still be fully reachable by scrolling — clipping content
	# that can never be scrolled to would trade a visual overflow for a
	# softlock (an un-clickable "Back").
	var v_scroll: VScrollBar = scroll.get_v_scroll_bar()
	assert_gt(
		v_scroll.max_value - v_scroll.page, 0.0,
		"sanity: the content is actually taller than the viewport here"
	)
	scroll.scroll_vertical = int(v_scroll.max_value)
	await get_tree().process_frame
	var back_button: Button = null
	for b in skill_buttons:
		if b.text == "Back":
			back_button = b
	assert_not_null(back_button, "the Back button exists")
	assert_true(
		scroll.get_global_rect().encloses(back_button.get_global_rect()),
		"scrolling to the bottom brings Back fully into the visible viewport"
	)


func test_no_two_top_level_panels_overlap_with_a_full_skill_menu():
	GameState.award_xp(GameState.xp_for_level(1) * 20)

	_ui = _spawn_ui()
	await get_tree().process_frame
	await get_tree().process_frame

	BattleManager.queue_encounter([ContentDB.enemy(&"frostbit")] as Array[EnemyData])
	BattleManager.start_battle(GameState.battle_party(), BattleManager.take_pending_encounter())
	await get_tree().process_frame
	await get_tree().process_frame

	var root_buttons: Array = _ui.find_children("*", "Button", true, false)
	for b in root_buttons:
		if b.text == "Skill":
			b.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame

	# The menu panel is the deepest-right, deepest-bottom fixture; the log
	# sits directly to its left. If the menu panel grew past its intended
	# footprint (rather than scrolling), it would encroach on the log's rect.
	# Looked up by name, not class: ScrollContainer has an internal "_focus"
	# child that also matches a PanelContainer type query.
	var menu_panel: Control = _ui.find_child("MenuPanel", true, false)
	var logs: Array = _ui.find_children("*", "RichTextLabel", true, false)
	assert_not_null(menu_panel, "the menu panel exists")
	assert_eq(logs.size(), 1, "sanity: exactly one log RichTextLabel exists")
	var log_label: Control = logs[0]
	var overlap: Rect2 = menu_panel.get_global_rect().intersection(log_label.get_global_rect())
	assert_true(
		overlap.size.x <= 0.5 or overlap.size.y <= 0.5,
		"the menu panel does not encroach on the log panel (overlap %s)" % overlap.size
	)
