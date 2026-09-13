extends CanvasLayer

signal player_char_selected(char_data: CharacterData)
signal opponent_selected(char_data: CharacterData)
signal bgm_selected(path: String)
signal gallery_requested
signal title_requested
signal coins_changed

const JP_FONT := preload("res://assets/fonts/ZenMaruGothic-Medium.ttf")
const BGM_DISC_ICON := preload("res://assets/sprites/ui/bgm_disc.svg")

@onready var toggle_button: Button = $ToggleButton
@onready var menu_dimmer: Button = $MenuDimmer
@onready var menu_panel: Panel = $MenuPanel
@onready var menu_close: Button = $MenuPanel/CloseButton
@onready var char_button: Button = $MenuPanel/Buttons/CharButton
@onready var bgm_button: Button = $MenuPanel/Buttons/BGMButton
@onready var volume_button: Button = $MenuPanel/Buttons/VolumeButton
@onready var gacha_button: Button = $MenuPanel/Buttons/GachaButton
@onready var gallery_button: Button = $MenuPanel/Buttons/GalleryButton
@onready var title_button: Button = $MenuPanel/Buttons/TitleButton

@onready var char_panel: Panel = $CharPanel
@onready var player_list: VBoxContainer = $CharPanel/Columns/PlayerColumn/PlayerScroll/PlayerList
@onready var opponent_list: VBoxContainer = $CharPanel/Columns/OpponentColumn/OpponentScroll/OpponentList
@onready var char_close: Button = $CharPanel/CloseButton

@onready var bgm_panel: Panel = $BGMPanel
@onready var bgm_list: VBoxContainer = $BGMPanel/BGMScroll/BGMList
@onready var bgm_close: Button = $BGMPanel/CloseButton
@onready var bgm_choice_panel: Panel = $BGMPanel/ChoicePanel
@onready var bgm_keep_button: Button = $BGMPanel/ChoicePanel/KeepButton
@onready var bgm_reset_button: Button = $BGMPanel/ChoicePanel/ResetButton

@onready var volume_panel: Panel = $VolumePanel
@onready var volume_slider: HSlider = $VolumePanel/VolumeSlider
@onready var se_slider: HSlider = $VolumePanel/SESlider
@onready var skip_talk_check: Button = $VolumePanel/SkipTalkCheck
@onready var volume_close: Button = $VolumePanel/CloseButton

@onready var gacha_panel: Panel = $GachaPanel
@onready var roll_button: Button = $GachaPanel/RollButton
@onready var ten_roll_button: Button = $GachaPanel/TenRollButton
@onready var gacha_coin_label: Label = $GachaPanel/GachaCoinLabel
@onready var pity_label: Label = $GachaPanel/PityLabel
@onready var result_image: TextureRect = $GachaPanel/ResultImage
@onready var result_label: Label = $GachaPanel/ResultLabel
@onready var gacha_close: Button = $GachaPanel/CloseButton

@onready var gacha_video_overlay: Button = $GachaVideoOverlay
@onready var gacha_video_player: VideoStreamPlayer = $GachaVideoOverlay/VideoStreamPlayer

# ガチャ設定(ここの定数で調整する)
const GACHA_COST_SINGLE := 100    # 1回の消費コイン
const GACHA_COST_TEN := 1000      # 10連の消費コイン(割引なし)
const GACHA_PITY_COUNT := 30      # 天井: この回数引くと未所持の自キャラ確定

var _chars: Array[CharacterData] = []
var _wheel_open := false
var _pending_bgm_path := ""

var current_player: CharacterData
var current_opponent: CharacterData

# ガチャ演出動画。再生完了 or タップスキップで _gacha_video_on_done を呼ぶ
var _gacha_video_on_done: Callable

