#!/bin/bash
echo "---------------------------------------------------------------"
#---------------------------------------------------------------#
#			usb-nuke.sh				#
# Description:							#
#	Menu driven script made to both wipe copious amounts	#
#	of USB devices and/or nuke them with a specified 	#
#	system image. Do not plug in any of the USB devices	#
#	you want to modify before starting this script.		#
#								#
# 		   Author: Aaron Beckett			#
# 		     Date: 02/12/2015				#
#---------------------------------------------------------------#


#---------------------------------------------------------------#
#			INITIALIZE VARIABLES			#
#---------------------------------------------------------------#
#
## Initialize temporary directory and temp files
#
mytmpdir=$(mktemp -d /tmp/nuke.XXXXXX) || { echo "Failed to create temp dir"; exit 1; }
mylist=$(mktemp $mytmpdir/list) || { echo "Failed to create temp file"; exit 1; }
myimg=$(mktemp $mytmpdir/img) || { echo "Failed to create temp file"; exit 1; }
#
## Initialize global variables
#
declare -a list=()
declare -a excluded=()
declare -a targets=()

imgpath=""
target_status="i"

#---------------------------------------------------------------#
#			FUNCTIONS				#
#---------------------------------------------------------------#

#------------------------------------------
# Name: get_usb_list
# Description:
#	Stores a list of the USB devices currently plugged
#	into the machine into the "list" array variable.
##
get_usb_list ()
{
    system_profiler SPUSBDataType | grep "BSD Name" | egrep -v s[0-9]\$ | awk '{print $3}' > $mylist
    list=( `cat "$mylist" `)
}

#------------------------------------------
# Name: find_eligible_usbs
# Description:
#	Stores a list of the USB devices plugged in and NOT part of
#	the "excluded" array into the "list" array variable.
##
find_eligible_usbs ()
{
    get_usb_list

    for safe_usb in "${excluded[@]}"; do
	list=( ${targets[@]/"$safe_usb"/} )
    done
}

#------------------------------------------
# Name: select_img
# Description:
#	Asks the user to select a disk image or read one off a
#	USB drive. Stores the path to the image in the "imgpath"
#	variable.
##

#------------------------------------------
# Name: wipe_targets
# Description:
#	Overwrites all USBs in the "targets" array with
#	random data.
##
wipe_targets ()
{
    echo "Clearing all data from USB targets..."
    for device in "${targets[@]}"; do
	{
	    diskutil unmount $device
	    diskutil unmountDisk $device
	} &> /dev/null
	dd if=/dev/urandom of=/dev/r$device bs=1024k &
    done
    wait
    for device in "${targets[@]}"; do
	{
	    diskutil mountDisk $device
	} &> /dev/null
    done
    echo "USB data cleared."
}

#------------------------------------------
# Name: nuke_targets
# Description:
#	Nuke all USBs in the "targets" array with the system image.
##
nuke_targets ()
{
    echo "Writing master image to USB targets..."
    for device in "${targets[@]}"; do
	{
	    diskutil unmount $device
	    diskutil unmountDisk $device
	} &> /dev/null
	dd if=$imgpath of=/dev/r$device bs=1024k &
    done
    wait
    for device in "${targets[@]}"; do
	{
	    diskutil mountDisk $device
	} &> /dev/null
    done
    echo "Master image copied to USB targets."
}


#---------------------------------------------------------------#
#		Initialize list of USB devices			#
#								#
# Compile list of usb devices currently plugged in so that we	#
# can exclude them from being nuked. The names of the safe	#
# USBs are stored in an array called "excluded".		#
#---------------------------------------------------------------#
get_usb_list
excluded=("${list[@]}")


#---------------------------------------------------------------#
#			Select a disk image			#
#---------------------------------------------------------------#

## Ignore this big block of code between the ENDs. It was what I used to
## read the img off of the master thumb drive before having the user
## enter the path instead.

: <<'END'
############ Find Master USB and get the master image ############
## Get the system image from the master usb and store in variable called "master"
read -p "Insert USB with the iCER system image then press Enter..." -s
echo
echo "Registering master USB..."
sleep 5   # sleep for 5 seconds to ensure the usb drive has spun up

find_eligible_usbs

if [ ${#list[@]} == 1 ]; then
    master=${list[0]}
else
    echo "You didn't insert a USB device or you inserted too many USB devices."
    echo "You must insert one and only one USB device while registering the master."
    exit 1
fi
echo "Master USB registered."

echo "Copying system image from master USB..."
diskutil unmountDisk $master
dd if=/dev/r$master of=$myimg bs=1024k
echo "System image copied, initialization complete."
echo
echo
END


############ Find .img file ############
read -p "Enter the full path name of the .img file: " imgpath

if [ -f "$imgpath" ]; then
    echo "Path to the .img file: $imgpath"
else
    echo "Invalid file path."
    exit 1
fi

#---------------------------------------------------------------#
#			MAIN MENU				#
#	1. Wipe USB devices					#
#	2. Nuke USBs with master image				#
#	3. Wipe USB devices AND nuke them with image		#
#	4. Exit							#
#---------------------------------------------------------------#
#
finished=0   # Variable sentry that watches for the user to select exit

## The select command below will make a menu and loop automatically
## but will not display the menu options each time. The while loop
## allows us to force the menu options to display each loop through.
while [ $finished -ne 1 ]; do
    echo
    echo "**************************************************************"
    PS3='Select option: '
    options=("Select New Master Image" "Save Master Image" "Eject All USB Targets" "Wipe USB devices" "Nuke USBs with master image" "Wipe USB devices AND nuke them with image" "Exit")
    select opt in "${options[@]}"
    do
	## Determine if we need to select new USB targets
	if [ "$opt" != "Exit" ]; then
	    if [ ${#targets[@]} -ne 0 ]; then
		echo "You already have valid USB targets, would you like to:"
		echo "	(t): Target them again, or"
		echo "	(i): Insert new targets?"
		echo
		read -p "(t/i): " newUSBs
	    else
		newUSBs="y"
	    fi

	    ## Compile new list of USB targets if needed
	    if [ "$newUSBs" = "i" ]; then
		read -p "Insert USB devices to target then press Enter..." -s
		echo
		echo "Registering USB devices..."
		sleep 2

		find_eligible_usbs
		targets=("${list[@]}")
		
		if [ ${#targets[@]} -gt 0 ]; then
		    echo "USB devices registered."
		else
		    echo "No USB devices were registered."
		    echo
		    break
		fi
	    fi
	fi
	
	## Take the requested action on the target USBs (or quit)
	case $opt in
	    "Select New Master Image")
		echo "select"
		;;
	    "Save Master Image")
		echo "save"
		;;
	    "Eject All USB Targets")
		echo "eject"
		;;
	    "Wipe USB devices")
		wipe_targets
		;;
	    "Nuke USBs with master image")
		nuke_targets
		;;
	    "Wipe USB devices AND nuke them with image")
		wipe_targets
		nuke_targets
		;;
	    "Exit")
		finished=1
		;;
	    *) echo invalid option;;
	esac
	break
    done
done
#---------------------------------------------------------------#

rm -r $mytmpdir

