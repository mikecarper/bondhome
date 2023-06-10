#!/usr/bin/env bash


# http://docs-local.appbond.com/
scriptName=${0}
bond_db_file="${HOME}/.bond/db.json"
bond_devices_file="${HOME}/.bond/devices"
bond_groups_file="${HOME}/.bond/groups"

# option --output/-o requires 1 argument
LONGOPTS=help,type:
OPTIONS=hhrRcFDGf:i:t:I:d:a:m:g:

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
action=''
updateRan=0
rescan=0
rescanNetwork=0
cronrun=0
tryagain=1
type=''
alldevices=1
allgroups=1

menu=0
selectedBondDevice=''
bondGroupsFinal=''

mkdir -p "${HOME}/.bond/"
touch "${bond_db_file}"

helpoutput() {
cat<<EOF
 -h -H  (--help) display this help file
 -f     json file used to read/write global info. Default is ${bond_db_file}
 -l     json file prefix for device list. Default is ${bond_devices_file}
 -L     json file prefix for group list. Default is ${bond_groups_file}
 -r     rescan for devices & groups.
 -R     rescan network for bond home base station devices.
 -c     rescan all base stations for devices & groups and exit. Useful for cron jobs.
 -m     1 for devices 2 for groups
 -i     bond id to use. If "ALL" is used then it'll run on all device ips found.
 -t     bond token to use
 -I     bond IP to use
 -d     bond device to use
 -g     bond group to use
 -a     bond action to take
 -D     run action only on all bond devices
 -G     run action only on all bond groups
 -F     fail if call did not work
 --type CF : Ceiling Fan
        FP : Fireplace
        MS : Motorized Window Coverings (Shades, Screens, Drapes) and Awnings
        GX : Generic device
        LT : Light
        BD : Bidet
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
        -L)
            if [[ -r "${2}" ]]
            then
                bond_groups_file="${2}"
                echo "Using file ${bond_groups_file}"
                shift 2
            else
                echo "File is not readable: ${2}"
                exit 4
            fi
        ;;
        -r)
            echo "Option -r rescan for devices & groups"
            rescan=1
            shift
        ;;
        -R)
            echo "Option -R rescan network for bond home base station devices"
            rescanNetwork=1
            shift
        ;;
        -c)
            echo "Option -c rescan all base stations for devices & groups and exit"
            cronrun=1
            shift
        ;;
        -m)
            echo "Option -m Set menu passed with argument: $2"
            menu="${2}"
            shift 2
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
        -g)
            echo "Option -g Set group passed with argument: $2"
            selectedBondGroup="${2}"
            shift 2
        ;;
        -a)
            echo "Option -a Set action passed with argument: $2"
            action="${2}"
            shift 2
        ;;
        -D)
            echo "Option -D run action only on all devices"
            allgroups=0
            shift
        ;;
        -G)
            echo "Option -G run action only on all groups"
            alldevices=0
            shift
        ;;
        --type)
            echo "Option --type Set action passed with argument: $2"
            type="${2}"
            shift 2
        ;;
        -F)
            echo "Option -F do not try curl again"
            tryagain=0
            shift
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

# Menu function
function display_menu() {
    echo "Menu:"
    echo "1. Devices"
    echo "2. Groups"
}

Menu() {
    if [[ "${menu}" -ne 0 ]]
    then
        return
    fi

    # Devices or Groups
    while true; do
        display_menu
        read -r -p "Enter your choice: " choice
        case $choice in
            1)
                menu=1
                break
                ;;
            2)
                menu=2
                break
                ;;
            *)
                echo "Invalid choice. Please try again."
                ;;
        esac
        echo
    done
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

