#!/bin/bash

# Script to detect if a computer has a local admin account on it with an UID of above 500, 
# excluding the "Administrator" and "Casper" accounts

# Initialize array
list=()

# Generate user list of users with UID greater than 500, excluding "Administrator" and "Casper" accounts
for username in $(dscl . list /Users UniqueID | awk '$2 > 500 { print $1 }' | grep -Ev '^(Administrator|Casper)$'); do

    # Check which usernames are reported as being admins. 
    # The check runs dsmemberutil's check membership and lists the
    # accounts that are reported as admin users. Actual check is
    # for accounts that are NOT not an admin (i.e. not standard users).
    if [[ $(dsmemberutil checkmembership -U "${username}" -G admin) != *not* ]]; then
        # Any reported accounts are added to the array list
        list+=("${username}")
    fi
done

# Print the array's list contents
echo "<result>${list[@]}</result>"