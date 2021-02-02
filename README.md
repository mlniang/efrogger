
EFrogger - Enhanced VLAN Hopping Frogger
============================================

Simple VLAN enumeration and hopping script.

Based on Frogger by NCC Group Plc - http://www.nccgroup.com/

The original Frogger is developed by Daniel Compton, daniel dot compton at nccgroup dot com

https://github.com/nccgroup/vlan-hopping

Released under AGPL see LICENSE for more information

What's New ?
=======================
* Possibility to pass the interface directly as parameter
* Possibility to pass the timing variables as parameters
* Use of nmcli from Network Manager for a better control and naming of discovered interfaces

Installing  
=======================
    git clone https://github.com/mlniang/efrogger.git


How To Use	
=======================
    ./efrogger.sh
        -h, --help
            Shows this help.

        -i, --interface string
            Network interface to use. If none is specified, will be asked interactively.

        -t, --tagsec int
            The number of seconds to sniff for 802.1Q tagged packets. Default is 90.

        -c, --cdpsec int
            The number of seconds to sniff for CDP packets once verified CDP is on. Default is 90.

        -d, --dtpwait int
            The number of seconds to wait for DTP attack via yersinia to trigger. Default is 20.

        -n, --noniccheck
            Use it if you are confident your built in NIC will work within VMware i.e you have made reg change for Intel card.

Run as root.

Features	
=======================

* Sniffs out CDP packets and extracts (VTP domain name, VLAN management address, Native VLAN ID and IOS version of Cisco devices)
* It will enable a DTP trunk attack automatically
* Sniffs out and extracts all 802.1Q tagged VLAN packets within STP packets and extracts the unique IDs.
* Auto arp-scans the discovered VLAN IDs and auto tags packets and scans each VLAN ID for live devices.
* Auto option to auto create a VLAN interface within the found network to connect to that VLAN.

Requirements   
=======================
* Arp-Scan 1.8 (in order to support VLAN tags must be V1.8 - Backtrack ships with V1.6 that does not support VLAN tags) http://www.nta-monitor.com/tools-resources/security-tools/arp-scan
* nmcli (built into Kali Linux)
* Yersina
* Tshark (built into Kali Linux)
* Screen (built into Kali Linux)
* Vconfig (built into Kali Linux)
* bc


Tested Kali Linux 2020.4.

* Notes for VMware. VLAN hopping generally (not just this script) can have issues within VMware if running the VM within Windows with certain Intel drivers. The Intel drivers strip off the tags before it reaches the VM. Either use an external USB ethernet card such as a DLink USB 2.0 DUB-E100 (old model 10/100 not gigabit) or boot into Backtrack nativiely from a USB stick. Intel has published a registry fix, to work on some models: http://www.intel.com/support/network/sb/CS-005897.htm - adding "MonitorMode" 1 to the registry does resolve the issue.


Screen Shot    
=======================
<img src="http://www.commonexploits.com/wp-content/uploads/2012/05/new1.png" alt="Screenshot" style="max-width:100%;">

<img src="http://www.commonexploits.com/wp-content/uploads/2012/05/new2.png" alt="Screenshot" style="max-width:100%;">