#!/bin/bash
last_user=$(defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
full_name=$(sudo /usr/libexec/PlistBuddy -c "Print :realname:0" "/var/db/dslocal/nodes/Default/users/$last_user.plist")
first_name=$(echo $full_name | awk '{print $1}')
last_name=$(echo $full_name | awk '{print $2}')
modified_name="$first_name.$last_name@saintandrews.net"
echo $modified_name
jamf recon -endUsername $modified_name

