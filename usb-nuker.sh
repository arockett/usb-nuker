#!/bin/bash

echo
echo "*** NOTE ***:"
echo "To ensure proper function of this program, do not remove or"
echo "insert any USB devices while this script is running unless"
echo "prompted to do so."
echo "---------------------------------------------------------------"
#---------------------------------------------------------------#
#			usb-nuker.sh				#
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
mylist=$(mktemp $mytmpdir/list1) || { echo "Failed to create temp file"; exit 1; }
mylist2=$(mktemp $mytmpdir/list2) || { echo "Failed to create temp file"; exit 1; }
mylist3=$(mktemp $mytmpdir/list3) || { echo "Failed to create temp file"; exit 1; }
myimg="$$.img"  # can't make an image file in tmp because then we couldn't use "open" to mount it when checking its validity. Don't know why

# Set the temporary files to delete whenever the program exits
trap "rm -fr $mytmpdir" EXIT
trap "rm -f $myimg" EXIT

#
## Initialize global variables
#
declare -a list=()
declare -a excluded=()
declare -a targets=()

imgpath=""
valid_img=0
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
	list=( ${list[@]/"$safe_usb"/} )
    done
}

#------------------------------------------
# Name: validate_img
# Description:
#	Checks a file to see if it is a valid disk image.
##
validate_img ()
{
    echo "Validating selected disk image..."
    valid_img=0
    if [ "$imgpath" != "" ]; then
	# Try to mount the file and see if it succeeds
	diskutil list | egrep /dev/disk > $mylist
	open $imgpath
	sleep 3  # This is needed to wait for the disk to spin up
	diskutil list | egrep /dev/disk > $mylist2
	grep -f $mylist -v $mylist2 | sed 's/[/]dev[/]*//g' > $mylist3
	list=( `cat "$mylist3" `)

	if [ ${#list[@]} -eq 1 ]; then
	    disk=${list[0]}
	    part="/dev/$disk"
	    part+="s1"
	    {
	    diskutil unmountDisk $disk
	    fsck_msdos $part
	    } > /dev/null
	    if [ $? -eq 0 ]; then
		diskutil eject $disk > /dev/null
		echo "Selected disk image is valid."
		valid_img=1
	    else
		echo
		echo "*** ERROR ***: There was a problem validating the disk image."
		echo -e "The file at:\n\t$imgpath"
		echo "is not a valid FAT file system."
		valid_img=0
	    fi
	else
	    echo
	    echo "*** ERROR ***: There was a problem validating the disk image."
	    echo -e "The file at:\n\t$imgpath"
	    echo "cannot be mounted as a disk."
	    valid_img=0
	fi
    else
	echo
	echo "*** No disk image has been selected. ***"
    fi
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
    selected=0

    while [ $selected -eq 0 ]; do
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

	    # If the path points to an existing file, check to make sure the
	    # file is a valid disk image
	    if [ -f "$imgpath" ]; then
		validate_img
		if [ $valid_img -eq 1 ]; then
		    selected=1
		fi
	    fi
	elif [ "$choice" == "2" ]; then
	    ############ Find Master USB and get the master image ############
	    rm -f $myimg
	    read -p "Insert USB with valid disk image then press [Enter]..." -s
	    echo
	    echo "Registering master USB..."
	    sleep 3   # sleep for 3 seconds to ensure the usb drive has spun up

	    # Get list of usb devices added that are not part of 'excluded' or 'targets'
	    get_usb_list
	    for usb in "${excluded[@]}" "${targets[@]}"; do
		list=( ${list[@]/"$usb"/} )
	    done

	    if [ ${#list[@]} -eq 1 ]; then
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

		# Validate disk image pulled
		validate_img
		if [ $valid_img -eq 1 ]; then
		    selected=1
		fi
	    else
		echo
		echo "*** NOTE ***: You inserted the wrong number of USB devices."
		echo "	You must insert one and only one USB device while registering"
		echo "	the master device. Safely eject any devices you just inserted"
		echo "	and try again."
	    fi
	elif [ "$choice" == "3" ]; then
	    selected=1
	else
	    echo
	    echo "*** Invalid Option ***: Enter '1', '2', or '3'." 
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
    if [ "$imgpath" != "" -a $valid_img -eq 1 ]; then
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
	    echo "*** ERROR ***: Invalid path."
	    echo "That path already has a file associated with it."
	fi
    else
	echo "*** No valid disk image has been selected. ***"
    fi
}

#------------------------------------------
# Name: wipe_targets
# Description:
#	Overwrites all USBs in the "targets" array with zeros.
##
wipe_targets ()
{
    echo "Clearing all data from USB targets..."
    for device in "${targets[@]}"; do
	{
	    diskutil unmount $device
	    diskutil unmountDisk $device
	} &> /dev/null
	dd if=/dev/zero of=/dev/r$device bs=1024k &
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
    if [ "$imgpath" != "" -a $valid_img -eq 1 ]; then
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
	    # Test the FAT file system
	    part="/dev/$device"
	    part+="s1"
	    {
	    diskutil unmountDisk $device
	    fsck_msdos $part
	    } > /dev/null
	    if [ $? -ne 0 ]; then
		echo
		echo "*** ERROR ***: There was a problem copying the disk image to $device."
		echo "$device does not have a valid FAT file system."
		echo
	    else
		diskutil mountDisk $device
	    fi
	done
	echo "Master image copied to USB targets."
    else
	echo "*** No valid disk image has been selected. ***"
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
	echo
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


if [ "$1" == "-q" -o "$1" == "--quick-nuke" ]; then
    #-----------------------------------------------------------#
    #			NUCLEAR OPTION				#
    #	Take whatever is on the first USB device and copy	#
    #	it automatically to every other USB device.		#
    #-----------------------------------------------------------#
    #
    echo "QUICK-NUKE MODE: Press [Ctrl+C] at any time to exit."
    echo "---------------------------------------------------------------"

    # Prompt user to insert master USB
    read -p "Insert Master USB with valid disk image then press [Enter]..." -s
    echo
    echo "Registering master USB..."
    sleep 3   # sleep for 3 seconds to ensure the usb drive has spun up
    find_eligible_usbs
    if [ ${#list[@]} -ne 1 ]; then
	echo
	echo "*** ERROR ***: You inserted the wrong number of USB devices."
	echo "	You must insert one and only one USB device while registering"
	echo "	the master device. Safely eject any devices you just inserted"
	echo "	and try again."
	exit 1
    else
	master=${list[0]}
	excluded=("${excluded[@]}" "$master")
	echo "Master USB registered."
    fi

    # Prompt user to insert target USBs
    echo
    read -p "Insert USB devices to target then press [Enter]..." -s
    echo
    echo "Registering USB devices..."
    sleep 5	# sleep for 5 seconds to ensure the usb drivers have spun up
    find_eligible_usbs
    if [ ${#list[@]} -lt 1 ]; then
	echo
	echo "*** ERROR ***: No USB devices were registered as targets."
	echo "You must insert at least one USB device to target."
	echo
	echo "*** NOTE ***: You should wait until all inserted USB devices"
	echo "have been noticed by the computer before pressing [Enter]."
	exit 1
    else
	targets=("${list[@]}")
	echo "USB devices registered as targets."
    fi

    # Pull master image from master USB
    echo
    echo "Copying disk image from master USB..."

    diskutil unmountDisk $master &> /dev/null
    dd if=/dev/r$master of=$myimg bs=1024k
    imgpath="$myimg"
    diskutil mountDisk $master &> /dev/null

    echo "Master USB copied to temporary file."

    # Validate disk image pulled
    echo
    validate_img
    if [ $valid_img -ne 1 ]; then
	echo
	echo "*** WARNING ***:"
	echo "The disk image from the master USB is not a complete FAT disk image."
	read -p "Would you like to continue anyway? (y/n): " ni
	if [ "$ni" == "n" ]; then
	    echo "Exiting USB Nuker..."
	    exit 1
	fi
    fi

    # Write master image to target USBs
    echo
    read -p "Press [Enter] to copy the master USB to ALL targets..." -s
    echo
    nuke_targets

    # Eject the master USB and all Targets
    echo
    echo "Ejecting master USB device..."
    diskutil eject $master &> /dev/null
    echo "Master USB ejected."
    eject_targets

else
    #-----------------------------------------------------------#
    #			Select a disk image			#
    #-----------------------------------------------------------#
    select_img

    #-----------------------------------------------------------#
    #			MAIN MENU				#
    #	1. Wipe USB devices					#
    #	2. Nuke USBs with master image				#
    #	3. Wipe USB devices AND nuke them with image		#
    #	4. Select New Master Image				#
    #	5. Save Master Image					#
    #	6. Eject All USB Targets				#
    #	7. Exit							#
    #-----------------------------------------------------------#
    #
        
    finished=0   # Variable sentry that watches for the user to select exit

    ## The select command below will make a menu and loop automatically
    ## but will not display the menu options each time. The while loop
    ## allows us to force the menu options to display each loop through.
    while [ $finished -ne 1 ]; do
	echo
	echo "MAIN MENU:"
	echo "---------------------------------------------------------------"
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
		    if [ "$target_status" == "i" ]; then
			eject_targets
		    fi
		else
		    target_status="i"
		fi

		## Compile new list of USB targets if needed
		if [ "$target_status" == "i" ]; then
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
			echo "*** WARNING ***: No USB devices were registered."
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
fi

