#!/bin/bash

#Make time for other stuff to finish
/bin/sleep 5

sleep=/bin/sleep

#Variables
############################################################
dockutil="/usr/local/bin/dockutil"
killall="/usr/bin/killall"
loggedInUser=$( ls -l /dev/console | awk '{print $3}' )
LoggedInUserHome="/Users/$loggedInUser"
UserPlist=$LoggedInUserHome/Library/Preferences/com.apple.dock.plist

############################################################

exec > /Users/$loggedInUser/.docklog.txt 2>&1

#Log the Variables
echo dockutil-variable = $dockutil
echo sleep-variable = $sleep
echo loggedInUser-variable = $loggedInUser

############################################################

#Check to see if Dock has been built already
dockscrap=/Users/$loggedInUser/.dockscrap.txt
echo "The dockscrap file is set to" $dockscrap

if [ -f $dockscrap ]; then
    echo "The dockscrap file exists. Exiting." 
    exit 0
fi

echo No dockscrap found. Continuing to build the dock!

################################################################################
# Use Dockutil to Modify Logged-In User's Dock
################################################################################
echo "------------------------------------------------------------------------"
echo "Current logged-in user: $loggedInUser"
echo "------------------------------------------------------------------------"
echo "Removing all Items from the Logged-In User's Dock..."
$dockutil --remove all --no-restart $UserPlist
$sleep 10

function create_dock {
    echo "Creating New Dock..."
    $dockutil --add '~/Downloads' --section others --view auto --display folder --no-restart $UserPlist
    $dockutil --add '/System/Applications/Launchpad.app' --no-restart $UserPlist
    $dockutil --add '/System/Applications/System Settings.app' --no-restart $UserPlist
    $dockutil --add '/Applications/Self Service.app' --no-restart $UserPlist
    $dockutil --add '/Applications/Safari.app' --no-restart $UserPlist
    $dockutil --add '/Applications/Google Chrome.app' --no-restart $UserPlist
    echo "Restarting Dock..."
    $sleep 10
    $killall Dock
    $sleep 5
}

function check_dock {
    PLIST_CONTENTS=$(defaults read com.apple.dock persistent-apps)

    SEARCH_TEXT_1='
            "file-label" = Safari;
    '

    SEARCH_TEXT_2='
            "file-label" = "Self Service";
    '

    SEARCH_TEXT_3='
            "file-label" = "Google Chrome";
    '

    if [[ "$PLIST_CONTENTS" == *"$SEARCH_TEXT_1"* ]] && \
       [[ "$PLIST_CONTENTS" == *"$SEARCH_TEXT_2"* ]] && \
       [[ "$PLIST_CONTENTS" == *"$SEARCH_TEXT_3"* ]]; then
        return 0
    else
        return 1
    fi
}

# Set the maximum number of attempts to create the correct dock
max_attempts=3
# Initialize the attempt counter
attempt=1

# Loop until the dock is created correctly or the maximum number of attempts is reached
while ! check_dock && [ $attempt -le $max_attempts ]; do
    # Print a message indicating the attempt number and the reason for recreating the dock
    echo "Attempt $attempt: Safari, Self Service, or Google Chrome not found in dock, recreating dock..."
    
    # If this is the second or later attempt, kill the Dock first
    if [ $attempt -gt 1 ]; then
        $dockutil --remove all --no-restart $UserPlist
        $sleep 5
        $killall Dock
        $sleep 5
    fi
    
    # Call the create_dock function to recreate the dock
    create_dock
    # Sleep for 1 second before the next attempt
    $sleep 1
    # Increment the attempt counter
    ((attempt++))
done

# Check if the maximum number of attempts was exceeded
if [ $attempt -gt $max_attempts ]; then
    # Print an error message indicating the failure to create the correct dock
    echo "Failed to create the correct dock after $max_attempts attempts. Exiting."
    # Exit the script with a non-zero status code to indicate an error
    exit 1
fi

#Create the dockscrap file
touch /Users/$loggedInUser/.dockscrap.txt

exit 0