BondSearchNetwork() {
    desired_bond_id=${1}
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
    bond_bridges=$( timeout 10s avahi-browse -a -p -t --resolve  2> /dev/null | grep bond | awk -F ';' '{print $8 " " $4}' | grep -v '^[[:space:]]' )
    echo "Parsing data"

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
                elif [[ "${bond_exists}" != "${ip_address}" ]]
                then
                    echo "updating bond ip: ${bond_id_from_url} ${ip_address}"
                    jq --arg new_ip "${ip_address}" '.bonds[].ip |= $new_ip' "${bond_db_file}" > "${bond_db_file}.tmp" && mv "${bond_db_file}.tmp" "${bond_db_file}"
                fi
            fi
            #cat "${bond_db_file}"
        fi
    done <<< "${bond_bridges}"

    if [[ -z "${bond_bridges_confirmed}" ]]
    then
        return
    fi

    if [[ -n "${desired_bond_id}" && "${bond_bridges_confirmed}" == *"${desired_bond_id}"* ]]
    then
        selected_bondid=$( echo "${bond_bridges_confirmed}" | grep "${desired_bond_id}" | awk '{print $2}' )
        ip_address=$( echo "${bond_bridges_confirmed}" | grep "${desired_bond_id}" | awk '{print $1}' )
        echo "Found bond ${selected_bondid} at ${ip_address}"

    else
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
    fi

    if [[ -n "${selected_bondid}" ]]
    then
        selected_bondid_test=$( jq -r '.selected_bondid // empty' < "$bond_db_file" )
        if [[ -z "${selected_bondid_test}" ]]
        then
            jq --arg var "${selected_bondid}" '.selected_bondid = ($var)' "${bond_db_file}" > "${bond_db_file}.tmp" && mv "${bond_db_file}.tmp" "${bond_db_file}"
        else
            jq --arg var "${selected_bondid}" '. + { "selected_bondid": ($var) }' "${bond_db_file}" > "${bond_db_file}.tmp" && mv "${bond_db_file}.tmp" "${bond_db_file}"
        fi
        #cat "${bond_db_file}"
    fi
}


BondSelect () {
    if [[ -r "${bond_db_file}" && -s "${bond_db_file}" ]]
    then
        echo "Reading .bond/db.json file"
        selected_bondid=$( jq -r '.selected_bondid // empty' < "$bond_db_file" )
        if [[ -n "${selected_bondid}" ]]
        then
            echo "Using ${selected_bondid}"
            return
        fi
    fi

    BondSearchNetwork
}

BondTokenGetFromJSON() {
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
}

