#!/bin/bash

# API Credentials and JSS URL
apiuser=""
apipass=""
jssURL=""

# Get the Mac's UUID
UUID=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')

# Set fields to empty value (" ")
value=""

# Update computer details in Jamf
curl -X PUT -H "Content-Type: application/xml" -u "$apiuser:$apipass" "$jssURL/JSSResource/computers/udid/$UUID" -d "<computer><location><username>$value</username><realname>$value</realname><real_name>$value</real_name><email_address>$value</email_address><position>$value</position><department>$value</department></location></computer>"
