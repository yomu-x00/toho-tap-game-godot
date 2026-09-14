extends Node

enum State { DIALOGUE, BATTLE, LOSE, RESULT }

const CHAR_IDS := ["reimu", "marisa", "sakuya", "reisen", "sanae", "youmu"]
const GALLERY_SCENE := preload("res://scenes/gallery/gallery.tscn")

@onready var background: TextureRect = $Background
@onready var bgm_player: AudioStreamPlayer = $BGMPlayer
@onready var se_player: AudioStreamPlayer = $SEPlayer
@onready var bgm_title_box: Control = $BattleLayer/BGMTitleBox
@onready var bgm_title_label: Label = $BattleLayer/BGMTitleBox/BGMTitleLabel
@onready var battle_layer: CanvasLayer = $BattleLayer
@onready var enemy_sprite: TextureRect = $BattleLayer/EnemySprite
@onready var enemy_hp_bar: ProgressBar = $BattleLayer/EnemyHPBar
@onready var enemy_hp_label: Label = $BattleLayer/EnemyHPLabel
@onready var enemy_hp_value_label: Label = $BattleLayer/EnemyHPValueLabel
@onready var player_hp_bar: ProgressBar = $BattleLayer/PlayerHPBar
@onready var player_hp_label: Label = $BattleLayer/PlayerHPLabel
@onready var player_hp_value_label: Label = $BattleLayer/PlayerHPValueLabel
@onready var stage_label: Label = $BattleLayer/StageLabel
@onready var phase_label: Label = $BattleLayer/PhaseLabel
@onready var coin_label: Label = $BattleLayer/CoinLabel
@onready var player_sd_sprite: TextureRect = $BattleLayer/PlayerSDSprite
@onready var player_level_label: Label = $BattleLayer/PlayerLevelLabel
@onready var player_xp_bar: ProgressBar = $BattleLayer/PlayerXPBar
@onready var tap_button: Button = $BattleLayer/TapButton
@onready var dialogue_layer = $DialogueLayer
@onready var lose_layer = $LoseLayer
@onready var result_layer = $ResultLayer
@onready var level_up_layer = $LevelUpLayer
@onready var option_wheel = $OptionWheel

var player_data: CharacterData
var all_chars: Array[CharacterData] = []
var enemy_list: Array[CharacterData] = []
var current_enemy: CharacterData
var current_enemy_index: int = 0
var current_phase: int = 1
var max_phase: int = 3

var enemy_hp: float
var enemy_max_hp: float
var enemy_damage: float
var enemy_level: int = 1
var player_hp: float
var player_max_hp: float
var tap_damage: float
var battle_active: bool = false
var attack_timer: float = 0.0
# 動画広告での復活はフェーズごとに1回まで
var _revive_used: bool = false
const ENEMY_ATTACK_INTERVAL: float = 1.2
const TAP_DAMAGE: float = 10.0
const ENEMY_DAMAGE: float = 8.0
const XP_PER_TAP: int = 1
# 動画広告リワード: 敗北時に復活したときのHP回復割合(最大HPに対する比率)
const AD_REVIVE_HP_RATIO: float = 1.0
# 動画広告リワード: 勝利リザルトで付与する経験値
const AD_XP_BONUS: int = 30
# 敵HPはステージごとに倍々で増える(必要タップ数の伸びを大きくする)。
# 一方で敵の攻撃力の伸びは緩やかにし、後半ほど「長く耐えて大量にタップする」戦いにする
const ENEMY_HP_BASE_MULT: float = 3.0     # キャラ設定のmax_hpに掛ける基礎倍率
const ENEMY_HP_STAGE_MULT: float = 2.0    # ステージが1つ進むごとのHP倍率
const ENEMY_ATK_GROWTH_PER_STAGE: float = 0.05
const COIN_GROWTH_PER_STAGE: float = 0.5  # ステージごとのコイン報酬の増加率
# 敵レベル: ステージごとに固定(プレイヤーには追従しない)。
# プレイヤーがレベルを上げて追いつかないと勝てない設計にする
const ENEMY_BASE_LEVEL: int = 3           # 最初のステージの敵レベル
const ENEMY_LEVEL_PER_STAGE: int = 4      # ステージが進むごとの敵レベル加算
const ENEMY_HP_PER_LEVEL: float = 40.0    # 敵レベル1あたりのHP増加
const ENEMY_ATK_PER_LEVEL: float = 0.4    # 敵レベル1あたりの攻撃力増加
# 動画広告リワード: レベルアップ時に視聴すると、通常上昇分にこの倍率分が追加される
const AD_LEVEL_UP_BOOST_MULT: float = 1.0
const COIN_PER_TAP: int = 1
const COIN_PER_FORM: int = 10
const COIN_STAGE_CLEAR_BONUS: int = 30

