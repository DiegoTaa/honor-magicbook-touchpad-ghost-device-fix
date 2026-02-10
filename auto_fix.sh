#!/bin/bash

# Automatic fix for GXTP7863 ghost touchpad device
# Creates udev rule and applies it properly

set -e

RULE_FILE="/etc/udev/rules.d/99-block-gxtp7863-ghost.rules"

echo "========================================="
echo "GXTP7863 Ghost Device Auto-Fix"
echo "========================================="
echo ""

if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: Run with sudo"
    exit 1
fi

echo "Step 1: Finding ghost device..."

# Parse device info
PARSING=0
GHOST_INFO=""
CURRENT_BLOCK=""

while IFS= read -r line; do
    if [[ "$line" =~ ^I:\ Bus= ]]; then
        if [[ "$CURRENT_BLOCK" =~ GXTP7863.*UNKNOWN ]]; then
            GHOST_INFO="$CURRENT_BLOCK"
        fi
        CURRENT_BLOCK="$line"$'\n'
    elif [[ -n "$line" ]]; then
        CURRENT_BLOCK="$CURRENT_BLOCK$line"$'\n'
    fi
done < /proc/bus/input/devices

if [[ "$CURRENT_BLOCK" =~ GXTP7863.*UNKNOWN ]]; then
    GHOST_INFO="$CURRENT_BLOCK"
fi

if [ -z "$GHOST_INFO" ]; then
    echo "ERROR: GXTP7863 UNKNOWN device not found"
    exit 1
fi

BUSTYPE=$(echo "$GHOST_INFO" | grep "^I:" | sed -n 's/.*Bus=\([0-9a-fA-F]*\).*/\1/p')
VENDOR=$(echo "$GHOST_INFO" | grep "^I:" | sed -n 's/.*Vendor=\([0-9a-fA-F]*\).*/\1/p')
PRODUCT=$(echo "$GHOST_INFO" | grep "^I:" | sed -n 's/.*Product=\([0-9a-fA-F]*\).*/\1/p')
VERSION=$(echo "$GHOST_INFO" | grep "^I:" | sed -n 's/.*Version=\([0-9a-fA-F]*\).*/\1/p')
SYSFS=$(echo "$GHOST_INFO" | grep "^S:" | sed -n 's/S: Sysfs=\(.*\)/\1/p')

echo "Found ghost device:"
echo "  Bus=$BUSTYPE Vendor=$VENDOR Product=$PRODUCT Version=$VERSION"
echo "  Path: $SYSFS"
echo ""

echo "Step 2: Creating udev rule..."

cat > "$RULE_FILE" << EOF
ACTION=="add", \\
  ATTRS{id/bustype}=="$BUSTYPE", \\
  ATTRS{id/vendor}=="$VENDOR", \\
  ATTRS{id/product}=="$PRODUCT", \\
  ATTRS{id/version}=="$VERSION", \\
  ATTRS{properties}=="0", \\
  ATTR{inhibited}="1"
EOF

echo "Rule created at: $RULE_FILE"
cat "$RULE_FILE"
echo ""

echo "Step 3: Reloading udev rules..."
udevadm control --reload-rules
echo "Done"
echo ""

echo "Step 4: Applying rule with udevadm trigger..."
# This is the key - trigger specifically with ACTION=add
udevadm trigger --action=add --subsystem-match=input --attr-match=name="*GXTP7863*UNKNOWN*"
echo "Triggered"
echo ""

# Give udev time to process
sleep 2

echo "Step 5: Verifying..."
INHIBITED_FILE="/sys/$SYSFS/inhibited"

if [ -f "$INHIBITED_FILE" ]; then
    INHIBITED_VALUE=$(cat "$INHIBITED_FILE")
    echo "Current inhibited value: $INHIBITED_VALUE"
    echo ""
    
    if [ "$INHIBITED_VALUE" = "1" ]; then
        echo "SUCCESS! Ghost device is blocked."
    else
        echo "WARNING: udev trigger did not work."
        echo "Trying direct write..."
        echo 1 > "$INHIBITED_FILE"
        INHIBITED_VALUE=$(cat "$INHIBITED_FILE")
        
        if [ "$INHIBITED_VALUE" = "1" ]; then
            echo "SUCCESS! Ghost device is now blocked."
        else
            echo "ERROR: Could not block device."
            echo "Please reboot to apply the fix."
        fi
    fi
else
    echo "ERROR: inhibited file not found at $INHIBITED_FILE"
fi

echo ""
echo "========================================="
echo "Installation complete!"
echo ""
echo "Verify with:"
echo "  cat $INHIBITED_FILE"
echo ""
echo "After reboot, the rule will apply automatically."
echo "========================================="
