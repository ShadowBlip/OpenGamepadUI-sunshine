extends Node

## Godot interface for sunshine
##
## Reference:
## - https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2api.html

var username: String:
	set(v):
		username = v
		if http_client:
			_update_credentials()
var password: String:
	set(v):
		password = v
		if http_client:
			_update_credentials()
var base_url: String = "https://localhost:47990":
	set(v):
		base_url = v
		if http_client:
			http_client.base_url = v
var logger := Log.get_logger("Sunshine")

@onready var http_client := HTTPAPIClient.new()

func _ready() -> void:
	http_client.base_url = base_url
	if http_client.get("verify_tls") != null:
		http_client.verify_tls = false
	_update_credentials()
	add_child(http_client)


func _update_credentials() -> void:
	if username.is_empty() and password.is_empty():
		return
	var credentials := Marshalls.utf8_to_base64(":".join([username, password]))
	http_client.headers = PackedStringArray(["Authorization: Basic " + credentials])


## Start the sunshine service
func start() -> Error:
	var cmd := Command.create("systemctl", ["--user", "start", "sunshine"])
	if cmd.execute() != OK:
		logger.error("Failed to start sunshine service")
		return -1
	if await cmd.finished as int != OK:
		logger.error("Failed to start sunshine service. Command exited with code", cmd.code, cmd.stdout, cmd.stderr)
		return -1
	return OK


## Stop the sunshine service
func stop() -> Error:
	var cmd := Command.create("systemctl", ["--user", "stop", "sunshine"])
	if cmd.execute() != OK:
		logger.error("Failed to stop sunshine service")
		return -1
	if await cmd.finished as int != OK:
		logger.error("Failed to stop sunshine service. Command exited with code", cmd.code, cmd.stdout, cmd.stderr)
		return -1
	return OK


## Restart the sunshine service
func restart() -> Error:
	var cmd := Command.create("systemctl", ["--user", "restart", "sunshine"])
	if cmd.execute() != OK:
		logger.error("Failed to restart sunshine service")
		return -1
	if await cmd.finished as int != OK:
		logger.error("Failed to restart sunshine service. Command exited with code", cmd.code, cmd.stdout, cmd.stderr)
		return -1
	return OK


## Returns true if the sunshine service is running
func is_running() -> bool:
	var cmd := Command.create("systemctl", ["--user", "status", "sunshine"])
	if cmd.execute() != OK:
		return false
	if await cmd.finished as int != OK:
		return false
	return true


## Resets the username and password for Sunshine and restarts the service.
func reset_credentials(user: String, passwd: String) -> Error:
	var cmd := Command.create("sunshine", ["--creds", user, passwd])
	if cmd.execute() != OK:
		logger.error("Failed to reset sunshine credentials")
		return -1
	if await cmd.finished as int != OK:
		logger.error("Failed to reset sunshine credentials. Command exited with code", cmd.code, cmd.stdout, cmd.stderr)
		return -1
	await self.restart()
	return OK


## Get all configured apps.
## {
##  "env": {
##    "PATH": "$(PATH):$(HOME)/.local/bin"
##  },
##  "apps": [
##    {
##      "name": "Desktop",
##      "image-path": "desktop.png"
##    },
##    {
##      "name": "Low Res Desktop",
##      "image-path": "desktop.png",
##      "prep-cmd": [
##        {
##          "do": "xrandr --output HDMI-1 --mode 1920x1080",
##          "undo": "xrandr --output HDMI-1 --mode 1920x1200"
##        }
##      ]
##    },
##    {
##      "name": "Steam Big Picture",
##      "detached": [
##        "setsid steam steam://open/bigpicture"
##      ],
##      "image-path": "steam.png"
##    }
##  ]
## }
func get_apps() -> Dictionary:
	var path := "/api/apps"
	var caching := Cache.FLAGS.NONE
	var headers := []
	var method := HTTPClient.METHOD_GET

	var response := await http_client.request(path, caching, headers, method) as HTTPAPIClient.Response
	if response.code < 200 or response.code >= 300:
		logger.warn("Received non-200 response: " + str(response.code))
		return {}
	var data = response.get_json()
	if not data is Dictionary:
		return {}
	if "apps" in data and data["apps"] is Array:
		var parsed_apps: Array[App] = []
		for app in (data["apps"] as Array):
			if not app is Dictionary:
				continue
			var parsed_app := App.from_dict(app)
			parsed_apps.push_back(parsed_app)
		data["apps"] = parsed_apps

	return data