var _state: State = State.DIALOGUE
var _last_stage_enemy: CharacterData = null

# ダメージ点滅用のスプライトごとのTween
var _flash_tweens: Dictionary = {}
# ダメージSE。assets/sounds/se/ に音声ファイルを置くと自動で読み込まれる
var _se_attack: AudioStream   # 与ダメージ時
var _se_damaged: AudioStream  # 被ダメージ時
const SE_DIR := "res://assets/sounds/se/"
# ステージ開始時点でクリア済みだったか(初回クリア時の勝利会話まで飛ばさないため)
var _stage_was_cleared: bool = false

# バナー高さは物理pxで保持し、画面サイズが変わるたび論理座標へ変換し直す
var _banner_height_px := 0

func _ready() -> void:
	# 画面下にバナー広告を常時表示し、端末の安全領域と合わせてUIを内側に収める
	AdManager.banner_height_changed.connect(_apply_banner_inset)
	get_viewport().size_changed.connect(_refresh_banner_layout)
	_apply_banner_inset(0)
	AdManager.show_banner()
	se_player.bus = GameState.SE_BUS_NAME
	_load_se()
	_load_characters()
	dialogue_layer.visible = false
	battle_layer.visible = false
	lose_layer.visible = false
	result_layer.visible = false

	tap_button.pressed.connect(_on_tap_enemy)
	lose_layer.retry_requested.connect(_on_retry)
	lose_layer.title_requested.connect(_on_title)
	lose_layer.revive_requested.connect(_on_revive)
	level_up_layer.boost_requested.connect(_on_level_up_boost)
	level_up_layer.closed.connect(_on_level_up_closed)
	result_layer.next_requested.connect(_on_next_enemy)
	result_layer.xp_bonus_requested.connect(_on_xp_bonus)

	option_wheel.setup(all_chars)
	option_wheel.player_char_selected.connect(_on_player_char_selected)
	option_wheel.opponent_selected.connect(_on_opponent_selected)
	option_wheel.bgm_selected.connect(_on_bgm_selected)
	option_wheel.gallery_requested.connect(_on_gallery_requested)
	option_wheel.title_requested.connect(_on_title_requested)
	option_wheel.coins_changed.connect(_update_coin_ui)

	start_stage()

func _load_characters() -> void:
	for cid in CHAR_IDS:
		var res := load("res://resources/characters/%s.tres" % cid) as CharacterData
		if res:
			all_chars.append(res)
	if all_chars.is_empty():
		push_error("No character data found")
		return
	player_data = all_chars[0]
	_restore_session()
	_rebuild_enemy_list()
	var enemy_idx := _find_enemy_index(GameState.session_enemy_id)
	if enemy_idx != -1:
		current_enemy_index = enemy_idx

# 前回セッションの操作キャラを復元(所持していることが条件)
func _restore_session() -> void:
	var pid := GameState.session_player_id
	if pid == "" or not GameState.owned_char_ids.has(pid):
		return
	for c in all_chars:
		if c.char_id == pid:
			player_data = c
			return

func _find_enemy_index(enemy_id: String) -> int:
	for i in enemy_list.size():
		if enemy_list[i].char_id == enemy_id:
			return i
	return -1

func _rebuild_enemy_list() -> void:
	enemy_list.clear()
	for c in all_chars:
		if c != player_data:
			enemy_list.append(c)

func start_stage() -> void:
	# 最後の敵を倒したら最初の敵に戻って周回する
	if current_enemy_index >= enemy_list.size():
		current_enemy_index = 0
	current_enemy = enemy_list[current_enemy_index]
	GameState.set_session(player_data.char_id, current_enemy.char_id)
	current_phase = 1
	max_phase = current_enemy.battle_forms.size()
	_stage_was_cleared = GameState.is_stage_cleared(player_data.char_id, current_enemy.char_id)
	option_wheel.current_player = player_data
	option_wheel.current_opponent = current_enemy
	if _last_stage_enemy != null and current_enemy != _last_stage_enemy \
			and not GameState.bgm_keep_on_opponent_change:
		GameState.selected_bgm_path = ""
	_last_stage_enemy = current_enemy
	apply_stage_visuals(current_enemy)
	start_first_talk()

