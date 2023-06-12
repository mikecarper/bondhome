#!/bin/bash

#
# This is an example file that will open and close blinds based off time (9AM & noon) and temp.
# It uses the following bond groups as an example; you'll need to change them
# aa80e661a4047dc6, f84acdf0292a075a, 55e32ff91127ef9a
#
# This will also close ALL blinds 1 hour before sunset. 
#

# Get today's info
weather_txt=$( cat "${HOME}/.bond/weather.txt" )
current_time_unix=$(date +%s)
max_temp=$( echo "${weather_txt}" | grep 'Max Temperature:' | grep -oE '[0-9]+' )

keepBlindsClosedTempHigh=85
openInteriorBlindsIfLowerThanTemp=65
openExteriorBlindsIfLowerThanTemp=45

secondsToHM() {
    seconds=${1}
    if [[ "${seconds}" -lt 0 ]]
    then
        seconds=$(( seconds + 86400 ))
    fi

    hours=$((seconds / 3600))
    minutes=$(( (seconds % 3600) / 60 ))

    # Build the duration string
    duration=""

    if [[ "${hours}" -gt 0 ]]
    then
        duration="$hours hour"
        if [[ "${hours}" -gt 1 ]]
        then
            duration="${duration}s"
        fi
    fi

    if [[ "${minutes}" -gt 0 ]]
    then
        if [[ -n "${duration}" ]]
        then
            duration="${duration} and "
        fi
        duration="${duration}$minutes minute"
        if [[ "${minutes}" -gt 1 ]]
        then
            duration="${duration}s"
        fi
    fi
    echo "${duration}"
}




# 1 hour before sunset.
timeBeforeSunset=3600
# sunset logic
sunset_time=$( echo "${weather_txt}" | grep 'sunset:' | awk '{print $NF}' )
threshold_lower=$((sunset_time - timeBeforeSunset))  # 1 hour before sunset
threshold_upper=$((threshold_lower + 900))  # 45 minutes before sunset
trigger_display=$(date -d "@${threshold_lower}" +'%I:%M %p')
if [[ $current_time_unix -gt $threshold_lower && $current_time_unix -lt $threshold_upper ]]
then
    duration=$( secondsToHM "${timeBeforeSunset}" )
    echo "Closing all blinds ${duration} before sunset"
    bash "${HOME}/bond-sh/deviceaction.sh" -i "ALL" --type "MS" -a "Close" -D
else
    time_until=$((threshold_lower - current_time_unix))
    duration=$( secondsToHM "${time_until}" )
    echo "Time until sunset trigger (${trigger_display}): ${duration}"
fi



# 9AM Morning
timeOfMorning='9:00 AM'
threshold_lower=$(date -d "${timeOfMorning}" +%s)
threshold_upper=$((threshold_lower + 900))  # 9:15
trigger_display=$(date -d "@${threshold_lower}" +'%I:%M %p')
if [[ $current_time_unix -gt $threshold_lower && $current_time_unix -lt $threshold_upper ]]
then
    if [[ "${max_temp}" -lt "${keepBlindsClosedTempHigh}" ]] # 85
    then
        echo "Current time is ${timeOfMorning}. Opening West Interior Blinds because today's high is ${max_temp} which is less than the trigger temp of ${keepBlindsClosedTempHigh} to keep the blinds closed"
        bash "${HOME}/bond-sh/deviceaction.sh" -i ZPEE65205 -m 2 -g aa80e661a4047dc6 -a Open
    fi

    if [[ "${max_temp}" -lt "${openInteriorBlindsIfLowerThanTemp}" ]] # 65
    then
        echo "Current time is ${timeOfMorning}. Opening East Interior Blinds because today's high is ${max_temp} which is less than the trigger temp of ${openInteriorBlindsIfLowerThanTemp} to keep the blinds closed"
        bash "${HOME}/bond-sh/deviceaction.sh" -i ZPEE65205 -m 2 -g f84acdf0292a075a -a Open
    fi

    if [[ "${max_temp}" -lt "${openExteriorBlindsIfLowerThanTemp}" ]] # 45
    then
        echo "Current time is ${timeOfMorning}. Opening East Exterior Blinds because today's high is ${max_temp} which is less than the trigger temp of ${openExteriorBlindsIfLowerThanTemp} to keep the blinds closed"
        bash "${HOME}/bond-sh/deviceaction.sh" -i ZPEE65205 -m 2 -g 55e32ff91127ef9a -a Open
    fi

else
    time_until=$((threshold_lower - current_time_unix))
    duration=$( secondsToHM "${time_until}" )
    echo "Time until morning (${trigger_display}): ${duration}"
fi



# Solar Noon
threshold_lower=$( echo "${weather_txt}" | grep 'midday:' | awk '{print $NF}' )
threshold_upper=$((threshold_lower + 900))  # Solar Noon + 15 min.
trigger_display=$(date -d "@${threshold_lower}" +'%I:%M %p')
if [[ $current_time_unix -gt $threshold_lower && $current_time_unix -lt $threshold_upper ]]
then
    if [[ "${max_temp}" -lt "${keepBlindsClosedTempHigh}" ]] # 85
    then
        echo "Current time is ${timeOfMorning}. Opening East Interior Blinds because today's high is ${max_temp} which is less than the trigger temp of ${keepBlindsClosedTempHigh} to keep the blinds closed"
        bash "${HOME}/bond-sh/deviceaction.sh" -i ZPEE65205 -m 2 -g f84acdf0292a075a -a Open
    fi

    if [[ "${max_temp}" -ge "${openInteriorBlindsIfLowerThanTemp}" ]] # 65
    then
        echo "Current time is ${timeOfMorning}. Closing West Interior Blinds because today's high is ${max_temp} which is greater than or equal to the trigger temp of ${openInteriorBlindsIfLowerThanTemp}"
        bash "${HOME}/bond-sh/deviceaction.sh" -i ZPEE65205 -m 2 -g aa80e661a4047dc6 -a Close
    fi

else
    time_until=$((threshold_lower - current_time_unix))
    duration=$( secondsToHM "${time_until}" )
    echo "Time until solar noon (${trigger_display}): ${duration}"
fi