## Save an application.
func add_app(app: App) -> Error:
	if app.index != -1:
		logger.error("Cannot add new app with index that is not `-1`")
		return -1
	var path := "/api/apps"
	var caching := Cache.FLAGS.NONE
	var headers := []
	var method := HTTPClient.METHOD_POST
	var data := JSON.stringify(app.to_dict())

	var response := await http_client.request(path, caching, headers, method, data) as HTTPAPIClient.Response
	if response.code < 200 or response.code >= 300:
		return response.code

	return OK


## Update an existing application
func update_app(app: App) -> Error:
	if app.index == -1:
		logger.error("Cannot update app with invalid index")
		return -1
	var path := "/api/apps"
	var caching := Cache.FLAGS.NONE
	var headers := []
	var method := HTTPClient.METHOD_POST
	var data := JSON.stringify(app.to_dict())

	var response := await http_client.request(path, caching, headers, method, data) as HTTPAPIClient.Response
	if response.code < 200 or response.code >= 300:
		return response.code

	return OK


## Delete an application.
func delete_app(index: int) -> Error:
	var path := "/api/apps/" + str(index)
	var caching := Cache.FLAGS.NONE
	var headers := []
	var method := HTTPClient.METHOD_DELETE

	var response := await http_client.request(path, caching, headers, method) as HTTPAPIClient.Response
	if response.code < 200 or response.code >= 300:
		return response.code

	return OK


## Get the logs from the log file.
func get_logs() -> String:
	var path := "/api/logs"
	var caching := Cache.FLAGS.NONE
	var headers := []
	var method := HTTPClient.METHOD_GET
	
	var response := await http_client.request(path, caching, headers, method) as HTTPAPIClient.Response
	if response.code < 200 or response.code >= 300:
		logger.warn("Received non-200 response: " + str(response.code))
		return ""

	return response.body.get_string_from_utf8()


## Get the list of paired clients.
## {
##    "status": "true",
##    "named_certs": [
##        {
##            "name": "Device 1",
##            "uuid": "abc-1234"
##        },
##        {
##            "name": "Device 2",
##            "uuid": "def-5678"
##        }
##    ]
## }
func get_clients() -> Dictionary:
	var path := "/api/clients/list"
	var caching := Cache.FLAGS.NONE
	var headers := []
	var method := HTTPClient.METHOD_GET
	
	var response := await http_client.request(path, caching, headers, method) as HTTPAPIClient.Response
	logger.debug("Got response code:", response.code)
	if response.code < 200 or response.code >= 300:
		logger.warn("Received non-200 response: " + str(response.code))
		return {}
	var data = response.get_json()
	if not data is Dictionary:
		return {}
	return data


## Send a pin code to the host. The pin is generated from the Moonlight client
## during the pairing process. 
func send_pin(device_name: String, code: int) -> Error:
	var path := "/api/pin"
	var caching := Cache.FLAGS.NONE
	var headers := []
	var method := HTTPClient.METHOD_POST
	var data := JSON.stringify({"pin": str(code), "name": device_name})

	var response := await http_client.request(path, caching, headers, method, data) as HTTPAPIClient.Response
	if response.code < 200 or response.code >= 300:
		logger.warn("Received non-200 response: " + str(response.code))
		return response.code

	return OK


## Unpair all clients.
func unpair_all(uuid: String) -> Error:
	var path := "/api/clients/unpair-all"
	var caching := Cache.FLAGS.NONE
	var headers := []
	var method := HTTPClient.METHOD_POST

	var response := await http_client.request(path, caching, headers, method) as HTTPAPIClient.Response
	if response.code < 200 or response.code >= 300:
		logger.warn("Received non-200 response: " + str(response.code))
		return response.code

	return OK


## Unpair a client.
func unpair(uuid: String) -> Error:
	var path := "/api/clients/unpair"
	var caching := Cache.FLAGS.NONE
	var headers := []
	var method := HTTPClient.METHOD_POST
	var data := JSON.stringify({"uuid": uuid})

	var response := await http_client.request(path, caching, headers, method, data) as HTTPAPIClient.Response
	if response.code < 200 or response.code >= 300:
		logger.warn("Received non-200 response: " + str(response.code))
		return response.code

	return OK


