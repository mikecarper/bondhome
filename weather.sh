#!/bin/bash

bond_db_file="${HOME}/.bond/db.json"
current_weather_json="${HOME}/.bond/weather.json"
current_weather_txt="${HOME}/.bond/weather.txt"
current_solar_json="${HOME}/.bond/solar.json"
updateRan=0
bond_token=''
ip_address=''
forcerefresh=0
current_hour=$( date +'%Y-%m-%dT%H:' )


while getopts "F" opt; do
  case $opt in
    F)
      forcerefresh=1
      ;;
    \?)
      echo "Invalid option: -$OPTARG"
      exit 1
      ;;
  esac
done


if [[ -s "${current_weather_txt}" && "${forcerefresh}" -eq 0 ]]
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
    unit=${1}
    if [[ -z "${unit}" ]]
    then
        echo "0.00"
        return
    fi
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

GetClosestTime() {
    timestamps=${1}
    target_timestamp=$(date +%s)
    for timestamp in $timestamps
    do
        diff=$((timestamp - target_timestamp))
        if [[ -z $closest_timestamp || $diff -lt $closest_diff ]]
        then
            closest_timestamp=$timestamp
            closest_diff=$diff
        fi
    done
    echo "${closest_timestamp}"
}

GetValueOfClosetTime() {
    input=${1}
    # Convert dates to unix time
    inputValues=$( echo "${input}" | cut -d " " -f 1 )
    inputTimes=$( echo "${input}" | cut -d " " -f 2 | awk -F"[-T:]" '{print mktime(sprintf("%04d %02d %02d %02d %02d %02d", $1, $2, $3, $4, $5, $6))}' )
    inputTimestamp=$( GetClosestTime "${inputTimes}" )
    inputCombinedData=$( paste -d ' ' <(echo "${inputValues}") <(echo "${inputTimes}") )
    input=$( echo "${inputCombinedData}" | grep "${inputTimestamp}" | cut -d " " -f 1 )
    echo "${input}"
}

BondGetTime
coordinates=$(maidenhead_to_lat_long "$maidenhead")
getSunriseSunset "${coordinates}" "${formatted_offset}"

# Get weather data.
if [[ -s "${current_weather_json}" || "${forcerefresh}" -eq 1 ]]
then
    if [[ $( find "${current_weather_json}" -mmin -15 | wc -l ) -eq 0 || "${forcerefresh}" -eq 1 ]]
    then
        echo "Updating weather info as it is older than 15 minutes."
        url=$( curl -s "https://api.weather.gov/points/${coordinates}" | jq -r '.properties.forecastGridData')
        echo "Weather URL: ${url}"
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
    weather=$( cat "$current_weather_json" )
fi


# Get sun data once every 8 hours.
current_hour=$(date +%H)
current_minute=$(date +%M)
if (( $current_hour % 8 == 0 )) && (( $current_minute < 10 ))
then
    lat=$( echo "$coordinates" | cut -d ',' -f 1 )
    long=$( echo "$coordinates" | cut -d ',' -f 2 )
    echo "https://api.forecast.solar/estimate/${lat}/${long}/0/0/1"
    solar=$( curl -s "https://api.forecast.solar/estimate/${lat}/${long}/0/0/1" )
    result=$(echo "$response" | jq -r '.result')
    if [[ "$result" != "null" ]]
    then
        echo "$solar" > "${current_solar_json}"
    fi
fi

if [[ -z "${solar}" ]]
then
    solar=$( cat "${current_solar_json}" )
fi

searchDate=$( date +'%Y-%m-%d' )
wattHoursDay=$( echo "${solar}" | jq -r --arg searchDate "${searchDate}" '.result.watt_hours_day[$searchDate]' )

updateTime=$( echo "${weather}" | jq -r '.updateTime' | cut -d '+' -f 1 )
validTime=$( echo "${weather}" | jq -r '.validTimes' | cut -d '+' -f 1 )

searchTime=$( date +'%Y-%m-%dT%H:' )
searchDate=$( date +'%Y-%m-%dT' )



