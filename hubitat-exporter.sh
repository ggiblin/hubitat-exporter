#!/bin/bash
# Version: 0.11.0

# Change to the project directory
cd "$(dirname "$0")"

# Load environment variables from .env file
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

# Function to URL encode strings
urlencode() {
    local string="$1"
    echo "$string" | curl -Gso /dev/null -w %{url_effective} --data-urlencode @- "" | cut -c 3-
}

# Function to get device state
get_device_state() {
    local base_uri="$1"
    local device_id="$2"
    local access_token="$3"
    
    device_uri="${base_uri}/devices/${device_id}?access_token=${access_token}"
    log "Fetching state from $device_uri"
    
    response=$(curl -s "$device_uri")
    if [ $? -ne 0 ]; then
        log "Error fetching device state"
        echo "{}"
        return
    fi
    
    # Debug log the response
    log "Device response: $response"
    
    # Check if response is valid JSON
    if ! echo "$response" | jq '.' >/dev/null 2>&1; then
        log "Error: Invalid JSON response from device"
        echo "{}"
        return
    fi
    
    # Extract attributes using jq, with better error handling
    result=$(echo "$response" | jq -r '.attributes | map(select(.currentValue != null) | {(.name): .currentValue}) | add // {}' 2>/dev/null)
    if [ $? -ne 0 ]; then
        log "Error parsing attributes from response"
        echo "{}"
        return
    fi
    echo "$result"
}

# Function to get hub devices
get_hub_devices() {
    local hub_uri="$1"
    local access_token="$2"
    
    # Get base URI without /devices
    base_uri="${hub_uri%/devices*}"
    
    log "Fetching devices from $hub_uri"
    devices=$(curl -s "${hub_uri}?access_token=${access_token}")
    if [ $? -ne 0 ]; then
        log "Error fetching devices"
        echo "[]"
        return
    fi
    
    # Debug log the devices response
    log "Devices response: $devices"
    
    # Check if devices response is valid JSON
    if ! echo "$devices" | jq '.' >/dev/null 2>&1; then
        log "Error: Invalid JSON response from devices endpoint"
        echo "[]"
        return
    fi
    
    # For each device, get its state and add it to the attributes
    echo "$devices" | jq -r '.[] | @base64' | while read -r device; do
        device_json=$(echo "$device" | base64 -d)
        device_id=$(echo "$device_json" | jq -r '.id')
        
        if [ "$device_id" != "null" ]; then
            state=$(get_device_state "$base_uri" "$device_id" "$access_token")
            echo "$device_json" | jq --argjson attrs "$state" '. + {attributes: $attrs}'
        fi
    done | jq -s '.'
}

