extends Node
# 動画リワード広告の汎用マネージャ(autoload: AdManager)
# 用途(ガチャ/Lv upなど)は placement 文字列で区別するだけで、呼び出し側は
#   AdManager.show_rewarded("gacha", func(success: bool) -> void: ...)
# と書けばよい。ロード・視聴後の再ロード・失敗時のリトライは内部で行う。
# 強制表示のインタースティシャル広告は
#   AdManager.show_interstitial(func() -> void: ...)
# で、閉じられた(または表示できなかった)ときにコールバックが呼ばれる。
# 画面下のバナーは show_banner()/hide_banner() で出し入れし、高さは
# banner_height_changed(高さ[物理px]) で通知する(UIをバナー分だけ避けるために使う)。
# 起動時広告(App Open)は初回ロード完了時と、バックグラウンド復帰時に自動で表示する。
# 広告削除(課金)を購入済みなら、バナー・インタースティシャル・起動時広告は出さない。
# 動画リワードは報酬目当てに自分で見るものなので購入後も残す。
# エディタやPC実行では AdMob プラグインが存在しないため、擬似視聴モードで
# 即座に成功を返す(ゲームロジック側の開発・検証用)。

# 報酬が確定した(=最後まで視聴した)ときに placement 付きで通知
signal rewarded(placement: String)
# 広告の準備状態が変わったときに通知(ボタンの活性化などに使う)
signal availability_changed(available: bool)
# バナーの表示高さ(物理px)が変わったときに通知。非表示・失敗時は 0
signal banner_height_changed(height_px: int)

# 本番の広告ユニットID。リリースビルドでのみ使う。
# placementごとにユニットIDを分けたくなったら値を Dictionary にして拡張する。
const AD_UNIT_IDS := {
	"Android": "",  # Android版リリース時に設定する
	"iOS": "ca-app-pub-7401497687267095/6072375289",
}
const INTERSTITIAL_UNIT_IDS := {
	"Android": "",  # Android版リリース時に設定する
	"iOS": "ca-app-pub-7401497687267095/3172989013",
}
const BANNER_UNIT_IDS := {
	"Android": "",  # Android版リリース時に設定する
	"iOS": "ca-app-pub-7401497687267095/6505371547",
}
# アプリ起動時広告(App Open)。起動時とバックグラウンド復帰時に表示する
const APP_OPEN_UNIT_IDS := {
	"Android": "",
	"iOS": "ca-app-pub-7401497687267095/3239457689",
}
# Google公式のテスト用ユニットID。デバッグビルド、または本番IDが未設定のときに使う。
# 本番ユニットは作成直後 No fill になりやすいので、開発中はこちらで動作確認する。
const TEST_AD_UNIT_IDS := {
	"Android": "ca-app-pub-3940256099942544/5224354917",
	"iOS": "ca-app-pub-3940256099942544/1712485313",
}
const TEST_INTERSTITIAL_UNIT_IDS := {
	"Android": "ca-app-pub-3940256099942544/1033173712",
	"iOS": "ca-app-pub-3940256099942544/4411468910",
}
const TEST_BANNER_UNIT_IDS := {
	"Android": "ca-app-pub-3940256099942544/6300978111",
	"iOS": "ca-app-pub-3940256099942544/2934735716",
}
const TEST_APP_OPEN_UNIT_IDS := {
	"Android": "ca-app-pub-3940256099942544/9257395921",
	"iOS": "ca-app-pub-3940256099942544/5575463023",
}
# バックグラウンドから復帰したとき、前回の起動時広告からこの秒数以上経っていれば再表示する
const APP_OPEN_MIN_INTERVAL_SECONDS := 60.0
# ロード済みの起動時広告の有効期限(AdMobの仕様で4時間)
const APP_OPEN_AD_EXPIRE_SECONDS := 4.0 * 60.0 * 60.0
const MAX_LOAD_RETRY := 5
# 擬似視聴モードで成功を返すまでの秒数
const FAKE_WATCH_SECONDS := 0.5
# 擬似モードで想定するバナー高さ(画面高に対する比率)。実機のアダプティブバナー相当
const FAKE_BANNER_HEIGHT_RATIO := 0.07

