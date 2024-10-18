#!/bin/bash

#reads the last user that was logged into the login window.
last_user=$(defaults read /Library/Preferences/com.apple.loginwindow lastUserName)

# Retrieve the full name from the user's plist file
full_name=$(sudo /usr/libexec/PlistBuddy -c "Print :realname:0" "/var/db/dslocal/nodes/Default/users/$last_user.plist")

echo $last_user
echo $full_name

# Extract the first name and last name using awk from the last_user.plist file
if [[ -n $full_name ]]; then
	first_name=$(echo $full_name | awk '{print $1}' | tr -d "-" | tr -d "'")
	last_name=$(echo $full_name | awk '{print $2}' | tr -d "-" | tr -d "'")
    last_name2=$(echo $full_name | awk '{print $3}' | tr -d "-" | tr -d "'")

	# Insert a words between the first name and last name and add domain
	modified_name="$first_name.$last_name$last_name2@saintandrews.net"

	# Echo the modified name (test purpose)
	echo $modified_name
    echo "Script ran successfully!"
    
    # change the assigned username to the modified_name in jamf
	#jamf recon -endUsername $modified_name
else
	echo "Script encountered error"
fi