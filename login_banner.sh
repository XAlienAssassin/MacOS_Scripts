#!/bin/bash
#Bearer Token generate
POST https://saintandrews.net:8443/api//v1/auth/token

# Credentials and API URL
JAMF_API_USERNAME="Your Jamf Pro Username"
JAMF_API_PASSWORD="Your Jamf Pro Password"
JAMF_API_URL="Your Jamf Pro Server URL"

# Get the serial number of the machine
SERIAL_NUMBER=$(ioreg -l | awk '/IOPlatformSerialNumber/ { print $4;}' | sed 's/"//g')

# Get the asset tag and the user's full name from the Jamf Pro Server
ASSET_TAG=$(curl -sku ${JAMF_API_USERNAME}:${JAMF_API_PASSWORD} -H "accept: application/xml" ${JAMF_API_URL}/JSSResource/computers/serialnumber/${SERIAL_NUMBER} | xpath //computer/general/asset_tag 2>/dev/null | sed -e 's/<asset_tag>//;s/<\/asset_tag>//')

USER_FULLNAME=$(curl -sku ${JAMF_API_USERNAME}:${JAMF_API_PASSWORD} -H "accept: application/xml" ${JAMF_API_URL}/JSSResource/computers/serialnumber/${SERIAL_NUMBER} | xpath //computer/location/realname 2>/dev/null | sed -e 's/<realname>//;s/<\/realname>//')

# Create the banner text
BANNER_TEXT="Asset Tag: $ASSET_TAG\nUser: $USER_FULLNAME"

# Create the login window banner
sudo defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText "$BANNER_TEXT"
