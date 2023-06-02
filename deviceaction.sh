#!/usr/bin/env bash


# http://docs-local.appbond.com/
scriptName=${0}
bond_db_file="${HOME}/.bond/db.json"
bond_devices_file="${HOME}/.bond/devices"

# option --output/-o requires 1 argument
LONGOPTS=help
OPTIONS=hhrRf:i:t:I:d:a:

# -regarding ! and PIPESTATUS see above
# -temporarily store output to be able to check for errors
# -activate quoting/enhanced mode (e.g. by writing out “--options”)
# -pass arguments only via   -- "$@"   to separate them correctly
! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    # e.g. return value is 1
    #  then getopt has complained about wrong arguments to stdout
    exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

selected_bondid=''
bond_token=''
ip_address=''
selectedBondDevice=''
action=''
updateRan=0
rescan=0
rescanNetwork=0
mkdir -p "${HOME}/.bond/"
touch "${bond_db_file}"

helpoutput() {
cat<<EOF
 -f     json file used to read/write global info. Default is ${bond_db_file}
 -l     json file prefix for device list. Default is ${bond_devices_file}
 -r     rescan for devices.
 -R     rescan network for bond home base station devices.
 -i     bond id to use
 -t     bond token to use
 -I     bond IP to use
 -d     bond device to use
 -a     bond action to take
 -h -H  (--help) display this help file
EOF
}

# now enjoy the options in order and nicely split until we see --
while true; do
    case "${1}" in
        -f)
            if [[ -r "${2}" ]]
            then
                bond_db_file="${2}"
                echo "Using file ${bond_db_file}"
                shift 2
            else
                echo "File is not readable: ${2}"
                exit 4
            fi
        ;;
        -l)
            if [[ -r "${2}" ]]
            then
                bond_devices_file="${2}"
                echo "Using file ${bond_devices_file}"
                shift 2
            else
                echo "File is not readable: ${2}"
                exit 4
            fi
        ;;
        -r)
            echo "Option -r rescan for devices"
            rescan=1
            shift
        ;;
        -R)
            echo "Option -R rescan network for bond home base station devices"
            rescanNetwork=1
            shift
        ;;
        -i)
            echo "Option -i Set Bond ID passed with argument: $2"
            selected_bondid="${2}"
            shift 2
        ;;
        -t)
            echo "Option -t Set Token passed with argument: $2"
            bond_token="${2}"
            shift 2
        ;;
        -I)
            echo "Option -I Set IP passed with argument: $2"
            ip_address="${2}"
            shift 2
        ;;
        -d)
            echo "Option -d Set device passed with argument: $2"
            selectedBondDevice="${2}"
            shift 2
        ;;
        -a)
            echo "Option -a Set action passed with argument: $2"
            action="${2}"
            shift 2
        ;;
        -h|-H|--help)
            helpoutput
            shift
            exit
        ;;
        --)
            echo
            shift
            break
            ;;
        *)
            echo "Invalid option: ${0} ${1} ${2}"
            exit
        ;;
    esac
done


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

BondGetIPFromFile () {
    if [[ -z "${ip_address}" ]]
    then
        if [[ -r "${bond_db_file}" ]]
        then
            ip_address=$( jq -r ".bonds.${selected_bondid}.ip // empty" < "$bond_db_file" )
        fi
    fi
}