func apply_stage_visuals(enemy: CharacterData) -> void:
	background.texture = enemy.stage_background
	if GameState.selected_bgm_path != "":
		switch_bgm(load(GameState.selected_bgm_path))
	else:
		switch_bgm(enemy.stage_bgm)

func switch_bgm(new_stream: AudioStream) -> void:
	_update_bgm_title(new_stream)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(bgm_player, "volume_db", -80.0, 0.3)
	tween.tween_callback(func():
		bgm_player.stream = new_stream
		bgm_player.volume_db = 0.0
		bgm_player.play()
	)

# 再生中の曲名を画面左下にマーキー(右から左へ流れる)表示する
var _bgm_marquee_tween: Tween
const BGM_MARQUEE_SPEED := 80.0  # スクロール速度(px/秒)

func _update_bgm_title(stream: AudioStream) -> void:
	if stream == null or stream.resource_path == "":
		bgm_title_label.text = ""
		if _bgm_marquee_tween != null and _bgm_marquee_tween.is_valid():
			_bgm_marquee_tween.kill()
		return
	bgm_title_label.text = "♪ %s" % stream.resource_path.get_file().get_basename()
	_restart_bgm_marquee.call_deferred()

func _restart_bgm_marquee() -> void:
	if _bgm_marquee_tween != null and _bgm_marquee_tween.is_valid():
		_bgm_marquee_tween.kill()
	bgm_title_label.reset_size()
	var box_w := bgm_title_box.size.x
	var text_w := bgm_title_label.size.x
	bgm_title_label.position.y = (bgm_title_box.size.y - bgm_title_label.size.y) / 2.0
	# 右端から画面外左まで流してループ
	_bgm_marquee_tween = create_tween().set_loops()
	_bgm_marquee_tween.tween_callback(func(): bgm_title_label.position.x = box_w)
	_bgm_marquee_tween.tween_property(bgm_title_label, "position:x", -text_w,
			(box_w + text_w) / BGM_MARQUEE_SPEED)

# 設定が有効で、かつステージ開始時点でクリア済みなら会話を飛ばす
func _skip_talk_enabled() -> bool:
	return GameState.skip_cleared_dialogue and _stage_was_cleared

func start_first_talk() -> void:
	if _skip_talk_enabled():
		start_battle_phase()
		return
	_state = State.DIALOGUE
	battle_active = false
	battle_layer.visible = false
	option_wheel.visible = false
	var csv := "res://assets/dialogues/%s/%s_vs_%s_talk1.csv" % [
		player_data.char_id, player_data.char_id, current_enemy.char_id
	]
	dialogue_layer.left_char_image.texture = player_data.tatie_sprite
	dialogue_layer.right_char_image.texture = current_enemy.tatie_sprite
	dialogue_layer.start_dialogue(csv, player_data, current_enemy, start_battle_phase)

func start_battle_phase() -> void:
	_state = State.BATTLE
	dialogue_layer.visible = false
	battle_layer.visible = true
	option_wheel.visible = true

	var form_index := current_phase - 1
	enemy_sprite.texture = current_enemy.battle_forms[form_index]
	player_sd_sprite.texture = player_data.sd_sprite
	# SDキャラは右向き(敵の方向)で統一する
	player_sd_sprite.flip_h = player_data.sd_faces_left

	_refresh_player_stats()
	_refresh_enemy_stats()

	enemy_hp = enemy_max_hp
	player_hp = player_max_hp

	enemy_hp_bar.max_value = enemy_max_hp
	enemy_hp_bar.value = enemy_hp
	player_hp_bar.max_value = player_max_hp
	player_hp_bar.value = player_hp
	_update_xp_ui()
	_update_battle_hud()

	attack_timer = 0.0
	battle_active = true
	_revive_used = false

