#!/bin/bash

# Bind to Active Directory without requiring confirmation for creating a mobile account
# Username and password are provided as per instructions
# If the computer is already bound to Active Directory, the script will skip the binding process

# Variables
AD_DOMAIN="" # Specify your Active Directory domain
AD_USER="" # AD username
AD_PASS="" # AD password
COMPUTER_ID=$(scutil --get LocalHostName) # Get the local host name of the computer

# Check if already bound to Active Directory
AD_CHECK=$(dsconfigad -show | grep "Active Directory Domain")

if [ -z "$AD_CHECK" ]; then
    # Not bound to AD, proceed with binding
    echo "Binding to Active Directory..."
    dsconfigad -add $AD_DOMAIN -username $AD_USER -password $AD_PASS -computer $COMPUTER_ID -force -mobile enable -mobileconfirm disable -localhome enable -useuncpath disable -groups "admin, domain admins" -alldomains enable

    if [ $? -eq 0 ]; then
        echo "Successfully bound to Active Directory."
    else
        echo "Failed to bind to Active Directory."
    fi
else
    echo "Computer is already bound to Active Directory. Skipping binding process."
fi

