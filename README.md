# Newton's Cradle

Live wallpaper for macOS. Five chrome balls on a dark walnut desk, sitting
behind your icons.

## Install

```bash
./install.sh
```

Menu bar: five-dot icon. Pause, input source, sensitivity, nudge, quit.

## Motion

Apple does not expose the MacBook's AOP accelerometer to apps (`CMMotionManager`
is iOS-only; the HID `accel` device does not stream). Auto mode uses, in order:

1. Mac HID accelerometer, if the OS ever delivers reports
2. Game-controller IMU
3. AirPods / headphone motion
4. Pointer position as desk tilt (always works; flick the cursor to bump)

The cradle also auto-demos when it goes still. Menu: Nudge Left / Right / Drop Two.

## Uninstall

```bash
./uninstall.sh
```
