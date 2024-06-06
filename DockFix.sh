# Fetch the latest release URL dynamically for dockutil
# Fetch the latest release URL dynamically for dockutil
# Use curl to make a silent request (-s) to the GitHub API endpoint for the latest release of the dockutil repository
# Pipe the JSON response to jq to parse it and extract the browser_download_url of the first asset
DOCKUTIL_DOWNLOAD_URL=$(curl -s https://api.github.com/repos/kcrawford/dockutil/releases/latest | awk '/browser_download_url/ {gsub(/[",]/, ""); print $2}')
# Store the extracted URL in the DOCKUTIL_DOWNLOAD_URL variable
curl -L $DOCKUTIL_DOWNLOAD_URL -o dockutil.zip
#!/bin/bash
# check if dockutil is installed, install if it's not.
dockutil="/usr/local/bin/dockutil"
if [[ -x $dockutil ]]; then
    echo "dockutil found, no need to install"
else
    echo "dockutil could not be found, installing..."
    # Fetch the latest release URL dynamically for dockutil
    DOCKUTIL_DOWNLOAD_URL=$(curl -s https://api.github.com/repos/kcrawford/dockutil/releases/latest | awk '/browser_download_url/ {gsub(/[",]/, ""); print $2}')
    curl -L --silent --output /tmp/dockutil.pkg "$DOCKUTIL_DOWNLOAD_URL" >/dev/null
    # install dockutil
    installer -pkg "/tmp/dockutil.pkg" -target /
fi
# vars to use script and set current logged in user dock
killall="/usr/bin/killall"
loggedInUser=$( ls -l /dev/console | awk '{print $3}' )
LoggedInUserHome="/Users/$loggedInUser"
UserPlist=$LoggedInUserHome/Library/Preferences/com.apple.dock.plist
################################################################################
# Use Dockutil to Modify Logged-In User's Dock
################################################################################
echo "------------------------------------------------------------------------"
echo "Current logged-in user: $loggedInUser"
echo "------------------------------------------------------------------------"
echo "Removing all Items from the Logged-In User's Dock..."
sudo -u $loggedInUser $dockutil --remove all --no-restart $UserPlist
echo "Creating New Dock..."
sudo -u $loggedInUser $dockutil --add "/Applications/Google Chrome.app" --no-restart $UserPlist
sudo -u $loggedInUser $dockutil --add "/Applications/Notes.app" --no-restart $UserPlist
sudo -u $loggedInUser $dockutil --add "/Applications/Self Service.app" --no-restart $UserPlist
sudo -u $loggedInUser $dockutil --add "/Applications/Finder.app" --no-restart $UserPlist
sudo -u $loggedInUser $dockutil --add "System/Applications/System Preferences.app" --no-restart $UserPlist
sudo -u $loggedInUser $dockutil --add "~/Downloads" --section others --view auto --display folder --no-restart $UserPlist
echo "Restarting Dock..."
sudo -u $loggedInUser $killall Dock

exit 0

