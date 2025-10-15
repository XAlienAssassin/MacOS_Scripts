#!/bin/bash
# Create a timestamped log file name
timestamp=$(date +"%Y%m%d_%H%M%S")
logFile="/Library/Logs/SetRecoveryPassword_${timestamp}.log"

# Set up logging to both file and terminal
# Create the log file
touch "$logFile"

# Set up logging to both file and terminal without using tee
# Save original stdout and stderr
exec 3>&1 4>&2

# Redirect stdout and stderr to the log file
exec 1>>"$logFile" 2>&1

# Define a function to echo to both log file and original stdout
log() {
    echo "$@" >&1
    echo "$@" >&3
}

# Use log function instead of echo for all subsequent output
alias echo="log"

echo "Log file created at: $logFile"

# Prompt for API credentials
echo "Enter your Jamf API username: "
read -u 3 apiuser
echo "Enter your Jamf API password: "
read -s -u 3 apipass
echo "Enter the Advanced Computer Search ID: "
read -u 3 advancedSearchID
echo "Enter the recovery password to set: "
read -u 3 recoveryPassword
echo

# URL (https://yourjamfserver.jamfcloud.com)
jssURL="https://macapps.saintandrews.net:8443"

# Function to get a Bearer Token
getBearerToken() {
    echo "Fetching bearer token..."
    token_response=$(curl -s -u "${apiuser}:${apipass}" -X POST "${jssURL}/api/v1/auth/token" 2>&1)
    bearer_token=$(echo "$token_response" | awk -F'"' '/token/{print $4}')
    token_expires=$(echo "$token_response" | awk -F'"' '/"expires"/{print $4}')
    
    # Check if authentication was successful
    if [[ -z "$bearer_token" ]]; then
        echo "ERROR: Failed to authenticate with Jamf API. Please check your credentials and URL."
        exit 1
    fi
    
    # Convert the expiration time to epoch
    # The expires time is in ISO 8601 format with milliseconds: 2025-10-03T10:30:00.000Z
    tokenExpirationEpoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${token_expires%.*}" +"%s")
    
    echo "Token acquired. Expires at: $token_expires"
}

# Invalidate the token once done
invalidateToken() {
    curl -w "%{http_code}" -H "Authorization: Bearer $bearer_token" "$jssURL/api/v1/auth/invalidate-token" -X POST -s -o /dev/null
    echo "\nToken invalidated."
}

# Check token expiration and get a new one if necessary
checkTokenExpiration() {
    nowEpochUTC=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$(date -u +"%Y-%m-%dT%H:%M:%S")" +"%s")
    
    # Check if token will expire in the next 60 seconds (buffer time)
    if [[ $((tokenExpirationEpoch - 60)) -gt $nowEpochUTC ]]; then
        echo "Token is still valid."
    else
        echo "Token expired or expiring soon, fetching new token."
        getBearerToken
    fi
}

# Get the initial Bearer Token
echo "Authenticating with Jamf API..."
getBearerToken

# Get advanced computer search results
echo "Fetching computers from advanced search ID: $advancedSearchID"
search_results=$(curl -s -H "Accept: text/xml" -H "Authorization: Bearer $bearer_token" "${jssURL}/JSSResource/advancedcomputersearches/id/${advancedSearchID}")

# Extract all computer IDs from the search results
echo "Extracting computer IDs from search results..."

computer_ids=()
# Save the results to a temporary file
echo "$search_results" | xmllint --xpath '//computer/id/text()' - 2>/dev/null > /tmp/computer_ids.txt
while read -r id; do
    if [[ ! -z "$id" ]]; then
        computer_ids+=("$id")
        echo "Found computer ID: $id"
    fi
done < /tmp/computer_ids.txt
rm /tmp/computer_ids.txt

# Count the number of computers found
echo "Found ${#computer_ids[@]} computers in the advanced search"

# Ask the user if they want to continue
echo -n "Do you want to continue with setting recovery passwords? (yes/no): "
read -u 3 confirm
if [[ "$confirm" != "yes" ]]; then
    echo "recovery password process aborted by user."
    exit 0
fi

# Loop through all computer IDs and set recovery passwords
for id in "${computer_ids[@]}"; do
    checkTokenExpiration
    
    # Get computer details to retrieve the managementId
    echo "Getting management ID for computer $id..."
    computerInfo=$(curl -s -H "Accept: application/json" \
        -H "Authorization: Bearer $bearer_token" \
        "${jssURL}/api/v2/computers-inventory/${id}?section=GENERAL")

    # Extract the managementId using sed corrected method
    managementId=$(echo "$computerInfo" | sed -n '/declarativeDeviceManagementEnabled.*true/{N;N;s/.*"managementId" : "\([^"]*\)".*/\1/p;}')

    echo "Extracted managementId: '$managementId'"
 
    if [[ -z "$managementId" || "$managementId" == "null" ]]; then
        echo "No management ID found for computer $id, skipping..."
        continue
    fi

    echo "Found Management ID: $managementId for computer $id"

    # Send SET_RECOVERY_LOCK command to the computer
    echo "Sending SET_RECOVERY_LOCK command to computer $id with management ID: $managementId"
    
    response=$(curl \
        --location \
        --request POST "$jssURL/api/v2/mdm/commands" \
        --header "Authorization: Bearer $bearer_token" \
        --header 'Content-Type: application/json' \
        --data-raw '{
            "clientData": [
                {
                    "managementId": "'"$managementId"'",
                    "clientType": "COMPUTER"
                }
            ],
            "commandData": {
                "commandType": "SET_RECOVERY_LOCK",
                "newPassword": "'"$recoveryPassword"'"
            }
        }')
    
    echo "Response for computer $id: $response"
    echo "---"
    
    sleep 2
done


# Invalidate the token when done
invalidateToken

exit 0

