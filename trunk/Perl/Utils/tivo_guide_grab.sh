#!/bin/sh
#
# Script to grab TV data and convert to ICE_EPG.DAT file for tvguide.com.au data
#
USER=username
PASS=password
mv xmlguide.xml ICE_EPG.DAT old_data/
echo "Getting XMLTV data..."
curl -u $USER:$PASS -o xmlguide.xml \
  http://minnie.tuhs.org/tivo-bin/xmlguide.pl
#wget --http-passwd=$PASS --http-user=$USER \
#  http://minnie.tuhs.org/tivo-bin/xmlguide.pl \
#  -O xmlguide.xml
echo "Converting $name with xmltv2epg.pl..."
../xmltv2epg.pl -i xmlguide.xml -o ICE_EPG.DAT
for ((  i = 0 ;  i <= 50;  i++  )); do
	dot="$dot."
	if [ -r '/Volumes/NO NAME/PVR/ICEEPG/' ]; then
		cp ICE_EPG.DAT '/Volumes/NO NAME/PVR/ICEEPG/'
		break
	else
		printf "Waiting for PVR to be connected by USB.$dot\r"
		sleep 5
	fi
done
hdiutil eject /Volumes/NO\ NAME 