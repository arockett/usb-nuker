#!/bin/bash
echo
echo "*** NOTE: ***"
echo "To ensure proper function of this program, do not remove or"
echo "insert any USB devices while this script is running unless"
echo "prompted to do so."
echo "*************"
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
select_img ()
{
    valid_img=0

    while [ $valid_img -eq 0 ]; do
	echo
	echo "Would you like to:"
	echo " 1. Choose an image file from your computer, or"
	echo " 2. Copy an image from a master USB?"
	echo " 3. Go to Main Menu"
	read -p "Option: " choice
	echo

	if [ "$choice" == "1" ]; then
	    ############ Specify path of a .img file ############
	    read -p "Enter full path name of the .img file: " imgpath
	    echo

	    # If the path name ends with '.img' AND the path points to an existing file
	    if [[ "$imgpath" == *.img ]]; then
		if [ -f "$imgpath" ]; then
		    valid_img=1
		fi
	    fi
	    if [ $valid_img -ne 1 ]; then
		echo "*** Invalid file path. ***"
	    fi
	elif [ "$choice" == "2" ]; then
	    echo "*** NOTE: This option has not been thoroughly tested yet. ***"
	    echo
	    ############ Find Master USB and get the master image ############
	    read -p "Insert USB with valid disk image then press [Enter]..." -s
	    echo
	    echo "Registering master USB..."
	    sleep 5   # sleep for 5 seconds to ensure the usb drive has spun up

	    find_eligible_usbs

	    if [ "${#list[@]}" -eq "1" ]; then
		master=${list[0]}
		echo "Master USB registered."
		echo "Copying disk image from master USB..."

		diskutil unmountDisk $master &> /dev/null
		dd if=/dev/r$master of=$myimg bs=1024k
		imgpath="$myimg"
		diskutil mountDisk $master &> /dev/null

		echo "Disk image copied to temporary file."
		echo
		diskutil eject $master
		read -p "Remove the master USB device then press [Enter]..." -s
		echo
		valid_img=1
	    else
		echo "*** You inserted the wrong number of USB devices. ***"
		echo "    You must insert one and only one USB device"
		echo "    while registering the master device."
	    fi
	elif [ "$choice" == "3" ]; then
	    break
	else
	    echo "*** Invalid Option, enter '1', '2', or '3'. ***"
	fi 
    done
}

#------------------------------------------
# Name: save_img
# Description:
#	Asks user for a location to save the disk image currently
#	used by the nuker and saves the image to that location.
##
save_img ()
{
    if [ "$imgpath" != "" ]; then
	read -p "Enter filename: " path
	echo

	# Make sure the path is not an empty string
	if [ "$path" == "" ]; then
	    echo "*** You must enter a path to save the disk image at. ***"
	    break
	fi

	# If the path doesn't end with '.img' then append it to the path
	if [[ "$path" != *.img ]]; then
	    path="$path.img"
	fi

	# If the path does not already refer to an existing file then copy the disk image
	if [ ! -f "$path" ]; then
	    echo "Saving disk image..."
	    cp $imgpath $path
	    echo "Disk image saved."
	else
	    echo "*** Invalid path. ***"
	    echo "That path already has a file associated with it."
	fi
    else
	echo "*** No disk image has been selected. ***"
    fi
}

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
    if [ "$imgpath" != "" ]; then
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
    else
	echo "*** No disk image has been selected. ***"
    fi
}

#------------------------------------------
# Name: eject_targets
# Description:
#	Eject all USB targets.
##
eject_targets ()
{
    if [ ${#targets[@]} -ne 0 ]; then
	echo "Ejecting USB targets..."
	for device in "${targets[@]}"; do
	    diskutil eject $device
	done
	unset targets
	echo "Finished ejecting USB targets."
	read -p "Remove the ejected devices then press [Enter]..." -s
    else
	echo "*** There are no USB targets to eject. ***"
    fi
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
select_img


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
    options=("Wipe USB devices" "Nuke USBs with master image" "Wipe USB devices AND nuke them with image" "Select New Master Image" "Save Master Image" "Eject All USB Targets"  "Exit")
    select opt in "${options[@]}"
    do
	echo
	## Determine if we need to select new USB targets
	if [ "$opt" == "Wipe USB devices" -o "$opt" == "Nuke USBs with master image" -o "$opt" == "Wipe USB devices AND nuke them with image" ]; then
	    if [ ${#targets[@]} -ne 0 ]; then
		echo "You already have valid USB targets, would you like to:"
		echo "	(t): Target them again, or"
		echo "	(i): Insert new targets?"
		echo
		read -p "(t/i): " target_status
		echo
	    else
		target_status="i"
	    fi

	    ## Compile new list of USB targets if needed
	    if [ "$target_status" = "i" ]; then
		read -p "Insert USB devices to target then press [Enter]..." -s
		echo
		echo "Registering USB devices..."
		sleep 5

		find_eligible_usbs
		targets=("${list[@]}")
		
		if [ ${#targets[@]} -gt 0 ]; then
		    echo "USB devices registered."
		    echo
		else
		    echo "*** No USB devices were registered. ***"
		    break
		fi
	    fi
	fi
	
	## Take the requested action on the target USBs (or quit)
	case $opt in
	    "Wipe USB devices")
		read -p "Are you sure you want to wipe ALL data from ALL targeted USB devices? (y/n): " choice
		if [ "$choice" == "y" ]; then
		    wipe_targets
		fi
		;;
	    "Nuke USBs with master image")
		read -p "Are you sure you want to overwrite ALL targeted USB devices with the selected disk image? (y/n): " choice
		if [ "$choice" == "y" ]; then
		    nuke_targets
		fi
		;;
	    "Wipe USB devices AND nuke them with image")
		read -p "Are you sure you want to wipe ALL data from ALL targeted USBs AND overwrite ALL targeted USB devices with the selected disk image? (y/n): " choice
		if [ "$choice" == "y" ]; then
		    wipe_targets
		    nuke_targets
		fi
		;;
	    "Select New Master Image")
		select_img
		;;
	    "Save Master Image")
		save_img
		;;
	    "Eject All USB Targets")
		eject_targets
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

