# Newton's Cradle

Live wallpaper for macOS. Five chrome balls on a dark walnut desk, sitting
behind your icons.

## Install

```bash
./install.sh
```

Menu bar: five-dot icon. Pause, input source, sensitivity, nudge, quit.

## Motion

Auto mode uses, in order:

1. **Mac accelerometer** — Apple SPU HID (`AppleSPUHIDDevice`, 22-byte
   reports). Tilt the laptop; bump the chassis to knock a ball.
2. Game-controller IMU
3. AirPods / headphone motion
4. Pointer position as desk tilt (fallback)

The cradle also auto-demos when it goes still. Menu: Nudge Left / Right / Drop Two.

## Uninstall

```bash
./uninstall.sh
```
