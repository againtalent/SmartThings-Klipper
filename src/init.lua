-- require st provided libraries
local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"

-- other libraries
local cosock = require "cosock"
local http = cosock.asyncify "socket.http"
local https = cosock.asyncify "ssl.https"
local ltn12 = require "ltn12"
local json = require "dkjson"

-- require custom handlers from driver package
local discovery = require "discovery"

-- capabilities
local cap_status = capabilities["againtalent19519.klipperstatus"]
local cap_temperature = capabilities["temperatureMeasurement"]
local cap_printerfan = capabilities["againtalent19519.printerfan"]
local cap_filename = capabilities["againtalent19519.filename"]
local cap_percentcomplete = capabilities["againtalent19519.percentcomplete"]
local cap_printtime = capabilities["againtalent19519.printtime"]
local cap_message = capabilities["againtalent19519.message"]

-- global variables
local refresh_timer                 -- timer object to refresh data and check online status
local printer_online = false        -- inernal printer online status: true=online, false=offline
local slicer_estimated_time = nil   -- estimated print time from gcode metadata: [int]=seconds, nil=no time (not tried), false=no time (tried)


-----------------------------------------------------------------
-- helper functions
-----------------------------------------------------------------

-- checks if a nested table key exists
-- params: table, "key", ["key", "key",...]
-- returns: boolean 
function isset(o, ...)

	local args = {...}
	local found = true

	for k, v in pairs(args) do
		if(found and o[v] ~= nil) then
			o = o[v]
		else
			found = false
		end
	end
	
	return found

end


function trim(s)

	return string.match(s, "^%s*(.-)%s*$")

end


-- format seconds to "1d 2h 3m" / "4s"
function to_string_time(s)

	seconds = math.floor(s % 60)
	minutes = math.floor((s % (60 * 60)) / 60)
	hours   = math.floor((s % (60 * 60 * 24)) / (60 * 60))
	days    = math.floor(s / (60 * 60 * 24))

	if(days > 0)        then return string.format("%dd %dh %dm", days, hours, minutes)
	elseif(hours > 0)   then return string.format("%dh %dm", hours, minutes)
	elseif(minutes > 0) then return string.format("%dm", minutes)
	else                     return string.format("%ds", seconds)
	end

end


-- escape non-word characters for adding to a url
function urlencode(s)

	return string.gsub(s, "%W", function(c) return string.format("%%%X", string.byte(c)) end)

end


-- make the filename look nice
function fixFilename(filename)

	-- strip out directories
	filename = string.match(filename, "([^%/]+)$")

	-- replace underscores with spaces
	filename = string.gsub(filename, "_", " ")

	return filename

end


-----------------------------------------------------------------
-- main functions
-----------------------------------------------------------------

-- log to the console if the verbose log setting is switced on
function console_log(device, message, log_level)

	if(device.preferences.verboseLog == true) then

		if(log_level == nil) then log_level = 'debug' end
		log.log({}, log_level, message)

	end
	
end


