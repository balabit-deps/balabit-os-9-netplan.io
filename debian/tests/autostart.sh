#!/bin/sh
#
# Check that netplan and systemd/networkd will properly cooperate and run
# out generator at boot.
#
set -eu

if [ ! -x /tmp/autopkgtest-reboot ]; then
    echo "SKIP: Testbed does not support reboot"
    exit 0
fi

trap 'rm -f /etc/netplan/00test.yaml' EXIT INT QUIT PIPE TERM

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
        echo "INFO: Doing initial check that there is no existing netplan config."
        # right after installation systemd-networkd may or may not be started
        assert_is_running systemd-networkd.service status
        echo "INFO: systemd-networkd is fine, rebooting..."
        /tmp/autopkgtest-reboot noconfig
        ;;

    noconfig)
        echo "INFO: Verifying that the test bridge is not up and writing config."
        if ip a show dev brtest00 2>/dev/null; then
            echo "ERROR: brtest00 bridge unexpectedly exists" >&2
            exit 1
        fi
        mkdir -p /etc/netplan
        cat <<EOF > /etc/netplan/00test.yaml
network:
  version: 2
  bridges:
    brtest00:
      optional: true # ignore in systemd-networkd-wait-online.service to avoid testbed timeouts
      addresses: [10.42.1.1/24]
EOF

        echo "INFO: Configuration written, rebooting..."
        /tmp/autopkgtest-reboot config
        ;;

    config)
        echo "INFO: Validate that systemd-networkd is running and our test bridge exists..."
        assert_is_running systemd-networkd.service 1
        ip a show dev brtest00
        echo "OK: Test bridge is configured."
        ;;

    *)
        echo "INTERNAL ERROR: autopkgtest marker $AUTOPKGTEST_REBOOT_MARK unexpected" >&2
        exit 1
        ;;
esac
