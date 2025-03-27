extends Plugin

const Sunshine := preload("res://plugins/sunshine/core/sunshine.gd")
const SunshineSettings := preload("res://plugins/sunshine/core/sunshine_settings.gd")

var settings_manager := load("res://core/global/settings_manager.tres") as SettingsManager

@onready var sunshine: Sunshine = Sunshine.new()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	logger = Log.get_logger("Sunshine", Log.LEVEL.DEBUG)
	logger.info("Sunshine plugin loaded")

	var username := settings_manager.get_value("plugin.sunshine", "username", "") as String
	var password := settings_manager.get_value("plugin.sunshine", "password", "") as String
	sunshine.username = username
	sunshine.password = password

	add_child(sunshine)

	var clients := await sunshine.get_clients()
	logger.info("Clients:", clients)


func get_settings_menu() -> Control:
	var settings_scene := load("res://plugins/sunshine/core/sunshine_settings.tscn") as PackedScene
	var settings := settings_scene.instantiate() as SunshineSettings
	settings.use_sunshine(sunshine)
	
	return settings