var _rewarded_ad: RewardedAd
var _is_loading := false
var _retry_count := 0
var _interstitial_ad: InterstitialAd
var _is_loading_interstitial := false
var _interstitial_retry_count := 0
var _banner: AdView
var _banner_visible := false
var _app_open_ad: AppOpenAd
var _is_loading_app_open := false
var _app_open_loaded_at := 0.0
var _app_open_last_shown_at := -1.0e9
var _app_open_showing := false
# ネイティブプラグインが使える環境か(Android/iOSの実機ビルドのみtrue)
var _plugin_available := false
# プラグインが無い環境で擬似視聴を許可するか(エディタ・PCのみ)
var _fake_mode := false
# MobileAds.initialize を呼んだか(同意フローの各経路から二重に呼ばないため)
var _ads_initialized := false

func _ready() -> void:
	_plugin_available = Engine.has_singleton("PoingGodotAdMob")
	if _plugin_available:
		# 初回はタイトルの年齢確認・規約同意が済んでから、ATT などの同意画面と広告を始める
		if GameState.has_accepted_terms():
			_gather_consent()
		else:
			GameState.terms_accepted.connect(_gather_consent, CONNECT_ONE_SHOT)
	else:
		# 実機以外は擬似モード。モバイル実機でプラグインが無い場合は
		# 導入ミスに気付けるよう擬似モードにはしない(常に利用不可)
		_fake_mode = OS.has_feature("editor") or OS.get_name() in ["Windows", "macOS", "Linux"]

# 広告SDKの初期化前に、UMP で同意を集める。AdMob 管理画面の「プライバシーとメッセージ」で
# 設定したメッセージ(EU向けGDPR同意・iOSのIDFA説明)が必要な人にだけ表示され、
# IDFA説明のあとに iOS の ATT(トラッキング許可)ダイアログが出る。
# 同意の取得に失敗しても広告は出したいので、どの経路でも最後は _initialize_ads() に進む。
func _gather_consent() -> void:
	if not Engine.has_singleton("PoingGodotAdMobConsentInformation"):
		_initialize_ads()
		return
	UserMessagingPlatform.consent_information.update(
		ConsentRequestParameters.new(), _on_consent_info_updated, _on_consent_error)

func _on_consent_info_updated() -> void:
	var consent := UserMessagingPlatform.consent_information
	var required := consent.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED
	if not required or not consent.get_is_consent_form_available():
		_initialize_ads()
		return
	UserMessagingPlatform.load_consent_form(_on_consent_form_loaded, _on_consent_error)

func _on_consent_form_loaded(form: ConsentForm) -> void:
	form.show(_on_consent_form_dismissed)

func _on_consent_form_dismissed(error: FormError) -> void:
	if error:
		push_warning("AdManager: 同意フォームのエラー " + str(error.message))
	_initialize_ads()

func _on_consent_error(error: FormError) -> void:
	push_warning("AdManager: 同意情報の取得失敗 " + str(error.message))
	_initialize_ads()

func _initialize_ads() -> void:
	if _ads_initialized:
		return
	_ads_initialized = true
	# v5 では初期化完了を待ってから広告をロードする必要がある
	var init_listener := OnInitializationCompleteListener.new()
	init_listener.on_initialization_complete = func(_status: InitializationStatus) -> void:
		_load_ad()
		if not GameState.ads_removed:
			_load_interstitial()
			_load_app_open()
	MobileAds.initialize(init_listener)

# 広告削除を購入した直後に呼ぶ(IAPManager から)。表示中のバナーも消す
func on_ads_removed() -> void:
	if _banner != null:
		_banner.destroy()
		_banner = null
	if _interstitial_ad != null:
		_interstitial_ad.destroy()
		_interstitial_ad = null
	if _app_open_ad != null:
		_app_open_ad.destroy()
		_app_open_ad = null
	banner_height_changed.emit(0)

# エディタ・PCの擬似モードか(バナーのプレースホルダー表示などに使う)
func is_fake_mode() -> bool:
	return _fake_mode

# 現在レイアウトで確保すべきバナー高さ(物理px)。画面サイズ変更時の再計算にも使う。
func get_banner_height_px() -> int:
	if not _banner_visible or GameState.ads_removed:
		return 0
	if _fake_mode:
		var height := DisplayServer.window_get_size().y
		if height <= 0:
			height = int(get_viewport().get_visible_rect().size.y)
		return int(height * FAKE_BANNER_HEIGHT_RATIO)
	if _banner != null:
		return maxi(_banner.get_height_in_pixels(), 0)
	return 0

