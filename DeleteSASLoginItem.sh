#!/bin/bash

# Get the logged-in user
loggedInUser=$(stat -f%Su /dev/console)

# Define the name of the network to delete
network_name="SAS"

# Delete the specific item from the user's login keychain
security delete-generic-password -l "$network_name" /Users/"$loggedInUser"/Library/Keychains/login.keychain-db

<<<<<<< Updated upstream
# Show the results
=======
# Check if iCloud keychain exists
icloudKeychainCheck=$(ls /Users/${loggedInUser}/Library/Keychains | grep ........-....-....-....-............)
if [[ $icloudKeychainCheck != "" ]]; then
# Delete the keychain-2.db file
rm -r /Users/"$loggedInUser"/Library/Keychains/"$icloudKeychainCheck"/keychain-2.db
echo "Deleting iCloud keychain"
else
echo "No iCloud keychain to delete!"
fi


>>>>>>> Stashed changes
echo "Network '$network_name' deleted from the user's login keychain"