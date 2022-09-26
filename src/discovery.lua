local log = require "log"
local discovery = {}

function discovery.handle_discovery(driver, _should_continue)
	log.info("Starting Moonraker Discovery")

	local metadata = {
		type = "LAN",
		device_network_id = "moonraker klipper device",
		label = "Klipper 3D Printer",
		profile = "moonraker-klipper.v1",
		manufacturer = "SmartThingsCommunity",
		model = "v1",
		vendor_provided_label = nil
	}

	driver:try_create_device(metadata)
end

return discovery
