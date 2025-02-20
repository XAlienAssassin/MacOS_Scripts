#!/bin/bash
user=""
# API PASSWORD
pass=""
# URL (https://yourjamfserver.jamfcloud.com)
jamfUrl=""
# New LAPS password to set
adminUser=$4
adminPassword=$5
#This will store the logged in user's name to a variable.
userName=$6
#This will state the password for other administrator account and store it in a variable.
userPassword=$7

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

# Check if Secure Token is enabled for the administrator
secureTokenStatus=$(sysadminctl -secureTokenStatus administrator)

#Check the UUID of the Computer
UUID=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')

id=$(curl -s "${jamfUrl}/JSSResource/computers/udid/${UUID}/subset/general" \
-H 'accept: application/xml' \
-H "Authorization: Bearer $token" | xmllint --xpath '/computer/general/id/text()' -)

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


administratorPasswd=$(curl -s "$jamfUrl/api/v2/local-admin-password/$managementId/account/Administrator/password" \
    -H 'accept: application/json' \
    -H "Authorization: Bearer $token" | jq -r '.password')

# Echo Password
echo "Administrator password: $administratorPasswd"

# If $administratorPasswd is empty, use $adminPassword instead
if [[ -z "$administratorPasswd" ]]; then
    administratorPasswd="$adminPassword"
fi

# If Secure Token is ENABLED for the administrator, transfer it to the user
if [[ $secureTokenStatus == *"Secure Token is ENABLED"* ]]; then
    sysadminctl -adminUser "$adminUser" -adminPassword "$administratorPasswd" -secureTokenOn $userName -password $userPassword
else
    echo "No need to transfer Secure Token"
    exit 1
fi

# Invalidate the token when done
invalidateToken

exit 0
