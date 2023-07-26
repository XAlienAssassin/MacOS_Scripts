#!/bin/bash

## Enter the API Username, API Password, and Jamf Pro URL here
apiuser="medinao"
apipass="Thecandyman1"
jssURL="https://macapps.saintandrews.net:8443/"

## Get the Mac's UUID string
UUID=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')

## Pull the Asset Tag by accessing the computer records "general" subsection
Asset_Tag=$(curl -H "Accept: text/xml" -sfku "${apiuser}:${apipass}" "${jssURL}/JSSResource/computers/udid/${UUID}/subset/general" | xmllint --format - 2>/dev/null | awk -F'>|<' '/<asset_tag>/{print $3}')

## Get Computers Name
Name=$(networksetup -getcomputername)

## Edit the raw text between the quotes below, do not edit ${Name} or ${Asset_Tag}.
loginWindowMessage="
This Bob's School Mac is 
Named ${Name}, has Asset Number ${Asset_Tag}, and is assigned to Bob John's 3rd Grade Class. If found, please contact Bob's School at xxx-xxx-xxxx."

/usr/bin/defaults write /Library/Preferences/com.apple.loginwindow.plist LoginwindowText -string "$loginWindowMessage"