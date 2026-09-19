extends Control

@onready var tap_hint: Label = $TapHint
@onready var agreement_layer: Control = $AgreementLayer
@onready var agreement_body: Label = $AgreementLayer/Panel/BodyLabel
@onready var terms_button: Button = $AgreementLayer/Panel/TermsButton
@onready var privacy_button: Button = $AgreementLayer/Panel/PrivacyButton
@onready var age_check: Button = $AgreementLayer/Panel/AgeCheck
@onready var agree_check: Button = $AgreementLayer/Panel/AgreeCheck
@onready var start_button: Button = $AgreementLayer/Panel/StartButton

var _started := false

func _ready() -> void:
	var blink := create_tween().set_loops()
	blink.tween_property(tap_hint, "modulate:a", 0.5, 0.7)
	blink.tween_property(tap_hint, "modulate:a", 1.0, 0.7)
	_setup_agreement()

# 初回起動時(または規約の改定後)だけ、年齢確認と規約・プライバシーポリシーへの同意を求める。
# 両方にチェックするまで「はじめる」は押せず、タイトルのタップも受け付けない
func _setup_agreement() -> void:
	if GameState.has_accepted_terms():
		return
	agreement_body.text = ("本アプリは%d歳以上の方を対象としています。\n\n" +
		"ご利用の前に、利用規約とプライバシーポリシーをお読みください。" +
		"本アプリは広告の配信のため、Google AdMob を通じて端末の情報を利用します。") % GameState.MIN_AGE
	terms_button.pressed.connect(OS.shell_open.bind(GameState.TERMS_URL))
	privacy_button.pressed.connect(OS.shell_open.bind(GameState.PRIVACY_URL))
	age_check.toggled.connect(func(_on: bool) -> void: _refresh_agreement())
	agree_check.toggled.connect(func(_on: bool) -> void: _refresh_agreement())
	start_button.pressed.connect(_on_agreement_start)
	_refresh_agreement()
	agreement_layer.show()

func _refresh_agreement() -> void:
	age_check.text = "%s  私は%d歳以上です" % ["■" if age_check.button_pressed else "□", GameState.MIN_AGE]
	agree_check.text = "%s  利用規約とプライバシーポリシーに同意します" % ["■" if agree_check.button_pressed else "□"]
	start_button.disabled = not (age_check.button_pressed and agree_check.button_pressed)

func _on_agreement_start() -> void:
	agreement_layer.hide()
	GameState.accept_terms()

# 画面のどこをタップ(クリック)してもスタートする
func _gui_input(event: InputEvent) -> void:
	if agreement_layer.visible:
		return
	if event is InputEventMouseButton and event.pressed:
		_start_game()
	elif event is InputEventScreenTouch and event.pressed:
		_start_game()

func _start_game() -> void:
	if _started:
		return
	_started = true
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")
