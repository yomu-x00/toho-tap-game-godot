extends CanvasLayer

class DialogueLine:
	var speaker: String
	var text: String
	var expression: String

	func _init(s: String, t: String, e: String) -> void:
		speaker = s
		text = t
		expression = e

@onready var left_char_image: TextureRect = $LeftCharImage
@onready var right_char_image: TextureRect = $RightCharImage
@onready var name_label: Label = $DialogueBox/NamePlate/NameLabel
@onready var body_label: Label = $DialogueBox/BodyLabel
@onready var advance_hint: Label = $DialogueBox/AdvanceHint
@onready var advance_button: Button = $AdvanceButton

var _lines: Array[DialogueLine] = []
var _current_index: int = 0
var _left_char: CharacterData
var _right_char: CharacterData
var _on_finished: Callable

# 立ち絵レイアウト。キャンバス幅がキャラごとに違っても表示高さを一律にし、
# tatie_eye_ratio で目線を共通ラインに揃える
const TATIE_HEIGHT_RATIO := 0.605   # 表示高さ(画面高比)。旧アンカー 0.18〜0.785 と同じ
const TATIE_EYE_LINE_RATIO := 0.38  # 目線ライン(画面高比)
const TATIE_LEFT_CENTER_X := 0.25   # 左キャラの中心(画面幅比)
const TATIE_RIGHT_CENTER_X := 0.75  # 右キャラの中心(画面幅比)

func _ready() -> void:
	advance_button.pressed.connect(_on_advance_pressed)
	var blink := create_tween().set_loops()
	blink.tween_property(advance_hint, "modulate:a", 0.2, 0.6)
	blink.tween_property(advance_hint, "modulate:a", 1.0, 0.6)

# 会話開始直後・行送り直後はこの秒数だけタップを無視する(戦闘の連打が会話に流れ込むのを防ぐ)
const ADVANCE_LOCK_SECONDS := 0.3
var _advance_unlock_msec: int = 0

func start_dialogue(csv_path: String, left_char: CharacterData, right_char: CharacterData, on_finished: Callable) -> void:
	_left_char = left_char
	_right_char = right_char
	_on_finished = on_finished
	_lines = _parse_csv(csv_path)
	# 会話が未収録(ファイル無し・プレースホルダーのみ)でも汎用会話でイベントを成立させる
	if _lines.is_empty():
		_lines = _generic_lines(csv_path)
	_current_index = 0
	_set_tatie(left_char_image, _left_char)
	_set_tatie(right_char_image, _right_char)
	visible = true
	if _lines.is_empty():
		_finish()
		return
	_lock_advance()
	_update_ui()

func _lock_advance() -> void:
	_advance_unlock_msec = Time.get_ticks_msec() + int(ADVANCE_LOCK_SECONDS * 1000.0)

# 未執筆ファイルに入っている仮テキスト。会話行として表示しない
const PLACEHOLDER_TEXT := "会話が用意されていない"

func _parse_csv(path: String) -> Array[DialogueLine]:
	var result: Array[DialogueLine] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var res_path := "res://" + path.lstrip("/")
		file = FileAccess.open(res_path, FileAccess.READ)
	if file == null:
		push_warning("dialogue: cannot open " + path)
		return result
	var first := true
	while not file.eof_reached():
		var cols := file.get_csv_line()
		if first:
			first = false
			continue
		if cols.size() < 2:
			continue
		var speaker := cols[0].strip_edges()
		var text := cols[1].strip_edges()
		if speaker.is_empty() or text.is_empty():
			continue
		if speaker.begins_with("#"):
			continue
		if text.begins_with(PLACEHOLDER_TEXT):
			continue
		var expression := cols[2].strip_edges() if cols.size() > 2 else ""
		result.append(DialogueLine.new(speaker, text, expression))
	return result

