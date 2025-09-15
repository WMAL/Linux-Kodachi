#!/bin/sh
#
# bodhibuilder
#   This is a script that runs during boot of the live system
#
#   It is called by the file  ~/.config/autostart/iso_boot_script.desktop
#   Which is created from file  /etc/skel/.config/autostart/iso_boot_script.desktop
#   Those two files are removed from the ISO at the end of this script
#   so that they are not put into a new system installation.
#   As of , this script works on the *buntu's, but not Bodhi
#

sleep 7 # lets the system get set up

# disable the dpms screen timeout in the live ISO
#xset s off; xset dpms 0 0 0

dpms_status=`xset q | grep 'Standby.*Suspend.*Off' | awk '{print $2" "$4" "$6}'`

while [ "${dpms_status}" != "0 0 0" ] ; do
  sleep 2
  xset s off
  xset dpms 0 0 0
  dpms_status=`xset q | grep 'Standby.*Suspend.*Off' | awk '{print $2" "$4" "$6}'`
done

# 

###########################################################
########## ADD ISO BOOT COMMANDS ABOVE THIS LINE ##########
sleep 10

# Remove desktop files that call this script during ISO startup
# This will prevent this script from running in a newly installed system
if [ -e ~/.config/autostart/iso_boot_script.desktop ] ; then
  yes | rm -f ~/.config/autostart/iso_boot_script.desktop
fi
if [ -e /etc/skel/.config/autostart/iso_boot_script.desktop ] ; then
  yes | rm -f /etc/skel/.config/autostart/iso_boot_script.desktop
fi

exit 0
