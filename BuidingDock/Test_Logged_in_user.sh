#!/bin/bash

#Make time for other stuff to finish
/bin/sleep 10

#Variables
############################################################
sleep=/bin/sleep
loggedInUser=$( ls -l /dev/console | awk '{print $3}' )
LoggedInUserHome="/Users/$loggedInUser"
############################################################

exec > /Users/$loggedInUser/.loggedinuser.txt 2>&1

#Log the Variables
echo sleep-variable = $sleep
echo loggedInUser-variable = $loggedInUser

############################################################

#Check to see if loggedinuser has been built already
dockscrap=/Users/$loggedInUser/.loggedinuser.txt
echo "The loggedinuser file is set to" $dockscrap

if [ -f $dockscrap ]; then
    echo "The loggedinuserfile exists. Exiting." 
    exit 0
fi

echo No loggedinuser found. Continuing to build the dock!

############################################################

echo "------------------------------------------------------------------------"
echo "Current logged-in user: $loggedInUser"
echo "------------------------------------------------------------------------"
echo "Removing all Items from the Logged-In User's Dock..."

#Create the loggedinuser file
touch /Users/$loggedInUser/.loggedinuser.txt

exit 0