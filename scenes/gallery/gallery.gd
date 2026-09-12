extends Control

signal closed

# ゲーム中からオーバーレイ表示された場合true。閉じるとシーン遷移せず呼び出し元に戻る
var overlay_mode := false

const CHAR_IDS := ["reimu", "marisa", "sakuya", "reisen", "sanae", "youmu"]
const FONT := preload("res://assets/fonts/ZenMaruGothic-Medium.ttf")

@onready var title_label: Label = $TitleLabel
@onready var back_button: Button = $BackButton
@onready var list_scroll: ScrollContainer = $ListScroll
@onready var list_box: VBoxContainer = $ListScroll/ListBox
@onready var detail_panel: Control = $DetailPanel
@onready var detail_title: Label = $DetailPanel/DetailTitle
@onready var to_list_button: Button = $DetailPanel/ToListButton
@onready var form_image: TextureRect = $DetailPanel/FormImage
@onready var form_label: Label = $DetailPanel/FormLabel
@onready var form_buttons: HBoxContainer = $DetailPanel/FormButtons

var chars := {}
var current_player_id := ""
var current_enemy_id := ""

func _ready() -> void:
	for cid in CHAR_IDS:
		var res := load("res://resources/characters/%s.tres" % cid) as CharacterData
		if res:
			chars[cid] = res
	if overlay_mode:
		back_button.text = "戻る"
	back_button.pressed.connect(_on_back_to_title)
	to_list_button.pressed.connect(_show_list)
	_build_form_buttons()
	_build_list()
	_show_list()

func _on_back_to_title() -> void:
	if overlay_mode:
		closed.emit()
		return
	get_tree().change_scene_to_file("res://scenes/title/title.tscn")

func _show_list() -> void:
	detail_panel.visible = false
	list_scroll.visible = true
	back_button.visible = true
	title_label.visible = true

func _styled_button(label: String, font_size: int) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_override("font", FONT)
	btn.add_theme_font_size_override("font_size", font_size)
	return btn

func _build_list() -> void:
	for player in CHAR_IDS:
		for enemy in CHAR_IDS:
			if enemy == player:
				continue
			list_box.add_child(_make_list_row(player, enemy))

# 「〇〇 vs 〇〇」の左右にSDキャラ画像を添えた一覧行を作る
func _make_list_row(player: String, enemy: String) -> Button:
	var cleared: bool = GameState.is_stage_cleared(player, enemy)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 130)
	if cleared:
		btn.pressed.connect(_open_detail.bind(player, enemy))
	else:
		btn.disabled = true

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 16
	hbox.offset_right = -16
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 12)
	if not cleared:
		hbox.modulate = Color(1, 1, 1, 0.5)

	# 両側のSDが行の中央(vs)を向くよう、素材の向きフラグを加味して反転する
	var left_sd := _make_sd_icon(chars[player].sd_sprite, chars[player].sd_faces_left)
	var label_text := "%s vs %s" % [chars[player].display_name, chars[enemy].display_name]
	if not cleared:
		label_text += "\n（未クリア）"
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var right_sd := _make_sd_icon(chars[enemy].sd_sprite, not chars[enemy].sd_faces_left)

	hbox.add_child(left_sd)
	hbox.add_child(label)
	hbox.add_child(right_sd)
	btn.add_child(hbox)
	return btn

func _make_sd_icon(tex: Texture2D, flip: bool) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = tex
	icon.flip_h = flip
	icon.custom_minimum_size = Vector2(120, 0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _build_form_buttons() -> void:
	for i in 3:
		var btn := _styled_button("形態%d" % (i + 1), 32)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_set_form.bind(i))
		form_buttons.add_child(btn)

func _open_detail(player: String, enemy: String) -> void:
	current_player_id = player
	current_enemy_id = enemy
	detail_title.text = "%s vs %s" % [chars[player].display_name, chars[enemy].display_name]
	list_scroll.visible = false
	back_button.visible = false
	# 「図鑑」の見出しと対戦カード名が重ならないよう、詳細表示中は見出しを隠す
	title_label.visible = false
	detail_panel.visible = true
	_set_form(0)

func _set_form(index: int) -> void:
	var enemy: CharacterData = chars[current_enemy_id]
	var forms := enemy.battle_forms
	if forms.is_empty():
		form_image.texture = null
		form_label.text = ""
		return
	index = clampi(index, 0, forms.size() - 1)
	form_image.texture = forms[index]
	form_label.text = "%s　形態 %d/%d" % [enemy.display_name, index + 1, forms.size()]
	for i in form_buttons.get_child_count():
		form_buttons.get_child(i).visible = i < forms.size()
