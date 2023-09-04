#!/bin/sh
#
# Check that netplan, systemd and cloud-init will properly cooperate
# and run newly generated service units just-in-time.
#
set -eu

if [ ! -x /tmp/autopkgtest-reboot ]; then
    echo "SKIP: Testbed does not support reboot"
    exit 0
fi

# parameters: service expect_running
assert_is_running() {
    if [ "$2" = 1 ] && ! systemctl --quiet is-active "$1"; then
        echo "ERROR: expected $1 to have started, but it was not" >&2
        systemctl --no-pager status "$1"
        exit 1
    elif [ "$2" = 0 ] && systemctl --quiet is-active "$1"; then
        echo "ERROR: expected $1 to not have started, but it was" >&2
        systemctl --no-pager status "$1"
        exit 1
    else
        systemctl --no-pager status "$1" || true
    fi
}

# Always try to keep the management interface up and running
mkdir -p /etc/systemd/network
cat <<EOF > /etc/systemd/network/20-mgmt.network
[Match]
Name=eth0 en*

[Network]
DHCP=yes
KeepConfiguration=yes
EOF

case "${AUTOPKGTEST_REBOOT_MARK:-}" in
    '')
        echo "INFO: Preparing configuration"
        mkdir -p /etc/netplan
        # Any netplan YAML config
        cat <<EOF > /etc/netplan/00test.yaml
network:
  version: 2
  bridges:
    brtest00:
      optional: true # ignore in systemd-networkd-wait-online.service to avoid testbed timeouts
      addresses: [10.42.1.1/24]
EOF
        # Prepare a dummy netplan service unit, which will be moved to /run/systemd/system/
        # during early boot, as if it would have been created by 'netplan generate'
        cat <<EOF > /netplan-dummy.service
[Unit]
Description=Check if this dummy is properly started by systemd

[Service]
Type=oneshot
# Keep it running, so we can verify it was properly started
RemainAfterExit=yes
ExecStart=echo "Doing nothing ..."
EOF
        # A service simulating cloud-init, calling 'netplan generate' during early boot
        # at the 'initialization' phase of systemd (before basic.target is reached).
        cat <<EOF > /etc/systemd/system/cloud-init-dummy.service
[Unit]
Description=Simulating cloud-init's 'netplan generate' call during early boot
DefaultDependencies=no
Before=basic.target
Before=network.target
After=sysinit.target

[Install]
RequiredBy=basic.target

[Service]
Type=oneshot
# Keep it running, so we can verify it was properly started
RemainAfterExit=yes
# Simulate creating a new service unit (i.e. netplan-wpa-*.service / netplan-ovs-*.service)
ExecStart=/bin/cp /netplan-dummy.service /run/systemd/system/
ExecStart=/usr/sbin/netplan generate
EOF

        # right after installation systemd-networkd may or may not be started
        assert_is_running systemd-networkd.service status

        systemctl disable systemd-networkd.service
        systemctl enable cloud-init-dummy.service
        echo "INFO: Configuration written, rebooting..."
        /tmp/autopkgtest-reboot config
        ;;

    config)
        sleep 5  # Give some time for systemd to finish the boot transaction
        echo "INFO: Validate that systemd-networkd, cloud-init-dummy.service and netplan-dummy.service are running and our test bridge exists..."
        assert_is_running systemd-networkd.service 1
        assert_is_running cloud-init-dummy.service 1
        assert_is_running netplan-dummy.service 1
        ip a show dev brtest00
        echo "OK: Test bridge is configured and just-in-time services running."

        # Cleanup
        systemctl enable systemd-networkd.service
        systemctl disable cloud-init-dummy.service
        rm /netplan-dummy.service
        rm /run/systemd/system/netplan-dummy.service
        rm /etc/systemd/system/cloud-init-dummy.service
        rm /etc/netplan/00test.yaml
        ;;

    *)
        echo "INTERNAL ERROR: autopkgtest marker $AUTOPKGTEST_REBOOT_MARK unexpected" >&2
        exit 1
        ;;
esac
