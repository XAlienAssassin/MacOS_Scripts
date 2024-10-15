# Set the Jamf Pro URL here if you want it hardcoded.
jamfpro_url=""	    

# Set the username here if you want it hardcoded.
jamfpro_user=""

# Set the password here if you want it hardcoded.
jamfpro_password=""	

token_response=$(curl -s -u "${jamfpro_user}:${jamfpro_password}" -X POST "${jamfpro_url}/api/v1/auth/token")
bearer_token=$(echo "$token_response" | awk -F'"' '/token/{print $4}')

api_token=$(/usr/bin/curl -X POST --silent -u "${jamfpro_user}:${jamfpro_password}" "${jamfpro_url}/api/v1/auth/token" | plutil -extract token raw -)

echo $bearer_token