# Function to generate metrics
generate_metrics() {
    local hub_name="colossus"
    log "Hub name: $hub_name"
    
    devices=$(get_hub_devices "$HE_URI" "$HE_TOKEN")
    
    # Validate devices JSON before continuing
    if ! echo "$devices" | jq '.' >/dev/null 2>&1; then
        log "Error: Invalid JSON returned from get_hub_devices"
        return
    fi
    
    device_count=$(echo "$devices" | jq 'length')
    log "Retrieved $device_count devices"
    
    if [ -z "$devices" ] || [ "$devices" = "[]" ]; then
        log "No devices found or empty response"
        echo "# HELP hubitat_up Indicates if the connection to Hubitat is up (1) or down (0)"
        echo "# TYPE hubitat_up gauge"
        echo "hubitat_up{hub=\"${hub_name}\"} 0"
        return
    fi
    
    # Output metric headers
    echo "# HELP hubitat_exporter_build_info Hubitat exporter build information"
    echo "# TYPE hubitat_exporter_build_info gauge"
    echo "hubitat_exporter_build_info{version=\"0.11.0\",hub=\"${hub_name}\"}  1"
    echo "# HELP hubitat_up Indicates if the connection to Hubitat is up (1) or down (0)"
    echo "# TYPE hubitat_up gauge"
    echo "hubitat_up{hub=\"${hub_name}\"} 1"
    
    echo "# HELP hubitat_device_info Information about Hubitat devices"
    echo "# TYPE hubitat_device_info gauge"
    
    # Process each device
    echo "$devices" | jq -r '.[] | @base64' | while read -r device; do
        device_json=$(echo "$device" | base64 -d)
        
        # Extract device info
        id=$(echo "$device_json" | jq -r '.id')
        label=$(echo "$device_json" | jq -r '.label' | sed 's/"/\\"/g')
        room=$(echo "$device_json" | jq -r '.room // "unknown"')
        type=$(echo "$device_json" | jq -r '.type // "unknown"')
        attributes=$(echo "$device_json" | jq -r '.attributes // {}')
        
        # Common labels
        labels="hub=\"${hub_name}\",id=\"${id}\",label=\"${label}\",room=\"${room}\",type=\"${type}\""
        
        # Process switch state
        switch_state=$(echo "$attributes" | jq -r '.switch // "unknown"')
        if [[ "$switch_state" == "on" || "$switch_state" == "off" ]]; then
            value=$([[ "$switch_state" == "on" ]] && echo "1" || echo "0")
            echo "hubitat_device_switch{$labels} $value"
        fi
        
        # Process battery level
        battery=$(echo "$attributes" | jq -r '.battery')
        if [[ "$battery" != "null" && "$battery" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_battery{$labels} $battery"
        fi

        # Process battery voltage
        battery_voltage=$(echo "$attributes" | jq -r '.batteryVoltage')
        if [[ "$battery_voltage" != "null" && "$battery_voltage" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_battery_voltage{$labels} $battery_voltage"
        fi

        amperage=$(echo "$attributes" | jq -r '.amperage')
        if [[ "$amperage" != "null" && "$amperage" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_amperage{$labels} $amperage"
        fi

        power_source=$(echo "$attributes" | jq -r '.powerSource // "unknown"')
        case "$power_source" in
            dc)       echo "hubitat_device_power_source{$labels} 1" ;;
            battery)  echo "hubitat_device_power_source{$labels} 2" ;;
            mains|ac) echo "hubitat_device_power_source{$labels} 3" ;;
            "?")      echo "hubitat_device_power_source{$labels} 0" ;;
        esac

        battery_last_replaced=$(echo "$attributes" | jq -r '.batteryLastReplaced // "unknown"')
        if [[ "$battery_last_replaced" != "unknown" && "$battery_last_replaced" != "null" ]]; then
            epoch=$(date -d "$battery_last_replaced" +%s 2>/dev/null)
            if [[ "$epoch" =~ ^[0-9]+$ ]]; then
                echo "hubitat_device_battery_last_replaced_epoch{$labels} $epoch"
            fi
        fi
        
        # Process illuminance
        illuminance=$(echo "$attributes" | jq -r '.illuminance')
        if [[ "$illuminance" != "null" && "$illuminance" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_illuminance{$labels} $illuminance"
        fi
        
        # Process temperature
        temperature=$(echo "$attributes" | jq -r '.temperature')
        if [[ "$temperature" != "null" && "$temperature" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_temperature{$labels} $temperature"
        fi
        
        # Process humidity
        humidity=$(echo "$attributes" | jq -r '.humidity')
        if [[ "$humidity" != "null" && "$humidity" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_humidity{$labels} $humidity"
        fi
        
        # Process power
        power=$(echo "$attributes" | jq -r '.power')
        if [[ "$power" != "null" && "$power" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_power{$labels} $power"
        fi
        
        # Process energy
        energy=$(echo "$attributes" | jq -r '.energy')
        if [[ "$energy" != "null" && "$energy" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_energy{$labels} $energy"
        fi

        # Process additional energy counters
        energy_today=$(echo "$attributes" | jq -r '.energyToday')
        if [[ "$energy_today" != "null" && "$energy_today" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_energy_today{$labels} $energy_today"
        fi

        energy_total=$(echo "$attributes" | jq -r '.energyTotal')
        if [[ "$energy_total" != "null" && "$energy_total" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_energy_total{$labels} $energy_total"
        fi

        energy_yesterday=$(echo "$attributes" | jq -r '.energyYesterday')
        if [[ "$energy_yesterday" != "null" && "$energy_yesterday" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_energy_yesterday{$labels} $energy_yesterday"
        fi

        hourly_energy=$(echo "$attributes" | jq -r '.hourlyEnergy')
        if [[ "$hourly_energy" != "null" && "$hourly_energy" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_hourly_energy{$labels} $hourly_energy"
        fi

        energy_cost=$(echo "$attributes" | jq -r '.energyCost')
        if [[ "$energy_cost" != "null" && "$energy_cost" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_energy_cost{$labels} $energy_cost"
        fi

        energy_duration=$(echo "$attributes" | jq -r '.energyDuration')
        if [[ "$energy_duration" != "null" && "$energy_duration" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_energy_duration{$labels} $energy_duration"
        fi

        # Process level (dimmer level)
        level=$(echo "$attributes" | jq -r '.level')
        if [[ "$level" != "null" && "$level" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_level{$labels} $level"
        fi

        # Process color controls
        hue=$(echo "$attributes" | jq -r '.hue')
        if [[ "$hue" != "null" && "$hue" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_hue{$labels} $hue"
        fi

        saturation=$(echo "$attributes" | jq -r '.saturation')
        if [[ "$saturation" != "null" && "$saturation" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_saturation{$labels} $saturation"
        fi

        color_temperature=$(echo "$attributes" | jq -r '.colorTemperature')
        if [[ "$color_temperature" != "null" && "$color_temperature" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_color_temperature{$labels} $color_temperature"
        fi

        # Process tilt (blinds/shades)
        tilt=$(echo "$attributes" | jq -r '.tilt')
        if [[ "$tilt" != "null" && "$tilt" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_tilt{$labels} $tilt"
        fi

        # Process tilt angle
        tilt_angle=$(echo "$attributes" | jq -r '.tiltAngle')
        if [[ "$tilt_angle" != "null" && "$tilt_angle" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_tilt_angle{$labels} $tilt_angle"
        fi

        # Process voltage
        voltage=$(echo "$attributes" | jq -r '.voltage')
        if [[ "$voltage" != "null" && "$voltage" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_voltage{$labels} $voltage"
        fi

        # Process current (some drivers use amperage instead)
        current=$(echo "$attributes" | jq -r '.current // .amperage')
        if [[ "$current" != "null" && "$current" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_current{$labels} $current"
        fi

        # Process power factor
        power_factor=$(echo "$attributes" | jq -r '.powerFactor')
        if [[ "$power_factor" != "null" && "$power_factor" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_power_factor{$labels} $power_factor"
        fi

        # Process power quality metrics
        apparent_power=$(echo "$attributes" | jq -r '.apparentPower')
        if [[ "$apparent_power" != "null" && "$apparent_power" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_apparent_power{$labels} $apparent_power"
        fi

        reactive_power=$(echo "$attributes" | jq -r '.reactivePower')
        if [[ "$reactive_power" != "null" && "$reactive_power" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_reactive_power{$labels} $reactive_power"
        fi

        frequency=$(echo "$attributes" | jq -r '.frequency')
        if [[ "$frequency" != "null" && "$frequency" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_frequency{$labels} $frequency"
        fi

        # Process air quality score
        air_quality=$(echo "$attributes" | jq -r '.airQuality')
        if [[ "$air_quality" != "null" && "$air_quality" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_air_quality{$labels} $air_quality"
        fi

        # Process air quality detail metrics
        air_quality_index=$(echo "$attributes" | jq -r '.airQualityIndex')
        if [[ "$air_quality_index" != "null" && "$air_quality_index" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_air_quality_index{$labels} $air_quality_index"
        fi

        air_quality_level=$(echo "$attributes" | jq -r '.airQualityLevel')
        if [[ "$air_quality_level" != "null" && "$air_quality_level" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_air_quality_level{$labels} $air_quality_level"
        fi

        # Process activity level when numeric
        activity_level=$(echo "$attributes" | jq -r '.activityLevel')
        if [[ "$activity_level" != "null" && "$activity_level" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_activity_level{$labels} $activity_level"
        fi

        # Process air quality alert states (good=0, warning=1, bad=2)
        alert_aiq=$(echo "$attributes" | jq -r '.alert_aiq // "unknown"')
        case "$alert_aiq" in
            good) echo "hubitat_device_alert_aiq{$labels} 0" ;;
            warning) echo "hubitat_device_alert_aiq{$labels} 1" ;;
            bad) echo "hubitat_device_alert_aiq{$labels} 2" ;;
        esac

        alert_co2=$(echo "$attributes" | jq -r '.alert_co2 // "unknown"')
        case "$alert_co2" in
            good) echo "hubitat_device_alert_co2{$labels} 0" ;;
            warning) echo "hubitat_device_alert_co2{$labels} 1" ;;
            bad) echo "hubitat_device_alert_co2{$labels} 2" ;;
        esac

        alert_pm10=$(echo "$attributes" | jq -r '.alert_pm10 // "unknown"')
        case "$alert_pm10" in
            good) echo "hubitat_device_alert_pm10{$labels} 0" ;;
            warning) echo "hubitat_device_alert_pm10{$labels} 1" ;;
            bad) echo "hubitat_device_alert_pm10{$labels} 2" ;;
        esac

        alert_pm25=$(echo "$attributes" | jq -r '.alert_pm25 // "unknown"')
        case "$alert_pm25" in
            good) echo "hubitat_device_alert_pm25{$labels} 0" ;;
            warning) echo "hubitat_device_alert_pm25{$labels} 1" ;;
            bad) echo "hubitat_device_alert_pm25{$labels} 2" ;;
        esac

        alert_voc=$(echo "$attributes" | jq -r '.alert_voc // "unknown"')
        case "$alert_voc" in
            good) echo "hubitat_device_alert_voc{$labels} 0" ;;
            warning) echo "hubitat_device_alert_voc{$labels} 1" ;;
            bad) echo "hubitat_device_alert_voc{$labels} 2" ;;
        esac

        # Process additional environmental numeric metrics
        gas2=$(echo "$attributes" | jq -r '.gas2')
        if [[ "$gas2" != "null" && "$gas2" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_gas2{$labels} $gas2"
        fi

        ammonia=$(echo "$attributes" | jq -r '.ammonia')
        if [[ "$ammonia" != "null" && "$ammonia" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_ammonia{$labels} $ammonia"
        fi

        cloudiness=$(echo "$attributes" | jq -r '.cloudiness')
        if [[ "$cloudiness" != "null" && "$cloudiness" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_cloudiness{$labels} $cloudiness"
        fi

        # Process interval and timing values
        check_interval=$(echo "$attributes" | jq -r '.checkInterval')
        if [[ "$check_interval" != "null" && "$check_interval" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_check_interval{$labels} $check_interval"
        fi

        fading_time=$(echo "$attributes" | jq -r '.fadingTime')
        if [[ "$fading_time" != "null" && "$fading_time" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_fading_time{$labels} $fading_time"
        fi

        angle=$(echo "$attributes" | jq -r '.angle')
        if [[ "$angle" != "null" && "$angle" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_angle{$labels} $angle"
        fi

        # Process radar and presence tuning values
        maximum_distance=$(echo "$attributes" | jq -r '.maximumDistance')
        if [[ "$maximum_distance" != "null" && "$maximum_distance" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_maximum_distance{$labels} $maximum_distance"
        fi

        minimum_distance=$(echo "$attributes" | jq -r '.minimumDistance')
        if [[ "$minimum_distance" != "null" && "$minimum_distance" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_minimum_distance{$labels} $minimum_distance"
        fi

        radar_sensitivity=$(echo "$attributes" | jq -r '.radarSensitivity')
        if [[ "$radar_sensitivity" != "null" && "$radar_sensitivity" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_radar_sensitivity{$labels} $radar_sensitivity"
        fi

        static_detection_sensitivity=$(echo "$attributes" | jq -r '.staticDetectionSensitivity')
        if [[ "$static_detection_sensitivity" != "null" && "$static_detection_sensitivity" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_static_detection_sensitivity{$labels} $static_detection_sensitivity"
        fi

        # Process media channel values
        channel=$(echo "$attributes" | jq -r '.channel')
        if [[ "$channel" != "null" && "$channel" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_channel{$labels} $channel"
        fi

        channel_full_number=$(echo "$attributes" | jq -r '.channelFullNumber')
        if [[ "$channel_full_number" != "null" && "$channel_full_number" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_channel_full_number{$labels} $channel_full_number"
        fi

        volume=$(echo "$attributes" | jq -r '.volume')
        if [[ "$volume" != "null" && "$volume" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_volume{$labels} $volume"
        fi

        mute=$(echo "$attributes" | jq -r '.mute // "unknown"')
        if [[ "$mute" == "muted" || "$mute" == "unmuted" ]]; then
            value=$([[ "$mute" == "muted" ]] && echo "1" || echo "0")
            echo "hubitat_device_mute{$labels} $value"
        fi

        power_on_state=$(echo "$attributes" | jq -r '.powerOnState // "unknown"')
        if [[ "$power_on_state" == "on" || "$power_on_state" == "off" ]]; then
            value=$([[ "$power_on_state" == "on" ]] && echo "1" || echo "0")
            echo "hubitat_device_power_on_state{$labels} $value"
        fi

        number_of_buttons=$(echo "$attributes" | jq -r '.numberOfButtons')
        if [[ "$number_of_buttons" != "null" && "$number_of_buttons" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_number_of_buttons{$labels} $number_of_buttons"
        fi

        # Process event stream and color mode states
        event_stream_status=$(echo "$attributes" | jq -r '.eventStreamStatus // "unknown"')
        if [[ "$event_stream_status" == "connected" || "$event_stream_status" == "disconnected" ]]; then
            value=$([[ "$event_stream_status" == "connected" ]] && echo "1" || echo "0")
            echo "hubitat_device_event_stream_status{$labels} $value"
        fi

        color_mode=$(echo "$attributes" | jq -r '.colorMode // "unknown"')
        case "$color_mode" in
            CT) echo "hubitat_device_color_mode{$labels} 1" ;;
            RGB) echo "hubitat_device_color_mode{$labels} 2" ;;
            RGBW) echo "hubitat_device_color_mode{$labels} 3" ;;
        esac

        illum_state=$(echo "$attributes" | jq -r '.illumState // "unknown"')
        if [[ "$illum_state" == "bright" || "$illum_state" == "dark" ]]; then
            value=$([[ "$illum_state" == "bright" ]] && echo "1" || echo "0")
            echo "hubitat_device_illum_state{$labels} $value"
        fi

        human_motion_state=$(echo "$attributes" | jq -r '.humanMotionState // "unknown"')
        case "$human_motion_state" in
            none)        echo "hubitat_device_human_motion_state{$labels} 0" ;;
            moving)      echo "hubitat_device_human_motion_state{$labels} 1" ;;
            small_move)  echo "hubitat_device_human_motion_state{$labels} 2" ;;
            standing)    echo "hubitat_device_human_motion_state{$labels} 3" ;;
        esac

        effect=$(echo "$attributes" | jq -r '.effect // "unknown"')
        if [[ "$effect" != "unknown" && "$effect" != "null" ]]; then
            value=$([[ "$effect" == "none" ]] && echo "0" || echo "1")
            echo "hubitat_device_effect{$labels} $value"
        fi

        # Process PM2.5
        pm25=$(echo "$attributes" | jq -r '.pm25')
        if [[ "$pm25" != "null" && "$pm25" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_pm25{$labels} $pm25"
        fi

        # Process PM10
        pm10=$(echo "$attributes" | jq -r '.pm10')
        if [[ "$pm10" != "null" && "$pm10" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_pm10{$labels} $pm10"
        fi

        # Process VOC (fallback for different drivers)
        voc=$(echo "$attributes" | jq -r '.voc // .sensirionVOCindex')
        if [[ "$voc" != "null" && "$voc" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_voc{$labels} $voc"
        fi

        # Process carbon dioxide
        carbon_dioxide=$(echo "$attributes" | jq -r '.carbonDioxide')
        if [[ "$carbon_dioxide" != "null" && "$carbon_dioxide" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_carbon_dioxide{$labels} $carbon_dioxide"
        fi

        # Process carbon monoxide
        carbon_monoxide=$(echo "$attributes" | jq -r '.carbonMonoxide')
        if [[ "$carbon_monoxide" != "null" && "$carbon_monoxide" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_carbon_monoxide{$labels} $carbon_monoxide"
        fi

        # Process thermostat setpoints
        thermostat_setpoint=$(echo "$attributes" | jq -r '.thermostatSetpoint')
        if [[ "$thermostat_setpoint" != "null" && "$thermostat_setpoint" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_thermostat_setpoint{$labels} $thermostat_setpoint"
        fi

        heating_setpoint=$(echo "$attributes" | jq -r '.heatingSetpoint')
        if [[ "$heating_setpoint" != "null" && "$heating_setpoint" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_heating_setpoint{$labels} $heating_setpoint"
        fi

        cooling_setpoint=$(echo "$attributes" | jq -r '.coolingSetpoint')
        if [[ "$cooling_setpoint" != "null" && "$cooling_setpoint" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_cooling_setpoint{$labels} $cooling_setpoint"
        fi

        # Process scheduler setpoints
        scheduled_setpoint=$(echo "$attributes" | jq -r '.scheduledSetpoint')
        if [[ "$scheduled_setpoint" != "null" && "$scheduled_setpoint" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_scheduled_setpoint{$labels} $scheduled_setpoint"
        fi

        next_scheduled_setpoint=$(echo "$attributes" | jq -r '.nextScheduledSetpoint')
        if [[ "$next_scheduled_setpoint" != "null" && "$next_scheduled_setpoint" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_next_scheduled_setpoint{$labels} $next_scheduled_setpoint"
        fi

        window_function=$(echo "$attributes" | jq -r '.windowFunction // "unknown"')
        if [[ "$window_function" == "active" || "$window_function" == "inactive" ]]; then
            value=$([[ "$window_function" == "active" ]] && echo "1" || echo "0")
            echo "hubitat_device_window_function{$labels} $value"
        fi

        thermostat_mode=$(echo "$attributes" | jq -r '.thermostatMode // "unknown"')
        case "$thermostat_mode" in
            off)                    echo "hubitat_device_thermostat_mode{$labels} 0" ;;
            heat)                   echo "hubitat_device_thermostat_mode{$labels} 1" ;;
            cool)                   echo "hubitat_device_thermostat_mode{$labels} 2" ;;
            auto)                   echo "hubitat_device_thermostat_mode{$labels} 3" ;;
            "fan only"|fan_only)    echo "hubitat_device_thermostat_mode{$labels} 4" ;;
            "emergency heat"|emergency_heat) echo "hubitat_device_thermostat_mode{$labels} 5" ;;
        esac

        thermostat_operating_state=$(echo "$attributes" | jq -r '.thermostatOperatingState // "unknown"')
        case "$thermostat_operating_state" in
            idle)                        echo "hubitat_device_thermostat_operating_state{$labels} 0" ;;
            heating)                     echo "hubitat_device_thermostat_operating_state{$labels} 1" ;;
            cooling)                     echo "hubitat_device_thermostat_operating_state{$labels} 2" ;;
            "fan only"|fan_only)         echo "hubitat_device_thermostat_operating_state{$labels} 3" ;;
            "pending cool"|pending_cool) echo "hubitat_device_thermostat_operating_state{$labels} 4" ;;
            "pending heat"|pending_heat) echo "hubitat_device_thermostat_operating_state{$labels} 5" ;;
        esac

        thermostat_setpoint_mode=$(echo "$attributes" | jq -r '.thermostatSetpointMode // "unknown"')
        case "$thermostat_setpoint_mode" in
            followSchedule|follow_schedule)        echo "hubitat_device_thermostat_setpoint_mode{$labels} 0" ;;
            temporaryOverride|temporary_override)  echo "hubitat_device_thermostat_setpoint_mode{$labels} 1" ;;
            permanentOverride|permanent_override)  echo "hubitat_device_thermostat_setpoint_mode{$labels} 2" ;;
        esac

        next_scheduled_time=$(echo "$attributes" | jq -r '.nextScheduledTime // "unknown"')
        if [[ "$next_scheduled_time" != "unknown" && "$next_scheduled_time" != "null" ]]; then
            epoch=$(date -d "$next_scheduled_time" +%s 2>/dev/null)
            if [[ "$epoch" =~ ^[0-9]+$ ]]; then
                echo "hubitat_device_next_scheduled_time_epoch{$labels} $epoch"
            fi
        fi

        thermostat_setpoint_until=$(echo "$attributes" | jq -r '.thermostatSetpointUntil // "unknown"')
        if [[ "$thermostat_setpoint_until" != "unknown" && "$thermostat_setpoint_until" != "null" ]]; then
            epoch=$(date -d "$thermostat_setpoint_until" +%s 2>/dev/null)
            if [[ "$epoch" =~ ^[0-9]+$ ]]; then
                echo "hubitat_device_thermostat_setpoint_until_epoch{$labels} $epoch"
            fi
        fi

        # Process weather and pressure metrics
        air_pressure=$(echo "$attributes" | jq -r '.airPressure // .pressure')
        if [[ "$air_pressure" != "null" && "$air_pressure" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_air_pressure{$labels} $air_pressure"
        fi

        wind_speed=$(echo "$attributes" | jq -r '.windSpeed')
        if [[ "$wind_speed" != "null" && "$wind_speed" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_wind_speed{$labels} $wind_speed"
        fi

        wind_direction=$(echo "$attributes" | jq -r '.windDirection')
        if [[ "$wind_direction" != "null" && "$wind_direction" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_wind_direction{$labels} $wind_direction"
        fi

        # Process presence and occupancy timing metrics
        occupied_time=$(echo "$attributes" | jq -r '.occupiedTime')
        if [[ "$occupied_time" != "null" && "$occupied_time" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_occupied_time{$labels} $occupied_time"
        fi

        absence_time=$(echo "$attributes" | jq -r '.absenceTime')
        if [[ "$absence_time" != "null" && "$absence_time" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_absence_time{$labels} $absence_time"
        fi

        existance_time=$(echo "$attributes" | jq -r '.existance_time')
        if [[ "$existance_time" != "null" && "$existance_time" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_existance_time{$labels} $existance_time"
        fi

        leave_time=$(echo "$attributes" | jq -r '.leave_time')
        if [[ "$leave_time" != "null" && "$leave_time" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_leave_time{$labels} $leave_time"
        fi

        distance=$(echo "$attributes" | jq -r '.distance')
        if [[ "$distance" != "null" && "$distance" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_distance{$labels} $distance"
        fi

        detection_delay=$(echo "$attributes" | jq -r '.detectionDelay')
        if [[ "$detection_delay" != "null" && "$detection_delay" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_detection_delay{$labels} $detection_delay"
        fi

        static_detection_distance=$(echo "$attributes" | jq -r '.staticDetectionDistance')
        if [[ "$static_detection_distance" != "null" && "$static_detection_distance" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_static_detection_distance{$labels} $static_detection_distance"
        fi

        motion_detection_distance=$(echo "$attributes" | jq -r '.motionDetectionDistance')
        if [[ "$motion_detection_distance" != "null" && "$motion_detection_distance" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_motion_detection_distance{$labels} $motion_detection_distance"
        fi

        small_motion_detection_sensitivity=$(echo "$attributes" | jq -r '.smallMotionDetectionSensitivity')
        if [[ "$small_motion_detection_sensitivity" != "null" && "$small_motion_detection_sensitivity" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_small_motion_detection_sensitivity{$labels} $small_motion_detection_sensitivity"
        fi

        keep_time=$(echo "$attributes" | jq -r '.keepTime')
        if [[ "$keep_time" != "null" && "$keep_time" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_keep_time{$labels} $keep_time"
        fi

        unacknowledged_time=$(echo "$attributes" | jq -r '.unacknowledgedTime')
        if [[ "$unacknowledged_time" != "null" && "$unacknowledged_time" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_unacknowledged_time{$labels} $unacknowledged_time"
        fi

        last_checkin_epoch=$(echo "$attributes" | jq -r '.lastCheckinEpoch')
        if [[ "$last_checkin_epoch" != "null" && "$last_checkin_epoch" =~ ^[0-9]+$ ]]; then
            echo "hubitat_device_last_checkin_epoch{$labels} $last_checkin_epoch"
        else
            last_checkin_time=$(echo "$attributes" | jq -r '.lastCheckinTime // .lastCheckin // "unknown"')
            if [[ "$last_checkin_time" != "unknown" && "$last_checkin_time" != "null" ]]; then
                epoch=$(date -d "$last_checkin_time" +%s 2>/dev/null)
                if [[ "$epoch" =~ ^[0-9]+$ ]]; then
                    echo "hubitat_device_last_checkin_epoch{$labels} $epoch"
                fi
            fi
        fi

        last_drop_epoch=$(echo "$attributes" | jq -r '.lastDropEpoch')
        if [[ "$last_drop_epoch" != "null" && "$last_drop_epoch" =~ ^[0-9]+$ ]]; then
            echo "hubitat_device_last_drop_epoch{$labels} $last_drop_epoch"
        else
            last_drop_time=$(echo "$attributes" | jq -r '.lastDropTime // "unknown"')
            if [[ "$last_drop_time" != "unknown" && "$last_drop_time" != "null" ]]; then
                epoch=$(date -d "$last_drop_time" +%s 2>/dev/null)
                if [[ "$epoch" =~ ^[0-9]+$ ]]; then
                    echo "hubitat_device_last_drop_epoch{$labels} $epoch"
                fi
            fi
        fi

        last_stationary_epoch=$(echo "$attributes" | jq -r '.lastStationaryEpoch')
        if [[ "$last_stationary_epoch" != "null" && "$last_stationary_epoch" =~ ^[0-9]+$ ]]; then
            echo "hubitat_device_last_stationary_epoch{$labels} $last_stationary_epoch"
        else
            last_stationary_time=$(echo "$attributes" | jq -r '.lastStationaryTime // "unknown"')
            if [[ "$last_stationary_time" != "unknown" && "$last_stationary_time" != "null" ]]; then
                epoch=$(date -d "$last_stationary_time" +%s 2>/dev/null)
                if [[ "$epoch" =~ ^[0-9]+$ ]]; then
                    echo "hubitat_device_last_stationary_epoch{$labels} $epoch"
                fi
            fi
        fi

        last_tilt_epoch=$(echo "$attributes" | jq -r '.lastTiltEpoch')
        if [[ "$last_tilt_epoch" != "null" && "$last_tilt_epoch" =~ ^[0-9]+$ ]]; then
            echo "hubitat_device_last_tilt_epoch{$labels} $last_tilt_epoch"
        else
            last_tilt_time=$(echo "$attributes" | jq -r '.lastTiltTime // "unknown"')
            if [[ "$last_tilt_time" != "unknown" && "$last_tilt_time" != "null" ]]; then
                epoch=$(date -d "$last_tilt_time" +%s 2>/dev/null)
                if [[ "$epoch" =~ ^[0-9]+$ ]]; then
                    echo "hubitat_device_last_tilt_epoch{$labels} $epoch"
                fi
            fi
        fi

        last_vibration_epoch=$(echo "$attributes" | jq -r '.lastVibrationEpoch')
        if [[ "$last_vibration_epoch" != "null" && "$last_vibration_epoch" =~ ^[0-9]+$ ]]; then
            echo "hubitat_device_last_vibration_epoch{$labels} $last_vibration_epoch"
        else
            last_vibration_time=$(echo "$attributes" | jq -r '.lastVibrationTime // "unknown"')
            if [[ "$last_vibration_time" != "unknown" && "$last_vibration_time" != "null" ]]; then
                epoch=$(date -d "$last_vibration_time" +%s 2>/dev/null)
                if [[ "$epoch" =~ ^[0-9]+$ ]]; then
                    echo "hubitat_device_last_vibration_epoch{$labels} $epoch"
                fi
            fi
        fi

        rtt=$(echo "$attributes" | jq -r '.rtt')
        if [[ "$rtt" != "null" && "$rtt" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_rtt{$labels} $rtt"
        fi
        
        # Process motion state
        motion=$(echo "$attributes" | jq -r '.motion')
        if [[ "$motion" == "active" || "$motion" == "inactive" ]]; then
            value=$([[ "$motion" == "active" ]] && echo "1" || echo "0")
            echo "hubitat_device_motion{$labels} $value"
        fi

        # Process acceleration state
        acceleration=$(echo "$attributes" | jq -r '.acceleration')
        if [[ "$acceleration" == "active" || "$acceleration" == "inactive" ]]; then
            value=$([[ "$acceleration" == "active" ]] && echo "1" || echo "0")
            echo "hubitat_device_acceleration{$labels} $value"
        fi

        # Process device health and connectivity states
        health_status=$(echo "$attributes" | jq -r '.healthStatus // "unknown"')
        if [[ "$health_status" == "online" || "$health_status" == "offline" ]]; then
            value=$([[ "$health_status" == "online" ]] && echo "1" || echo "0")
            echo "hubitat_device_health_status{$labels} $value"
        fi

        network_status=$(echo "$attributes" | jq -r '.networkStatus // "unknown"')
        if [[ "$network_status" == "connected" || "$network_status" == "disconnected" ]]; then
            value=$([[ "$network_status" == "connected" ]] && echo "1" || echo "0")
            echo "hubitat_device_network_status{$labels} $value"
        fi

        sync_status=$(echo "$attributes" | jq -r '.syncStatus // "unknown"')
        case "$sync_status" in
            Synced|synced)             echo "hubitat_device_sync_status{$labels} 1" ;;
            "Not Synced"|not_synced)  echo "hubitat_device_sync_status{$labels} 0" ;;
        esac

        status=$(echo "$attributes" | jq -r '.status // "unknown"')
        if [[ "$status" == "Online" || "$status" == "Offline" ]]; then
            value=$([[ "$status" == "Online" ]] && echo "1" || echo "0")
            echo "hubitat_device_status{$labels} $value"
        fi

        status_upper=$(echo "$attributes" | jq -r '.Status // "unknown"')
        case "$status_upper" in
            clear)             echo "hubitat_device_status_upper{$labels} 1" ;;
            Complete:Success)  echo "hubitat_device_status_upper{$labels} 2" ;;
            Complete:Timeout)  echo "hubitat_device_status_upper{$labels} 0" ;;
        esac

        hub_mesh_disabled=$(echo "$attributes" | jq -r '.hubMeshDisabled // "unknown"')
        if [[ "$hub_mesh_disabled" == "true" || "$hub_mesh_disabled" == "false" ]]; then
            value=$([[ "$hub_mesh_disabled" == "true" ]] && echo "1" || echo "0")
            echo "hubitat_device_hub_mesh_disabled{$labels} $value"
        fi

        sensor_status=$(echo "$attributes" | jq -r '.sensorStatus // "unknown"')
        case "$sensor_status" in
            Stationary|inactive) echo "hubitat_device_sensor_status{$labels} 0" ;;
            Active|Moving|active) echo "hubitat_device_sensor_status{$labels} 1" ;;
        esac

        # Process presence state
        presence=$(echo "$attributes" | jq -r '.presence // "unknown"')
        if [[ "$presence" == "present" || "$presence" == "not present" ]]; then
            value=$([[ "$presence" == "present" ]] && echo "1" || echo "0")
            echo "hubitat_device_presence{$labels} $value"
        fi

        # Process occupancy state
        occupancy=$(echo "$attributes" | jq -r '.occupancy // "unknown"')
        if [[ "$occupancy" == "occupied" || "$occupancy" == "clear" || "$occupancy" == "active" || "$occupancy" == "inactive" ]]; then
            value=$([[ "$occupancy" == "occupied" || "$occupancy" == "active" ]] && echo "1" || echo "0")
            echo "hubitat_device_occupancy{$labels} $value"
        fi
        
        # Process contact state
        contact=$(echo "$attributes" | jq -r '.contact')
        if [[ "$contact" == "open" || "$contact" == "closed" ]]; then
            value=$([[ "$contact" == "open" ]] && echo "1" || echo "0")
            echo "hubitat_device_contact{$labels} $value"
        fi

        # Process water leak state
        water=$(echo "$attributes" | jq -r '.water // "unknown"')
        if [[ "$water" == "wet" || "$water" == "dry" || "$water" == "detected" || "$water" == "clear" ]]; then
            value=$([[ "$water" == "wet" || "$water" == "detected" ]] && echo "1" || echo "0")
            echo "hubitat_device_water{$labels} $value"
        fi

        # Process tamper state
        tamper=$(echo "$attributes" | jq -r '.tamper // "unknown"')
        if [[ "$tamper" == "detected" || "$tamper" == "clear" || "$tamper" == "active" || "$tamper" == "inactive" ]]; then
            value=$([[ "$tamper" == "detected" || "$tamper" == "active" ]] && echo "1" || echo "0")
            echo "hubitat_device_tamper{$labels} $value"
        fi

        # Process button and interaction event counters
        pushed=$(echo "$attributes" | jq -r '.pushed')
        if [[ "$pushed" != "null" && "$pushed" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_pushed{$labels} $pushed"
        fi

        held=$(echo "$attributes" | jq -r '.held')
        if [[ "$held" != "null" && "$held" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_held{$labels} $held"
        fi

        double_tapped=$(echo "$attributes" | jq -r '.doubleTapped')
        if [[ "$double_tapped" != "null" && "$double_tapped" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_double_tapped{$labels} $double_tapped"
        fi

        released=$(echo "$attributes" | jq -r '.released')
        if [[ "$released" != "null" && "$released" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_released{$labels} $released"
        fi

        taps=$(echo "$attributes" | jq -r '.taps')
        if [[ "$taps" != "null" && "$taps" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "hubitat_device_taps{$labels} $taps"
        fi

        action=$(echo "$attributes" | jq -r '.action // "unknown"')
        case "$action" in
            wakeup)           echo "hubitat_device_action{$labels} 1" ;;
            shake)            echo "hubitat_device_action{$labels} 2" ;;
            flip_to_side)     echo "hubitat_device_action{$labels} 3" ;;
            tap_twice)        echo "hubitat_device_action{$labels} 4" ;;
            rotate_left)      echo "hubitat_device_action{$labels} 5" ;;
            rotate_right)     echo "hubitat_device_action{$labels} 6" ;;
            start_rotating)   echo "hubitat_device_action{$labels} 7" ;;
            rotation_stopped) echo "hubitat_device_action{$labels} 8" ;;
            1_min_inactivity) echo "hubitat_device_action{$labels} 9" ;;
        esac

        poked=$(echo "$attributes" | jq -r '.poked // "unknown"')
        if [[ "$poked" =~ :([0-9]+)$ ]]; then
            echo "hubitat_device_poked_side{$labels} ${BASH_REMATCH[1]}"
        fi
    done
}

# Simple HTTP server using socat
serve_metrics() {
    local metrics_file
    metrics_file=$(mktemp)
    trap 'rm -f "$metrics_file"; [[ -n "$socat_pid" ]] && kill $socat_pid 2>/dev/null; exit' INT TERM EXIT
    
    log "Server starting on port 5000"
    
    # Start socat in the background to continuously listen
    socat TCP-LISTEN:5000,reuseaddr,fork EXEC:"cat $metrics_file" &
    socat_pid=$!
    
    # Main loop to update metrics
    while true; do
        # Generate fresh metrics
        metrics=$(generate_metrics 2>"$metrics_file.err")
        if [ $? -eq 0 ]; then
            log "Metrics generated successfully"
            # Store metrics in file
            echo -ne "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n$metrics" > "$metrics_file"
        else
            log "Error generating metrics: $(cat "$metrics_file.err")"
            echo -ne "HTTP/1.1 500 Internal Server Error\r\nContent-Type: text/plain\r\n\r\nError generating metrics" > "$metrics_file"
        fi
        
        # Check if socat is still running
        if ! kill -0 $socat_pid 2>/dev/null; then
            log "Socat process died, restarting..."
            socat TCP-LISTEN:5000,reuseaddr,fork EXEC:"cat $metrics_file" &
            socat_pid=$!
        fi
        
        # Wait before next update
        sleep 15
    done
}

# Check for required commands
for cmd in curl jq socat base64; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is required but not installed."
        exit 1
    fi
done

# Check for required environment variables
if [ -z "$HE_URI" ] || [ -z "$HE_TOKEN" ]; then
    echo "Error: HE_URI and HE_TOKEN must be set in environment or .env file"
    exit 1
fi

# Start the server
log "Starting Hubitat Prometheus exporter on port 5000..."
serve_metrics