BondTokenGet() {
    # Read from json file.
    BondTokenGetFromJSON
    if [[ -n "${bond_token}" ]]
    then
        return
    fi

    BondGetIPFromFile
    bond_id_from_url=$( curl -s --max-time 5 "http://${ip_address}/v2/sys/version" | grep -e "^\[" -e "^{"  | jq -r '.bondid' )
    if [[ -z "${bond_id_from_url}" ]]
    then
        BondSearchNetwork "${selected_bondid}"
    fi

    # Read from json file.
    BondTokenGetFromJSON
    if [[ -n "${bond_token}" ]]
    then
        return
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

BondGetGroups() {
    if [[ -r "${bond_groups_file}-${selected_bondid}.json" ]]
    then
        bondGroupsFinal=$( cat "${bond_groups_file}-${selected_bondid}.json")
    fi
    if [[ -n "${bondGroupsFinal}" && "${rescan}" -eq 0 ]]
    then

        return
    fi

    BondGetIPFromFile
    echo "Getting groups  under bond ${selected_bondid} at ${ip_address}"

    bondGroups=$( curl -s --max-time 10 -H "BOND-Token: ${bond_token}" -s "http://${ip_address}/v2/groups"  )
    if [[ -z "${bondGroups}" || $( echo "${bondGroups}" | jq -e 2>&1 | grep -c 'parse error' ) -eq 1 ]]
    then
        echo "No groups found here http://${ip_address}/v2/groups"
        return
    fi
    bondGroupsFinal=$bondGroups
    while read -r line1
    do
        echo -n "$line1"

        group=$( curl -s --max-time 5 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/groups/${line1}" )
        if [[ -z "${group}" ]]
        then
            group=$( curl -s --max-time 5 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/groups/${line1}" )
        fi
        echo -n " getting schedules"
        skeds=$( curl -s --max-time 10 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/groups/${line1}/skeds" )
        if [[ -z "${skeds}" ]]
        then
            skeds=$( curl -s --max-time 10 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/groups/${line1}/skeds" )
        fi

        skeds_final="${skeds}"
        while read -r sked
        do
            schedule=$( curl -s --max-time 10 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/groups/${line1}/skeds/${sked}" )
            if [[ -z "${schedule}" ]]
            then
                schedule=$( curl -s --max-time 10 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/groups/${line1}/skeds${sked}" )
            fi
            skeds_final=$( jq --argjson schedule "${schedule}" --arg key "${sked}"  '.[($key)] += { "schedule": $schedule }' <<< "$skeds_final" )
        done <<< "$( echo "${skeds}" | jq -r 'keys_unsorted[]' | grep -v '_' )"

        combined=${group}
        combined=$( echo "${group}" | jq --argjson skeds "${skeds}" '.skeds += $skeds' )
        bondGroupsFinal=$( echo "${bondGroupsFinal}" | jq --arg keyvar "${line1}" --argjson combined "${combined}" '.[($keyvar)] += $combined' )
        echo -ne "\r\033[K"
    done <<< "$( echo "${bondGroups}" | jq -r 'keys_unsorted[]' | grep -v '_' )"

    # Store groups in a json file.
    echo "${bondGroupsFinal}" > "${bond_groups_file}-${selected_bondid}.json"
}

BondSelectGroup() {

    # Read the menu selection
    PS3="Enter your choice: "

    # Create an array of menu options
    IFS=$'\n' read -rd '' -a options <<< "$( echo "${bondGroupsFinal}" | jq -r 'to_entries[] | select(.value.locations? and .value.name?) | "\(.value.locations | join(", ")) - \(.value.name) - \(.key)"' | sort )"

    # Display the menu options
    select selectedGroup in "${options[@]}"
    do
        if [[ -z $selectedGroup ]]
        then
            echo "Invalid option ${selectedGroup}"
        else
            break
        fi

    done
    selectedBondGroup=$( echo "${selectedGroup}" | awk '{print $NF}')
}

BondSelectGroupAction() {
    BondGetIPFromFile

    echo "${selectedBondGroup} selected"

    selectedBondGroupDetails=$( echo "${bondGroupsFinal}" | jq --arg keyvar "${selectedBondGroup}" '.[($keyvar)]' )

    state=$( curl -s --max-time 5 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/groups/${selectedBondGroup}/state" )
    if [[ -z "${state}" ]]
    then
        state=$( curl -s --max-time 10 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/groups/${selectedBondGroup}/state" )
    fi
    selectedBondGroupDetails=$( echo "${selectedBondGroupDetails}" | jq --argjson state "${state}" '.state += $state' )

    echo ""
    echo "Current state:"
    echo "${selectedBondGroupDetails}" | jq -r '.state | to_entries[] | "  \(.key): \(.value)"'  | grep -vE '^ +\_'
    echo ""

    PS3="Select Action: "
    # Create an array of menu options
    IFS=$'\n' read -rd '' -a actions <<< "$( echo "${selectedBondGroupDetails}" | jq -r '.actions | to_entries[] | "\(.value)"' | grep -v '^_' )"

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

BondDoGroupAction() {
    BondGetIPFromFile

    echo
    echo "PUT http://${ip_address}/v2/groups/${selectedBondGroup}/actions/${action}"
    http_code=$( curl -s -w "%{http_code}\n" -X PUT -H "BOND-Token: ${bond_token}" -H "Content-Type: application/json" -d "{}" "http://${ip_address}/v2/groups/${selectedBondGroup}/actions/${action}" | tail -1 )
    echo "${http_code}"
    if [[ "${http_code}" != "200" && "${tryagain}" -eq 1 ]]
    then
        echo "${scriptName} -i ${selected_bondid} -t ${bond_token} -d ${selectedBondGroup} -a ${action} -F -R"
        ${scriptName} "-i" "${selected_bondid}" "-t" "${bond_token}" "-d" "${selectedBondGroup}" "-a" "${action}" "-F" "-R"
        exit
    fi
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

    BondGetIPFromFile
    echo "Getting devices under bond ${selected_bondid} at ${ip_address}"


    bondDevices=$( curl -s --max-time 10 -H "BOND-Token: ${bond_token}" -s "http://${ip_address}/v2/devices"  )
    if [[ -z "${bondDevices}" || $( echo "${bondDevices}" | jq -e 2>&1 | grep -c 'parse error' ) -eq 1 ]]
    then
        echo "No devices found here http://${ip_address}/v2/devices"
        return
    fi
    bondDevicesFinal=$bondDevices
    while read -r line1
    do
        echo -n "$line1"

        device=$( curl -s --max-time 5 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/devices/${line1}" )
        if [[ -z "${device}" ]]
        then
            device=$( curl -s --max-time 5 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/devices/${line1}" )
        fi
        echo -n " getting schedules"
        skeds=$( curl -s --max-time 10 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/devices/${line1}/skeds" )
        if [[ -z "${skeds}" ]]
        then
            skeds=$( curl -s --max-time 10 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/devices/${line1}/skeds" )
        fi

        skeds_final="${skeds}"
        while read -r sked
        do
            schedule=$( curl -s --max-time 10 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/devices/${line1}/skeds/${sked}" )
            if [[ -z "${schedule}" ]]
            then
                schedule=$( curl -s --max-time 10 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/devices/${line1}/skeds${sked}" )
            fi
            skeds_final=$( jq --argjson schedule "${schedule}" --arg key "${sked}"  '.[($key)] += { "schedule": $schedule }' <<< "$skeds_final" )
        done <<< "$( echo "${skeds}" | jq -r 'keys_unsorted[]' | grep -v '_' )"


        combined=${device}
        combined=$( echo "${device}" | jq --argjson skeds "${skeds_final}" '.skeds += $skeds' )
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

BondSelectDeviceAction() {
    BondGetIPFromFile

    echo "${selectedBondDevice} selected"

    selectedBondDeviceDetails=$( echo "${bondDevicesFinal}" | jq --arg keyvar "${selectedBondDevice}" '.[($keyvar)]' )

    state=$( curl -s --max-time 5 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/devices/${selectedBondDevice}/state" )
    if [[ -z "${state}" ]]
    then
        state=$( curl -s --max-time 10 -H "BOND-Token: ${bond_token}" "http://${ip_address}/v2/devices/${selectedBondDevice}/state" )
    fi
    selectedBondDeviceDetails=$( echo "${selectedBondDeviceDetails}" | jq --argjson state "${state}" '.state += $state' )

    echo ""
    echo "Current state:"
    echo "${selectedBondDeviceDetails}" | jq -r '.state | to_entries[] | "  \(.key): \(.value)"'  | grep -vE '^ +\_'
    echo ""

    PS3="Select Action: "
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

BondDoDeviceAction() {
    BondGetIPFromFile

    echo
    echo "PUT http://${ip_address}/v2/devices/${selectedBondDevice}/actions/${action}"
    http_code=$( curl -s -w "%{http_code}\n" -X PUT -H "BOND-Token: ${bond_token}" -H "Content-Type: application/json" -d "{}" "http://${ip_address}/v2/devices/${selectedBondDevice}/actions/${action}" | tail -1 )
    echo "${http_code}"
    if [[ "${http_code}" != "200" && "${tryagain}" -eq 1 ]]
    then
        echo "${scriptName} -i ${selected_bondid} -t ${bond_token} -d ${selectedBondDevice} -a ${action} -F -R"
        ${scriptName} "-i" "${selected_bondid}" "-t" "${bond_token}" "-d" "${selectedBondDevice}" "-a" "${action}" "-F" "-R"
        exit
    fi
}

BondRunAll() {
    BondTokenGetFromJSON
    BondGetIPFromFile
    BondGetDevices
    BondGetGroups


    if [[ -n "${type}" ]]
    then
        bondDevicesFinalAlt=$( echo "${bondDevicesFinal}" | jq --arg var "${type}" 'to_entries[] | select(.value.type? == $var)' )
        bondGroupsFinalAlt=$( echo "${bondGroupsFinal}" | jq --arg var "${type}" 'to_entries[] | select(.value.types?[] == $var)' )
    else
        bondDevicesFinalAlt=$( echo "${bondDevicesFinal}" | jq --arg var "${type}" 'to_entries[]' )
        bondGroupsFinalAlt=$( echo "${bondGroupsFinal}" | jq --arg var "${type}" 'to_entries[]' )
    fi
    #echo "${bondDevicesFinalAlt}"

    if [[ -n "${action}" ]]
    then
        bondDevicesFinalAlt=$( echo "${bondDevicesFinalAlt}" | jq --arg var "${action}" 'select(.value.actions?[] == $var)' )
        bondGroupsFinalAlt=$( echo "${bondGroupsFinalAlt}" | jq --arg var "${action}" 'select(.value.actions?[] == $var)' )
    fi


    if [[ "${alldevices}" -eq 1 ]]
    then
        while read -r selectedBondDevice
        do
            http_code=$( curl --max-time 10 -s -w "%{http_code}\n" -X PUT -H "BOND-Token: ${bond_token}" -H "Content-Type: application/json" -d "{}" "http://${ip_address}/v2/devices/${selectedBondDevice}/actions/${action}" | tail -1 )
            if [[ "${http_code}" != "200" ]]
            then
                sleep 1
                http_code=$( curl --max-time 10 -s -w "%{http_code}\n" -X PUT -H "BOND-Token: ${bond_token}" -H "Content-Type: application/json" -d "{}" "http://${ip_address}/v2/devices/${selectedBondDevice}/actions/${action}" | tail -1 )
                if [[ "${http_code}" != "200" ]]
                then
                    sleep 5
                    http_code=$( curl --max-time 10 -s -w "%{http_code}\n" -X PUT -H "BOND-Token: ${bond_token}" -H "Content-Type: application/json" -d "{}" "http://${ip_address}/v2/devices/${selectedBondDevice}/actions/${action}" | tail -1 )
                fi
            fi
            echo ">${http_code}< PUT http://${ip_address}/v2/devices/${selectedBondDevice}/actions/${action}"
        done <<< "$(  echo "${bondDevicesFinalAlt}" | jq -r '.key' )"
    fi

    if [[ "${allgroups}" -eq 1 ]]
    then
        while read -r selectedBondGroup
        do
            http_code=$( curl --max-time 10 -s -w "%{http_code}\n" -X PUT -H "BOND-Token: ${bond_token}" -H "Content-Type: application/json" -d "{}" "http://${ip_address}/v2/groups/${selectedBondGroup}/actions/${action}" | tail -1 )
            if [[ "${http_code}" != "200" ]]
            then
                sleep 1
                http_code=$( curl --max-time 10 -s -w "%{http_code}\n" -X PUT -H "BOND-Token: ${bond_token}" -H "Content-Type: application/json" -d "{}" "http://${ip_address}/v2/groups/${selectedBondGroup}/actions/${action}" | tail -1 )
                if [[ "${http_code}" != "200" ]]
                then
                    sleep 5
                    http_code=$( curl --max-time 10 -s -w "%{http_code}\n" -X PUT -H "BOND-Token: ${bond_token}" -H "Content-Type: application/json" -d "{}" "http://${ip_address}/v2/groups/${selectedBondGroup}/actions/${action}" | tail -1 )
                fi
            fi
            echo ">${http_code}< PUT http://${ip_address}/v2/groups/${selectedBondGroup}/actions/${action}"
        done <<< "$(  echo "${bondGroupsFinalAlt}" | jq -r '.key' )"
    fi

    exit
}


###
### Start of program
###




if [[ "${cronrun}" -eq 1 ]]
then
    rescan=1
    BondSelect
    if [[ -z "${selected_bondid}" ]]
    then
        exit 1
    fi
    BondSearchNetwork "${selected_bondid}"

    while read -r line
    do
        selected_bondid=$( echo "${line}" | awk '{print $1}' )
        ip_address=$( echo "${line}" | awk '{print $2}' )
        bond_token=$( echo "${line}" | awk '{print $3}' )
        echo
        BondGetDevices
        echo
        BondGetGroups
        echo
    done <<< "$( jq -r '.bonds | to_entries[] | select(.value.ip? and .value.token?) | "\(.key) \(.value.ip) \(.value.token)"' < "$bond_db_file" )"

    exit
fi

if [[ "${selected_bondid}" == 'ALL' ]]
then

    while read -r line
    do
        selected_bondid=$( echo "${line}" | awk '{print $1}' )
        ip_address=$( echo "${line}" | awk '{print $2}' )
        bond_token=$( echo "${line}" | awk '{print $3}' )
        echo

        BondRunAll

    done <<< "$( jq -r '.bonds | to_entries[] | select(.value.ip? and .value.token?) | "\(.key) \(.value.ip) \(.value.token)"' < "$bond_db_file" )"

    exit
fi


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

if [[ "${rescanNetwork}" -eq 1 ]]
then
    BondSearchNetwork "${selected_bondid}"
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


Menu
if [[ "${menu}" -eq 1 ]]
then
    BondGetDevices
    if [[ -z "${selectedBondDevice}" ]]
    then
        BondSelectDevice
        if [[ -z "${selectedBondDevice}" ]]
        then
            echo "Bond device not found"
            exit 2
        fi
    fi

    if [[ -z "${action}" ]]
    then
        BondSelectDeviceAction
        if [[ -z "${action}" ]]
        then
            echo "Action to do not found"
            exit 2
        fi
        echo "Action: ${action}"
    fi
    BondDoDeviceAction

    echo
    echo "command to do this again"
    echo "${scriptName} -i ${selected_bondid} -t ${bond_token} -I ${ip_address} -m 1 -d ${selectedBondDevice} -a ${action}"
fi
if [[ "${menu}" -eq 2 ]]
then
    BondGetGroups
    if [[ -z "${selectedBondGroup}" ]]
    then
        BondSelectGroup "${bondGroupsFinal}"
        if [[ -z "${selectedBondGroup}" ]]
        then
            echo "Bond group not found"
            exit 2
        fi
    fi

    if [[ -z "${action}" ]]
    then
        BondSelectGroupAction
        if [[ -z "${action}" ]]
        then
            echo "Action to do not found"
            exit 2
        fi
        echo "Action: ${action}"
    fi
    BondDoGroupAction

    echo
    echo "command to do this again"
    echo "${scriptName} -i ${selected_bondid} -t ${bond_token} -I ${ip_address} -m 2 -g ${selectedBondGroup} -a ${action}"
fi