temperatureNow=$( echo "${weather}" | jq --arg searchDate "${searchDate}" -r '.temperature.values[] | select(.validTime | startswith($searchDate)) | "\(.value) \(.validTime)"' | cut -d "+" -f 1 )
temperatureNow=$( GetValueOfClosetTime "${temperatureNow}" )
temperatureNowUnit=$( echo "${weather}" | jq -r '.temperature.uom' | tail -c 2 | tr -d '[:space:]' )
#echo "temperatureNow ${temperatureNow} ${temperatureNowUnit}"

temperatureMax=$( echo "${weather}" | jq --arg searchDate "${searchDate}" -r '.maxTemperature.values[] | select(.validTime | startswith($searchDate)) | .value' )
temperatureMaxUnit=$( echo "${weather}" | jq -r '.maxTemperature.uom' | tail -c 2 | tr -d '[:space:]' )
#echo "temperatureMax ${temperatureMax} ${temperatureMaxUnit}"

temperatureMin=$( echo "${weather}" | jq --arg searchDate "${searchDate}" -r '.minTemperature.values[] | select(.validTime | startswith($searchDate)) | .value' )
temperatureMinUnit=$( echo "${weather}" | jq -r '.minTemperature.uom' | tail -c 2 | tr -d '[:space:]' )
#echo "temperatureMin ${temperatureMin} ${temperatureMinUnit}"

heatIndexNow=$( echo "${weather}" | jq --arg searchTime "${searchTime}" -r '.heatIndex.values[] | select(.validTime | startswith($searchTime)) | .value // empty' | tr -d '[:space:]' )
heatIndexNowUnit=$( echo "${weather}" | jq -r '.heatIndex.uom' | tail -c 2 | tr -d '[:space:]' )
#echo "heatIndexNow ${heatIndexNow} ${heatIndexNowUnit}"

apparentTemperatureNow=$( echo "${weather}" | jq --arg searchDate "${searchDate}" -r '.apparentTemperature.values[]  | select(.validTime | startswith($searchDate)) | "\(.value) \(.validTime)"' | cut -d "+" -f 1 )
apparentTemperatureNow=$( GetValueOfClosetTime "${apparentTemperatureNow}" )
apparentTemperatureNowUnit=$( echo "${weather}" | jq -r '.apparentTemperature.uom' | tail -c 2 | tr -d '[:space:]' )
#echo "apparentTemperatureNow ${apparentTemperatureNow} ${apparentTemperatureNowUnit}"

relativeHumidity=$( echo "${weather}" | jq --arg searchDate "${searchDate}" -r '.relativeHumidity.values[]  | select(.validTime | startswith($searchDate)) | "\(.value) \(.validTime)"' | cut -d "+" -f 1 )
relativeHumidity=$( GetValueOfClosetTime "${relativeHumidity}" )
#echo "relativeHumidity ${relativeHumidity}"

skyCoverNow=$( echo "${weather}" | jq --arg searchDate "${searchDate}" -r '.skyCover.values[]  | select(.validTime | startswith($searchDate)) | "\(.value) \(.validTime)"' | cut -d "+" -f 1 )
skyCoverNow=$( GetValueOfClosetTime "${skyCoverNow}" )
#echo "skyCoverNow ${skyCoverNow}"

probabilityOfPrecipitationNow=$( echo "${weather}" | jq --arg searchTime "${searchTime}" -r '.probabilityOfPrecipitation.values[] | select(.validTime | startswith($searchTime)) | .value // empty' | tr -d '[:space:]' )
if [[ -z "${probabilityOfPrecipitationNow}" ]]
then
    probabilityOfPrecipitationNow=0
fi
#echo "probabilityOfPrecipitationNow ${probabilityOfPrecipitationNow}"

quantitativePrecipitationNow=$( echo "${weather}" | jq --arg searchTime "${searchTime}" -r '.quantitativePrecipitation.values[] | select(.validTime | startswith($searchTime)) | .value // empty' | tr -d '[:space:]' )
quantitativePrecipitationNowUnit=$( echo "${weather}" | jq -r '.quantitativePrecipitation.uom // empty' | tr -d '[:space:]' | tail -c 2 )
#echo "quantitativePrecipitationNow ${quantitativePrecipitationNow} ${quantitativePrecipitationNowUnit}"

