#!/usr/bin/env bash
####################################################################################################
# A script to collect the domain-associated accounts logged-in to iCloud                           #
# • If no accounts are logged-in to iCloud, "None" will be returned.                               #
####################################################################################################



####################################################################################################
#
# Global Variables
#
####################################################################################################

scriptVersion="0.0.3"
domainsToCheck=("domain1.org" "domain2.org" "domain3.org")
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ && ! /loginwindow/ { print $3 }' )

# If no user is logged-in; fail back to last logged-in user
if [[ -z "${loggedInUser}" || "${loggedInUser}" == "loginwindow" ]]; then
    loggedInUser=$( last -1 -t ttys000 | awk '{print $1}' )
fi



####################################################################################################
#
# Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Check for match in domains to check
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function domainCheck() {
    accountDomain="${1}"
    if [[ "${iCloudTest}" == *"${accountDomain}"* ]]; then
        appleID=$( grep -e "[a-zA-Z0-9._]\+@${accountDomain}" <<< "${iCloudTest}" )
        RESULT+="${appleID}; "
    fi
}



####################################################################################################
#
# Program
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Retrieve all iCloud accounts
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

iCloudTest=$( defaults read /Users/"${loggedInUser}"/Library/Preferences/MobileMeAccounts.plist Accounts | grep AccountID | cut -d '"' -f 2)



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Evalute domain-specific iCloud accounts
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ -n "${iCloudTest}" ]]; then
    for accountDomain in "${domainsToCheck[@]}"; do
        domainCheck "${accountDomain}"
    done
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Output Results
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ -z "${RESULT}" ]]; then RESULT="None"; fi

echo "<result>${RESULT}</result>"