BondSelect () {
    if [[ -r "${bond_db_file}" ]]
    then
        echo "Reading .bond/db.json file"
        selected_bondid=$( jq -r '.selected_bondid // empty' < "$bond_db_file" )
        if [[ -n "${selected_bondid}" && "${rescanNetwork}" -eq 0 ]]
        then
            echo "Using ${selected_bondid}"
            return
        fi
    fi

    if [[ -z "$( command -v avahi-browse )" ]]
    then
        if [[ "${updateRan}" -eq 0 ]]
        then
            sudo apt update
            updateRan=1
        fi
        echo "Installing avahi-browse"
        sudo apt install avahi-utils -y
        echo
    fi

    echo "Searching network for bond bridges"
    bond_bridges=$( avahi-browse -a -p -t --resolve  2> /dev/null | grep bond | awk -F ';' '{print $8 " " $4}' | grep -v '^[[:space:]]' )

    while read -r line
    do
        ip_address=$( echo "${line}" | awk '{print $1}' )
        #bond_id=$( echo "${line}" | awk '{print $2}' )
        echo "Checking IP: ${ip_address}"
        bond_id_from_url=$( curl -s --max-time 5 "http://${ip_address}/v2/sys/version" | grep -e "^\[" -e "^{"  | jq -r '.bondid' )
        if [[ -n "${bond_id_from_url}" ]]
        then
            if [[ -z "${bond_bridges_confirmed}" ]]
            then
                bond_bridges_confirmed=$( echo -e "${ip_address}\t${bond_id_from_url}" )
            else
                bond_bridges_confirmed=$( echo -e "${bond_bridges_confirmed}\n${ip_address}\t${bond_id_from_url}" )
            fi
            file_size=$(stat -c "%s" "${bond_db_file}")
            if [[ "${file_size}" -lt 3 ]]
            then
                echo "adding bond: ${bond_id_from_url} ${ip_address}"
                jq -n --arg keyvar "${bond_id_from_url}" --arg ip "${ip_address}" '.bonds[($keyvar)] = {
                "ip": ($ip),
                "port": 80
                }' > "${bond_db_file}"
            else
                bond_exists=$( jq -r ".bonds.${bond_id_from_url}.ip // empty" < "$bond_db_file" )
                if [[ -z "${bond_exists}" ]]
                then
                    echo "adding bond: ${bond_id_from_url} ${ip_address}"
                    jq --arg keyvar "${bond_id_from_url}" --arg ip "${ip_address}" '.bonds[($keyvar)] = {
                    "ip": ($ip),
                    "port": 80
                    }' "${bond_db_file}" > "${bond_db_file}.tmp" && mv "${bond_db_file}.tmp" "${bond_db_file}"
                fi
            fi
        fi
    done <<< "${bond_bridges}"
    if [[ -z "${bond_bridges_confirmed}" ]]
    then
        return
    fi

    wordcount=$( echo "${bond_bridges_confirmed}" | wc -l )
    if [[ $wordcount -eq 1 ]]
    then
        selected_bondid=$( echo "${bond_bridges_confirmed}" | awk '{print $2}' )
        ip_address=$( echo "${bond_bridges_confirmed}" | awk '{print $1}' )
    elif [[ $wordcount -gt 1 ]]
    then
        # Read the lines into an array
        IFS=$'\n' read -d '' -r -a lines_array <<< "${bond_bridges_confirmed}"

        # Prompt the user to select a line from the menu
        PS3="Select The Default Bond Device: "
        select option in "${lines_array[@]}"
        do
            if [[ -n $option ]]; then
                echo "${option} has been selected."
                selected_bondid=$( echo "${option}" | awk '{print $2}' )
                ip_address=$( echo "${option}" | awk '{print $1}' )
                break
            else
                echo "Invalid option. Please try again."
            fi
        done
    fi

    if [[ -n "${selected_bondid}" ]]
    then
        selected_bondid_test=$( jq -r '.selected_bondid // empty' < "$bond_db_file" )
        if [[ -z "${selected_bondid_test}" ]]
        then
            jq --arg var "${selected_bondid}" '{
            "selected_bondid": ($var),
            }' "${bond_db_file}" > "${bond_db_file}.tmp" && mv "${bond_db_file}.tmp" "${bond_db_file}"
        else
            jq --arg var "${selected_bondid}" '. + { "selected_bondid": ($var) }' "${bond_db_file}" > "${bond_db_file}.tmp" && mv "${bond_db_file}.tmp" "${bond_db_file}"
        fi
    fi
}

BondTokenGet() {
    # JSON
    if [[ -r "$bond_db_file" ]]
    then
        bond_token=$( jq -r ".bonds.${selected_bondid}.token // empty" < "$bond_db_file" )
        if [[ -n "${bond_token}" ]]
        then
            tokenworked=$( BondTokenTest )
            if [[ -n "${tokenworked}" ]]
            then
                return
            else
                bond_token=''
            fi
        fi
    fi

    # User Input
    echo "Open Bond App on your phone"
    echo "Go to Devices on the bottom menu"
    echo 'Scroll down to "My Bonds"'
    echo "Select your bond device"
    echo 'Expand "Advanced Settings"'
    echo 'Enter the "Local Token" here'

    while [[ -z "${bond_token}" ]]
    do
        read -r -p 'Token: ' bond_token
        BondTokenTest
        if [[ -z "${tokenworks}" ]]
        then
            bond_token=''
        fi
    done

    if [[ -n "${bond_token}" ]]
    then
        jq --arg keyvar "${selected_bondid}" --arg token "${bond_token}" '.bonds[($keyvar)].token |= $token' "${bond_db_file}" > "${bond_db_file}.tmp" && mv "${bond_db_file}.tmp" "${bond_db_file}"
    fi

    # Screen Shot
    #if [[ -z "$( command -v tesseract )" ]]
    #then
    #    if [[ "${updateRan}" -eq 0 ]]
    #    then
    #        sudo apt update
    #        updateRan=1
    #    fi
    #    echo "Installing tesseract"
    #    sudo apt install tesseract -y
    #    echo
    #fi
    #tesseract --dpi 72 IMG_0795.jpg - | grep -i "Local Token" | awk '{print $3}'
}