# 操作キャラのレベルに応じた最大HP・タップ攻撃力を反映
func _refresh_player_stats() -> void:
	player_max_hp = player_data.max_hp + GameState.hp_bonus()
	tap_damage = TAP_DAMAGE + GameState.atk_bonus()

# 敵レベル(ステージ固定)とステージ倍率で敵のHP・攻撃力を決める
func _refresh_enemy_stats() -> void:
	var stage := float(current_enemy_index)
	enemy_level = ENEMY_BASE_LEVEL + current_enemy_index * ENEMY_LEVEL_PER_STAGE
	enemy_max_hp = current_enemy.max_hp * ENEMY_HP_BASE_MULT * pow(ENEMY_HP_STAGE_MULT, stage) \
			+ ENEMY_HP_PER_LEVEL * float(enemy_level - 1)
	enemy_damage = ENEMY_DAMAGE * (1.0 + ENEMY_ATK_GROWTH_PER_STAGE * stage) \
			+ ENEMY_ATK_PER_LEVEL * float(enemy_level - 1)

func _update_xp_ui() -> void:
	var lvl: int = GameState.player_level
	var xp: int = GameState.player_xp
	var to_next: int = GameState.xp_to_next(lvl)
	player_level_label.text = "Lv.%d  XP %d/%d" % [lvl, xp, to_next]
	player_xp_bar.max_value = to_next
	player_xp_bar.value = xp

# ステージ・フェーズ・名前・コインなど戦闘HUD全体を更新
func _update_battle_hud() -> void:
	stage_label.text = "Stage %d" % (current_enemy_index + 1)
	phase_label.text = "Phase %d/%d" % [current_phase, max_phase]
	enemy_hp_label.text = "%s Lv.%d" % [current_enemy.display_name, enemy_level]
	player_hp_label.text = player_data.display_name
	_update_coin_ui()
	_update_hp_labels()

func _update_coin_ui() -> void:
	coin_label.text = "コイン %d" % GameState.coins

func _update_hp_labels() -> void:
	enemy_hp_value_label.text = "%d / %d" % [roundi(enemy_hp), roundi(enemy_max_hp)]
	player_hp_value_label.text = "%d / %d" % [roundi(player_hp), roundi(player_max_hp)]

func _process(delta: float) -> void:
	if not battle_active:
		return
	attack_timer += delta
	if attack_timer >= ENEMY_ATTACK_INTERVAL:
		attack_timer = 0.0
		_execute_enemy_attack()

# attack.* = 与ダメージ時 / damage.* = 被ダメージ時 のSEを読み込む(無ければ鳴らさない)
func _load_se() -> void:
	_se_attack = _try_load_se("attack")
	_se_damaged = _try_load_se("damage")

func _try_load_se(base_name: String) -> AudioStream:
	for ext in ["ogg", "mp3", "wav"]:
		var path: String = SE_DIR + base_name + "." + ext
		if ResourceLoader.exists(path):
			return load(path)
	return null

func _play_se(stream: AudioStream) -> void:
	if stream == null:
		return
	se_player.stream = stream
	se_player.play()

# ダメージ時にスプライトを赤く点滅させる
func _flash_sprite(sprite: CanvasItem) -> void:
	var prev: Tween = _flash_tweens.get(sprite)
	if prev != null and prev.is_valid():
		prev.kill()
	sprite.modulate = Color.WHITE
	var tween := create_tween()
	for i in 2:
		tween.tween_property(sprite, "modulate", Color(1.0, 0.3, 0.3, 0.75), 0.07)
		tween.tween_property(sprite, "modulate", Color.WHITE, 0.07)
	_flash_tweens[sprite] = tween

func _on_tap_enemy() -> void:
	if not battle_active:
		return
	enemy_hp = maxf(enemy_hp - tap_damage, 0.0)
	enemy_hp_bar.value = enemy_hp
	_flash_sprite(enemy_sprite)
	_play_se(_se_attack)
	GameState.add_coins(COIN_PER_TAP)
	var levels_gained: int = GameState.add_xp(XP_PER_TAP)
	if levels_gained > 0:
		_on_level_up(levels_gained)
	_update_xp_ui()
	_update_coin_ui()
	_update_hp_labels()
	if enemy_hp <= 0.0:
		_on_enemy_form_defeated()

