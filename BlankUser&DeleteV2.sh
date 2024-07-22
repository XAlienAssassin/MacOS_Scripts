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

# Default Username
Username2="nacUnassigned@saintandrews.net"

# Check if Username exists and handle account deletion/update
username_without_domain=${Username%%@*}

if id "$username_without_domain" >/dev/null 2>&1; then
    # Delete user account associated with assignment
    sudo dscl . -delete /Users/${Username%%@*}
    sudo rm -rf /Users/${Username%%@*}
    echo "Deleted account: ${Username%%@*}"
    # Set fields to empty value (" ")
    value=""
    # Set fields to email NAC address
    value2="nacUnassigned@saintandrews.net"
    # Update computer details in Jamf
    curl -X PUT -H "Content-Type: application/xml" -H "Authorization: Bearer $bearer_token" "$jssURL/JSSResource/computers/udid/$UUID" -d "<computer><location><username>$value2</username><realname>$value</realname><real_name>$value</real_name><email_address>$value2</email_address><position>$value</position><department>$value</department><phone_number>$value</phone_number><phone>$value</phone></location></computer>"
    jamf recon
else
    echo "Username $Username does not exist on this computer. Skipping account deletion."
    exit 1
fi