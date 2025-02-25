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
    echo $'\nToken invalidated.'
}

# Run the function to get the token
getBearerToken

#Check the UUID of the Computer
UUID=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')

id=$(curl -s "${jamfUrl}/JSSResource/computers/udid/${UUID}/subset/general" \
-H 'accept: application/xml' \
-H "Authorization: Bearer $token" | xmllint --xpath '/computer/general/id/text()' -)

# Get computer details to retrieve the managementId
computerInfo=$(curl -s "$jamfUrl/api/v1/computers-inventory/$id" \
    -H 'accept: application/json' \
    -H "Authorization: Bearer $token")

# Extract the managementId using plutil
managementId=$(echo "$computerInfo" | plutil -extract general.managementId raw -)

if [[ -z "$managementId" || "$managementId" == "null" ]]; then
    echo "No management ID found for computer $id, skipping..."
    exit 1
fi

echo "Found Management ID: $managementId for computer $id"

administratorPasswd=$(curl -s "$jamfUrl/api/v2/local-admin-password/$managementId/account/Administrator/password" \
    -H 'accept: application/json' \
    -H "Authorization: Bearer $token" | plutil -extract password raw -)

# Echo Password
echo "Administrator password: $administratorPasswd"

# If $administratorPasswd says "<stdin>: Could not extract value, error: No value at that key path or invalid key path: password", use $adminPassword instead
if [[ "$administratorPasswd" == *"Could not extract value, error: No value at that key path or invalid key path: password"* ]]; then
    administratorPasswd="$adminPassword"
else 
    adminPassword=$5
fi

secureTokenUsers=()

while IFS= read -r user; do
    status=$(sysadminctl -secureTokenStatus "$user" 2>&1)
    if echo "$status" | grep -q "Secure token is ENABLED"; then
        secureTokenUsers+=("$user")
    fi
done < <(dscl . -list /Users | grep -v '^_')

if [[ ${#secureTokenUsers[@]} -eq 1 && "${secureTokenUsers[0]}" == "$adminUser" ]]; then
    sysadminctl -adminUser "$adminUser" -adminPassword "$adminPassword" -secureTokenOn "$userName" -password "$userPassword"
else
    echo "No need to transfer Secure Token another account is enabled"
fi

# Invalidate the token when done
invalidateToken

exit 0



sudo sysadminctl -adminUser 'administrator' -adminPassword 'EGLPJT-QIYI3K-GMT3W5-BC5WOSCE' -secureTokenOn 'administrator1' -password 'S@intAppleSc0ts!!'
