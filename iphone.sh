#!/bin/bash

bond_phones_file="${HOME}/.bond/phone"
updateRan=0

# Make sure we have nmap installed.
if [[ -z "$( command -v nmap )" ]]
then
    if [[ "${updateRan}" -eq 0 ]]
    then
        sudo apt update
        updateRan=1
    fi
    echo "Installing nmap"
    sudo apt install nmap -y
    echo
fi


# Make sure we have tshark installed.
if [[ -z "$( command -v tshark )" ]]
then
    if [[ "${updateRan}" -eq 0 ]]
    then
        sudo apt update
        updateRan=1
    fi
    echo "Installing tshark"
    sudo apt install tshark -y
    sudo chmod +x /usr/bin/dumpcap
    echo
fi

# Get interface info on this box.
myIP=$( ip route get 8.8.8.8 | awk '{print $7}' | head -n 1 )
interfaceName=$( ip route get 8.8.8.8 | awk '{print $5}' | head -n 1 )
nmapScanRange=$( ip route | grep '/' | grep "${interfaceName}" | awk '{print $1}' | head -n 1 )

# Check for open ports.
openPorts=$( nmap -p 62078 "${nmapScanRange}" | grep -B 4 'open' )

# Wait 3 seconds.
sleep 3

# Check for MAC to IP table.
arplist=$( arp -a | grep -v '<incomplete>' | sort -V )

checkphone() {
    phoneMacAddress=${1}
    phoneMacAddress=$(echo "${phoneMacAddress}" | sed 's/-/:/g')
    phoneName=$(echo "${phoneMacAddress}" | sed 's/:/-/g')
    phoneOpenPort=0
    phoneIP=$( echo "${arplist}" | grep "${phoneMacAddress}" | awk '{print $2}' | tr -d '()' )

    if [[ -n "${phone1IP}" ]]
    then
        phoneOpenPort=$( echo "${openPorts}" | grep -cF "${phone1IP}" )
    fi
    timestamp=$(date +%s)

    if [[ "${phoneOpenPort}" -gt 0 ]]
    then
        echo -e "${phoneMacAddress} phone found on local network via open port.\n\n${timestamp}" > "${bond_phones_file}-${phoneName}.txt"
        return
    fi
    (trap 'kill 0' SIGINT; ( tshark -i "${interfaceName}" -f "ether src host ${phoneMacAddress} or ether dst host ${phoneMacAddress}" -c 2 -a duration:590 2>/dev/null > "${bond_phones_file}-${phoneName}.tmp";
    date +%s >> "${bond_phones_file}-${phoneName}.tmp";
    echo -e "\n\n${timestamp}" >> "${bond_phones_file}-${phoneName}.tmp";
    mv "${bond_phones_file}-${phoneName}.tmp" "${bond_phones_file}-${phoneName}.txt" ) & )
    echo "${phoneMacAddress} running"
}

# MAC addresses of the phones. Add or remove more checkphone function calls depending on how many iphones you have in your household
#
# How to get the iphone mac address
# Open the Settings app
# Select General
# Select About
# Scroll down and note Wi-Fi Address
# The Wi-Fi address is your Mac address 
checkphone "00:B0:D0:63:C2:26"
checkphone "80:BD:05:39:D6:4E"
