#!/bin/sh
set -x
# Just share my own adhole.sh grab result to github, for those do not want to run adhole.sh on there small Pi.
# Upload compressed unbound zone config file: adhole.conf.zst and status file to github
# Just download the zst zone config file from https://github.com/LeisureLinux/adhole/releases/tag/adhole
# How this work: https://www.bilibili.com/video/BV1sh411j7eC/?vd_source=ec0ecea47be88aad834eee5694d7ed18
#
# Most time, github is slow or not able to access due to GFW, so need a local proxy
export ALL_PROXY="http://wpad.lan:8888/"
#
WORK_DIR=$(dirname "$0")
cd "$WORK_DIR" || exit
[ ! -x /usr/bin/gh ] && echo "Error: missing github cli!" && exit
if ! gh auth status >/dev/null; then
  echo "Error: github cli was not setup correctly!"
  exit
else
  echo "Info: github cli looked OK."
fi
if [ -s "$WORK_DIR"/result/adhole_status.txt ] && [ -s "$WORK_DIR"/result/adhole.conf.zst ]; then
  for a in adhole_status.txt adhole.conf.zst; do
    gh release delete-asset -y adhole $a
  done
  gh release upload adhole result/adhole_status.txt result/adhole.conf.zst
fi
