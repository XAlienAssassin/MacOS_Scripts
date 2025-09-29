#!/bin/bash
# Create a timestamped log file name
timestamp=$(date +"%Y%m%d_%H%M%S")
logFile="/Library/Logs/Set_Recovery_Password_${timestamp}.log"

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
read -s -u 3 recoveryPassword
echo

# URL (https://yourjamfserver.jamfcloud.com)
jssURL="https://macapps.saintandrews.net:8443"

# Function to get a new bearer token
get_bearer_token() {
    echo "Authenticating with Jamf API..."
    local token_response=$(curl -s -u "${apiuser}:${apipass}" -X POST "${jssURL}/api/v1/auth/token")
    local new_token=$(echo "$token_response" | awk -F'"' '/token/{print $4}')
    
    if [[ -z "$new_token" ]]; then
        echo "Error: Failed to obtain bearer token"
        return 1
    fi
    
    bearer_token="$new_token"
    # Store the time when token was obtained (for tracking)
    token_obtained_time=$(date +%s)
    echo "Bearer token obtained successfully"
    return 0
}

# Function to check if we need to refresh the token and do so if needed
refresh_token_if_needed() {
    # Jamf tokens typically expire after 30 minutes (1800 seconds)
    # We'll refresh if it's been more than 25 minutes (1500 seconds) to be safe
    local current_time=$(date +%s)
    local token_age=$((current_time - token_obtained_time))
    
    if [[ $token_age -gt 1500 ]]; then
        echo "Token is getting old (${token_age} seconds), refreshing..."
        get_bearer_token
        return $?
    fi
    return 0
}

# Function to get computer management ID from computer ID
get_management_id() {
    local computer_id="$1"
    
    # Get computer details to extract management ID
    local computer_details=$(curl -s -H "Accept: application/json" \
        -H "Authorization: Bearer $bearer_token" \
        "${jssURL}/api/v1/computers-inventory-detail/${computer_id}")
    
    # Extract management ID from the response
    local management_id=$(echo "$computer_details" | awk -F'"' '/"managementId"/{print $4}')
    
    if [[ -z "$management_id" ]]; then
        echo "Error: Could not retrieve management ID for computer $computer_id"
        return 1
    fi
    
    echo "$management_id"
    return 0
}

# Function to make API call with automatic token refresh on 401/403 errors
api_call_with_retry() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    # First attempt
    local response=$(curl -s -w "\n%{http_code}" -X "$method" "$endpoint" \
        -H "Authorization: Bearer $bearer_token" \
        -H "Content-Type: application/json" \
        -d "$data")
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    # If we get 401 or 403, try refreshing token and retry once
    if [[ "$http_code" == "401" ]] || [[ "$http_code" == "403" ]]; then
        echo "Received HTTP $http_code, attempting to refresh token..."
        if get_bearer_token; then
            # Retry the call with new token
            response=$(curl -s -w "\n%{http_code}" -X "$method" "$endpoint" \
                -H "Authorization: Bearer $bearer_token" \
                -H "Content-Type: application/json" \
                -d "$data")
            http_code=$(echo "$response" | tail -n1)
            body=$(echo "$response" | sed '$d')
        else
            echo "Error: Failed to refresh token"
            return 1
        fi
    fi
    
    # Output the response body and return success/failure based on HTTP code
    echo "$body"
    
    # Check if the HTTP code indicates success (2xx)
    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        return 0
    else
        echo "Error: API call failed with HTTP code $http_code"
        return 1
    fi
}

# Get initial Bearer Token
if ! get_bearer_token; then
    echo "Failed to authenticate. Exiting."
    exit 1
fi

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
    echo "Recovery password process aborted by user."
    exit 0
fi

# Loop through all computer IDs and set recovery passwords
echo "Starting to set recovery passwords for all computers..."
failed_computers=()
successful_computers=()

for id in "${computer_ids[@]}"; do
    echo "Setting recovery password for Computer ID: $id"
    
    # Check if we need to refresh the token before making the API call
    if ! refresh_token_if_needed; then
        echo "Error: Failed to refresh token for computer $id. Skipping..."
        failed_computers+=("$id")
        continue
    fi
    
    # Get the management ID for this computer
    echo "Getting management ID for computer $id..."
    management_id=$(get_management_id "$id")
    
    if [[ $? -ne 0 ]] || [[ -z "$management_id" ]]; then
        echo "Error: Could not get management ID for computer $id. Skipping..."
        failed_computers+=("$id")
        continue
    fi
    
    echo "Management ID for computer $id: $management_id"
    
    # Create the JSON payload for the recovery password command
    json_payload=$(cat << EOF
{
    "clientData": [
        {
            "managementId": "$management_id",
            "clientType": "COMPUTER"
        }
    ],
    "commandData": {
        "commandType": "SET_RECOVERY_LOCK",
        "newPassword": "$recoveryPassword"
    }
}
EOF
)
    
    # Make the API call to set recovery password
    recovery_result=$(api_call_with_retry "POST" "${jssURL}/api/v2/mdm/commands" "$json_payload")
    
    if [[ $? -eq 0 ]]; then
        echo "Recovery password command sent successfully for computer $id"
        echo "Response: $recovery_result"
        successful_computers+=("$id")
    else
        echo "Error: Failed to set recovery password for computer $id"
        echo "Response: $recovery_result"
        failed_computers+=("$id")
    fi
    
    # Add a small delay to avoid overwhelming the server
    sleep 2
done

echo "Recovery password process completed."
echo "Successful: ${#successful_computers[@]} computers"
echo "Failed: ${#failed_computers[@]} computers"

if [[ ${#failed_computers[@]} -gt 0 ]]; then
    echo "Failed computer IDs: ${failed_computers[*]}"
fi

if [[ ${#successful_computers[@]} -gt 0 ]]; then
    echo "Successful computer IDs: ${successful_computers[*]}"
fi
