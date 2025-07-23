# Hubitat Prometheus Exporter

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
- `hubitat_device_temperature` - Temperature reading
- `hubitat_device_humidity` - Humidity percentage
- `hubitat_device_illuminance` - Light level
- `hubitat_device_power` - Power consumption in watts
- `hubitat_device_energy` - Energy consumption
- `hubitat_device_motion` - Motion detection state (1=active, 0=inactive)
- `hubitat_device_contact` - Contact sensor state (1=open, 0=closed)

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

This project is open source and available under the Elmer Fudd License.
