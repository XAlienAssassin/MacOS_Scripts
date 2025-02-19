#!/bin/bash

# API USER
user=""
# API PASSWORD
pass=""
# URL (https://yourjamfserver.jamfcloud.com)
jamfUrl=""
# Smart group or static group ID to get computer IDs from
groupID="408"
# Define the admin user name
adminname=""
# New LAPS password to set
newPassword=""  


# Get Bearer token for API calls
getBearerToken() {
    response=$(curl -s -u "$user:$pass" "$jamfUrl/api/v1/auth/token" -X POST)
    token=$(echo "$response" | plutil -extract token raw -)
    tokenExpiration=$(echo "$response" | plutil -extract expires raw - | awk -F . '{print $1}')
    tokenExpirationEpoch=$(date -j -f "%Y-%m-%dT%T" "$tokenExpiration" +"%s")
    echo "Token acquired."
}

# Invalidate the token once done
invalidateToken() {
    curl -w "%{http_code}" -H "Authorization: Bearer $token" "$jamfUrl/api/v1/auth/invalidate-token" -X POST -s -o /dev/null
    echo "\nToken invalidated."
}

# Check token expiration and get a new one if necessary
checkTokenExpiration() {
    nowEpochUTC=$(date -j -f "%Y-%m-%dT%T" "$(date -u +"%Y-%m-%dT%T")" +"%s")
    if [[ tokenExpirationEpoch -gt nowEpochUTC ]]; then
        echo "Token is valid."
    else
        echo "Token expired, fetching new token."
        getBearerToken
    fi
}

# Run the function to get the token
getBearerToken

# Grab all computer IDs from the smart group (ID 802)
echo "Fetching computer IDs from group ID: $groupID"
computerids=($(curl -s $jamfUrl/JSSResource/computergroups/id/$groupID \
-H 'accept: application/xml' \
-H "Authorization: Bearer $token" | xmllint --xpath '/computer_group/computers/computer/id/text()' -))

echo "Found Computer IDs: ${computerids[@]}"

# Loop through all computer IDs to look up the managementId and reset the LAPS password
for id in "${computerids[@]}"; do
    checkTokenExpiration
    
    # Get computer details to retrieve the managementId
    computerInfo=$(curl -s "$jamfUrl/api/v1/computers-inventory/$id" \
        -H 'accept: application/json' \
        -H "Authorization: Bearer $token")

    # Extract the managementId using jq
    managementId=$(jq -r '.general.managementId' <<< "$computerInfo")    

    if [[ -z "$managementId" || "$managementId" == "null" ]]; then
        echo "No management ID found for computer $id, skipping..."
        continue
    fi

    echo "Found Management ID: $managementId for computer $id"
    

    # Reset the LAPS password for the macadmin user using the correct API endpoint
    curl -s -X PUT "$jamfUrl/api/v2/local-admin-password/$managementId/set-password" \
        -H "accept: application/json" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{\"lapsUserPasswordList\": [{\"username\": \"$adminname\", \"password\": \"$newPassword\"}]}" || echo "Failed to reset LAPS password for computer $id with Management ID: $managementId"

done

# Invalidate the token when done
invalidateToken

exit 0