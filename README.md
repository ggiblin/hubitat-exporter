# Hubitat Prometheus Gateway

A lightweight Bash-based Prometheus exporter for Hubitat Elevation smart home hub metrics. This exporter collects device states and metrics from your Hubitat hub and exposes them in Prometheus format.

## Features

- Exports device states (on/off, temperature, humidity, etc.)
- Supports multiple device types and attributes
- Updates metrics every 15 seconds
- Minimal dependencies (uses common Unix tools)
- Handles concurrent connections efficiently
- Automatic reconnection on errors

## Prerequisites

The following tools must be installed:
- `curl`
- `jq`
- `socat`
- `base64`

## Configuration

Create a `.env` file in the same directory as the script with the following variables:

```bash
HE_URI=http://your-hubitat-ip/apps/api/26/devices
HE_TOKEN=your-access-token
```

Replace `your-hubitat-ip` with your Hubitat hub's IP address and `your-access-token` with your Maker API access token.

## Installation

1. Clone this repository
2. Make the script executable:
   ```bash
   chmod +x hubitat-exporter.sh
   ```
3. Create and configure the `.env` file as described above
4. Run the exporter:
   ```bash
   ./hubitat-exporter.sh
   ```

## Exported Metrics

The exporter provides the following metrics:

- `hubitat_up` - Indicates if the connection to Hubitat is up (1) or down (0)
- `hubitat_device_switch` - Switch state (1=on, 0=off)
- `hubitat_device_battery` - Battery level percentage
- `hubitat_device_battery_voltage` - Battery voltage reading
- `hubitat_device_temperature` - Temperature reading
- `hubitat_device_humidity` - Humidity percentage
- `hubitat_device_illuminance` - Light level
- `hubitat_device_power` - Power consumption in watts
- `hubitat_device_energy` - Energy consumption
- `hubitat_device_energy_today` - Energy usage for today
- `hubitat_device_energy_total` - Lifetime/total energy usage
- `hubitat_device_energy_yesterday` - Energy usage for yesterday
- `hubitat_device_hourly_energy` - Hourly energy value
- `hubitat_device_energy_cost` - Energy cost value
- `hubitat_device_energy_duration` - Energy duration value
- `hubitat_device_level` - Dimmer level
- `hubitat_device_hue` - Hue value for color lights
- `hubitat_device_saturation` - Saturation value for color lights
- `hubitat_device_color_temperature` - Color temperature reading
- `hubitat_device_tilt` - Blind/shade tilt position
- `hubitat_device_tilt_angle` - Tilt angle reading
- `hubitat_device_voltage` - Voltage reading
- `hubitat_device_current` - Current reading (or amperage if current is unavailable)
- `hubitat_device_power_factor` - Power factor reading
- `hubitat_device_apparent_power` - Apparent power reading
- `hubitat_device_reactive_power` - Reactive power reading
- `hubitat_device_frequency` - Line frequency reading
- `hubitat_device_air_quality` - Air quality score when numeric
- `hubitat_device_air_quality_index` - Air quality index (AQI) when numeric
- `hubitat_device_air_quality_level` - Air quality level when numeric
- `hubitat_device_activity_level` - Activity level when numeric
- `hubitat_device_alert_aiq` - Air quality alert state (0=good, 1=warning, 2=bad)
- `hubitat_device_alert_co2` - CO2 alert state (0=good, 1=warning, 2=bad)
- `hubitat_device_alert_pm10` - PM10 alert state (0=good, 1=warning, 2=bad)
- `hubitat_device_alert_pm25` - PM2.5 alert state (0=good, 1=warning, 2=bad)
- `hubitat_device_alert_voc` - VOC alert state (0=good, 1=warning, 2=bad)
- `hubitat_device_pm25` - PM2.5 reading
- `hubitat_device_pm10` - PM10 reading
- `hubitat_device_voc` - VOC reading (or Sensirion VOC index)
- `hubitat_device_gas2` - Gas concentration reading
- `hubitat_device_ammonia` - Ammonia concentration reading
- `hubitat_device_cloudiness` - Cloudiness percentage
- `hubitat_device_carbon_dioxide` - CO2 reading
- `hubitat_device_carbon_monoxide` - CO reading
- `hubitat_device_thermostat_setpoint` - Thermostat setpoint
- `hubitat_device_heating_setpoint` - Heating setpoint
- `hubitat_device_cooling_setpoint` - Cooling setpoint
- `hubitat_device_scheduled_setpoint` - Scheduled thermostat setpoint
- `hubitat_device_next_scheduled_setpoint` - Next scheduled thermostat setpoint
- `hubitat_device_window_function` - Window function state (1=active, 0=inactive)
- `hubitat_device_air_pressure` - Air pressure reading (uses `airPressure` or `pressure`)
- `hubitat_device_wind_speed` - Wind speed reading
- `hubitat_device_wind_direction` - Wind direction reading
- `hubitat_device_occupied_time` - Occupied duration
- `hubitat_device_absence_time` - Absence duration
- `hubitat_device_existance_time` - Presence existence duration (Hubitat attribute `existance_time`)
- `hubitat_device_leave_time` - Leave duration
- `hubitat_device_distance` - Distance reading
- `hubitat_device_rtt` - RTT reading
- `hubitat_device_check_interval` - Device check interval value
- `hubitat_device_fading_time` - Fading time value
- `hubitat_device_angle` - Angle reading (can be negative)
- `hubitat_device_maximum_distance` - Maximum detection distance
- `hubitat_device_minimum_distance` - Minimum detection distance
- `hubitat_device_radar_sensitivity` - Radar sensitivity value
- `hubitat_device_static_detection_sensitivity` - Static detection sensitivity value
- `hubitat_device_channel` - Numeric channel value
- `hubitat_device_channel_full_number` - Numeric full channel value
- `hubitat_device_volume` - Volume level
- `hubitat_device_mute` - Mute state (1=muted, 0=unmuted)
- `hubitat_device_power_on_state` - Power-on state (1=on, 0=off)
- `hubitat_device_number_of_buttons` - Number of buttons reported by a device
- `hubitat_device_event_stream_status` - Event stream state (1=connected, 0=disconnected)
- `hubitat_device_color_mode` - Color mode (1=CT, 2=RGB, 3=RGBW)
- `hubitat_device_motion` - Motion detection state (1=active, 0=inactive)
- `hubitat_device_acceleration` - Acceleration state (1=active, 0=inactive)
- `hubitat_device_health_status` - Device health state (1=online, 0=offline)
- `hubitat_device_network_status` - Network state (1=connected, 0=disconnected)
- `hubitat_device_status` - Generic status (1=Online, 0=Offline)
- `hubitat_device_hub_mesh_disabled` - Hub mesh disable state (1=true, 0=false)
- `hubitat_device_sensor_status` - Sensor status (1=active/moving, 0=stationary/inactive)
- `hubitat_device_presence` - Presence state (1=present, 0=not present)
- `hubitat_device_occupancy` - Occupancy state (1=occupied/active, 0=clear/inactive)
- `hubitat_device_contact` - Contact sensor state (1=open, 0=closed)
- `hubitat_device_water` - Water leak state (1=wet/detected, 0=dry/clear)
- `hubitat_device_tamper` - Tamper state (1=detected/active, 0=clear/inactive)
- `hubitat_device_pushed` - Button pushed event value
- `hubitat_device_held` - Button held event value
- `hubitat_device_double_tapped` - Button double-tapped event value
- `hubitat_device_released` - Button released event value
- `hubitat_device_taps` - Tap count/event value
- `hubitat_device_action` - Last Aqara Cube action (1=wakeup, 2=shake, 3=flip_to_side, 4=tap_twice, 5=rotate_left, 6=rotate_right, 7=start_rotating, 8=rotation_stopped, 9=1_min_inactivity)

