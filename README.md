# SmartThings Edge Klipper 3D Printer Monitor

SmartThings Edge Driver to monitor the status and issue basic commands to a [Klipper](https://github.com/Klipper3d/klipper) 3D printer (via the [Moonraker API](https://github.com/Arksine/moonraker)) on the Samsung SmartThings platform.

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

Both the status and commands can be used in routines. For example, sending a notification when a print is completed, or automatically shutting down the printer once it's cooled down.

## Prerequisites

- Klipper (with Moonraker) running on the same LAN as your SmartThings hub

## Installation

1. Enroll your SmartThings hub in the AgainTalent Release Channel: https://bestow-regional.api.smartthings.com/invite/QLMO8LK4rk23
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

## Support, Feedback, Bug Reports

Please use the dedicated thread on the SmartThings Community: https://community.smartthings.com/t/st-edge-klipper-3d-printer/248479