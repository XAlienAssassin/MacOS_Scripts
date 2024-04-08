#!/bin/bash

# API Credentials and JSS URL
apiuser=""
apipass=""
jssURL=""

# Get the Mac's UUID
UUID=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')

#delete account associated with assigned user
Username=$(curl -H "Accept: text/xml" -sfku "${apiuser}:${apipass}" "${jssURL}/JSSResource/computers/udid/${UUID}/subset/location" | xmllint --format - 2>/dev/null | awk -F'>|<' '/<username>/{print $3}')

#delete user account associated to assignment
# Check if the variable Username is not empty
if [ ! -z "$Username" ]; then
# End of Selection
    sudo dscl . -delete /Users/$Username
    sudo rm -rf /Users/$Username
    echo "Deleted account: $Username"
else
    echo "No username provided. Skipping account deletion."
fi

# Set fields to empty value (" ")
value=""

# Update computer details in Jamf
curl -X PUT -H "Content-Type: application/xml" -u "$apiuser:$apipass" "$jssURL/JSSResource/computers/udid/$UUID" -d "<computer><location><username>$value</username><realname>$value</realname><real_name>$value</real_name><email_address>$value</email_address><position>$value</position><department>$value</department><phone_number>$value</phone_number><phone>$value</phone></location></computer>"

jamf recon