### Thermostat Operating State
- `hubitat_device_thermostat_mode` - Thermostat mode (0=off, 1=heat, 2=cool, 3=auto, 4=fan_only, 5=emergency_heat)
- `hubitat_device_thermostat_operating_state` - Thermostat operating state (0=idle, 1=heating, 2=cooling, 3=fan_only, 4=pending_cool, 5=pending_heat)
- `hubitat_device_thermostat_setpoint_mode` - Thermostat setpoint mode (0=followSchedule, 1=temporaryOverride, 2=permanentOverride)

### Sensor State
- `hubitat_device_illum_state` - Illumination state (1=bright, 0=dark)
- `hubitat_device_human_motion_state` - Human motion state (0=none, 1=moving, 2=small_move, 3=standing)
- `hubitat_device_effect` - Light effect active (0=none, 1=active/colorloop)
- `hubitat_device_sync_status` - Zigbee sync state (1=synced, 0=not synced)
- `hubitat_device_status_upper` - Driver/device status enum (`clear`=1, `Complete:Success`=2, `Complete:Timeout`=0)
- `hubitat_device_power_source` - Power source enum (`?`=0, `dc`=1, `battery`=2, `mains/ac`=3)

### Radar / Presence Sensor Tuning
- `hubitat_device_detection_delay` - Detection delay (seconds)
- `hubitat_device_static_detection_distance` - Static detection distance (meters)
- `hubitat_device_motion_detection_distance` - Motion detection distance (meters)
- `hubitat_device_small_motion_detection_sensitivity` - Small motion detection sensitivity
- `hubitat_device_keep_time` - Keep time / hold-on period (seconds)
- `hubitat_device_unacknowledged_time` - Unacknowledged presence time (seconds)
- `hubitat_device_amperage` - Amperage reading
- `hubitat_device_poked_side` - Parsed side value from Zigbee map helper `poked` events