-- attempt to connect to the server and download data
-- params: ['GET', 'POST'], '/path/', (device)
-- returns: http code (200 on success) - nil on timeout
--          http status (eg. 'HTTP/1.1 200 OK')
--          response body (string)
function download_data(request_method, path, device)

	local request_url = device.preferences.ipProtocol .. "://" .. trim(device.preferences.ipAddress) .. ":" .. device.preferences.ipPort .. path
	local body = {}
	local request_headers = {}

	if(#device.preferences.apiKey > 0) then
		console_log(device, "Using API key")
		request_headers["x-api-key"] = trim(device.preferences.apiKey)
	end

	console_log(device, 'REQUESTING DATA FROM MOONRAKER: ' .. request_url)


	if(device.preferences.ipProtocol == 'http') then

		http.TIMEOUT = device.preferences.httpTimeout

		success, code, return_headers, status = http.request{
			url = request_url,
			method = request_method,
			headers = request_headers,
			sink = ltn12.sink.table(body)
		}

	else

		https.TIMEOUT = device.preferences.httpTimeout

		success, code, return_headers, status = https.request{
			url = request_url,
			method = request_method,
			headers = request_headers,
			verify = "none",
			protocol = "any",
			options =  {"all"},
			sink = ltn12.sink.table(body)
		}

	end

	if(success == nil) then
		console_log(device, "SERVER TIMEOUT")
		return nil
	end

	console_log(device, "SUCCESS")
	return code, table.concat(body)

end


-- main refresh cycle, triggered by timer
-- connects to moonraker and handles the response
function refresh_data(driver, device, command)

	if(device.preferences.ipAddress == "192.168.1.x") then
		console_log(device, 'IP NOT CONFIGURED')
		return false
	end

	console_log(device, 'STARTING REFRESH CYCLE')

	return_code, return_data = download_data('GET', '/printer/objects/query?extruder&heater_bed&fan&print_stats&idle_timeout&virtual_sdcard&display_status', device)

	if(return_code == nil) then

		console_log(device, ' - No response')
		update_status('offline', false, driver, device)

	elseif(return_code == 200) then
	
		console_log(device, ' - Data Received')
		
		local printer_data, pos, err = json.decode(return_data)
		
		if(err) then

			console_log(device, ' - Decode error')
			update_status('Data Decode Error', false, driver, device)

		else

			console_log(device, ' - Data Decoded')
			update_printer_stats(printer_data, device)
			update_status(nil, true, driver, device)

		end
	
	elseif(return_code == 401) then

		console_log(device, ' - 401 error')
		update_status('unauthorised', false, driver, device)

	else

		console_log(device, ' - Other server error ('..return_code..')')
		update_status('Error ' .. return_code, false, driver, device)

	end
	
	console_log(device, 'END OF REFRESH CYCLE')

end


-- update each field in the detail view
function update_printer_stats(printer_data, device)

	if isset(printer_data, "result", "status", "heater_bed", "temperature") then
		bed_temp = tonumber(printer_data["result"]["status"]["heater_bed"]["temperature"])
		device:emit_component_event(device.profile.components.bed, cap_temperature.temperature({value=bed_temp, unit="C"}))
	else console_log(device, 'MISSING Bed Temperature')
	end

	if isset(printer_data, "result", "status", "extruder", "temperature") then
		extruder_temp = tonumber(printer_data["result"]["status"]["extruder"]["temperature"])
		device:emit_component_event(device.profile.components.extruder, cap_temperature.temperature({value=extruder_temp, unit="C"}))
	else console_log(device, 'MISSING Extruder Temperature')
	end

	if isset(printer_data, "result", "status", "fan", "speed") then
		fan_speed = tonumber(printer_data["result"]["status"]["fan"]["speed"]) * 100
		device:emit_component_event(device.profile.components.extruder, cap_printerfan.speed({value=fan_speed, unit="%"}))
	else console_log(device, 'MISSING Fan Speed')
	end

	if isset(printer_data, "result", "status", "print_stats", "state") then
		printer_status = printer_data["result"]["status"]["print_stats"]["state"]
		device:emit_event(cap_status.printer(printer_status))
	else console_log(device, 'MISSING Printer State')
	end

	if isset(printer_data, "result", "status", "print_stats", "filename") then
		filename = fixFilename(printer_data["result"]["status"]["print_stats"]["filename"])  
		if((filename ~= nil) and (#filename > 0)) then
			device:emit_component_event(device.profile.components.printJob, cap_filename.filename(filename))
		else
			device:emit_component_event(device.profile.components.printJob, cap_filename.filename("-"))
		end
	else console_log(device, 'MISSING gcode Filename')
	end

	if isset(printer_data, "result", "status", "display_status", "progress") then
		progress = tonumber(printer_data["result"]["status"]["display_status"]["progress"]) * 100
		device:emit_component_event(device.profile.components.printJob, cap_percentcomplete.percentComplete({value=progress, unit="%"}))
	else console_log(device, 'MISSING Progress')
	end

	if isset(printer_data, "result", "status", "display_status", "message") then
		message = printer_data["result"]["status"]["display_status"]["message"]
		if(#message > 0) then
			device:emit_event(cap_message.message(message))
		else
			device:emit_event(cap_message.message("-"))
		end
	else console_log(device, 'MISSING M117 Message')
	end

	-- allow potential error message to use the message field
	if isset(printer_data, "result", "status", "print_stats", "message") then
		error_message = printer_data["result"]["status"]["print_stats"]["message"]
		if(#error_message > 0) then
			device:emit_event(cap_message.message(error_message))
		end
	end

	if isset(printer_data, "result", "status", "print_stats", "total_duration") then
		total_time = printer_data["result"]["status"]["print_stats"]["total_duration"]
		device:emit_component_event(device.profile.components.printJob, cap_printtime.totalTime(to_string_time(total_time)))
	else console_log(device, 'MISSING Total Duration')
	end

	if(printer_status == "printing") then

		if(slicer_estimated_time == false) then

			-- no estimated time available from slicer
			device:emit_component_event(device.profile.components.printJob, cap_printtime.remainingTime("N/A"))
			console_log(device, 'No Slicer estimated time to calculate time remaining')
		
		elseif(slicer_estimated_time == nil) then

			-- not yet checked for estimated time from slicer
			-- check now, attempt to download gcode file's metadata
			device:emit_component_event(device.profile.components.printJob, cap_printtime.remainingTime("..."))
			slicer_estimated_time = false  -- assume it failed, update later

			console_log(device, 'Downloading current gcode file metadata')
			return_code, return_data = download_data('GET', '/server/files/metadata?filename=' .. urlencode(printer_data["result"]["status"]["print_stats"]["filename"]), device)

			if(return_code == 200) then

				file_data, pos, err = json.decode(return_data)
				if(err) then
					console_log(device, ' - Error decoding file metadata')
				else
					console_log(device, ' - Metadata Decoded')

					if isset(file_data, "result", "estimated_time") then
						slicer_estimated_time = file_data["result"]["estimated_time"]  -- will get picked up on next refresh cycle
					else
						console_log(device, ' - No estimated time')
					end
				end

			else

				console_log(device, ' - Error downloading gcode file metadata')

			end

		else

			-- calculate estimated time remaining
			console_log(device, 'Calculating print time remaining')
			time_remaining = math.max((slicer_estimated_time - printer_data["result"]["status"]["print_stats"]["print_duration"]), 0)
			device:emit_component_event(device.profile.components.printJob, cap_printtime.remainingTime(to_string_time(time_remaining)))

		end
	else

		slicer_estimated_time = nil
		device:emit_component_event(device.profile.components.printJob, cap_printtime.remainingTime("-"))

	end
end


-- reset the fields in the detail view, usually when the printer goes offline
function reset_printer_stats(device)

	console_log(device, 'Resetting Stats')

	device:emit_component_event(device.profile.components.bed, cap_temperature.temperature({value=0, unit="C"}))
	device:emit_component_event(device.profile.components.extruder, cap_temperature.temperature({value=0, unit="C"}))
	device:emit_component_event(device.profile.components.extruder, cap_printerfan.speed({value=0, unit="%"}))
	device:emit_component_event(device.profile.components.printJob, cap_filename.filename("-"))
	device:emit_component_event(device.profile.components.printJob, cap_percentcomplete.percentComplete({value=0, unit="%"}))
	device:emit_component_event(device.profile.components.printJob, cap_printtime.totalTime("-"))
	device:emit_component_event(device.profile.components.printJob, cap_printtime.remainingTime("-"))
	slicer_estimated_time = nil

end


-- handle sending commands (pause, shutdown, etc.) to moonraker
function send_command(driver, device, command)

	if(printer_online == false) then
	
		console_log(device, 'Printer is offline')
		update_status('offline', false, driver, device)
		return false

	end

	console_log(device, 'SENDING COMMAND '..command.args.command)
	local status_message  -- temporary status (if successful) to display while waiting for the next refresh

	if(command.args.command == 'pause') then

		status_message = 'pause'
		return_code, return_data = download_data('POST', '/printer/print/pause', device)

	elseif(command.args.command == 'resume') then

		status_message = 'resume'
		return_code, return_data = download_data('POST', '/printer/print/resume', device)

	elseif(command.args.command == 'cancel') then

		status_message = 'cancel'
		return_code, return_data = download_data('POST', '/printer/print/cancel', device)


	elseif(command.args.command == 'emergency') then

		status_message = 'emergency'
		return_code, return_data = download_data('POST', '/printer/emergency_stop', device)


	elseif(command.args.command == 'reboot') then

		status_message = 'reboot'
		return_code, return_data = download_data('POST', '/machine/reboot', device)


	elseif(command.args.command == 'shutdown') then

		status_message = 'shutdown'
		return_code, return_data = download_data('POST', '/machine/shutdown', device)

	else

		device:emit_event(cap_status.printer(command.args.command .. ' not implemented'))
		return false

	end

	if(return_code == nil) then

		console_log(device, ' - No response')
		update_status('offline', false, driver, device)

	elseif(return_code == 200) then
	
		console_log(device, ' - Success')
		update_status(status_message, true, driver, device)
	
	elseif(return_code == 401) then

		console_log(device, ' - 401 error')
		update_status('unauthorised', false, driver, device)

	else

		console_log(device, ' - Other server error ('..return_code..')')
		update_status('Error ' .. return_code, false, driver, device)

	end
  
end


-- update the status field of the printer, used on dashboard and detail view
-- update/change the internal state (online/offline) of the printer to trigger other events
-- params: print_status:string - status to display. most staus values have alternatives in presentation
--         new_online_state:boolean - true=online, false=offline
function update_status(print_status, new_online_state, driver, device)

	if(print_status ~= nil) then
		console_log(device, 'Updating printer status: ' .. print_status)
		device:emit_event(cap_status.printer(print_status))
	end

	if(printer_online ~= new_online_state) then

		console_log(device, 'Online state change')
		printer_online = new_online_state
		restart_timer(driver, device)

		if(printer_online == false) then
			reset_printer_stats(device)
		end

	else

		console_log(device, 'No change to online state')
		printer_online = new_online_state

	end

end


-- timer needs restarting on printer state change or settings change
function restart_timer(driver, device)

	local cycle_time = printer_online and device.preferences.pollOnline or device.preferences.pollOffline

	console_log(device, 'RESTARTING TIMER ('..cycle_time..'s)')

	if(refresh_timer ~= nil) then driver:cancel_timer(refresh_timer) end

	refresh_timer = driver:call_on_schedule(cycle_time, function() refresh_data(driver, device) end)

end


-- triggered when any value on the settings screen is changed
function handle_infochanged(driver, device, event)

	console_log(device, 'PREFERENCES CHANGED')
	console_log(device, '    ipAddress: ' .. device.preferences.ipAddress)
	console_log(device, '       ipPort: ' .. device.preferences.ipPort)
	console_log(device, '   ipProtocol: ' .. device.preferences.ipProtocol)
	console_log(device, '       apiKey: ' .. ((#device.preferences.apiKey > 0) and '(yes)' or '(none)'))
	console_log(device, '  httpTimeout: ' .. device.preferences.httpTimeout)
	console_log(device, '   pollOnline: ' .. device.preferences.pollOnline)
	console_log(device, '  pollOffline: ' .. device.preferences.pollOffline)
	console_log(device, '   verboseLog: ' .. (device.preferences.verboseLog and 'true' or 'false'))

	-- restart the refresh timer
	restart_timer(driver, device)

end


-----------------------------------------------------------------
-- smartthings functions
-----------------------------------------------------------------

-- this is called once a device is added by the cloud and synchronized down to the hub
local function device_added(driver, device)
	log.info("[" .. device.id .. "] Adding new Klipper printer")
end


-- this is called both when a device is added (but after `added`) and after a hub reboots.
local function device_init(driver, device)
	log.info("[" .. device.id .. "] Initializing Klipper printer")

	-- mark device as online so it can be controlled from the app
	device:online()

	refresh_timer = driver:call_on_schedule(device.preferences.pollOffline, function() refresh_data(driver, device) end)
end


-- this is called when a device is removed by the cloud and synchronized down to the hub
local function device_removed(driver, device)
	log.info("[" .. device.id .. "] Removing Klipper printer")
end


-- create the driver object
local moonraker_driver = Driver("moonraker", {
	discovery = discovery.handle_discovery,
	lifecycle_handlers = {
		added = device_added,
		init = device_init,
		removed = device_removed,
		infoChanged = handle_infochanged
	},
	capability_handlers = {
		[cap_status.ID] = {
			[cap_status.commands.sendCommand.NAME] = send_command,
		},
	}
})


-- run the driver
moonraker_driver:run()