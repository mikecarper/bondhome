#!/bin/bash


bond_db_file="${HOME}/.bond/db.json"
current_airquality_json="${HOME}/.bond/airquality.json"
updateRan=0
bond_token=''
ip_address=''

# Make sure we have jq installed.
if [[ -z "$( command -v jq )" ]]
then
  if [[ "${updateRan}" -eq 0 ]]
  then
    sudo apt update
    updateRan=1
  fi
  #echo "Installing jq"
  sudo apt install jq -y
  echo
fi


BondSelect () {
  if [[ -r "${bond_db_file}" ]]
  then
    #echo "Reading ${bond_db_file} file"
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

urlencode() {
  local string="$1"
  string=${string//%/%25}
  string=${string//:/%3A}
  string=${string//\//%2F}
  string=${string//\?/%3F}
  string=${string//#/%23}
  string=${string//\[/%5B}
  string=${string//\]/%5D}
  string=${string//@/%40}
  string=${string//\!/%21}
  string=${string//\$/%24}
  string=${string//\&/%26}
  string=${string//\'/%27}
  string=${string//\(/%28}
  string=${string//\)/%29}
  string=${string//\*/%2A}
  string=${string//\+/%2B}
  string=${string//\,/%2C}
  string=${string//\;/%3B}
  string=${string//\=/%3D}
  string=${string// /%20}
  echo "$string"
}

getnewdata() {
  BondGetTime
  coordinates=$(maidenhead_to_lat_long "$maidenhead")

  lat=$( echo "$coordinates" | cut -d ',' -f 1 )
  long=$( echo "$coordinates" | cut -d ',' -f 2 )

  today=$(date -d "today" "+%Y-%m-%d")
  tomorrow=$(date -d "tomorrow" "+%Y-%m-%d")
  url_encoded_tz=$( urlencode "${timezone}" )

  url="https://air-quality-api.open-meteo.com/v1/air-quality?latitude=${lat}&longitude=${long}&timezone=${url_encoded_tz}&start_date=${today}&end_date=${tomorrow}&hourly=pm10,pm2_5,carbon_monoxide,nitrogen_dioxide,sulphur_dioxide,ozone,aerosol_optical_depth,dust,uv_index,uv_index_clear_sky"
  #echo "${url}"
  curl -s "${url}" > "${current_airquality_json}"
}

get_air_quality_data() {
  local time="$1"
  echo "${data}" | jq -r --arg time "${time}" '.hourly | select(.time[] == $time) | {pm10: .pm10[], pm2_5: .pm2_5[]}'
}

# Define the breakpoints and corresponding AQI values for each pollutant
declare -A ozone_breakpoints=(
  [0]=0 [0.06]=50 [0.076]=100 [0.096]=150 [0.117]=200 [0.201]=300 [0.385]=400 [0.505]=500
)

declare -A pm25_breakpoints=(
  [0]=0 [12.1]=50 [35.5]=100 [55.5]=150 [150.5]=200 [250.5]=300 [350.5]=400 [500.5]=500
)

declare -A pm10_breakpoints=(
  [0]=0 [54]=50 [154]=100 [254]=150 [354]=200 [424]=300 [504]=400 [604]=500
)

declare -A co_breakpoints=(
  [0]=0 [4.5]=50 [9.5]=100 [12.5]=150 [15.5]=200 [30.5]=300 [40.5]=400 [50.5]=500
)

declare -A no2_breakpoints=(
  [0]=0 [53]=50 [100]=100 [360]=150 [649]=200 [1249]=300 [1649]=400 [2049]=500
)

declare -A so2_breakpoints=(
  [0]=0 [36]=50 [76]=100 [186]=150 [305]=200 [605]=300 [805]=400 [1004]=500
)

# Define the function to calculate the AQI
calculate_aqi() {
  local concentration=$1
  local breakpoints_name=${2}
  local breakpoints=("${@:3}")

  IFS=$'\n' read -d '' -r -a sorted_bp < <(printf '%s\n' "${breakpoints[@]}" | sort -V)
  unset IFS


  local index=0
  local i=0
  for ((i = 0; i < ${#sorted_bp[@]}; i++))
  do
    if (( $(echo "$concentration >= ${sorted_bp[i]}" | bc -l) ))
    then
      index=$i
    else
      break
    fi
  done

  local c_low="${sorted_bp[index]}"
  local c_high="${sorted_bp[index+1]}"
  local level=50
  level=$( eval "echo \${${breakpoints_name}[${c_high}]}" )
  local i_low="$index"
  local i_high=$((index+1))

  local aqi=1
  aqi=$(echo "scale=8; (((${i_high} - ${i_low}) * (${concentration} - ${c_low})) / ((${c_high} - ${c_low}) + ${i_low})) * ${level}" | bc)


  printf "%.0f" "$aqi"
}

# Define the mapping table
declare -A mapping=(
  [0]="0: Good Green"
  [50]="50: Moderate Yellow"
  [100]="100: Unhealthy for Sensitive Groups Orange"
  [150]="150: Unhealthy Red"
  [200]="200: Very Unhealthy Purple"
  [300]="300: Hazardous Maroon"
)

# Function to convert integer to string
convert_int_to_string() {
  local input=$1

  IFS=$'\n' read -d '' -r -a sorted_map < <(printf '%s\n' "${mapping[@]}" | sort -V)
  unset IFS

  local best_value=""
  for key in "${!sorted_map[@]}"
  do
    value="${sorted_map[$key]}"
    number=$(echo "$value" | grep -oE '^[0-9]+')

    if (( $(echo "$input >= ${number}" | bc -l) ))
    then
      best_value=$( echo "${value}" | awk '{$1=""; sub(/^ /, ""); print}' )
    else
      break
    fi
  done


  echo "${best_value}"
}




# Start of program

if [[ $( find "${current_airquality_json}"  -type f -mmin -45 | wc -l ) -eq 0 ]]
then
  getnewdata
fi
data=$( cat "${current_airquality_json}" )


nowtime="$( date +%Y-%m-%dT%H:00 )"
timeindex=$( echo "${data}" | jq -r --arg time "${nowtime}" '.hourly.time | index($time)' )

if [[ -z "${timeindex}" ]]
then
  getnewdata
  data=$( cat "${current_airquality_json}" )
  timeindex=$( echo "${data}" | jq -r --arg time "${nowtime}" '.hourly.time | index($time)' )
fi
pm10=$(echo "$data" | jq -r --arg timeindex "${timeindex}" '.hourly | .pm10[$timeindex | tonumber]')
pm25=$(echo "$data" | jq -r --arg timeindex "${timeindex}" '.hourly | .pm2_5[$timeindex | tonumber]')
carbon_monoxide=$(echo "$data" | jq -r --arg timeindex "${timeindex}" '.hourly | .carbon_monoxide[$timeindex | tonumber]')
nitrogen_dioxide=$(echo "$data" | jq -r --arg timeindex "${timeindex}" '.hourly | .nitrogen_dioxide[$timeindex | tonumber]')
sulphur_dioxide=$(echo "$data" | jq -r --arg timeindex "${timeindex}" '.hourly | .sulphur_dioxide[$timeindex | tonumber]')
ozone=$(echo "$data" | jq -r --arg timeindex "${timeindex}" '.hourly | .ozone[$timeindex | tonumber]')
aerosol_optical_depth=$(echo "$data" | jq -r --arg timeindex "${timeindex}" '.hourly | .aerosol_optical_depth[$timeindex | tonumber]')
dust=$(echo "$data" | jq -r --arg timeindex "${timeindex}" '.hourly | .dust[$timeindex | tonumber]')
uv_index=$(echo "$data" | jq -r --arg timeindex "${timeindex}" '.hourly | .uv_index[$timeindex | tonumber]')
uv_index_clear_sky=$(echo "$data" | jq -r --arg timeindex "${timeindex}" '.hourly | .uv_index_clear_sky[$timeindex | tonumber]')

#echo "${data}" | jq '.hourly_units'
echo "pm10: ${pm10}"
echo "pm25: ${pm25}"
echo "carbon_monoxide: ${carbon_monoxide}"
echo "nitrogen_dioxide: ${nitrogen_dioxide}"
echo "sulphur_dioxide: ${sulphur_dioxide}"
echo "ozone: ${ozone}"
echo "aerosol_optical_depth: ${aerosol_optical_depth}"
echo "dust: ${dust}"
echo "uv_index: ${uv_index}"
echo "uv_index_clear_sky: ${uv_index_clear_sky}"


ozone_mg=$(echo "scale=6; $ozone / 1000" | bc)
carbon_monoxide_mg=$(echo "scale=6; $carbon_monoxide / 1000" | bc)

ozone_aqi=$(calculate_aqi "$ozone_mg" "ozone_breakpoints" "${!ozone_breakpoints[@]}")
pm25_aqi=$(calculate_aqi "$pm25" "pm25_breakpoints" "${!pm25_breakpoints[@]}")
pm10_aqi=$(calculate_aqi "$pm10" "pm10_breakpoints" "${!pm10_breakpoints[@]}")
co_aqi=$(calculate_aqi "$carbon_monoxide_mg" "co_breakpoints" "${!co_breakpoints[@]}")
no2_aqi=$(calculate_aqi "$nitrogen_dioxide" "no2_breakpoints" "${!no2_breakpoints[@]}")
so2_aqi=$(calculate_aqi "$sulphur_dioxide" "so2_breakpoints" "${!so2_breakpoints[@]}")

echo
echo "Ozone AQI: $ozone_aqi $( convert_int_to_string "$ozone_aqi" )"
echo "PM2.5 AQI: $pm25_aqi $( convert_int_to_string "$pm25_aqi" )"
echo "PM10 AQI: $pm10_aqi $( convert_int_to_string "$pm10_aqi" )"
echo "CO AQI: $co_aqi $( convert_int_to_string "$co_aqi" )"
echo "NO2 AQI: $no2_aqi $( convert_int_to_string "$no2_aqi" )"
echo "SO2 AQI: $so2_aqi $( convert_int_to_string "$so2_aqi" )"
echo
