#!/bin/bash
## from http://groups.google.com/group/macenterprise/browse_thread/thread/25647cbd9e346d16
# remove exiting printers
curPrinterList=`lpstat -p | grep printer | awk '{ print $2 }'`
for p in $curPrinterList; do
    echo "Removing $p..."
        if lpadmin -x $p; then
          echo "Done"
        else
          echo "\n*******Error removing $p********\n$result\n\n"
    fi
    echo
done