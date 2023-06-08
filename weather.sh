#!/bin/bash

bond_db_file="${HOME}/.bond/db.json"
current_weather_json="${HOME}/.bond/weather.json"
current_weather_txt="${HOME}/.bond/weather.txt"
updateRan=0
bond_token=''
ip_address=''

if [[ -s "${current_weather_txt}" ]]
then
    if [[ $( find "${current_weather_txt}" -mmin -20 | wc -l ) -eq 1 ]]
    then
        cat "${current_weather_txt}"
        exit
    fi
fi

# Make sure we have jq installed.
if [[ -z "$( command -v jq )" ]]
then
    if [[ "${updateRan}" -eq 0 ]]
    then
        sudo apt update
        updateRan=1
    fi
    echo "Installing jq"
    sudo apt install jq -y
    echo
fi

# Make sure we have bc installed.
if [[ -z "$( command -v bc )" ]]
then
    if [[ "${updateRan}" -eq 0 ]]
    then
        sudo apt update
        updateRan=1
    fi
    echo "Installing bc"
    sudo apt install bc -y
    echo
fi


# Make sure we have hdate installed.
if [[ -z "$( command -v hdate )" ]]
then
    if [[ "${updateRan}" -eq 0 ]]
    then
        sudo apt update
        updateRan=1
    fi
    echo "Installing hdate"
    sudo apt install hdate -y
    echo
fi

BondSelect () {
    if [[ -r "${bond_db_file}" ]]
    then
        echo "Reading ${bond_db_file} file"
        selected_bondid=$( jq -r '.selected_bondid // empty' < "$bond_db_file" )
    fi
}

BondGetIPFromFile () {
    if [[ -z "${ip_address}" ]]
    then
        if [[ -r "${bond_db_file}" ]]
        then
            ip_address=$( jq -r ".bonds.${selected_bondid}.ip // empty" < "$bond_db_file" )
        fi
    fi
}


BondTokenGet() {
    # JSON
    if [[ -z "${bond_token}" ]]
    then
        if [[ -r "$bond_db_file" ]]
        then
            bond_token=$( jq -r ".bonds.${selected_bondid}.token // empty" < "$bond_db_file" )
        fi
    fi
}