windSpeedNow=$( echo "${weather}" | jq --arg searchDate "${searchDate}" -r '.windSpeed.values[] | select(.validTime | startswith($searchDate)) | "\(.value) \(.validTime)"' | cut -d "+" -f 1 )
windSpeedNow=$( GetValueOfClosetTime "${windSpeedNow}" )
windSpeedNowUnit=$( echo "${weather}" | jq -r '.windSpeed.uom' | cut -d ":" -f2 | sed 's/_h-1/\/h/g' )
#echo "windSpeedNow ${windSpeedNow} ${windSpeedNowUnit}"

windGustNow=$( echo "${weather}" | jq --arg searchDate "${searchDate}" -r '.windGust.values[] | select(.validTime | startswith($searchDate)) | "\(.value) \(.validTime)"' | cut -d "+" -f 1 )
windGustNow=$( GetValueOfClosetTime "${windGustNow}" )
windGustNowUnit=$( echo "${weather}" | jq -r '.windGust.uom' | cut -d ":" -f2 | sed 's/_h-1/\/h/g' )
#echo "windGustNow ${windGustNow} ${windGustNowUnit}"

transportWindSpeedNow=$( echo "${weather}" | jq --arg searchDate "${searchDate}" -r '.transportWindSpeed.values[] | select(.validTime | startswith($searchDate)) | "\(.value) \(.validTime)"' | cut -d "+" -f 1 )
transportWindSpeedNow=$( GetValueOfClosetTime "${transportWindSpeedNow}" )
transportWindSpeedNowUnit=$( echo "${weather}" | jq -r '.transportWindSpeed.uom' | cut -d ":" -f2 | sed 's/_h-1/\/h/g' )
#echo "transportWindSpeedNow ${transportWindSpeedNow} ${transportWindSpeedNowUnit}"


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

max_wind_speed=$(echo -e "${windSpeedNow}\n${windGustNow}\n${transportWindSpeedNow}" | grep -oE '[0-9.]+' | awk '{print $1}' | sort -nr | head -1)

current_time=$( date +"%H:%M" )
unix_time_now=$( date +%s )
unix_validTime=$( echo "${validTime}" | awk -F"[-T:]" '{print mktime(sprintf("%04d %02d %02d %02d %02d %02d", $1, $2, $3, $4, $5, $6))}' )
unix_updateTime=$( echo "${updateTime}" | awk -F"[-T:]" '{print mktime(sprintf("%04d %02d %02d %02d %02d %02d", $1, $2, $3, $4, $5, $6))}' )
unix_sunrise=$( echo "${sunrise} ${tzOffest}" | awk '{print $2 $3}' )
unix_sunrise=$( date -d "${unix_sunrise}" +%s )
unix_sunset=$( echo "${sunset} ${tzOffest}" | awk '{print $2 $3}' )
unix_sunset=$( date -d "${unix_sunset}" +%s )
unix_midday=$( echo "${midday} ${tzOffest}" | awk '{print $2 $3}' )
unix_midday=$( date -d "${unix_midday}" +%s )



output=$(cat <<EOF
Coordinates: ${coordinates}
Valid Weather Time: ${validTime} ${unix_validTime}
Weather Data Good Until: ${updateTime} ${unix_updateTime}
Generated time: ${current_time} ${tzOffest} ${unix_time_now}
${sunrise} ${tzOffest} ${unix_sunrise}
${sunset} ${tzOffest} ${unix_sunset}
${midday} ${tzOffest} ${unix_midday}

Heat Index: ${heatIndexNow} F
Apparent Temperature: ${apparentTemperatureNow} ${apparentTemperatureNowUnit}
Temperature: ${temperatureNow} ${temperatureNowUnit}
Max Temperature: ${temperatureMax} ${temperatureMaxUnit}
Min Temperature: ${temperatureMin} ${temperatureMinUnit}
Relative Humidity: ${relativeHumidity} %

Sky Cover: ${skyCoverNow} %
Solar Watt Hours Today: ${wattHoursDay} (1kw system)
Probability of Precipitation: ${probabilityOfPrecipitationNow} %
Quantitative Precipitation: ${quantitativePrecipitationNow} ${quantitativePrecipitationNowUnit}

Wind: ${windSpeedNow} ${windSpeedNowUnit}
Wind Gust: ${windGustNow} ${windGustNowUnit}
Transport Wind: ${transportWindSpeedNow} ${transportWindSpeedNowUnit}
Max Wind: ${max_wind_speed} ${windSpeedNowUnit}
EOF
)

echo "$output" > "${current_weather_txt}"
echo "$output"
