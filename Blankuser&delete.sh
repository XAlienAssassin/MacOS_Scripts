#!/bin/bash

# API Credentials and JSS URL
apiuser=""
apipass=""
jssURL=""

# Get the Bearer Token
token_response=$(curl -s -u "${apiuser}:${apipass}" -X POST "${jssURL}/api/v1/auth/token")
bearer_token=$(echo "$token_response" | awk -F'"' '/token/{print $4}')

# Get the Mac's UUID
UUID=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')

# Delete account associated with assigned user
Username=$(curl -H "Accept: text/xml" -sfk -H "Authorization: Bearer $bearer_token" "${jssURL}/JSSResource/computers/udid/${UUID}/subset/location" | xmllint --format - 2>/dev/null | awk -F'>|<' '/<username>/{print $3}')

# Delete user account associated to assignment
# Check if the variable Username is not empty
if [ ! -z "$Username" ]; then
    sudo dscl . -delete /Users/$Username
    sudo rm -rf /Users/$Username
    echo "Deleted account: $Username"
else
    echo "No username provided. Skipping account deletion."
    exit 1
fi

# Set fields to empty value (" ")
value=""

# Update computer details in Jamf
curl -X PUT -H "Content-Type: application/xml" -H "Authorization: Bearer $bearer_token" "$jssURL/JSSResource/computers/udid/$UUID" -d "<computer><location><username>$value</username><realname>$value</realname><real_name>$value</real_name><email_address>$value</email_address><position>$value</position><department>$value</department><phone_number>$value</phone_number><phone>$value</phone></location></computer>"

jamf recon