# レベルアップ: 最大HP・攻撃力を再計算し、増えた分のHPを回復。恩恵をポップアップで明示する
func _on_level_up(levels_gained: int) -> void:
	var old_max := player_max_hp
	_refresh_player_stats()
	player_hp = minf(player_hp + (player_max_hp - old_max), player_max_hp)
	player_hp_bar.max_value = player_max_hp
	player_hp_bar.value = player_hp
	_update_hp_labels()
	player_level_label.modulate = Color(1.0, 0.9, 0.2)
	var tween := create_tween()
	tween.tween_property(player_level_label, "modulate", Color.WHITE, 0.6)
	# 敵の攻撃を止めてポップアップを出す。閉じたら _on_level_up_closed で再開
	battle_active = false
	_pending_boost_hp = int(GameState.HP_PER_LEVEL * levels_gained * AD_LEVEL_UP_BOOST_MULT)
	_pending_boost_atk = int(GameState.ATK_PER_LEVEL * levels_gained * AD_LEVEL_UP_BOOST_MULT)
	level_up_layer.show_level_up(
		GameState.player_level,
		int(GameState.HP_PER_LEVEL) * levels_gained,
		int(GameState.ATK_PER_LEVEL) * levels_gained,
		_pending_boost_hp,
		_pending_boost_atk,
	)

# レベルアップポップアップで提示している追加ステータス量
var _pending_boost_hp := 0
var _pending_boost_atk := 0

# 動画広告視聴の報酬としてレベルアップの上昇量を積み増す(永続)
func _on_level_up_boost() -> void:
	GameState.add_stat_boost(float(_pending_boost_hp), float(_pending_boost_atk))
	var old_max := player_max_hp
	_refresh_player_stats()
	player_hp = minf(player_hp + (player_max_hp - old_max), player_max_hp)
	player_hp_bar.max_value = player_max_hp
	player_hp_bar.value = player_hp
	_update_hp_labels()

func _on_level_up_closed() -> void:
	if _state == State.BATTLE:
		attack_timer = 0.0
		battle_active = true

func _execute_enemy_attack() -> void:
	player_hp = maxf(player_hp - enemy_damage, 0.0)
	player_hp_bar.value = player_hp
	_flash_sprite(player_sd_sprite)
	_play_se(_se_damaged)
	_update_hp_labels()
	if player_hp <= 0.0:
		_on_player_death()

func _on_enemy_form_defeated() -> void:
	battle_active = false
	# フェーズ撃破報酬。ステージが進むほど敵HP増加率と同じ係数で増える
	var reward := int(COIN_PER_FORM * (1.0 + COIN_GROWTH_PER_STAGE * float(current_enemy_index)))
	if current_phase >= max_phase:
		reward += COIN_STAGE_CLEAR_BONUS
		GameState.mark_stage_cleared(player_data.char_id, current_enemy.char_id)
	GameState.add_coins(reward)
	GameState.save_progress()
	_update_coin_ui()
	if current_phase < max_phase:
		current_phase += 1
		_start_middle_talk()
	else:
		_start_win_talk()

func _start_middle_talk() -> void:
	# 形態ごとの会話: 1形態目撃破後はtalk2、2形態目撃破後はtalk3
	var csv := "res://assets/dialogues/%s/%s_vs_%s_talk%d.csv" % [
		player_data.char_id, player_data.char_id, current_enemy.char_id, current_phase
	]
	# ファイルが無い場合もdialogue側の汎用会話フォールバックで表示する
	if _skip_talk_enabled():
		start_battle_phase()
		return
	_state = State.DIALOGUE
	battle_layer.visible = false
	option_wheel.visible = false
	dialogue_layer.left_char_image.texture = player_data.tatie_sprite
	dialogue_layer.right_char_image.texture = current_enemy.tatie_sprite
	dialogue_layer.start_dialogue(csv, player_data, current_enemy, start_battle_phase)

func _start_win_talk() -> void:
	_state = State.DIALOGUE
	battle_layer.visible = false
	option_wheel.visible = false
	if _skip_talk_enabled():
		_show_result()
		return
	var csv := "res://assets/dialogues/%s/%s_vs_%s_win.csv" % [
		player_data.char_id, player_data.char_id, current_enemy.char_id
	]
	dialogue_layer.left_char_image.texture = player_data.tatie_sprite
	dialogue_layer.right_char_image.texture = current_enemy.tatie_sprite
	dialogue_layer.start_dialogue(csv, player_data, current_enemy, _show_result)

