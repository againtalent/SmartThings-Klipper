# SmartThings Edge Klipper 3D Printer Monitor

Monitor the status and issue basic commands to a Klipper 3D printer (via Moonraker) on the Samsung SmartThings platform.

Monitoring includes:
- Online/offline status
- Current printer state
- Extruder and bed temperatures
- Part cooling fan speed
- Messages via the M117 gcode

Printer commands:
- Emergency stop
- Pause
- Resume
- Cancel
- Reboot Host (Pi)
- Shutdown Host (Pi)

Both the status and commands can be used in routines.

## Prerequisites

- Klipper (with Moonraker) running on the same LAN as your SmartThings hub

## Installation

1. Enroll your SmartThings hub in the AgainTalent Release Channel: https://bestow-regional.api.smartthings.com/invite/QLMOr0rARQj3
2. Install the Moonraker-Klipper driver
3. Open the SmartThings app and scan for nearby devices
4. Once the printer is 'found', edit its settings to configure the IP address and other fields
5. If your Moonraker installation requires an API key, you can retrieve this from Fluidd's settings screen or by following the instructions here: https://moonraker.readthedocs.io/en/latest/installation/#retrieving-the-api-key

## Limitations

- HTTPS is untested
- Only the main extruder is supported
- Only one printer (instance) is supported
  - Multiple instances will be implemented in the future
- Temperature values in routines are limited to -20°C - 50°C because the driver uses SmartThings' temperatureMeasurement capability
  - You do get pretty graphs in return, however
- Print time remaining estimate uses the metadata provided by the slicer