extends CanvasLayer

@onready var enemy_defeated_image: TextureRect = $EnemyDefeatedImage
@onready var next_button: Button = $NextButton
@onready var xp_bonus_button: Button = $XpBonusButton
@onready var bonus_label: Label = $BonusLabel
@onready var result_label: Label = $ResultLabel

signal next_requested
# 動画広告を最後まで視聴し、XPボーナスの付与が確定したときに通知
signal xp_bonus_requested

const AD_PLACEMENT := "xp_bonus"
# 「勝利！」表示直後はこの秒数だけボタンを無効にする(会話の連打が流れ込んで「次へ」を押すのを防ぐ)
const INPUT_LOCK_SECONDS := 0.3
var _input_locked := false
var _bonus_amount := 0
var _bonus_claimed := false
var _ad_in_progress := false

func _ready() -> void:
	next_button.pressed.connect(_on_next_button_pressed)
	xp_bonus_button.pressed.connect(_on_xp_bonus_button_pressed)
	AdManager.availability_changed.connect(func(_available: bool) -> void: _refresh_bonus_button())

# enemy_texture には倒した敵の最終形態の画像を渡す。bonus_xp<=0 のときはボーナスボタンを出さない
func show_result(bonus_xp: int = 0, enemy_texture: Texture2D = null) -> void:
	enemy_defeated_image.texture = enemy_texture
	result_label.text = "勝利！"
	_bonus_amount = bonus_xp
	_bonus_claimed = false
	_ad_in_progress = false
	bonus_label.text = ""
	xp_bonus_button.visible = bonus_xp > 0
	next_button.visible = true
	visible = true
	_input_locked = true
	next_button.disabled = true
	_refresh_bonus_button()
	await get_tree().create_timer(INPUT_LOCK_SECONDS).timeout
	_input_locked = false
	next_button.disabled = false
	_refresh_bonus_button()

# ボーナスとは無関係のお知らせ(ドロップ等)を表示する。XPボーナスボタンには影響しない
func show_notice(message: String) -> void:
	bonus_label.text = message

# ボーナス付与後に呼び、獲得結果を表示する
func show_bonus_granted(message: String) -> void:
	_bonus_claimed = true
	bonus_label.text = message
	_refresh_bonus_button()

func _refresh_bonus_button() -> void:
	if _bonus_claimed:
		xp_bonus_button.disabled = true
		xp_bonus_button.text = "XPボーナス獲得済み"
		return
	var ready := AdManager.is_ready() and not _ad_in_progress
	xp_bonus_button.disabled = not ready or _input_locked
	if _ad_in_progress:
		xp_bonus_button.text = "動画を再生中..."
	elif ready:
		xp_bonus_button.text = "▶ 動画を見て XP +%d" % _bonus_amount
	else:
		xp_bonus_button.text = "動画を準備中..."

func _on_xp_bonus_button_pressed() -> void:
	if _ad_in_progress or _bonus_claimed:
		return
	_ad_in_progress = true
	_refresh_bonus_button()
	AdManager.show_rewarded(AD_PLACEMENT, func(success: bool) -> void:
		_ad_in_progress = false
		if success:
			xp_bonus_requested.emit()
		else:
			_refresh_bonus_button())

func _on_next_button_pressed() -> void:
	visible = false
	next_requested.emit()
