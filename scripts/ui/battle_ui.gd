class_name BattleUI
extends CanvasLayer

## Combat UI (the job the spec's build order forgot — see docs/REVIEW.md).
##
## Built in code rather than as a .tscn so the layout diffs as text and the
## menu flow lives next to the state it drives. Swap for a designed scene once
## the fight is proven fun; the signal contract stays the same.

signal action_chosen(action: BattleAction)

enum Menu { ROOT, SKILL, ITEM, TARGET }

const PANEL_MARGIN := 16
const LOG_LINES := 5

var _actor: Battler = null
var _menu: Menu = Menu.ROOT
var _pending_move: MoveData = null
var _pending_item: ItemData = null

var _log_label: RichTextLabel
var _party_box: VBoxContainer
var _enemy_box: VBoxContainer
var _menu_box: VBoxContainer
var _prompt: Label
var _banner: Label
var _log_lines: Array[String] = []


func _ready() -> void:
	layer = 10
	_build()
	_set_menu_visible(false)

	BattleManager.awaiting_action.connect(_on_awaiting_action)
	BattleManager.action_resolved.connect(append_log)
	BattleManager.round_started.connect(_on_round_started)
	BattleManager.one_more_granted.connect(_on_one_more)
	BattleManager.battle_finished.connect(_on_battle_finished)


# --- Construction -----------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_banner = _make_label("", 28)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 24
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_banner)

	_enemy_box = VBoxContainer.new()
	_enemy_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_enemy_box.offset_left = -320
	_enemy_box.offset_top = PANEL_MARGIN
	_enemy_box.offset_right = -PANEL_MARGIN
	root.add_child(_enemy_box)

	_party_box = VBoxContainer.new()
	_party_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_party_box.offset_left = PANEL_MARGIN
	_party_box.offset_top = -180
	_party_box.offset_bottom = -PANEL_MARGIN
	root.add_child(_party_box)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.fit_content = false
	_log_label.scroll_following = true
	_log_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_log_label.offset_left = 340
	_log_label.offset_right = -340
	_log_label.offset_top = -140
	_log_label.offset_bottom = -PANEL_MARGIN
	root.add_child(_log_label)

	var menu_panel := PanelContainer.new()
	menu_panel.name = "MenuPanel"
	menu_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	menu_panel.offset_left = -260
	menu_panel.offset_top = -240
	menu_panel.offset_right = -PANEL_MARGIN
	menu_panel.offset_bottom = -PANEL_MARGIN
	root.add_child(menu_panel)

	var inner := VBoxContainer.new()
	menu_panel.add_child(inner)

	_prompt = _make_label("", 14)
	inner.add_child(_prompt)

	# A ScrollContainer between the panel and the button list breaks minimum
	# -size propagation: however many buttons a menu holds (the skill menu
	# grows with the learnset — 7 entries by level 5 overflows a plain
	# VBoxContainer in this fixed-height panel), the panel itself never grows
	# past its anchored footprint. Extra entries scroll instead of spilling
	# past the canvas or overlapping the log panel to its left.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(scroll)

	_menu_box = VBoxContainer.new()
	_menu_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_menu_box)


func _make_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	return label


# --- Flow -------------------------------------------------------------------

func _on_awaiting_action(actor: Battler) -> void:
	_actor = actor
	_menu = Menu.ROOT
	_refresh_status()
	_show_root_menu()


func _on_round_started(round_number: int) -> void:
	append_log("[b]-- Round %d --[/b]" % round_number)
	_refresh_status()


func _on_one_more(actor: Battler) -> void:
	_flash_banner("ONE MORE — %s" % actor.display_name())


func _on_battle_finished(outcome: int, rewards: Dictionary) -> void:
	_set_menu_visible(false)
	match outcome:
		Combat.Outcome.VICTORY:
			_flash_banner("VICTORY")
			append_log("Won. +%d XP, +%d gold." % [rewards.get("xp", 0), rewards.get("gold", 0)])
		Combat.Outcome.DEFEAT:
			_flash_banner("DEFEAT")
		Combat.Outcome.FLED:
			_flash_banner("Escaped")


func _show_root_menu() -> void:
	_prompt.text = "%s — what do you do?" % _actor.display_name()
	_clear_menu()
	_add_button("Attack", _on_attack)
	_add_button("Skill", _on_skill, _actor.usable_moves().is_empty())
	_add_button("Item", _on_item, GameState.inventory.is_empty())
	_add_button("Defend", _on_defend)
	_add_button("Flee", _on_flee)
	_set_menu_visible(true)


