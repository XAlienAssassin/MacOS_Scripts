#!/bin/bash

# Get the logged-in user
loggedInUser=$(stat -f%Su /dev/console)

# Define the name of the network to delete
network_name="SAS"

# Delete the specific item from the user's login keychain
security delete-generic-password -l "$network_name" /Users/"$loggedInUser"/Library/Keychains/login.keychain-db

# Show the results
echo "Network '$network_name' deleted from the user's login keychain"