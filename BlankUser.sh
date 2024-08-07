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

# Set fields to empty value (" ")
value=""

# Set fields to email NAC address
value2="nacUnassigned@saintandrews.net"

# Create the XML payload
xml_payload="<computer><location><username>$value2</username><realname>$value</realname><real_name>$value</real_name><email_address>$value2</email_address><position>$value</position><department>$value</department><phone_number>$value</phone_number><phone>$value</phone></location></computer>"

# Write the XML payload to a temporary file
tmp_file=$(mktemp)
echo "$xml_payload" > "$tmp_file"

# Update computer details in Jamf using the temporary file
curl -X PUT -H "Content-Type: application/xml" -H "Authorization: Bearer $bearer_token" "$jssURL/JSSResource/computers/udid/$UUID" -d "@$tmp_file" &
pid=$!
(sleep 15 && kill $pid 2>/dev/null & ) 
wait $pid 2>/dev/null

# Remove the temporary file
rm "$tmp_file"