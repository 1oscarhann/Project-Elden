extends Node

## Autoload. Serialise/deserialise GameState, and talk to the backend
## (SPEC §5, §7).
##
## Local disk is the source of truth at runtime. The cloud is a mirror, and it
## is NEVER on the boot path — a sleeping Render free-tier service takes tens
## of seconds to wake, and a game that hangs on that looks broken. Boot local,
## sync in the background (see docs/REVIEW.md).

signal local_save_completed(slot: int, ok: bool)
signal local_load_completed(slot: int, ok: bool)
signal cloud_sync_started()
signal cloud_sync_completed(ok: bool, message: String)
signal auth_completed(ok: bool, message: String)

const SAVE_DIR := "user://saves"

## Set to your deployed FastAPI origin, e.g. "https://elden-api.onrender.com".
## Empty disables all cloud calls, which is the correct state until step 7.
var api_base_url: String = ""

var _token: String = ""
var _http: HTTPRequest


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)


## True once login()/register() has stashed a bearer token.
func is_signed_in() -> bool:
	return _token != ""


## The on-disk path a given slot index reads from / writes to.
func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


## True if `slot` has a save file on disk (does not validate its contents).
func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## Header info for a save-select screen without deserialising the whole blob.
##
## Every number is coerced to int: JSON.parse_string() (via _read_slot) hands
## every number back as a float, so without this a save-select screen would
## render "Gold: 931.0" / "Lv 5.0". (Found by GUT's Float/Int comparison
## warning during the iteration-1 test pass — see PROGRESS.md.)
func slot_summary(slot: int) -> Dictionary:
	if not slot_exists(slot):
		return {}
	var blob: Dictionary = _read_slot(slot)
	if blob.is_empty():
		return {}
	var party_list: Array = blob.get("party", [])
	var lead: Dictionary = party_list[0] if not party_list.is_empty() else {}
	return {
		"slot": slot,
		"zone": String(blob.get("zone", "")),
		"gold": int(blob.get("gold", 0)),
		"level": int(lead.get("level", 1)),
	}


# --- Local (build order step 5) --------------------------------------------

## Writes the current GameState to `slot` as JSON. Refuses (and returns
## false without touching the file) if the serialised blob exceeds
## SaveFormat.MAX_BLOB_BYTES.
func save_local(slot: int) -> bool:
	var blob: Dictionary = GameState.to_dict()
	var text: String = JSON.stringify(blob)

	if text.to_utf8_buffer().size() > SaveFormat.MAX_BLOB_BYTES:
		push_error("SaveManager: blob exceeds %d bytes, refusing to write" % SaveFormat.MAX_BLOB_BYTES)
		local_save_completed.emit(slot, false)
		return false

	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot open slot %d for writing" % slot)
		local_save_completed.emit(slot, false)
		return false

	file.store_string(text)
	file.close()
	local_save_completed.emit(slot, true)
	return true


## Reads `slot` from disk and restores it into GameState via from_dict().
## Returns false (leaving GameState untouched) if the slot is empty or the
## blob fails validation.
func load_local(slot: int) -> bool:
	var blob: Dictionary = _read_slot(slot)
	if blob.is_empty():
		local_load_completed.emit(slot, false)
		return false
	var ok: bool = GameState.from_dict(blob)
	local_load_completed.emit(slot, ok)
	return ok


## Removes `slot`'s save file, if it exists. A no-op otherwise.
func delete_local(slot: int) -> void:
	if slot_exists(slot):
		DirAccess.remove_absolute(slot_path(slot))


func _read_slot(slot: int) -> Dictionary:
	if not slot_exists(slot):
		return {}
	var file := FileAccess.open(slot_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


# --- Cloud (build order step 7) --------------------------------------------

## Creates an account on the backend and, on success, stashes its bearer
## token so subsequent sync_up()/sync_down() calls are authenticated.
func register(username: String, password: String) -> void:
	await _auth_call("/register", username, password)


## Signs into an existing account and stashes its bearer token on success.
func login(username: String, password: String) -> void:
	await _auth_call("/login", username, password)


func _auth_call(path: String, username: String, password: String) -> void:
	var response: Dictionary = await _post(path, {"username": username, "password": password}, false)
	if not response.get("ok", false):
		auth_completed.emit(false, str(response.get("error", "request failed")))
		return
	_token = str(response.get("body", {}).get("token", ""))
	auth_completed.emit(_token != "", "signed in" if _token != "" else "no token returned")


## Push the current GameState to the cloud. Safe to call and ignore.
func sync_up(slot: int) -> void:
	if api_base_url == "" or not is_signed_in():
		return
	cloud_sync_started.emit()
	var blob: Dictionary = GameState.to_dict()
	if JSON.stringify(blob).to_utf8_buffer().size() > SaveFormat.MAX_BLOB_BYTES:
		cloud_sync_completed.emit(false, "save too large")
		return
	var response: Dictionary = await _post("/save", {"slot_index": slot, "data": blob}, true)
	cloud_sync_completed.emit(
		response.get("ok", false), str(response.get("error", "saved to cloud"))
	)


## Pulls `slot` from the backend and restores it into GameState. A no-op
## returning false if no api_base_url is configured or nobody is signed in
## — never blocks the game on a cloud round trip that might not happen.
func sync_down(slot: int) -> bool:
	if api_base_url == "" or not is_signed_in():
		return false
	cloud_sync_started.emit()
	var response: Dictionary = await _http_get("/load?slot_index=%d" % slot)
	if not response.get("ok", false):
		cloud_sync_completed.emit(false, str(response.get("error", "load failed")))
		return false
	var ok: bool = GameState.from_dict(response.get("body", {}).get("data", {}))
	cloud_sync_completed.emit(ok, "loaded from cloud" if ok else "blob rejected")
	return ok


func _headers(authed: bool) -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if authed and _token != "":
		headers.append("Authorization: Bearer %s" % _token)
	return headers


func _post(path: String, payload: Dictionary, authed: bool) -> Dictionary:
	return await _request(path, HTTPClient.METHOD_POST, JSON.stringify(payload), authed)


func _http_get(path: String) -> Dictionary:
	return await _request(path, HTTPClient.METHOD_GET, "", true)


func _request(path: String, method: int, body: String, authed: bool) -> Dictionary:
	if api_base_url == "":
		return {"ok": false, "error": "no api_base_url configured"}

	var err: int = _http.request(api_base_url + path, _headers(authed), method, body)
	if err != OK:
		return {"ok": false, "error": "request failed to start (%d)" % err}

	var result: Array = await _http.request_completed
	var response_code: int = result[1]
	var parsed: Variant = JSON.parse_string(result[3].get_string_from_utf8())

	if response_code < 200 or response_code >= 300:
		var message: String = "HTTP %d" % response_code
		if parsed is Dictionary and parsed.has("detail"):
			message = str(parsed["detail"])
		return {"ok": false, "error": message}

	return {"ok": true, "body": parsed if parsed is Dictionary else {}}