func _show_result() -> void:
	_state = State.RESULT
	# 敵撃破ごとにインタースティシャル広告を強制表示し、閉じられたらリザルトを出す
	AdManager.show_interstitial(func() -> void:
		# 倒した敵の最終形態(衣装破壊)を表示したままリザルトを出す
		result_layer.show_result(AD_XP_BONUS, current_enemy.battle_forms[max_phase - 1]))

# 動画広告視聴の報酬として経験値を付与する(勝利リザルト)
func _on_xp_bonus() -> void:
	var levels_gained: int = GameState.add_xp(AD_XP_BONUS)
	GameState.save_progress()
	_refresh_player_stats()
	_update_xp_ui()
	var msg := "XP +%d 獲得！" % AD_XP_BONUS
	if levels_gained > 0:
		msg += "  レベルアップ！ Lv.%d" % GameState.player_level
	result_layer.show_bonus_granted(msg)

func _on_next_enemy() -> void:
	# 一番下の敵を倒した後は最初の敵に戻る(周回)
	current_enemy_index = (current_enemy_index + 1) % enemy_list.size()
	start_stage()

func _on_player_death() -> void:
	battle_active = false
	_state = State.LOSE
	battle_layer.visible = false
	option_wheel.visible = false
	if _skip_talk_enabled():
		_show_lose()
		return
	var csv := "res://assets/dialogues/%s/%s_vs_%s_lose.csv" % [
		player_data.char_id, player_data.char_id, current_enemy.char_id
	]
	dialogue_layer.left_char_image.texture = player_data.tatie_sprite
	dialogue_layer.right_char_image.texture = current_enemy.tatie_sprite
	dialogue_layer.start_dialogue(csv, player_data, current_enemy, _show_lose)

func _show_lose() -> void:
	lose_layer.show_lose(player_data.defeated_sprite, not _revive_used)

# 動画広告視聴の報酬として復活する。敵HPはそのまま、自分のHPだけ回復して戦闘を再開
func _on_revive() -> void:
	_revive_used = true
	_state = State.BATTLE
	_refresh_player_stats()
	player_hp = maxf(1.0, player_max_hp * AD_REVIVE_HP_RATIO)
	player_hp_bar.max_value = player_max_hp
	player_hp_bar.value = player_hp
	_update_hp_labels()
	battle_layer.visible = true
	option_wheel.visible = true
	attack_timer = 0.0
	battle_active = true

func _on_retry() -> void:
	start_battle_phase()

func _on_title() -> void:
	get_tree().change_scene_to_file("res://scenes/title/title.tscn")

func _on_player_char_selected(c: CharacterData) -> void:
	if c == player_data:
		return
	player_data = c
	_rebuild_enemy_list()
	var idx := enemy_list.find(current_enemy)
	if idx != -1:
		current_enemy_index = idx
	else:
		current_enemy_index = mini(current_enemy_index, enemy_list.size() - 1)
	start_stage()

func _on_opponent_selected(c: CharacterData) -> void:
	if c == current_enemy:
		return
	var idx := enemy_list.find(c)
	if idx == -1:
		return
	current_enemy_index = idx
	start_stage()

func _on_bgm_selected(path: String) -> void:
	if path != "":
		switch_bgm(load(path))
	else:
		switch_bgm(current_enemy.stage_bgm)

# 図鑑をオーバーレイ表示する。閉じるとホイールが開いたままの状態に戻る
func _on_gallery_requested() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GalleryOverlayLayer"
	layer.layer = 10
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var gallery := GALLERY_SCENE.instantiate()
	gallery.overlay_mode = true
	gallery.closed.connect(layer.queue_free)
	layer.add_child(gallery)
	add_child(layer)
	# バナー表示後に生成されるオーバーレイも、現在の安全領域へ直ちに収める
	_apply_safe_root_insets(layer, _calculate_safe_insets(_banner_height_px))

func _on_title_requested() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/title/title.tscn")

func _exit_tree() -> void:
	AdManager.hide_banner()

