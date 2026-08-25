import evdev
import subprocess
import glob
import os
import sys
import random
import select
import tomllib
from dataclasses import dataclass
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SOUND_DIR = Path.home() / ".local/share/sounds/click-sounds"
CONFIG_PATH = Path.home() / ".config/click-sounds/config.toml"
MOUSE_CLICK = SCRIPT_DIR.parent / "sounds" / "mouse-click.mp3"

KEY_DOWN_SOUNDS = sorted(SOUND_DIR.glob("down*.wav"))
KEY_UP_SOUNDS = sorted(SOUND_DIR.glob("up*.wav"))

if not KEY_DOWN_SOUNDS:
    KEY_DOWN_SOUNDS = [SOUND_DIR / "key-click.wav"]
    KEY_UP_SOUNDS = []


@dataclass
class VolumeConfig:
    key_down: float = 1.0
    key_up: float = 1.0
    mouse: float = 1.0

    @classmethod
    def load(cls) -> "VolumeConfig":
        if not CONFIG_PATH.exists():
            return cls()

        try:
            with open(CONFIG_PATH, "rb") as f:
                data = tomllib.load(f)
            vol = data.get("volume", {})
            return cls(
                key_down=float(vol.get("key_down", cls.key_down)),
                key_up=float(vol.get("key_up", cls.key_up)),
                mouse=float(vol.get("mouse", cls.mouse)),
            )
        except Exception as e:
            print(f"Failed loading config: {e}", file=sys.stderr)
            return cls()


def find_devices():
    keyboards = []
    mice = []
    for path in glob.glob("/dev/input/event*"):
        try:
            dev = evdev.InputDevice(path)
            cap = dev.capabilities().get(evdev.ecodes.EV_KEY, [])
            has_letters = any(ec in cap for ec in [
                evdev.ecodes.KEY_A, evdev.ecodes.KEY_Q, evdev.ecodes.KEY_Z
            ])
            has_mouse = evdev.ecodes.BTN_MOUSE in cap
            if has_letters:
                keyboards.append(dev)
            if has_mouse:
                pass
        except Exception:
            pass
    return keyboards, mice


def play_sound(path: Path, volume: float):
    vol = max(0.0, min(2.0, volume))
    subprocess.Popen(
        ["pw-play", "--volume", str(vol), str(path)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def main():
    vol = VolumeConfig.load()
    print(f"Volume config: key_down={vol.key_down}, key_up={vol.key_up}, mouse={vol.mouse}",
          file=sys.stderr)

    keyboards, mice = find_devices()
    if not keyboards and not mice:
        print("No input devices found", file=sys.stderr)
        sys.exit(1)

    devices = keyboards + mice
    for dev in devices:
        print(f"Monitoring: {dev.name} ({dev.path})", file=sys.stderr)

    poll_map = {dev.fd: dev for dev in devices}
    try:
        while True:
            r, _, _ = select.select(list(poll_map.keys()), [], [])
            for fd in r:
                dev = poll_map[fd]
                for event in dev.read():
                    if event.type != evdev.ecodes.EV_KEY:
                        continue
                    if dev in keyboards:
                        if event.value == 1 and KEY_DOWN_SOUNDS:
                            play_sound(random.choice(KEY_DOWN_SOUNDS), vol.key_down)
                        elif event.value == 0 and KEY_UP_SOUNDS:
                            play_sound(random.choice(KEY_UP_SOUNDS), vol.key_up)
                    elif dev in mice and event.value == 1:
                        play_sound(MOUSE_CLICK, vol.mouse)
    except KeyboardInterrupt:
        pass
    finally:
        for dev in devices:
            dev.close()


if __name__ == "__main__":
    main()
