#!/bin/bash

# Remove JAMF Framework
/usr/local/jamf/bin/jamf removeFramework

# Delete this script after execution
rm -f /Library/scripts/Decommision.sh

exit 0