func _ready() -> void:
	toggle_button.pressed.connect(_on_toggle)
	menu_dimmer.pressed.connect(close_wheel)
	menu_close.pressed.connect(close_wheel)
	char_button.pressed.connect(_on_char_button)
	bgm_button.pressed.connect(_on_bgm_button)
	volume_button.pressed.connect(_open_panel.bind(volume_panel))
	gacha_button.pressed.connect(_on_gacha_button)
	gallery_button.pressed.connect(func(): gallery_requested.emit())
	title_button.pressed.connect(func(): title_requested.emit())
	char_close.pressed.connect(_close_sub_panel.bind(char_panel))
	bgm_close.pressed.connect(_close_sub_panel.bind(bgm_panel))
	volume_close.pressed.connect(_close_sub_panel.bind(volume_panel))
	gacha_close.pressed.connect(_close_sub_panel.bind(gacha_panel))
	roll_button.pressed.connect(_on_roll)
	ten_roll_button.pressed.connect(_on_roll_ten)
	roll_button.text = "1回 %dコイン" % GACHA_COST_SINGLE
	ten_roll_button.text = "10連 %dコイン" % GACHA_COST_TEN
	volume_slider.value_changed.connect(_on_volume_changed)
	volume_slider.drag_ended.connect(_on_volume_drag_ended)
	se_slider.value_changed.connect(_on_se_volume_changed)
	se_slider.drag_ended.connect(_on_volume_drag_ended)
	bgm_keep_button.pressed.connect(_on_bgm_choice.bind(true))
	bgm_reset_button.pressed.connect(_on_bgm_choice.bind(false))
	gacha_video_overlay.pressed.connect(_finish_gacha_video)
	# 演出中は画面全体を覆いたいので、バナー/安全領域の内側に縮める対象から外す
	gacha_video_overlay.set_meta("ignore_safe_area", true)
	gacha_video_player.finished.connect(_finish_gacha_video)

	volume_slider.set_value_no_signal(GameState.master_volume)
	se_slider.set_value_no_signal(GameState.se_volume)

	skip_talk_check.set_pressed_no_signal(GameState.skip_cleared_dialogue)
	skip_talk_check.toggled.connect(_on_skip_talk_toggled)
	_update_skip_talk_text(GameState.skip_cleared_dialogue)

	_set_wheel_buttons_visible(false)

func setup(chars: Array[CharacterData]) -> void:
	_chars = chars

func close_wheel() -> void:
	_wheel_open = false
	_set_wheel_buttons_visible(false)
	for p in [char_panel, bgm_panel, volume_panel, gacha_panel]:
		p.hide()
	if gacha_video_overlay.visible:
		gacha_video_player.stop()
		gacha_video_overlay.hide()
		_gacha_video_on_done = Callable()
	get_tree().paused = false

func _on_toggle() -> void:
	if _wheel_open:
		close_wheel()
	else:
		_wheel_open = true
		get_tree().paused = true
		_set_wheel_buttons_visible(true)

# メニューをポップアップ(ディマー + 中央パネル)で表示する。バトルUIの上に重ねず全面を占有する
func _set_wheel_buttons_visible(open: bool) -> void:
	menu_dimmer.visible = open
	menu_panel.visible = open
	toggle_button.visible = not open
	if not open:
		return
	var buttons := [char_button, bgm_button, gacha_button, gallery_button, volume_button, title_button]
	var tween := create_tween()
	var delay := 0.0
	for b in buttons:
		b.modulate.a = 0.0
		tween.parallel().tween_property(b, "modulate:a", 1.0, 0.15).set_delay(delay)
		delay += 0.05

func _open_panel(panel: Panel) -> void:
	for p in [char_panel, bgm_panel, volume_panel, gacha_panel]:
		p.hide()
	menu_panel.hide()
	panel.show()

func _close_sub_panel(panel: Panel) -> void:
	panel.hide()
	if _wheel_open:
		menu_panel.show()

func _on_char_button() -> void:
	_rebuild_char_lists()
	_open_panel(char_panel)

func _on_bgm_button() -> void:
	bgm_choice_panel.hide()
	_rebuild_bgm_list()
	_open_panel(bgm_panel)

func _make_list_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_override("font", JP_FONT)
	b.add_theme_font_size_override("font_size", 36)
	b.custom_minimum_size = Vector2(0, 84)
	b.clip_text = true
	return b

func _rebuild_char_lists() -> void:
	for child in player_list.get_children():
		child.queue_free()
	for child in opponent_list.get_children():
		child.queue_free()
	for c in _chars:
		if GameState.owned_char_ids.has(c.char_id):
			var pb := _make_list_button(c.display_name + ("（使用中）" if c == current_player else ""))
			pb.disabled = c == current_player
			pb.pressed.connect(_on_player_chosen.bind(c))
			player_list.add_child(pb)
	for c in _chars:
		if c == current_player:
			continue
		var label_text := c.display_name
		# 現在の操作キャラでクリア済みの組み合わせが分かるようにする
		if current_player != null and GameState.is_stage_cleared(current_player.char_id, c.char_id):
			label_text += "　★クリア済"
		if c == current_opponent:
			label_text += "（対戦中）"
		var ob := _make_list_button(label_text)
		ob.disabled = c == current_opponent
		ob.pressed.connect(_on_opponent_chosen.bind(c))
		opponent_list.add_child(ob)