# 各 CanvasLayer 直下の Control を SafeRoot でまとめ、端末のノッチ・ホーム
# インジケータと下部バナーを避ける。背景はGame直下なので全面表示を維持する。
func _apply_banner_inset(height_px: int) -> void:
	_banner_height_px = maxi(height_px, 0)
	var insets := _calculate_safe_insets(_banner_height_px)
	for child in get_children():
		if child is CanvasLayer and child.name != "BannerPlaceholderLayer":
			_apply_safe_root_insets(child, insets)
	_update_banner_placeholder(_logical_banner_height(_banner_height_px))
	# 立ち絵はアンカーではなくサイズ計算で配置するため、安全領域変更後に再配置する
	if is_instance_valid(dialogue_layer):
		dialogue_layer.call_deferred("refresh_character_layout")

func _refresh_banner_layout() -> void:
	# 擬似バナーは画面高に比例するので、その時点の値を取り直す
	_apply_banner_inset(AdManager.get_banner_height_px())

func _calculate_safe_insets(banner_height_px: int) -> Vector4:
	var window_size := Vector2(DisplayServer.window_get_size())
	var viewport_size := get_viewport().get_visible_rect().size
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		# ヘッドレス実行など物理ウィンドウ寸法を取得できない場合は論理寸法を使う
		window_size = viewport_size

	var scale_x := viewport_size.x / window_size.x
	var scale_y := viewport_size.y / window_size.y
	var safe_left := 0.0
	var safe_top := 0.0
	var safe_right := 0.0
	var safe_bottom := 0.0
	if OS.get_name() in ["iOS", "Android"]:
		var safe_area := DisplayServer.get_display_safe_area()
		safe_left = float(safe_area.position.x)
		safe_top = float(safe_area.position.y)
		safe_right = maxf(
			window_size.x - float(safe_area.position.x + safe_area.size.x), 0.0
		)
		safe_bottom = maxf(
			window_size.y - float(safe_area.position.y + safe_area.size.y), 0.0
		)

	return Vector4(
		maxf(safe_left * scale_x, 0.0),
		maxf(safe_top * scale_y, 0.0),
		maxf(safe_right * scale_x, 0.0),
		maxf((safe_bottom + float(banner_height_px)) * scale_y, 0.0),
	)

func _logical_banner_height(height_px: int) -> float:
	var window_h := float(DisplayServer.window_get_size().y)
	if height_px <= 0:
		return 0.0
	if window_h <= 0.0:
		window_h = get_viewport().get_visible_rect().size.y
	return float(height_px) * (get_viewport().get_visible_rect().size.y / window_h)

func _apply_safe_root_insets(layer: CanvasLayer, insets: Vector4) -> void:
	var safe_root := _safe_root_for(layer)
	safe_root.offset_left = insets.x
	safe_root.offset_top = insets.y
	safe_root.offset_right = -insets.z
	safe_root.offset_bottom = -insets.w

# 擬似モード(エディタ・PC)ではバナーが出ないので、同じ高さの帯を描いて位置を確認できるようにする
var _banner_placeholder: Control

func _update_banner_placeholder(inset: float) -> void:
	if not AdManager.is_fake_mode():
		return
	if _banner_placeholder == null:
		var layer := CanvasLayer.new()
		layer.name = "BannerPlaceholderLayer"
		layer.layer = 10
		add_child(layer)
		var rect := ColorRect.new()
		rect.color = Color(0.15, 0.15, 0.15, 1)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		layer.add_child(rect)
		var label := Label.new()
		label.text = "AD BANNER (擬似)"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.add_child(label)
		_banner_placeholder = rect
	_banner_placeholder.offset_top = -inset
	_banner_placeholder.visible = inset > 0.0

func _safe_root_for(layer: CanvasLayer) -> Control:
	var safe_root := layer.get_node_or_null("SafeRoot") as Control
	if safe_root == null:
		safe_root = Control.new()
		safe_root.name = "SafeRoot"
		safe_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		safe_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(safe_root)
		# 全画面で覆いたい(ignore_safe_area)オーバーレイが SafeRoot より手前に描かれるよう先頭に置く
		layer.move_child(safe_root, 0)
	# SafeRoot作成後に追加されたControlも取り込めるよう、毎回直下を確認する
	var controls: Array[Node] = []
	for c in layer.get_children():
		if c is Control and c != safe_root and not c.get_meta("ignore_safe_area", false):
			controls.append(c)
	for c in controls:
		c.reparent(safe_root, false)
	return safe_root
