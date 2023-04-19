#!/bin/sh
# Add wpad record, this need to to dynamically since IP could be changed
# /etc/unbound/wpad.sh
HIP=$(hostname -I | awk '{print $1}')
[ "$(dig -4 +short wpad. @localhost)" = "$HIP" ] && echo "Info: No need to update wpad. record" && exit 0
echo "Adding wpad.local. record ..."
sudo unbound-control local_data wpad. A $HIP
sudo unbound-control local_data wpad.local. A $HIP
[ $? != 0 ] && echo "Error: not able to update wpad. record!" && exit 6
[ "$(dig -4 +short wpad.local. @localhost)" != "$HIP" ] && echo "Error: added wpad not able to resolv!" && exit 7
echo "Congrats, All is well! Added wpad. as $HIP"
# cat >/etc/unbound/wpad.conf <<EOF
# local-zone: "wpad." static
# local-data: "wpad. 10800 IN NS localhost."
# local-zone: "local." static
# local-data: "local. 10800 IN NS localhost."
# local-data: "wpad. 3600 IN A $HIP"
# local-data: "wpad.local. 3600 IN A $HIP"
# EOF
# exit 1