## Close the currently running application. 
func close_app() -> Error:
	var path := "/api/apps/close"
	var caching := Cache.FLAGS.NONE
	var headers := []
	var method := HTTPClient.METHOD_POST

	var response := await http_client.request(path, caching, headers, method) as HTTPAPIClient.Response
	if response.code < 200 or response.code >= 300:
		logger.warn("Received non-200 response: " + str(response.code))
		return response.code

	return OK


## App represents a Sunshine App
class App:
	## Application name
	var name: String
	## The file where the output of the command is stored, if it is not specified,
	## the output is ignored
	var output: String
	## The main application to start. If blank, no application will be started.
	## Note: If the path to the command executable contains spaces, you must
	## enclose it in quotes.
	var cmd: String
	## Index number
	var index: int
	## Enable/Disable the execution of Global Prep Commands for this application.
	var exclude_global_prep_cmd: bool
	## Elevated command
	var elevated: bool
	## Wait all
	var wait_all: bool
	## Number of seconds to wait for all app processes to gracefully exit when
	## requested to quit. If unset, the default is to wait up to 5 seconds.
	## If set to zero or a negative value, the app will be immediately terminated.
	var exit_timeout: int
	## A list of commands to be run before/after this application. If any of the
	## prep-commands fail, starting the application is aborted.
	var prep_cmd: Array[PrepCommand]
	## A list of commands to be run in the background.
	var detached: Array[String]
	## Full path to the application image. Must be a png file.
	var image_path: String

	func _init(idx: int = -1) -> void:
		self.index = -1

	static func from_dict(data: Dictionary) -> App:
		var app := App.new()
		if "name" in data and data["name"] is String:
			app.name = data["name"]
		if "output" in data and data["output"] is String:
			app.output = data["output"]
		if "index" in data and data["index"] is int:
			app.index = data["index"]
		if "exclude_global_prep_cmd" in data and data["exclude_global_prep_cmd"] is bool:
			app.exclude_global_prep_cmd = data["exclude_global_prep_cmd"]
		if "elevated" in data and data["elevated"] is bool:
			app.elevated = data["elevated"]
		if "wait_all" in data and data["wait_all"] is bool:
			app.wait_all = data["wait_all"]
		if "exit_timeout" in data and data["exit_timeout"] is int:
			app.exit_timeout = data["exit_timeout"]
		if "prep_cmd" in data and data["prep_cmd"] is Array:
			var prep_cmd: Array[PrepCommand] = []
			for cmd in (data["prep_cmd"] as Array):
				if not cmd is Dictionary:
					continue
				prep_cmd.push_back(PrepCommand.from_dict(cmd))
			app.prep_cmd = prep_cmd
		if "detached" in data and data["detached"] is Array:
			var detached: Array[String] = []
			for item in data["detached"]:
				if not item is String:
					continue
				detached.push_back(item)
			app.detached = detached
		if "image_path" in data and data["image_path"] is String:
			app.image_path = data["image_path"]
		
		return app
	
	static func from_library_item(item: LibraryItem) -> App:
		var app := App.new()
		app.name = item.name
		app.cmd = "opengamepadui ogui://run/" + item.name
		
		return app

	func to_dict() -> Dictionary:
		var data := {}
		data["name"] = self.name
		data["output"] = self.output
		data["cmd"] = self.cmd
		data["index"] = self.index
		data["exclude_global_prep_cmd"] = self.exclude_global_prep_cmd
		data["elevated"] = self.elevated
		var prep_cmd := []
		for cmd in self.prep_cmd:
			prep_cmd.push_back(cmd.to_dict())
		data["prep_cmd"] = prep_cmd
		data["detached"] = self.detached
		data["image_path"] = self.image_path
		
		return data


## Command to be run before/after this application. If any prep-commands fail, 
## starting the application is aborted.
class PrepCommand:
	## Command to prepare
	var do: String
	## Command to undo preparation
	var undo: String
	## Elevated command
	var elevated: bool

	static func from_dict(data: Dictionary) -> PrepCommand:
		var cmd := PrepCommand.new()
		if "do" in data and data["do"] is String:
			cmd.do = data["do"]
		if "undo" in data and data["undo"] is String:
			cmd.undo = data["undo"]
		if "elevated" in data and data["elevated"] is bool:
			cmd.elevated = data["elevated"]
		
		return cmd

	func to_dict() -> Dictionary:
		var data := {}
		if not self.do.is_empty():
			data["do"] = self.do
		if not self.undo.is_empty():
			data["undo"] = self.undo
		data["elevated"] = self.elevated
		
		return data