func _rebuild_bgm_list() -> void:
	for child in bgm_list.get_children():
		child.queue_free()
	var default_btn := _make_list_button("ステージ標準" + ("（選択中）" if GameState.selected_bgm_path == "" else ""))
	default_btn.disabled = GameState.selected_bgm_path == ""
	default_btn.pressed.connect(_on_bgm_chosen.bind(""))
	bgm_list.add_child(default_btn)
	for path in GameState.owned_bgm_paths:
		var bname: String = path.get_file().get_basename()
		var b := _make_list_button(bname + ("（選択中）" if path == GameState.selected_bgm_path else ""))
		b.disabled = path == GameState.selected_bgm_path
		b.pressed.connect(_on_bgm_chosen.bind(path))
		bgm_list.add_child(b)

func _on_player_chosen(c: CharacterData) -> void:
	close_wheel()
	player_char_selected.emit(c)

func _on_opponent_chosen(c: CharacterData) -> void:
	close_wheel()
	opponent_selected.emit(c)

func _on_bgm_chosen(path: String) -> void:
	if path == "":
		GameState.selected_bgm_path = ""
		_rebuild_bgm_list()
		bgm_selected.emit("")
		return
	_pending_bgm_path = path
	bgm_choice_panel.show()

func _on_bgm_choice(keep_on_opponent_change: bool) -> void:
	GameState.selected_bgm_path = _pending_bgm_path
	GameState.bgm_keep_on_opponent_change = keep_on_opponent_change
	bgm_choice_panel.hide()
	_rebuild_bgm_list()
	bgm_selected.emit(_pending_bgm_path)

func _on_skip_talk_toggled(pressed: bool) -> void:
	GameState.skip_cleared_dialogue = pressed
	GameState.save_progress()
	_update_skip_talk_text(pressed)

func _update_skip_talk_text(pressed: bool) -> void:
	skip_talk_check.text = "クリア済み会話スキップ：%s" % ("ON" if pressed else "OFF")

func _on_volume_changed(value: float) -> void:
	GameState.master_volume = value
	GameState.apply_volumes()

func _on_se_volume_changed(value: float) -> void:
	GameState.se_volume = value
	GameState.apply_volumes()

# スライダー操作が終わったタイミングでのみセーブする(毎フレーム書き込まないため)
func _on_volume_drag_ended(_changed: bool) -> void:
	GameState.save_progress()

func _on_gacha_button() -> void:
	_update_gacha_ui()
	_open_panel(gacha_panel)

func _update_gacha_ui() -> void:
	gacha_coin_label.text = "所持コイン：%d" % GameState.coins
	var remaining: int = maxi(GACHA_PITY_COUNT - GameState.gacha_pity_count, 1)
	if _unowned_chars().is_empty():
		pity_label.text = "自キャラはすべて入手済み！"
	else:
		pity_label.text = "あと%d回で未所持キャラ確定！" % remaining
	roll_button.disabled = GameState.coins < GACHA_COST_SINGLE
	ten_roll_button.disabled = GameState.coins < GACHA_COST_TEN

func _unowned_chars() -> Array[CharacterData]:
	var result: Array[CharacterData] = []
	for c in _chars:
		if not GameState.owned_char_ids.has(c.char_id):
			result.append(c)
	return result

# 1回分の抽選。天井到達時は未所持の自キャラを確定排出する
func _roll_prize() -> Dictionary:
	GameState.gacha_pity_count += 1
	var unowned := _unowned_chars()
	if not unowned.is_empty() and GameState.gacha_pity_count >= GACHA_PITY_COUNT:
		var pity_char: CharacterData = unowned.pick_random()
		GameState.owned_char_ids.append(pity_char.char_id)
		GameState.gacha_pity_count = 0
		return {"type": "char", "char": pity_char, "new": true, "pity": true}
	var pool: Array[Dictionary] = []
	for c in _chars:
		pool.append({"type": "char", "char": c})
	for p in GameState.all_bgm_paths():
		pool.append({"type": "bgm", "path": p})
	if pool.is_empty():
		return {}
	var prize: Dictionary = pool.pick_random().duplicate()
	prize["pity"] = false
	if prize.type == "char":
		var c: CharacterData = prize.char
		prize["new"] = not GameState.owned_char_ids.has(c.char_id)
		if prize.new:
			GameState.owned_char_ids.append(c.char_id)
			GameState.gacha_pity_count = 0
	else:
		prize["new"] = not GameState.owned_bgm_paths.has(prize.path)
		if prize.new:
			GameState.owned_bgm_paths.append(prize.path)
	return prize

func _on_roll() -> void:
	if not GameState.spend_coins(GACHA_COST_SINGLE):
		result_label.text = "コインが足りない…（1回 %dコイン）" % GACHA_COST_SINGLE
		return
	var prize := _roll_prize()
	GameState.save_progress()
	_update_gacha_ui()
	coins_changed.emit()
	_play_gacha_video(func() -> void:
		_show_single_result(prize))