# 汎用会話。種別(talk1/talk2/talk3/win/lose)はファイル名末尾から推定する
func _generic_lines(csv_path: String) -> Array[DialogueLine]:
	var kind := csv_path.get_file().get_basename().get_slice("_", 3)
	var left_name := _left_char.display_name
	var right_name := _right_char.display_name
	var lines: Array[DialogueLine] = []
	match kind:
		"talk1":
			lines.append(DialogueLine.new(_right_char.char_id, "あら、%sじゃない。私に何か用かしら？" % left_name, ""))
			lines.append(DialogueLine.new(_left_char.char_id, "%s、あなたに勝負を申し込むわ！" % right_name, "shinken"))
			lines.append(DialogueLine.new(_right_char.char_id, "面白いじゃない。かかってきなさい！", "shinken"))
		"talk2":
			lines.append(DialogueLine.new(_right_char.char_id, "やるわね…。でも、まだまだこれからよ！", "shinken"))
			lines.append(DialogueLine.new(_left_char.char_id, "その程度じゃ、私は止められないわよ！", ""))
		"talk3":
			lines.append(DialogueLine.new(_right_char.char_id, "ここからが本気よ…！覚悟しなさい！", "shinken"))
			lines.append(DialogueLine.new(_left_char.char_id, "望むところよ。決着をつけましょう！", "shinken"))
		"win":
			lines.append(DialogueLine.new(_left_char.char_id, "私の勝ちね。いい勝負だったわ、%s。" % right_name, "warai"))
			lines.append(DialogueLine.new(_right_char.char_id, "参ったわ…。今日のところは私の負けね。", "ressei"))
		"lose":
			lines.append(DialogueLine.new(_right_char.char_id, "ふふ、私の勝ちね。出直してきなさい、%s。" % left_name, "warai"))
			lines.append(DialogueLine.new(_left_char.char_id, "うう…次は絶対に負けないんだから…！", "ressei"))
	return lines

func _on_advance_pressed() -> void:
	if Time.get_ticks_msec() < _advance_unlock_msec:
		return
	_lock_advance()
	_current_index += 1
	if _current_index >= _lines.size():
		_finish()
	else:
		_update_ui()

func _finish() -> void:
	visible = false
	_on_finished.call()

func _update_ui() -> void:
	if _current_index >= _lines.size():
		return
	var dl := _lines[_current_index]
	name_label.text = _resolve_display_name(dl.speaker)
	body_label.text = dl.text
	_update_focus(dl.speaker)
	# 話者側の立ち絵を表情差分に切り替える
	if dl.speaker == _left_char.char_id or dl.speaker == _left_char.display_name:
		_set_tatie(left_char_image, _left_char, dl.expression)
	else:
		_set_tatie(right_char_image, _right_char, dl.expression)

# 立ち絵をセットし、表示高さを一律にしたうえで目線ラインに縦位置を合わせる
func _set_tatie(rect: TextureRect, chara: CharacterData, expression: String = "") -> void:
	var tex := chara.get_tatie(expression)
	rect.texture = tex
	if tex == null:
		return
	_layout_tatie(rect, chara)

# バナーや端末の安全領域が変わったとき、現在の立ち絵を安全領域基準で再配置する
func refresh_character_layout() -> void:
	if _left_char != null and left_char_image.texture != null:
		_layout_tatie(left_char_image, _left_char)
	if _right_char != null and right_char_image.texture != null:
		_layout_tatie(right_char_image, _right_char)

func _layout_tatie(rect: TextureRect, chara: CharacterData) -> void:
	var layout_size := rect.get_viewport_rect().size
	var parent_control := rect.get_parent() as Control
	if parent_control != null and parent_control.size.x > 0.0 and parent_control.size.y > 0.0:
		layout_size = parent_control.size
	var tex := rect.texture
	var h := layout_size.y * TATIE_HEIGHT_RATIO
	var w := h * float(tex.get_width()) / float(tex.get_height())
	var center_x := layout_size.x * (TATIE_LEFT_CENTER_X if rect == left_char_image else TATIE_RIGHT_CENTER_X)
	rect.size = Vector2(w, h)
	rect.position = Vector2(
		center_x - w * 0.5,
		layout_size.y * TATIE_EYE_LINE_RATIO - chara.tatie_eye_ratio * h,
	)

func _resolve_display_name(speaker: String) -> String:
	if speaker == _left_char.char_id or speaker == _left_char.display_name:
		return _left_char.display_name
	if speaker == _right_char.char_id or speaker == _right_char.display_name:
		return _right_char.display_name
	return speaker

func _update_focus(speaker: String) -> void:
	var left_active := (speaker == _left_char.char_id or speaker == _left_char.display_name)
	left_char_image.modulate = Color.WHITE if left_active else Color(0.5, 0.5, 0.5, 1.0)
	right_char_image.modulate = Color.WHITE if not left_active else Color(0.5, 0.5, 0.5, 1.0)
	# 話者を前面、相手を背面に(立ち絵は中央で少し重なるレイアウト)
	left_char_image.z_index = 2 if left_active else 1
	right_char_image.z_index = 1 if left_active else 2
