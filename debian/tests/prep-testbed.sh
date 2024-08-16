#!/bin/sh
set -xe
# stop NetworkManager, to start with a common state
if [ "$(systemctl is-active NetworkManager.service)" = active ]; then
    systemctl stop NetworkManager.service
fi

# Make sure the system is ready before starting our tests
systemctl daemon-reload

# only relevant on Debian
dpkg-vendor --is Debian || exit 0

# disable ifupdown
rm -f /etc/network/interfaces
# enable systemd-networkd
systemctl unmask systemd-networkd.service
systemctl unmask systemd-networkd.socket
systemctl unmask systemd-networkd-wait-online.service
systemctl enable systemd-networkd.service
systemctl start systemd-networkd.service
# enable systemd-resolved
systemctl unmask systemd-resolved.service
systemctl enable systemd-resolved.service
systemctl restart systemd-resolved.service
# enable systemd-udevd
mount -o remount,rw /sys
systemctl unmask systemd-udevd.service
systemctl start systemd-udevd.service
