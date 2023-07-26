#!/bin/bash

# Define domain suffix to add to username
domain="saintandrews.net"

# Get the last user of computer
lastUser=`defaults read /Library/Preferences/com.apple.loginwindow lastUserName`

if [ $lastUser != "" ]; then
	username=$(echo "$lastUser"\@"$domain")
	# Update Computer Inventory Record
	jamf recon -endUsername $username
else
	echo "No Logins, exiting..."
fi