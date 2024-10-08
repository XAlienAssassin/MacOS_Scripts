: '
androidstudio)
    name="Android Studio"
    type="dmg"
    if [[ $(arch) == arm64 ]]; then
	 downloadURL=$(curl -fsL "https://developer.android.com/studio#downloads" | grep -i arm.dmg | head -2 | grep -o -i -E "https.*" | cut -d '"' -f1)
	 appNewVersion=$( echo "${downloadURL}" | head -1 | sed 's/^.*[^0-9]\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\).*$/\1/' )
    elif [[ $(arch) == i386 ]]; then
     downloadURL=$(curl -fsL "https://developer.android.com/studio#downloads" | grep -i mac.dmg | head -2 | grep -o -i -E "https.*" | cut -d '"' -f1)
	 appNewVersion=$( echo "${downloadURL}" | head -1 | sed 's/^.*[^0-9]\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\).*$/\1/' )
	fi
    expectedTeamID="EQHXZ8M8AV"
    blockingProcesses=( androidstudio )
    ;;


    curl -fsL "https://developer.android.com/studio#downloads" | grep -i mac.dmg | head -2 | grep -o -i -E "https.*" | cut -d '"' -f1| head -1 | sed 's/^.*[^0-9]\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\).*$/\1/'



vitalsourcebookshelf)
    name="VitalSource Bookshelf"
    type="dmg"
    downloadURL="https://downloads.vitalbook.com/vsti/bookshelf/10.5.3/mac/bookshelf/VitalSource-Bookshelf_10.5.3.2801.dmg"
    appNewVersion=$( echo "${downloadURL}" | sed 's/^.*[^0-9]\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\).*$/\1/' )
    expectedTeamID="QX549BPYZ"
    blockingProcesses=( vitalsourcebookshelf )
    ;;
'


#vitalsourcebookshelf)
#    name="VitalSource Bookshelf"
#    type="dmg"
    # Get the latest version directory
    downloadURL=$(curl -fsL "https://support.vitalsource.com/hc/en-us/articles/360014107913-Mac" | grep -i /mac/bookshelf/ | head -2 | grep -o -i -E "https.*" | cut -d '"' -f1)
    # Construct the download URL
    # Set the app new version
#    appNewVersion=$( echo "${downloadURL}" | sed 's/^.*[^0-9]\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\).*$/\1/' )
#    expectedTeamID="QX549BPYZ8"
#    blockingProcesses=( vitalsourcebookshelf )
#    ;;


    echo $downloadURL