func _on_attack() -> void:
	_pending_move = null
	_pending_item = null
	_show_target_menu()


func _on_skill() -> void:
	_menu = Menu.SKILL
	_prompt.text = "Skill  (SP: %d)" % _actor.sp
	_clear_menu()
	for move in _actor.usable_moves():
		var label: String = "%s  [%s]  %d SP" % [move.display_name, move.type, move.sp_cost]
		_add_button(label, _on_skill_picked.bind(move))
	_add_button("Back", _show_root_menu)


func _on_skill_picked(move: MoveData) -> void:
	_pending_move = move
	_pending_item = null
	if move.is_offensive():
		_show_target_menu()
	else:
		_emit(BattleAction.skill(_actor, _actor, move))


func _on_item() -> void:
	_menu = Menu.ITEM
	_prompt.text = "Item"
	_clear_menu()
	for id in GameState.inventory:
		var item: ItemData = ContentDB.item(id)
		if item == null:
			continue
		_add_button(
			"%s  x%d" % [item.display_name, GameState.item_count(id)],
			_on_item_picked.bind(item)
		)
	_add_button("Back", _show_root_menu)


func _on_item_picked(item: ItemData) -> void:
	# Healing items target the party, so they skip the enemy target list.
	_emit(BattleAction.use_item(_actor, _actor, item))


func _on_defend() -> void:
	_emit(BattleAction.defend(_actor))


func _on_flee() -> void:
	_emit(BattleAction.flee(_actor))


func _show_target_menu() -> void:
	_menu = Menu.TARGET
	_prompt.text = "Target"
	_clear_menu()
	for foe in BattleManager.enemies:
		if not foe.is_alive():
			continue
		var hint: String = ""
		var attack_type: StringName = (
			_pending_move.type if _pending_move != null else Damage.BASIC_ATTACK_TYPE
		)
		if GameState.get_flag(_weakness_flag(foe), false):
			var mult: float = TypeChart.multiplier(attack_type, foe.data.defend_type)
			if mult > TypeChart.NEUTRAL:
				hint = "  (WEAK)"
			elif is_zero_approx(mult):
				hint = "  (null)"
			elif mult < TypeChart.NEUTRAL:
				hint = "  (resist)"
		_add_button("%s  %d HP%s" % [foe.display_name(), foe.hp, hint], _on_target_picked.bind(foe))
	_add_button("Back", _show_root_menu)


func _on_target_picked(target: Battler) -> void:
	if _pending_move != null:
		_emit(BattleAction.skill(_actor, target, _pending_move))
	else:
		_emit(BattleAction.attack(_actor, target))


func _emit(action: BattleAction) -> void:
	_set_menu_visible(false)
	action_chosen.emit(action)
	BattleManager.submit_action(action)


# --- Status -----------------------------------------------------------------

func _refresh_status() -> void:
	_rebuild_group(_party_box, BattleManager.player_party, true)
	_rebuild_group(_enemy_box, BattleManager.enemies, false)


func _rebuild_group(box: VBoxContainer, group: Array[Battler], show_sp: bool) -> void:
	for child in box.get_children():
		child.queue_free()
	for b in group:
		var text: String = "%s   HP %d/%d" % [b.display_name(), b.hp, b.data.max_hp]
		if show_sp:
			text += "   SP %d/%d" % [b.sp, b.data.max_sp]
		if not b.is_alive():
			text = "%s   DOWN" % b.display_name()
		box.add_child(_make_label(text, 16))


## Adds a line to the on-screen log, trimming to the last LOG_LINES entries.
## Public because BattleManager.action_resolved lines land here directly.
func append_log(line: String) -> void:
	_log_lines.append(line)
	while _log_lines.size() > LOG_LINES:
		_log_lines.pop_front()
	_log_label.text = "\n".join(_log_lines)
	_refresh_status()


func _flash_banner(text: String) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.5)


func _clear_menu() -> void:
	for child in _menu_box.get_children():
		child.queue_free()


func _add_button(text: String, handler: Callable, disabled: bool = false) -> void:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	button.pressed.connect(handler)
	_menu_box.add_child(button)
	if _menu_box.get_child_count() == 1:
		button.call_deferred(&"grab_focus")


func _set_menu_visible(value: bool) -> void:
	_menu_box.visible = value
	_prompt.visible = value


static func _weakness_flag(foe: Battler) -> StringName:
	return StringName("scouted_%s" % foe.data.id)
