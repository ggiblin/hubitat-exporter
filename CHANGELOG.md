# Changelog

All notable changes to hubitat-exporter-k3s are documented here.
Versioning follows [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.

---

## [0.8.0] — 2026-04-07

### Added
- Versioning system: `VERSION` file, script header comments, `CHANGELOG.md`, git tags
- `hubitat_exporter_build_info` gauge metric (labels: `version`, `hub`) — always emitted; use in Grafana to track deployed version
- **Batch 7 metrics**: `tilt_angle`, `maximum_distance`, `minimum_distance`, `radar_sensitivity`, `static_detection_sensitivity`, `volume`, `mute`, `power_on_state`, `number_of_buttons`, `scheduled_setpoint`, `next_scheduled_setpoint`, `window_function`

---

## [0.7.0] — 2026-03

### Added
- **Batch 6 metrics**: `health_status`, `network_status`, `status`, `hub_mesh_disabled`, `sensor_status` (all encoded 1=positive/0=negative)

---

## [0.6.0] — 2026-03

### Added
- **Batch 5 metrics**: `alert_aiq`, `alert_co2`, `alert_pm10`, `alert_pm25`, `alert_voc` (0=good, 1=warning, 2=bad), `gas2`, `ammonia`, `cloudiness`, `check_interval`, `fading_time`, `angle`, `channel`, `channel_full_number`, `event_stream_status`, `color_mode` (1=CT, 2=RGB, 3=RGBW)

---

## [0.5.0] — 2026-03

### Added
- **Batch 4 metrics**: `battery_voltage`, `energy_today`, `energy_total`, `energy_yesterday`, `hourly_energy`, `energy_cost`, `energy_duration`, `air_quality_index`, `air_quality_level`, `activity_level`, `acceleration`

---

## [0.4.0] — 2026-03

### Added
- **Batch 3 metrics**: `air_pressure`, `wind_speed`, `wind_direction`, `occupied_time`, `absence_time`, `existance_time`, `leave_time`, `distance`, `rtt`, `pushed`, `held`, `double_tapped`, `released`, `taps`

---

## [0.3.0] — 2026-02

### Added
- **Batch 2 metrics**: `color_temperature`, `tilt`, `voltage`, `current`, `power_factor`, `apparent_power`, `reactive_power`, `frequency`, `air_quality`, `pm25`, `pm10`, `voc`, `co2`, `co`, `thermostat` setpoints, `motion`, `presence`, `occupancy`, `contact`, `water`, `tamper`

---

## [0.2.0] — 2026-01

### Added
- **Batch 1 metrics**: `switch`, `battery`, `temperature`, `humidity`, `illuminance`, `power`, `energy`, `level`, `hue`, `saturation`
- Kubernetes deployment via K8s manifests (ConfigMap-embedded script, socat HTTP server)
- Two-hub support: shankmata and colossus

---

## [0.1.0] — 2025

### Added
- Initial standalone bash exporter (`hubitat-exporter.sh`)
- Hubitat REST API polling with `curl` + `jq`
- Prometheus text format output
- `.env`-based configuration
