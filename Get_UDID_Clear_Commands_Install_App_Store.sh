#!/bin/bash

# API Credentials and JSS URL
apiuser="$4"
apipass="$5"
jssURL="https://macapps.saintandrews.net:8443"

# Get the Bearer Token
token_response=$(curl -s -u "${apiuser}:${apipass}" -X POST "${jssURL}/api/v1/auth/token")
bearer_token=$(echo "$token_response" | awk -F'"' '/token/{print $4}')

# Get the Mac's UUID
UUID=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')

#get the computer id from the udid
computerID=$(curl -X 'GET' \
  "${jssURL}/api/v2/computers-inventory?section=IBEACONS&page=0&page-size=100&sort=id&filter=udid%3D%3D%22${UUID}%22" \
  -H 'accept: application/json' \
  -H "Authorization: Bearer $bearer_token" \
  -sfk | grep -oE '"id"\s*:\s*"[^"]*"' | head -1 | cut -d'"' -f4)

echo "Computer ID: $computerID"

deleteCommands=$(curl -X DELETE \
  "${jssURL}/JSSResource/commandflush/computers/id/${computerID}/status/Pending+Failed" \
  -H "Authorization: Bearer $bearer_token")

echo "Delete Commands: $deleteCommands"