BondTokenTest() {
    BondGetIPFromFile

    tokenworks=$( curl -s --max-time 5 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/sys/time" | jq -r '.unix_time //empty' )
    echo "${tokenworks}"
}

BondGetDevices() {
    if [[ -r "${bond_devices_file}-${selected_bondid}.json" ]]
    then
        bondDevicesFinal=$( cat "${bond_devices_file}-${selected_bondid}.json")
    fi
    if [[ -n "${bondDevicesFinal}" && "${rescan}" -eq 0 ]]
    then
        return
    fi

    echo "Getting devices under bond ${selected_bondid} at ${ip_address}"
    BondGetIPFromFile

    bondDevices=$( curl -H "BOND-Token: ${bond_token}" -s "http://${ip_address}/v2/devices"  )
    bondDevicesFinal=$bondDevices
    while read -r line1
    do
        echo -n "$line1"

        device=$( curl -s --max-time 5 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/devices/${line1}" )
        if [[ -z "${device}" ]]
        then
            device=$( curl -s --max-time 5 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/devices/${line1}" )
        fi
        #echo -n " getting state"
        #state=$( curl -s --max-time 10 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/devices/${line1}/state" )
        #if [[ -z "${state}" ]]
        #then
        #    state=$( curl -s --max-time 10 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/devices/${line1}/state" )
        #fi

        combined=${device}
        #combined=$( echo "${device}" | jq --argjson state "${state}" '.state += $state' )
        bondDevicesFinal=$( echo "${bondDevicesFinal}" | jq --arg keyvar "${line1}" --argjson combined "${combined}" '.[($keyvar)] += $combined' )
        echo -ne "\r\033[K"
    done <<< "$( echo "${bondDevices}" | jq -r 'keys_unsorted[]' | grep -v '_' )"

    # Store devices in a json file.
    echo "${bondDevicesFinal}" > "${bond_devices_file}-${selected_bondid}.json"

}

BondSelectDevice() {
    echo

    # Read the menu selection
    PS3="Enter your choice: "

    # Create an array of menu options
    IFS=$'\n' read -rd '' -a options <<< "$( echo "${bondDevicesFinal}" | jq -r 'to_entries[] | select(.value.location? and .value.name?) | "\(.value.location) - \(.value.name) - \(.key)"' | sort )"

    # Display the menu options
    select selectedDevice in "${options[@]}"
    do
        if [[ -z $selectedDevice ]]
        then
            echo "Invalid option ${selectedDevice}"
        else
            break
        fi

    done
    selectedBondDevice=$( echo "${selectedDevice}" | awk '{print $NF}')
}

BondSelectAction() {
    BondGetIPFromFile

    echo "You selected ${selectedBondDevice}"

    selectedBondDeviceDetails=$( echo "${bondDevicesFinal}" | jq --arg keyvar "${selectedBondDevice}" '.[($keyvar)]' )

    state=$( curl -s --max-time 5 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/devices/${selectedBondDevice}/state" )
    if [[ -z "${state}" ]]
    then
        state=$( curl -s --max-time 10 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/devices/${selectedBondDevice}/state" )
    fi
    selectedBondDeviceDetails=$( echo "${selectedBondDeviceDetails}" | jq --argjson state "${state}" '.state += $state' )

    echo "Current state:"
    echo "${selectedBondDeviceDetails}" | jq -r '.state | to_entries[] | "  \(.key): \(.value)"'  | grep -vE '^ +\_'

    PS3="Available actions: "
    # Create an array of menu options
    IFS=$'\n' read -rd '' -a actions <<< "$( echo "${selectedBondDeviceDetails}" | jq -r '.actions | to_entries[] | "\(.value)"' | grep -v '^_' )"

    # Display the menu options
    select action in "${actions[@]}"
    do
        if [[ -z $action ]]
        then
            echo "Invalid option"
        else
            break
        fi

    done

}

BondDoAction() {
    BondGetIPFromFile

    echo
    echo "PUT http://${ip_address}/v2/devices/${selectedBondDevice}/actions/${action}"
    curl -o /dev/null -s -w "%{http_code}\n" -X PUT -H "BOND-Token: ${bond_token}" -H "Content-Type: application/json" -d "{}" "http://${ip_address}/v2/devices/${selectedBondDevice}/actions/${action}"
}

if [[ -z "${selected_bondid}" ]]
then
    BondSelect
    if [[ -z "${selected_bondid}" ]]
    then
        echo "Bond selection failed"
        echo "${bond_bridges}"
        echo "${bond_db_file}"
        exit 1
    fi
    echo "Using bond bridge ${selected_bondid}"
fi

if [[ -z "${bond_token}" ]]
then
    BondTokenGet
    if [[ -z "${bond_token}" ]]
    then
        echo "Bond token not found"
        exit 2
    fi
    echo "Using bond token ${bond_token}"
fi

BondGetDevices

if [[ -z "${selectedBondDevice}" ]]
then
    BondSelectDevice
    if [[ -z "${selectedBondDevice}" ]]
    then
        echo "Bond device not found"
        exit 2
    fi
    echo "Using bond device ${selectedBondDevice}"
fi

if [[ -z "${action}" ]]
then
    BondSelectAction
    if [[ -z "${action}" ]]
    then
        echo "Action to do not found"
        exit 2
    fi
    echo "Action: ${action}"
fi

BondDoAction

echo
echo "command to do this again"
echo "${scriptName} -i ${selected_bondid} -t ${bond_token} -I ${ip_address} -d ${selectedBondDevice} -a ${action}"
