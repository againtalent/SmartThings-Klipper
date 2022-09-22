local log = require "log"
local discovery = {}

-- handle discovery events, normally you'd try to discover devices on your
-- network in a loop until calling `should_continue()` returns false.
function discovery.handle_discovery(driver, _should_continue)
	log.info("Starting Moonraker Discovery")

	local metadata = {
		type = "LAN",
		-- the DNI must be unique across your hub, using static ID here so that we
		-- only ever have a single instance of this "device"
		device_network_id = "moonraker klipper device",
		label = "Klipper 3D Printer",
		profile = "moonraker-klipper.v1",
		manufacturer = "SmartThingsCommunity",
		model = "v1",
		vendor_provided_label = nil
	}

	-- tell the cloud to create a new device record, will get synced back down
	-- and `device_added` and `device_init` callbacks will be called
	driver:try_create_device(metadata)
end

return discovery