### Time / Epoch Metrics
- `hubitat_device_battery_last_replaced_epoch` - Parsed battery replacement date as Unix epoch
- `hubitat_device_next_scheduled_time_epoch` - Next scheduled thermostat time as Unix epoch
- `hubitat_device_thermostat_setpoint_until_epoch` - Thermostat override end time as Unix epoch
- `hubitat_device_last_checkin_epoch` - Device last check-in time as Unix epoch
- `hubitat_device_last_drop_epoch` - Last drop event time as Unix epoch
- `hubitat_device_last_stationary_epoch` - Last stationary event time as Unix epoch
- `hubitat_device_last_tilt_epoch` - Last tilt event time as Unix epoch
- `hubitat_device_last_vibration_epoch` - Last vibration event time as Unix epoch

### Batch 11 State/Metadata Metrics
- `hubitat_device_channel_name_present` - Channel name is available (1=yes)
- `hubitat_device_channel_desc_present` - Channel description available (1=yes, 0=`[none]`)
- `hubitat_device_color_rgb` - RGB color as packed integer from `#RRGGBB`
- `hubitat_device_color_name_present` - Color name is available (1=yes)
- `hubitat_device_thermostat_setpoint_status` - Setpoint status (0=Following Schedule, 1=Temporary Override)
- `hubitat_device_thermostat_status` - Thermostat status (0=idle, 1=heating, 2=cooling)
- `hubitat_device_optimisation` - Optimisation state (1=active, 0=inactive)
- `hubitat_device_weather_icon_code` - Weather icon numeric code extracted from values like `04n`
- `hubitat_device_variable` - Numeric variable value from generic drivers

All metrics include the following labels:
- `hub` - Hub name
- `id` - Device ID
- `label` - Device label
- `room` - Room name
- `type` - Device type

## Usage

The exporter runs on port 5000 by default. To test:

```bash
curl http://localhost:5000/metrics
```

### Prometheus Configuration

Add the following to your `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'hubitat'
    static_configs:
      - targets: ['localhost:5000']
    scrape_interval: 30s
```

## Logging

The exporter logs its activity to stderr with timestamps. You can:

- View logs in real-time by running the script directly:
  ```bash
  ./hubitat-exporter.sh
  ```

- Redirect logs to a file while running in the background:
  ```bash
  ./hubitat-exporter.sh 2>/var/log/hubitat-exporter.log &
  ```

- Follow the logs in real-time using `tail`:
  ```bash
  tail -f /var/log/hubitat-exporter.log
  ```

The logs include:
- Server start/stop events
- Metrics generation status
- API connection issues
- Error messages with details

## Troubleshooting

- If the exporter fails to start, check that all required tools are installed
- Verify your Hubitat hub is accessible and the Maker API is properly configured
- Check the logs as described in the Logging section above
- Ensure the port 5000 is not in use by another application

## License

This project is open source and available under the Elmer Fudd and MIT License.

