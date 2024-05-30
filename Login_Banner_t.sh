#!/bin/bash

# API Credentials
#########################################################################################
apiuser=""
apipass=""
jssURL="https://macapps.saintandrews.net:8443"

## Get the Bearer Token
token_response=$(curl -s -u "${apiuser}:${apipass}" -X POST "${jssURL}/api/v1/auth/token")
bearer_token=$(echo "$token_response" | jq -r '.token')

## Get the Mac's UUID string
UUID=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')

## Pull the Asset Tag by accessing the computer records "general" subsection
Real_Name=$(curl -H "Accept: text/xml" -H "Authorization: Bearer ${bearer_token}" -sfk "${jssURL}/JSSResource/computers/udid/${UUID}/subset/location" | xmllint --format - 2>/dev/null | awk -F'>|<' '/<realname>/{print $3}')

## Get Computers Name
Name=$(networksetup -getcomputername)

## Edit the raw text between the quotes below, do not edit ${Name} or ${Asset_Tag}.
loginWindowMessage="Saint Andrew's School
Honor Above All 
Assigned to: ${Real_Name}"

sudo /usr/bin/defaults write /Library/Preferences/com.apple.loginwindow.plist LoginwindowText -string "$loginWindowMessage"

echo "$token_response"
