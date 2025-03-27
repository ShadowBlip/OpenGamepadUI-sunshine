extends Control

const Sunshine := preload("res://plugins/sunshine/core/sunshine.gd")

var notification_manager := load("res://core/global/notification_manager.tres") as NotificationManager
var settings_manager := load("res://core/global/settings_manager.tres") as SettingsManager
var card_settings_button_scene := load("res://core/ui/components/card_button_setting.tscn") as PackedScene
var sunshine: Sunshine
var _is_running := false
var _service_changing := false
var _paired_clients: Dictionary[String, String] = {}
var _paired_client_buttons: Dictionary[String, CardButtonSetting] = {}

@onready var status := $%Status as StatusPanel
@onready var enable_toggle := $%EnableToggle as Toggle
@onready var sync_toggle := $%SyncLibraryToggle as Toggle
@onready var user_text_input := $%UserTextInput as ComponentTextInput
@onready var pass_text_input := $%PassTextInput as ComponentTextInput
@onready var update_creds_button := $%UpdateCredentialsButton as CardButtonSetting
@onready var no_clients_label := %NoClientsLabel as Label
@onready var name_text_input := $%NameTextInput as ComponentTextInput
@onready var pin_text_input := $%PinTextInput as ComponentTextInput
@onready var pair_button := $%PairButton as CardButtonSetting

func _ready() -> void:
	user_text_input.text = sunshine.username
	pass_text_input.text = sunshine.password
	await _update_status()
	enable_toggle.toggled.connect(_on_enable_toggled)
	await _update_paired_clients()
	pair_button.button_up.connect(_on_pair_pressed)
	update_creds_button.button_up.connect(_on_update_creds)
	visibility_changed.connect(_on_visibility_changed)


func use_sunshine(node: Sunshine) -> void:
	sunshine = node


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		return
	_update_status()
	_update_paired_clients()


func _update_status() -> void:
	_is_running = await sunshine.is_running()
	if _is_running:
		status.status = status.STATUS.ACTIVE
		enable_toggle.button_pressed = true
	else:
		status.status = status.STATUS.CLOSED
		enable_toggle.button_pressed = false


func _update_paired_clients() -> void:
	_paired_clients.clear()
	if not _is_running:
		return
	var clients := await sunshine.get_clients()
	if "named_certs" in clients and clients["named_certs"] is Array:
		for client in clients["named_certs"]:
			if not "uuid" in client:
				continue
			if not "name" in client:
				continue
			_paired_clients[client["uuid"]] = client["name"]
	_update_paired_client_buttons()


func _update_paired_client_buttons() -> void:
	# Remove buttons that no longer have a paired client
	for uuid in _paired_client_buttons:
		if uuid in _paired_clients:
			continue
		var button := _paired_client_buttons[uuid]
		var next := button.find_valid_focus_neighbor(SIDE_BOTTOM)
		if next:
			next.grab_focus.call_deferred()
		button.queue_free()
		_paired_client_buttons.erase(uuid)

	# Create buttons that need to be created
	for uuid in _paired_clients:
		if uuid in _paired_client_buttons:
			continue
		var button := card_settings_button_scene.instantiate() as CardButtonSetting
		button.text = _paired_clients[uuid]
		button.button_text = "Unpair"
		_paired_client_buttons[uuid] = button
		no_clients_label.add_sibling(button)
		
		var on_unpair_pressed := func():
			if await sunshine.unpair(uuid) != OK:
				notification_manager.show(Notification.new("Failed to unpair device: " + _paired_clients[uuid]))
			notification_manager.show(Notification.new("Unpaired device: " + _paired_clients[uuid]))
			_update_paired_clients.call_deferred()
		button.button_up.connect(on_unpair_pressed)

	# Hide the label if there are clients
	no_clients_label.visible = _paired_clients.is_empty()


func _on_enable_toggled(enabled: bool) -> void:
	if _service_changing:
		return
	_service_changing = true
	if enabled:
		await sunshine.start()
	else:
		await sunshine.stop()
	await _update_status()
	_service_changing = false


func _on_pair_pressed() -> void:
	var device_name := name_text_input.text
	var pin := pin_text_input.text
	if not pin.is_valid_int():
		notification_manager.show(Notification.new("Invalid pin"))
		return

	if await sunshine.send_pin(device_name, pin.to_int()) != OK:
		notification_manager.show(Notification.new("Failed to pair with device"))
		return

	notification_manager.show(Notification.new("Successfully paired: " + device_name))
	name_text_input.text = ""
	pin_text_input.text = ""
	await get_tree().create_timer(0.5).timeout
	_update_paired_clients.call_deferred()


func _on_update_creds() -> void:
	var user := user_text_input.text
	var passwd := pass_text_input.text
	if await sunshine.reset_credentials(user, passwd) != OK:
		notification_manager.show(Notification.new("Failed to update Sunshine credentials"))
		return
	settings_manager.set_value("plugin.sunshine", "username", user)
	settings_manager.set_value("plugin.sunshine", "password", passwd)
	notification_manager.show(Notification.new("Successfully updated Sunshine credentials"))