# 広告を表示できる状態か。リワードボタンの表示/活性の判定に使う
func is_ready() -> bool:
	return _fake_mode or _rewarded_ad != null

# 動画リワードを表示する。視聴完了で on_result.call(true)、
# 途中で閉じた・表示に失敗した場合は on_result.call(false) が呼ばれる。
func show_rewarded(placement: String, on_result: Callable = Callable()) -> void:
	if _fake_mode:
		await get_tree().create_timer(FAKE_WATCH_SECONDS).timeout
		print("AdManager: 擬似リワード視聴完了 placement=", placement)
		_finish(placement, true, on_result)
		return
	if _rewarded_ad == null:
		_finish(placement, false, on_result)
		_load_ad()
		return

	var ad := _rewarded_ad
	_rewarded_ad = null
	availability_changed.emit(false)
	var outcome := {"earned": false}

	var reward_listener := OnUserEarnedRewardListener.new()
	reward_listener.on_user_earned_reward = func(_item: RewardedItem) -> void:
		outcome.earned = true

	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content = func() -> void:
		ad.destroy()
		_finish(placement, outcome.earned, on_result)
		_load_ad()
	ad.full_screen_content_callback.on_ad_failed_to_show_full_screen_content = func(error: AdError) -> void:
		push_warning("AdManager: 表示失敗 " + str(error.message))
		ad.destroy()
		_finish(placement, false, on_result)
		_load_ad()

	ad.show(reward_listener)

func _finish(placement: String, success: bool, on_result: Callable) -> void:
	if success:
		rewarded.emit(placement)
	if on_result.is_valid():
		on_result.call(success)

# 使うユニットIDを決める。デバッグビルドや本番IDが空のときはテストIDにフォールバック
func _resolve_unit_id(production: Dictionary, test: Dictionary) -> String:
	var os_name := OS.get_name()
	var prod_id: String = production.get(os_name, "")
	if OS.is_debug_build() or prod_id.is_empty():
		return test.get(os_name, "")
	return prod_id

func _load_ad() -> void:
	if _is_loading or _rewarded_ad != null:
		return
	var unit_id := _resolve_unit_id(AD_UNIT_IDS, TEST_AD_UNIT_IDS)
	if unit_id.is_empty():
		return
	_is_loading = true

	var callback := RewardedAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: RewardedAd) -> void:
		_is_loading = false
		_retry_count = 0
		_rewarded_ad = ad
		availability_changed.emit(true)
	callback.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		_is_loading = false
		push_warning("AdManager: ロード失敗 " + str(error.message))
		_retry_load()

	RewardedAdLoader.new().load(unit_id, AdRequest.new(), callback)

# ロード失敗時は指数バックオフ(2,4,8...秒)で再試行する
func _retry_load() -> void:
	if _retry_count >= MAX_LOAD_RETRY:
		return
	_retry_count += 1
	await get_tree().create_timer(pow(2.0, _retry_count)).timeout
	_load_ad()

# インタースティシャル広告を表示する。閉じられた・表示できなかった、どちらの場合も
# on_closed が呼ばれるので、呼び出し側はゲーム進行をそこに続ければよい。
func show_interstitial(on_closed: Callable = Callable()) -> void:
	if GameState.ads_removed:
		_call_if_valid(on_closed)
		return
	if _fake_mode:
		await get_tree().create_timer(FAKE_WATCH_SECONDS).timeout
		print("AdManager: 擬似インタースティシャル表示完了")
		_call_if_valid(on_closed)
		return
	if _interstitial_ad == null:
		_call_if_valid(on_closed)
		_load_interstitial()
		return

	var ad := _interstitial_ad
	_interstitial_ad = null
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content = func() -> void:
		ad.destroy()
		_call_if_valid(on_closed)
		_load_interstitial()
	ad.full_screen_content_callback.on_ad_failed_to_show_full_screen_content = func(error: AdError) -> void:
		push_warning("AdManager: インタースティシャル表示失敗 " + str(error.message))
		ad.destroy()
		_call_if_valid(on_closed)
		_load_interstitial()
	ad.show()

func _call_if_valid(callback: Callable) -> void:
	if callback.is_valid():
		callback.call()

