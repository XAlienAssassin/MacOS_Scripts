#!/bin/bash

#Make time for other stuff to finish
/bin/sleep 3

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
$sleep 2
echo "Creating New Dock..."
$dockutil --add '~/Downloads' --section others --view auto --display folder --no-restart $UserPlist
$dockutil --add '/System/Applications/Launchpad.app' --no-restart $UserPlist
$dockutil --add '/System/Applications/System Settings.app' --no-restart $UserPlist
$dockutil --add '/Applications/Self Service.app' --no-restart $UserPlist
$dockutil --add '/Applications/Safari.app' --no-restart $UserPlist
$dockutil --add '/Applications/Google Chrome.app' --no-restart $UserPlist
echo "Restarting Dock..."
$killall Dock

$sleep 2

# Check if Safari, Self Service, and Google Chrome are in the dock, if not, redo the dock additions
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

$sleep 2

while [[ "$PLIST_CONTENTS" != *"$SEARCH_TEXT_1"* ]] && \
      [[ "$PLIST_CONTENTS" != *"$SEARCH_TEXT_2"* ]] && \
      [[ "$PLIST_CONTENTS" != *"$SEARCH_TEXT_3"* ]]; do
    echo "Safari, Self Service, or Google Chrome not found in dock, redoing dock additions..."
    $dockutil --add '~/Downloads' --section others --view auto --display folder --no-restart $UserPlist
    $dockutil --add '/System/Applications/Launchpad.app' --no-restart $UserPlist 
    $dockutil --add '/System/Applications/System Settings.app' --no-restart $UserPlist
    $dockutil --add '/Applications/Self Service.app' --no-restart $UserPlist
    $dockutil --add '/Applications/Safari.app' --no-restart $UserPlist
    $dockutil --add '/Applications/Google Chrome.app' --no-restart $UserPlist
    $killall Dock
    PLIST_CONTENTS=$(defaults read com.apple.dock persistent-apps)
done

#Create the dockscrap file
touch /Users/$loggedInUser/.dockscrap.txt

exit 0