BondGetTime() {
    BondSelect
    BondGetIPFromFile
    BondTokenGet

    local bondTime
    local timezone

    bondTime=$( curl -s --max-time 5 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/sys/time" )
    maidenhead=$( echo "${bondTime}" | jq -r '.grid //empty' )

    timezone=$( echo "${bondTime}" | jq -r '.tz //empty' )
    tzOffest=$( TZ=":${timezone}" date +%:z )
    # Replace "+0" with "+"
    formatted_offset=$(echo "$tzOffest" | sed 's/+0/+/g' | sed 's/-0/-/g')
}

maidenhead_to_lat_long() {

    local grid="$1"

    # Initialize variables
    local latmult=10
    local lonmult=20
    local lat=-90
    local lon=-180

    # Initialize initial_String with L and 5
    local initial_String="LL55LL55LL"

    # Replace the first characters of initial_String with the grid value
    local initial_String="${grid}${initial_String:${#grid}}"

    for ((i = 0; i < ${#initial_String}; i+=2)); do
        if (( (i+1) % 4 == 1 )); then
            if (( i > 0 )); then
                lonmult=$(bc <<< "scale=8; $lonmult / 24")
                latmult=$(bc <<< "scale=8; $latmult / 24")
            fi

            char1="${initial_String:i:1}"
            char2="${initial_String:i+1:1}"
            char1_rank=$(printf "%d" "'${char1^^}'")
            char2_rank=$(printf "%d" "'${char2^^}'")

            lon=$(bc <<< "scale=8; $lon + $lonmult * ($char1_rank - 65)")
            lat=$(bc <<< "scale=8; $lat + $latmult * ($char2_rank - 65)")
        else
            latmult=$(bc <<< "scale=8; $latmult / 10")
            lonmult=$(bc <<< "scale=8; $lonmult / 10")

            char1="${initial_String:i:1}"
            char2="${initial_String:i+1:1}"

            lon=$(bc <<< "scale=8; $lon + $lonmult * $char1")
            lat=$(bc <<< "scale=8; $lat + $latmult * $char2")
        fi
    done

    printf "%.4f,%.4f" "${lat}" "${lon}"
}

getSunriseSunset() {
    coordinates=$1
    formatted_offset=$2

    lat=$(echo "${coordinates}" | cut -d',' -f1)
    long=$(echo "${coordinates}" | cut -d',' -f2)
    hdateOutput=$( hdate -z "${formatted_offset}" -l "${lat}" -L "${long}" -t)
    sunrise=$( echo "${hdateOutput}" | grep 'sunrise' )
    sunset=$( echo "${hdateOutput}" | grep 'sunset' )
    midday=$( echo "${hdateOutput}" | grep 'midday' )


}

cToF() {
    printf "%.0f" "$( bc <<< "scale=2; 9/5 * $1 + 32" )"
}

fToC() {
    printf "%.0f" "$( bc <<< "scale=2; ($1 - 32) * 5 / 9" )"
}

mmToInch() {
    printf "%.2f" "$( bc <<< "scale=4; $1 / 25.4")"
}

kphToMph() {
    # Conversion factor: 1 km/h = 0.621371 mph
    local conversion_factor=0.621371

    # Perform the conversion using bc
    printf "%.1f" "$(echo "scale=2; $1 * $conversion_factor" | bc)"
}

calculate_heat_index_f() {
    local temperature=$1
    local humidity=$2

    local hi1
    local hi2
    local c1
    local adjustment
    hi1=$( echo "scale=8; 0.5 * (${temperature} + 61.0 + ((${temperature}-68.0) * 1.2) + ($humidity * 0.094))" | bc -l )
    if [[ $(echo "${hi1} < 80" | bc -l) ]]
    then
        printf "%.0f" "${hi1}"
        return
    fi

    hi2=$( echo "scale=8; -42.379 + (2.04901523 * $temperature) + (10.14333127 * $humidity) - (0.22475541 * $temperature * $humidity) - (0.00683783 * $temperature * $temperature) - (0.05481717 * $humidity * $humidity) + (0.00122874 * $temperature * $temperature * $humidity) + (0.00085282 * $temperature * $humidity * $humidity) - (0.00000199 * $temperature * $temperature * $humidity * $humidity )" | bc -l )

    if [[ $( echo "${humidity} < 13" | bc -l ) && $( echo "${temperature} > 80" | bc -l ) && $( echo "${temperature} < 112" | bc -l ) ]]
    then
        c1=$( echo "($temperature - 95)" | bc )
        adjustment=$(echo "scale=8; ((13 - $humidity) / 4) * sqrt((17 - ${c1#-}) / 17)" | bc -l)
        hi2=$( echo "${hi2} - ${adjustment}" | bc -l )
        printf "%.0f" "${hi2}"
        return
    fi

    if [[ $( echo "${humidity} > 85" | bc -l ) && $( echo "${temperature} > 80" | bc -l ) && $( echo "${temperature} < 87" | bc -l ) ]]
    then
        adjustment=$(echo "scale=8; (($humidity - 85) / 10) * ((87 - $temperature) / 5)" | bc -l)
        hi2=$( echo "${hi2} + ${adjustment}" | bc -l )
        printf "%.0f" "${hi2}"
        return
    fi

    printf "%.0f" "${hi2}"
}

BondGetTime
coordinates=$(maidenhead_to_lat_long "$maidenhead")
getSunriseSunset "${coordinates}" "${formatted_offset}"


if [[ -s "${current_weather_json}" ]]
then
    if [[ $( find "${current_weather_json}" -mmin -15 | wc -l ) -eq 0 ]]
    then
        echo "Updating weather info as it is older than 15 minutes."
        url=$( curl -s "https://api.weather.gov/points/${coordinates}" | jq -r '.properties.forecastGridData')
        if [[ -n "${url}" ]]
        then
            weather=$( curl -s "${url}" | jq '.properties' )
            if [[ -n "${weather}" ]]
            then
                echo "${weather}" > "${current_weather_json}"
            fi
        fi
    fi
fi

if [[ -z "${weather}" ]]
then
    weather=$(cat "$current_weather_json")
fi


temperatureNow=$( echo "${weather}" | jq -r '.temperature.values[0].value' )
temperatureNowUnit=$( echo "${weather}" | jq -r '.temperature.uom' | tail -c 2 | tr -d '[:space:]' )

temperatureMax=$( echo "${weather}" | jq -r '.maxTemperature.values[0].value' )
temperatureMaxUnit=$( echo "${weather}" | jq -r '.maxTemperature.uom' | tail -c 2 | tr -d '[:space:]' )

temperatureMin=$( echo "${weather}" | jq -r '.minTemperature.values[0].value' )
temperatureMinUnit=$( echo "${weather}" | jq -r '.minTemperature.uom' | tail -c 2 | tr -d '[:space:]' )

heatIndexNow=$( echo "${weather}" | jq -r '.heatIndex.values[0].value // empty' | tr -d '[:space:]' )
heatIndexNowUnit=$( echo "${weather}" | jq -r '.heatIndex.uom' | tail -c 2 | tr -d '[:space:]' )

apparentTemperatureNow=$( echo "${weather}" | jq -r '.apparentTemperature.values[0].value' )
apparentTemperatureNowUnit=$( echo "${weather}" | jq -r '.apparentTemperature.uom' | tail -c 2 | tr -d '[:space:]' )

relativeHumidity=$( echo "${weather}" | jq -r '.relativeHumidity.values[0].value' )

skyCoverNow=$( echo "${weather}" | jq -r '.skyCover.values[0].value' )
probabilityOfPrecipitationNow=$( echo "${weather}" | jq -r '.probabilityOfPrecipitation.values[0].value // empty' | tr -d '[:space:]' )

quantitativePrecipitationNow=$( echo "${weather}" | jq -r '.quantitativePrecipitation.values[0].value // empty' | tr -d '[:space:]' )
quantitativePrecipitationNowUnit=$( echo "${weather}" | jq -r '.quantitativePrecipitation.uom // empty' | tr -d '[:space:]' | tail -c 2 )

windSpeedNow=$( echo "${weather}" | jq -r '.windSpeed.values[0].value' )
windSpeedNowUnit=$( echo "${weather}" | jq -r '.windSpeed.uom' | cut -d ":" -f2 | sed 's/_h-1/\/h/g' )

windGustNow=$( echo "${weather}" | jq -r '.windGust.values[0].value' )
windGustNowUnit=$( echo "${weather}" | jq -r '.windGust.uom' | cut -d ":" -f2 | sed 's/_h-1/\/h/g' )

transportWindSpeedNow=$( echo "${weather}" | jq -r '.transportWindSpeed.values[0].value' )
transportWindSpeedNowUnit=$( echo "${weather}" | jq -r '.transportWindSpeed.uom' | cut -d ":" -f2 | sed 's/_h-1/\/h/g' )

# Convert to F from C if needed.
if [[ "${temperatureNowUnit}" == "C" || "${temperatureNowUnit}" == "c" ]]
then
    temperatureNow=$( cToF "${temperatureNow}" )
    temperatureNowUnit="F"
fi
if [[ "${temperatureMaxUnit}" == "C" || "${temperatureMaxUnit}" == "c" ]]
then
    temperatureMax=$( cToF "${temperatureMax}" )
    temperatureMaxUnit="F"
fi
if [[ "${temperatureMinUnit}" == "C" || "${temperatureMinUnit}" == "c" ]]
then
    temperatureMin=$( cToF "${temperatureMin}" )
    temperatureMinUnit="F"
fi
if [[ "${heatIndexNowUnit}" == "C" || "${heatIndexNowUnit}" == "c" ]]
then
    if [[ -n "${heatIndexNow}" ]]
    then
        heatIndexNow=$( cToF "${heatIndexNow}" )
        heatIndexNowUnit="F"
    fi
fi
if [[ "${apparentTemperatureNowUnit}" == "C" || "${apparentTemperatureNowUnit}" == "c" ]]
then
    apparentTemperatureNow=$( cToF "${apparentTemperatureNow}" )
    apparentTemperatureNowUnit="F"
fi

# Convert to mph from km/h.
if [[ "${windSpeedNowUnit}" == "km/h" || "${windSpeedNowUnit}" == "km/h" ]]
then
    windSpeedNow=$( kphToMph "${windSpeedNow}" )
    windSpeedNowUnit="mph"
fi
if [[ "${windGustNowUnit}" == "km/h" || "${windGustNowUnit}" == "km/h" ]]
then
    windGustNow=$( kphToMph "${windGustNow}" )
    windGustNowUnit="mph"
fi
if [[ "${transportWindSpeedNowUnit}" == "km/h" || "${transportWindSpeedNowUnit}" == "km/h" ]]
then
    transportWindSpeedNow=$( kphToMph "${transportWindSpeedNow}" )
    transportWindSpeedNowUnit="mph"
fi

# Convert to in from mm
if [[ "${quantitativePrecipitationNowUnit}" == "mm" ]]
then
    quantitativePrecipitationNow=$( mmToInch "${quantitativePrecipitationNow}" )
    quantitativePrecipitationNowUnit="in"
fi

# Calculate heat index if missing.
if [[ -z "${heatIndexNow}" ]]
then
    heatIndexNow=$( calculate_heat_index_f "${temperatureNow}" "${relativeHumidity}" )
    heatIndexNowUnit="F"
fi

current_time=$(date +"%H:%M")

output=$(cat <<EOF
Generated time: ${current_time}
Coordinates: ${coordinates}
${sunrise}
${sunset}
${midday}

Heat Index: ${heatIndexNow} F
Apparent Temperature: ${apparentTemperatureNow} ${apparentTemperatureNowUnit}
Temperature: ${temperatureNow} ${temperatureNowUnit}
Max Temperature: ${temperatureMax} ${temperatureMaxUnit}
Min Temperature: ${temperatureMin} ${temperatureMinUnit}
Relative Humidity: ${relativeHumidity} %

Sky Cover: ${skyCoverNow} %
Probability of Precipitation: ${probabilityOfPrecipitationNow} %
Quantitative Precipitation: ${quantitativePrecipitationNow} ${quantitativePrecipitationNowUnit}

Wind: ${windSpeedNow} ${windSpeedNowUnit}
Wind Gust: ${windGustNow} ${windGustNowUnit}
Transport Wind: ${transportWindSpeedNow} ${transportWindSpeedNowUnit}
EOF
)

echo "$output" > "${current_weather_txt}"
echo "$output"