func _load_interstitial() -> void:
	if _is_loading_interstitial or _interstitial_ad != null:
		return
	var unit_id := _resolve_unit_id(INTERSTITIAL_UNIT_IDS, TEST_INTERSTITIAL_UNIT_IDS)
	if unit_id.is_empty():
		return
	_is_loading_interstitial = true

	var callback := InterstitialAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: InterstitialAd) -> void:
		_is_loading_interstitial = false
		_interstitial_retry_count = 0
		_interstitial_ad = ad
	callback.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		_is_loading_interstitial = false
		push_warning("AdManager: インタースティシャルロード失敗 " + str(error.message))
		if _interstitial_retry_count >= MAX_LOAD_RETRY:
			return
		_interstitial_retry_count += 1
		await get_tree().create_timer(pow(2.0, _interstitial_retry_count)).timeout
		_load_interstitial()

	InterstitialAdLoader.new().load(unit_id, AdRequest.new(), callback)

# 画面下にアダプティブバナーを表示する。ロード完了後に banner_height_changed を発火する
func show_banner() -> void:
	_banner_visible = true
	if GameState.ads_removed:
		banner_height_changed.emit(0)
		return
	if _fake_mode:
		# エディタ・PCでもレイアウト確認できるよう、バナー相当の高さだけ通知する
		banner_height_changed.emit(get_banner_height_px())
		return
	if not _plugin_available:
		banner_height_changed.emit(0)
		return
	if _banner != null:
		_banner.show()
		banner_height_changed.emit(get_banner_height_px())
		return
	var unit_id := _resolve_unit_id(BANNER_UNIT_IDS, TEST_BANNER_UNIT_IDS)
	if unit_id.is_empty():
		return
	var size := AdSize.get_current_orientation_anchored_adaptive_banner_ad_size(AdSize.FULL_WIDTH)
	var view := AdView.new(unit_id, size, AdPosition.BOTTOM)
	var listener := AdListener.new()
	listener.on_ad_loaded = func() -> void:
		if not _banner_visible:
			view.hide()
			return
		banner_height_changed.emit(view.get_height_in_pixels())
	listener.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		push_warning("AdManager: バナーロード失敗 " + str(error.message))
		banner_height_changed.emit(0)
	view.ad_listener = listener
	_banner = view
	view.load_ad(AdRequest.new())

func hide_banner() -> void:
	_banner_visible = false
	if _banner != null:
		_banner.hide()
	banner_height_changed.emit(0)

# --- 起動時広告(App Open) ---

# バックグラウンドから戻ったら起動時広告を出す(iOS/Android ともにこの通知が来る)
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_try_show_app_open()

func _load_app_open() -> void:
	if _is_loading_app_open or _app_open_ad != null:
		return
	var unit_id := _resolve_unit_id(APP_OPEN_UNIT_IDS, TEST_APP_OPEN_UNIT_IDS)
	if unit_id.is_empty():
		return
	_is_loading_app_open = true

	var callback := AppOpenAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: AppOpenAd) -> void:
		_is_loading_app_open = false
		_app_open_ad = ad
		_app_open_loaded_at = Time.get_unix_time_from_system()
		# 初回ロードは起動直後なので、そのまま起動時広告として表示する
		_try_show_app_open()
	callback.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		_is_loading_app_open = false
		push_warning("AdManager: 起動時広告ロード失敗 " + str(error.message))

	AppOpenAdLoader.new().load(unit_id, AdRequest.new(), callback)

func _try_show_app_open() -> void:
	if _fake_mode or not _plugin_available or _app_open_showing or GameState.ads_removed:
		return
	var now := Time.get_unix_time_from_system()
	if now - _app_open_last_shown_at < APP_OPEN_MIN_INTERVAL_SECONDS:
		return
	if _app_open_ad == null:
		_load_app_open()
		return
	if now - _app_open_loaded_at > APP_OPEN_AD_EXPIRE_SECONDS:
		_app_open_ad.destroy()
		_app_open_ad = null
		_load_app_open()
		return

	var ad := _app_open_ad
	_app_open_ad = null
	_app_open_showing = true
	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content = func() -> void:
		_app_open_showing = false
		_app_open_last_shown_at = Time.get_unix_time_from_system()
		ad.destroy()
		_load_app_open()
	ad.full_screen_content_callback.on_ad_failed_to_show_full_screen_content = func(error: AdError) -> void:
		_app_open_showing = false
		push_warning("AdManager: 起動時広告表示失敗 " + str(error.message))
		ad.destroy()
		_load_app_open()
	ad.show()