# ガチャ演出動画を再生し、終了(再生完了 or タップスキップ)後に on_done を呼ぶ
# 演出中はガチャパネル/クイックメニューを閉じ、動画だけが画面いっぱいに見えるようにする
# 動画の冒頭には「Tap to Start」の文字が焼き込まれているため、その区間は飛ばして再生する
const GACHA_VIDEO_START_SECONDS := 2.3

func _play_gacha_video(on_done: Callable) -> void:
	_gacha_video_on_done = on_done
	gacha_panel.hide()
	menu_dimmer.hide()
	gacha_video_overlay.show()
	gacha_video_player.play()
	gacha_video_player.stream_position = GACHA_VIDEO_START_SECONDS

func _finish_gacha_video() -> void:
	if not gacha_video_overlay.visible:
		return
	gacha_video_player.stop()
	gacha_video_overlay.hide()
	menu_dimmer.show()
	gacha_panel.show()
	var on_done := _gacha_video_on_done
	_gacha_video_on_done = Callable()
	if on_done.is_valid():
		on_done.call()

func _show_single_result(prize: Dictionary) -> void:
	if prize.is_empty():
		return
	result_label.add_theme_font_size_override("font_size", 36)
	if prize.type == "char":
		var c: CharacterData = prize.char
		result_image.texture = c.tatie_sprite
		if prize.pity:
			result_label.text = "天井到達！【キャラ】%s を手に入れた！\nキャラ変更で使えるよ" % c.display_name
		elif prize.new:
			result_label.text = "【キャラ】%s を手に入れた！\nキャラ変更で使えるよ" % c.display_name
		else:
			result_label.text = "【キャラ】%s\n（すでに持っている）" % c.display_name
	else:
		result_image.texture = BGM_DISC_ICON
		var bname: String = prize.path.get_file().get_basename()
		if prize.new:
			result_label.text = "♪【BGM】%s を手に入れた！\nBGM変更で聴けるよ" % bname
		else:
			result_label.text = "♪【BGM】%s\n（すでに持っている）" % bname

# 未所持のキャラ/BGMから1つ確定で付与する(10連の確定枠用。すべて所持済みなら空)
func _grant_unowned() -> Dictionary:
	var pool: Array[Dictionary] = []
	for c in _unowned_chars():
		pool.append({"type": "char", "char": c, "new": true, "pity": false, "guaranteed": true})
	for p in GameState.all_bgm_paths():
		if not GameState.owned_bgm_paths.has(p):
			pool.append({"type": "bgm", "path": p, "new": true, "pity": false, "guaranteed": true})
	if pool.is_empty():
		return {}
	var prize: Dictionary = pool.pick_random()
	if prize.type == "char":
		GameState.owned_char_ids.append(prize.char.char_id)
		GameState.gacha_pity_count = 0
	else:
		GameState.owned_bgm_paths.append(prize.path)
	return prize

func _on_roll_ten() -> void:
	if not GameState.spend_coins(GACHA_COST_TEN):
		result_label.text = "コインが足りない…（10連 %dコイン）" % GACHA_COST_TEN
		return
	var results: Array[Dictionary] = []
	for i in 10:
		results.append(_roll_prize())
	# 10連は最低1つ未所持アイテム確定。新規が出なかったら最後の枠を差し替える
	var has_new := false
	for p in results:
		if not p.is_empty() and p.new:
			has_new = true
			break
	if not has_new:
		var guaranteed := _grant_unowned()
		if not guaranteed.is_empty():
			results[results.size() - 1] = guaranteed
	var lines: PackedStringArray = []
	var last_new_char: CharacterData = null
	var has_bgm := false
	for prize in results:
		if prize.is_empty():
			continue
		var mark := ""
		if prize.get("guaranteed", false):
			mark = "　★確定！"
		elif prize.pity:
			mark = "　★天井！"
		elif prize.new:
			mark = "　★NEW"
		if prize.type == "char":
			var c: CharacterData = prize.char
			lines.append("【キャラ】%s%s" % [c.display_name, mark])
			if prize.new:
				last_new_char = c
		else:
			lines.append("♪ %s%s" % [prize.path.get_file().get_basename(), mark])
			has_bgm = true
	GameState.save_progress()
	_update_gacha_ui()
	coins_changed.emit()
	_play_gacha_video(func() -> void:
		if last_new_char:
			result_image.texture = last_new_char.tatie_sprite
		elif has_bgm:
			result_image.texture = BGM_DISC_ICON
		else:
			result_image.texture = null
		result_label.add_theme_font_size_override("font_size", 24)
		result_label.text = "\n".join(lines))
