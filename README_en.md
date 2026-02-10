# honor-magicbook-touchpad-ghost-device-fix

Fixing spontaneous screen brightness changes in Linux on Honor MagicBook laptops. (Laptop model: HONOR MagicBook X14 2025 5301ALWG/FRG-X)

## What's happening

The `GXTP7863` touchpad controller creates several `input` devices. Among them is a phantom device named `UNKNOWN` with handler `kbd`, which constantly spams keycodes even without touching the touchpad. These codes can interfere with brightness control, causing random brightness jumps.

The real touchpad and phantom device have identical `Vendor`, `Product`, and `Version` values, but differ in the `properties` field:

| Device | Name | Handlers | PROP |
|---|---|---|---|
| Real touchpad | `...Touchpad` | `mouse` | `5` |
| Phantom | `...UNKNOWN` | `kbd` | `0` |

## How to verify you have the same issue

Run:

```bash
cat /proc/bus/input/devices
```

Look for two devices with identical `Vendor` and `Product` from the `GXTP7863` controller. One will be named `Touchpad` with `PROP=5`, the other `UNKNOWN` with `PROP=0` and `Handlers=kbd`. The second one needs to be blocked.

## Solution

There are two ways to fix this issue: automatic installation using a script, or manual configuration.

### Method 1: Automatic installation (recommended)

Download and run the `auto_fix.sh` script:

[Download file](auto_fix.sh)

```bash
sudo ./auto_fix.sh
```

The script will:
1. Automatically detect the ghost device
2. Extract correct Bus/Vendor/Product/Version values
3. Create the udev rule with these values
4. Apply the rule immediately
5. Verify that the real touchpad remains active

After running, verify the fix worked:

```bash
cat /sys/devices/pci0000:00/0000:00:15.0/i2c_designware.0/i2c-0/i2c-GXTP7863:00/0018:27C6:01E0.0002/input/input16/inhibited
# Expected output: 1
```

Note: The path may differ on your system. The script will show you the correct path.

After reboot, the rule will apply automatically and the brightness issue should be resolved.

### Method 2: Manual installation

If you prefer to configure everything manually:

#### 1. Create the rule file

```bash
sudo nano /etc/udev/rules.d/99-block-gxtp7863-ghost.rules
```

File contents:

```
ACTION=="add", \
  ATTRS{id/bustype}=="0018", \
  ATTRS{id/vendor}=="27c6", \
  ATTRS{id/product}=="01e0", \
  ATTRS{id/version}=="0100", \
  ATTRS{properties}=="0", \
  ATTR{inhibited}="1"
```

Note: The `vendor`, `product`, `version`, and `bustype` values may differ on other laptops. Get them from the output of `cat /proc/bus/input/devices` for your phantom device. The key distinguishing feature is `ATTRS{properties}=="0"`.

#### 2. Verify the rule syntax

Get the `Sysfs=` path of the phantom device from the output of `cat /proc/bus/input/devices` and substitute it:

```bash
sudo udevadm test /sys/devices/pci0000:00/0000:00:15.0/i2c_designware.0/i2c-0/i2c-GXTP7863:00/0018:27C6:01E0.0002/input/input16 2>&1 | grep -E "inhibit|Running|ATTR"
```

The output should contain a line with `ATTR{inhibited}` and either `set to '1'` or `skipping writing` (in test mode). If there's no such line, check the values in your rule.

#### 3. Apply the rule

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger --action=add --subsystem-match=input --attr-match=name="*GXTP7863*UNKNOWN*"
```

Alternatively, trigger for a specific device path:

```bash
sudo udevadm trigger --action=add /sys/devices/pci0000:00/0000:00:15.0/i2c_designware.0/i2c-0/i2c-GXTP7863:00/0018:27C6:01E0.0002/input/input16
```

Note: The path after `--action=add` must start with `/sys/` and correspond to the `Sysfs=` path of the phantom device (with `/sys/` prefix added).

#### 4. Verify the result

The phantom device should be blocked:

```bash
cat /sys/devices/pci0000:00/0000:00:15.0/i2c_designware.0/i2c-0/i2c-GXTP7863:00/0018:27C6:01E0.0002/input/input16/inhibited
# Expected output: 1
```

The real touchpad should remain active:

```bash
cat /sys/devices/pci0000:00/0000:00:15.0/i2c_designware.0/i2c-0/i2c-GXTP7863:00/0018:27C6:01E0.0002/input/input15/inhibited
# Expected output: 0
```

#### 5. Reboot

After reboot, the rule will apply automatically. The brightness issue should be gone.

## Troubleshooting

- If `inhibited` doesn't appear, check the file path: `find /sys/devices/pci0000:00/0000:00:15.0/ -name "inhibited"`. The file might be at a different hierarchy level.
- If `udevadm trigger` without an explicit path doesn't apply the rule, specify the full path with `/sys/` and add `--action=add`.
- If the `input` numbers (input14, input15, input16) differ, rely on `Name` and `PROP` from the output of `cat /proc/bus/input/devices`, not the numbers.
- Remember that the `Sysfs=` path in `/proc/bus/input/devices` is relative and needs `/sys/` prefix when used in commands.

## Removing the fix

To remove the fix:

```bash
sudo rm /etc/udev/rules.d/99-block-gxtp7863-ghost.rules
sudo udevadm control --reload-rules
sudo reboot
```
