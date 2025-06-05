#!/bin/bash

# Make time for other stuff to finish
/bin/sleep 1

# Variables
############################################################
loggedInUser=$( ls -l /dev/console | awk '{print $3}' )
LoggedInUserHome="/Users/$loggedInUser"

############################################################

exec > /Users/$loggedInUser/.assigntologin.txt 2>&1

# Log the Variables
echo loggedInUser-variable = $loggedInUser

############################################################

# Check to see if Dock has been built already
assigntologin=/Users/$loggedInUser/.assigntologincheck.txt
echo "The assigntologin file is set to" $assigntologin

if [ -f $assigntologin ]; then
    echo "The assigntologin file exists. Exiting." 
    exit 0
fi

echo No assigntologin found. Continuing to assign $loggedInUser to JAMF!

################################################################################
# Check if loggedInUser is in the exclusion list (case-insensitive)
################################################################################

# List of excluded usernames (all lowercase for comparison)
excluded_users=(
    admin
    presentation
    casper
    scot
    zoom
    administrator
    cgo
    scots
    videos
    sn00py
    infirmary
    sage
    camp
    sagecooks
    livestream
)

# Convert loggedInUser to lowercase for comparison
loggedInUserLower=$(echo "$loggedInUser" | tr '[:upper:]' '[:lower:]')

should_assign=1
for user in "${excluded_users[@]}"; do
    if [[ "$loggedInUserLower" == "$user" ]]; then
        should_assign=0
        break
    fi
done

# Create the assigntologin file
touch /Users/$loggedInUser/.assigntologincheck.txt

if [[ $should_assign -eq 1 ]]; then
    ################################################################################
    # Use Jamf policy trigger to assign $loggedInUser to JAMF
    ################################################################################
    jamf_output=$(jamf policy -event UserAssignment -username "$loggedInUser")
    echo "$jamf_output"
    if echo "$jamf_output" | grep -q 'No policies were found for the "UserAssignment" trigger.' || \
       echo "$jamf_output" | grep -q 'Connection failure: "The network connection was lost."'; then
        echo "No policies found for UserAssignment trigger. Deleting $assigntologin."
        rm -f "$assigntologin"
    fi
else
    echo "User '$loggedInUser' is in the exclusion list. Skipping Jamf policy assignment."
fi

################################################################################

exit 0