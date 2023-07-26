#!/bin/bash

# API Credentials
#########################################################################################
apiuser="API_Banner"
apipass="saint12345"
jssURL="https://macapps.saintandrews.net:8443"

## Get the Mac's UUID string
UUID=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')

## Pull the Asset Tag by accessing the computer records "general" subsection
Real_Name=$(curl -H "Accept: text/xml" -sfku "${apiuser}:${apipass}" "${jssURL}/JSSResource/computers/udid/${UUID}/subset/location" | xmllint --format - 2>/dev/null | awk -F'>|<' '/<realname>/{print $3}')

## Get Computers Name
Name=$(networksetup -getcomputername)

## Edit the raw text between the quotes below, do not edit ${Name} or ${Asset_Tag}.
loginWindowMessage="Saint Andrew's School
Honor Above All 
Assigned to: ${Real_Name}"

sudo /usr/bin/defaults write /Library/Preferences/com.apple.loginwindow.plist LoginwindowText -string "$loginWindowMessage"