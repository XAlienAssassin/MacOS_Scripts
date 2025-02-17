#!/bin/bash

# API Credentials
#########################################################################################
apiuser=""
apipass=""
jssURL=""

# Get the Bearer Token
token_response=$(curl -s -u "${apiuser}:${apipass}" -X POST "${jssURL}/api/v1/auth/token")
bearer_token=$(echo "$token_response" | awk -F'"' '/token/{print $4}')

# Get the Mac's UUID string
UUID=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')

# Pull the Asset Tag by accessing the computer records "general" subsection
Real_Name=$(curl -H "Accept: text/xml" -H "Authorization: Bearer ${bearer_token}" -sfk "${jssURL}/JSSResource/computers/udid/${UUID}/subset/location" | xmllint --format - 2>/dev/null | awk -F'>|<' '/<realname>/{print $3}')

# Split the real name into words
First_word=$(echo "$Real_Name" | awk '{print $1}')
Last_word=$(echo "$Real_Name" | awk '{print $NF}')

# Set first_name and last_name variables for use in computer name
first_name="$First_word"
last_name="$Last_word"

serial=$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')

# Check the length of the serial number
if [[ ${#serial} -eq 12 ]]; then
    # If the length is 12, extract 4 characters starting from index 4
    middle4=${serial:4:4}
else
    # Otherwise, extract 4 characters starting from index 3
    middle4=${serial:3:4}
fi

echo "$middle4"

# Change Computer Name
# Set the new computer name
new_computer_name="${first_name}-${last_name}"

sudo scutil --set ComputerName "$new_computer_name"
sudo scutil --set LocalHostName "$new_computer_name"
sudo scutil --set HostName "$new_computer_name"
    
echo "Computer name changed to: $new_computer_name"
