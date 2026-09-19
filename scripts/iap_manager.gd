extends Node
# アプリ内課金の窓口(autoload: IAPManager)。OpenIAP の godot-iap プラグインを使う。
# 今は「広告削除」(買い切り)のみ。購入状態は Apple/Google 側が正なので、起動時に
# ストアへ問い合わせて反映し、ローカルにはキャッシュとして保存する。
#   IAPManager.ads_removed            … 広告削除を購入済みか
#   IAPManager.purchase_remove_ads()  … 購入フローを開始
#   IAPManager.restore_purchases()    … 購入の復元
# エディタ・PCではストアが無いので、purchase_* は失敗を返す(擬似購入はしない)。

signal ads_removed_changed(removed: bool)
# 購入・復元が失敗/キャンセルされたときの表示用メッセージ
signal purchase_failed(message: String)
# 商品情報(価格)を取得できたとき
signal product_info_updated

# App Store Connect / Google Play Console で作る商品ID(非消耗型)。変える場合はここだけ
const PRODUCT_REMOVE_ADS := "com.yomu.tohotap.remove_ads"

var ads_removed: bool = false
# ストアから取れた表示価格(例 "¥490")。未取得なら空
var remove_ads_price: String = ""
var _iap: Node
var _store_ready := false
var _busy := false

func _ready() -> void:
	ads_removed = GameState.ads_removed
	_iap = get_node_or_null("/root/GodotIapPlugin")
	if _iap == null:
		return
	_iap.purchase_updated.connect(_on_purchase_updated)
	_iap.purchase_error.connect(_on_purchase_error)
	_connect_store()

func is_store_available() -> bool:
	return _store_ready

func _connect_store() -> void:
	if not OS.get_name() in ["iOS", "Android"]:
		return
	_store_ready = await _iap.init_connection()
	if not _store_ready:
		push_warning("IAPManager: ストアに接続できませんでした")
		return
	await _fetch_price()
	await _sync_entitlements()

func _fetch_price() -> void:
	var request = _iap.ProductRequest.new()
	request.skus = [PRODUCT_REMOVE_ADS]
	request.type = _iap.ProductQueryType.IN_APP
	var products: Array = await _iap.fetch_products(request)
	for p in products:
		if p.id == PRODUCT_REMOVE_ADS:
			remove_ads_price = p.display_price
	product_info_updated.emit()

# ストアの購入履歴を見て広告削除の有無を反映する(再インストール・機種変更でも自動で戻る)
func _sync_entitlements() -> void:
	var purchases: Array = await _iap.get_available_purchases()
	var owned := false
	for p in purchases:
		if p.product_id == PRODUCT_REMOVE_ADS and p.purchase_state == _iap.Types.PurchaseState.PURCHASED:
			owned = true
	if owned:
		_set_ads_removed(true)

func purchase_remove_ads() -> void:
	if ads_removed or _busy:
		return
	if not _store_ready:
		purchase_failed.emit("ストアに接続できません")
		return
	_busy = true
	var props = _iap.RequestPurchaseProps.new()
	props.request = _iap.RequestPurchasePropsByPlatforms.new()
	props.request.apple = _iap.RequestPurchaseIosProps.new()
	props.request.apple.sku = PRODUCT_REMOVE_ADS
	props.request.google = _iap.RequestPurchaseAndroidProps.new()
	props.request.google.skus = [PRODUCT_REMOVE_ADS]
	props.type = _iap.ProductQueryType.IN_APP
	_iap.request_purchase(props)

func restore_purchases() -> void:
	if _busy:
		return
	if not _store_ready:
		purchase_failed.emit("ストアに接続できません")
		return
	_busy = true
	await _iap.restore_purchases()
	await _sync_entitlements()
	_busy = false
	if not ads_removed:
		purchase_failed.emit("復元できる購入はありませんでした")

func _on_purchase_updated(purchase: Dictionary) -> void:
	_busy = false
	if purchase.get("productId", "") != PRODUCT_REMOVE_ADS:
		return
	var state := str(purchase.get("purchaseState", "")).to_lower()
	if state != "purchased":
		return
	# 非消耗型: トランザクションを完了させてから反映する
	await _iap.finish_transaction_dict(purchase, false)
	_set_ads_removed(true)

func _on_purchase_error(error: Dictionary) -> void:
	_busy = false
	var code := str(error.get("code", ""))
	if code == "user-cancelled":
		return
	purchase_failed.emit(str(error.get("message", "購入に失敗しました")))

func _set_ads_removed(removed: bool) -> void:
	if ads_removed == removed:
		return
	ads_removed = removed
	GameState.ads_removed = removed
	GameState.save_progress()
	ads_removed_changed.emit(removed)
