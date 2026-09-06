#!/usr/bin/env python3
"""Lightweight keyboard/mouse typing-sound daemon.

Architecture: evdev + select() polling + pw-play (PipeWire). No pygame,
no pydub, no GUI. Profiles come from ~/.config/click-sounds/profiles/<name>/
and are parsed from profile.yaml (PyYAML).

Runtime control: commands are read from ~/.cache/click-sounds/control
(one per line) and state is written to ~/.cache/click-sounds/status.
"""

import glob
import os
import random
import re
import select
import shutil
import signal
import subprocess
import sys
import time
import tomllib
from pathlib import Path

try:
    import yaml
except ImportError:
    print("PyYAML is required: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

import evdev
import evdev.ecodes as ec

# ---------------------------------------------------------------------------
# Paths / constants
# ---------------------------------------------------------------------------

CONFIG_PATH = Path.home() / ".config/click-sounds/config.toml"
PROFILES_DIR = Path.home() / ".config/click-sounds/profiles"
CACHE_DIR = Path.home() / ".cache/click-sounds"
CONTROL_PATH = CACHE_DIR / "control"
STATUS_PATH = CACHE_DIR / "status"
STATE_PATH = CACHE_DIR / "state"  # persists current profile name
PID_PATH = CACHE_DIR / "daemon.pid"
DEFAULT_PROFILE = "typewriter"
DEFAULT_MOUSE_PROFILE = "g502x-wireless"

PW_PLAY = shutil.which("pw-play") or "/usr/sbin/pw-play"
FFMPEG = shutil.which("ffmpeg") or "/usr/sbin/ffmpeg"
FFPROBE = shutil.which("ffprobe") or "/usr/sbin/ffprobe"

DEVICE_RESCAN_INTERVAL = 3.0
STATUS_INTERVAL = 2.0
SELECT_TIMEOUT = 0.2

# ---------------------------------------------------------------------------
# evdev -> profile key-name mapping
# ---------------------------------------------------------------------------


def _build_key_map():
    """Map evdev KEY_* codes to candidate profile key names (specific first)."""
    m = {}

    def add(code, names):
        if code is not None:
            m[code] = names

    # Letters
    for ch in "abcdefghijklmnopqrstuvwxyz":
        add(getattr(ec, "KEY_" + ch.upper(), None), [ch])
    # Number row
    for n in range(1, 10):
        add(getattr(ec, "KEY_%d" % n, None), [str(n)])
    add(getattr(ec, "KEY_0", None), ["0"])
    # Function keys
    for n in range(1, 13):
        add(getattr(ec, "KEY_F%d" % n, None), ["f%d" % n])
    # Keypad
    for n in range(0, 10):
        add(getattr(ec, "KEY_KP%d" % n, None), ["kp%d" % n])

    specials = {
        "KEY_ESC": ["esc"],
        "KEY_MINUS": ["-"],
        "KEY_EQUAL": ["="],
        "KEY_BACKSPACE": ["backspace", "back space"],
        "KEY_TAB": ["tab"],
        "KEY_LEFTBRACE": ["["],
        "KEY_RIGHTBRACE": ["]"],
        "KEY_ENTER": ["enter"],
        "KEY_LEFTCTRL": ["ctrl_l", "ctrl"],
        "KEY_SEMICOLON": [";"],
        "KEY_APOSTROPHE": ["'"],
        "KEY_GRAVE": ["`"],
        "KEY_LEFTSHIFT": ["shift_l", "shift"],
        "KEY_BACKSLASH": ["\\"],
        "KEY_COMMA": [","],
        "KEY_DOT": ["."],
        "KEY_SLASH": ["/"],
        "KEY_RIGHTSHIFT": ["shift_r", "shift"],
        "KEY_KPASTERISK": ["*"],
        "KEY_LEFTALT": ["alt_l", "alt"],
        "KEY_SPACE": ["space"],
        "KEY_CAPSLOCK": ["capslock", "caps lock"],
        "KEY_NUMLOCK": ["numlock"],
        "KEY_SCROLLLOCK": ["scrolllock"],
        "KEY_RIGHTCTRL": ["ctrl_r", "ctrl"],
        "KEY_SYSRQ": ["sysrq"],
        "KEY_RIGHTALT": ["alt_r", "alt"],
        "KEY_HOME": ["home"],
        "KEY_UP": ["up"],
        "KEY_PAGEUP": ["page_up", "pageup"],
        "KEY_LEFT": ["left"],
        "KEY_RIGHT": ["right"],
        "KEY_END": ["end"],
        "KEY_DOWN": ["down"],
        "KEY_PAGEDOWN": ["page_down", "pagedown"],
        "KEY_INSERT": ["insert"],
        "KEY_DELETE": ["delete"],
        "KEY_MUTE": ["mute"],
        "KEY_VOLUMEDOWN": ["volumedown"],
        "KEY_VOLUMEUP": ["volumeup"],
        "KEY_LEFTMETA": ["meta_l", "meta"],
        "KEY_RIGHTMETA": ["meta_r", "meta"],
        "KEY_COMPOSE": ["compose"],
        "KEY_MENU": ["menu"],
        "KEY_PAUSE": ["pause"],
        "KEY_PRINT": ["print"],
        "KEY_KPENTER": ["kpenter"],
        "KEY_KPPLUS": ["kpplus"],
        "KEY_KPMINUS": ["kpminus"],
        "KEY_KPSLASH": ["kpslash"],
        "KEY_KPEQUAL": ["kpequal"],
    }
    for name, names in specials.items():
        add(getattr(ec, name, None), names)
    return m


KEY_NAME_MAP = _build_key_map()

MOUSE_BUTTON_MAP = {
    ec.BTN_LEFT: ["left"],
    ec.BTN_RIGHT: ["right"],
    ec.BTN_MIDDLE: ["middle"],
    ec.BTN_SIDE: ["side"],
    ec.BTN_EXTRA: ["extra"],
}


# ---------------------------------------------------------------------------
# Profile loading
# ---------------------------------------------------------------------------


class Profile:
    def __init__(self, name, sources, default_ids, other_map, is_mouse):
        self.name = name
        self.sources = sources          # id -> {"press": Path|None, "release": Path|None}
        self.default_ids = default_ids  # list of source ids
        self.other_map = other_map      # key/button name -> source id
        self.is_mouse = is_mouse


def _as_list(value):
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return list(value)
    return [value]


def load_profile(name):
    """Load a profile from PROFILES_DIR/<name>/profile.yaml."""
    yaml_path = PROFILES_DIR / name / "profile.yaml"
    with open(yaml_path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}

    profile_dir = yaml_path.parent
    sources = {}
    for s in _as_list(data.get("sources")):
        sid = s.get("id")
        if not sid:
            continue
        src = s.get("source")
        if isinstance(src, dict):
            press = src.get("press")
            release = src.get("release")
            sources[sid] = {
                "press": (profile_dir / press).resolve() if press else None,
                "release": (profile_dir / release).resolve() if release else None,
            }
        elif src:
            sources[sid] = {"press": (profile_dir / src).resolve(), "release": None}

    is_mouse = (data.get("profile") or {}).get("device") == "mouse"

    if is_mouse:
        buttons = data.get("buttons") or {}
        default = _as_list(buttons.get("default"))
        other_map = {}
        for entry in _as_list(buttons.get("other")):
            sound = entry.get("sound")
            for b in _as_list(entry.get("buttons")):
                if b not in other_map:
                    other_map[b] = sound
    else:
        keys = data.get("keys") or {}
        default = _as_list(keys.get("default"))
        other_map = {}
        for entry in _as_list(keys.get("other")):
            sound = entry.get("sound")
            for k in _as_list(entry.get("keys")):
                if k not in other_map:  # first match wins
                    other_map[k] = sound

    # Filter default ids to existing sources; fall back to all sources.
    default = [d for d in default if d in sources]
    if not default:
        default = list(sources.keys())

    return Profile(name, sources, default, other_map, is_mouse)


# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------


def default_config():
    return {
        "volume": {"key_down": 1.5, "key_up": 1.5, "mouse": 1.5},
        "profile": {"name": None, "mouse_name": None},
        "pitch": {"enabled": False, "lower": -2, "upper": 2},
    }


def load_config():
    cfg = default_config()
    if not CONFIG_PATH.exists():
        return cfg
    try:
        with open(CONFIG_PATH, "rb") as f:
            data = tomllib.load(f)
        vol = data.get("volume", {})
        cfg["volume"]["key_down"] = float(vol.get("key_down", 1.5))
        cfg["volume"]["key_up"] = float(vol.get("key_up", 1.5))
        cfg["volume"]["mouse"] = float(vol.get("mouse", 1.5))
        prof = data.get("profile", {})
        cfg["profile"]["name"] = prof.get("name")
        cfg["profile"]["mouse_name"] = prof.get("mouse_name")
        pitch = data.get("pitch", {})
        cfg["pitch"]["enabled"] = bool(pitch.get("enabled", False))
        cfg["pitch"]["lower"] = int(pitch.get("lower", -2))
        cfg["pitch"]["upper"] = int(pitch.get("upper", 2))
    except Exception as e:
        print("Failed loading config: %s" % e, file=sys.stderr)
    return cfg


def set_toml_value(path, section, key, value):
    """Best-effort line-based edit of a TOML file (preserves other content)."""
    try:
        text = path.read_text(encoding="utf-8") if path.exists() else ""
    except OSError:
        return
    lines = text.splitlines()
    out = []
    in_section = False
    section_found = False
    key_found = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_section = stripped == "[%s]" % section
            if in_section:
                section_found = True
            out.append(line)
            continue
        if in_section and re.match(r"^%s\s*=" % re.escape(key), stripped):
            out.append("%s = %s" % (key, value))
            key_found = True
            continue
        out.append(line)
    if not key_found:
        if not section_found:
            out.append("[%s]" % section)
            out.append("%s = %s" % (key, value))
        else:
            for i, line in enumerate(out):
                if line.strip() == "[%s]" % section:
                    out.insert(i + 1, "%s = %s" % (key, value))
                    break
    try:
        path.write_text("\n".join(out) + "\n", encoding="utf-8")
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Daemon
# ---------------------------------------------------------------------------


class Daemon:
    def __init__(self):
        self.config = load_config()
        try:
            self.config_mtime = CONFIG_PATH.stat().st_mtime
        except OSError:
            self.config_mtime = None
        self.kb_profile_name = self._resolve_profile("name", DEFAULT_PROFILE)
        self.mouse_profile_name = self._resolve_profile(
            "mouse_name", DEFAULT_MOUSE_PROFILE)
        self.kb_profile = self._load_profile_or_empty(self.kb_profile_name)
        self.mouse_profile = self._load_profile_or_empty(self.mouse_profile_name)
        self.devices = []  # list of (InputDevice, is_keyboard)
        self.poll_map = {}
        self.last_scan = 0.0
        self.last_status = 0.0
        self.sample_rates = {}
        self.running = True
        self.no_devices_logged = False

    # -- profile -----------------------------------------------------------

    def _resolve_profile(self, key, default):
        """Resolve a profile name from config -> state file -> default."""
        name = self.config["profile"].get(key)
        if name:
            return name
        try:
            if STATE_PATH.exists():
                for line in STATE_PATH.read_text(encoding="utf-8").splitlines():
                    line = line.strip()
                    if not line:
                        continue
                    if "=" in line:
                        k, v = line.split("=", 1)
                        if k.strip() == key and v.strip():
                            return v.strip()
                    elif key == "name":
                        # legacy single-name state file -> keyboard profile
                        return line
        except OSError:
            pass
        return default

    def _write_state(self):
        try:
            STATE_PATH.write_text(
                "keyboard=%s\nmouse=%s\n"
                % (self.kb_profile_name, self.mouse_profile_name),
                encoding="utf-8")
        except OSError:
            pass

    def _load_profile_or_empty(self, name):
        try:
            return load_profile(name)
        except Exception as e:
            print("Failed to load profile '%s': %s" % (name, e), file=sys.stderr)
            return Profile(name, {}, [], {}, False)

    def switch_kb_profile(self, name):
        if name == self.kb_profile_name:
            return
        try:
            prof = load_profile(name)
        except Exception as e:
            print("Failed to load profile '%s': %s" % (name, e), file=sys.stderr)
            return
        self.kb_profile = prof
        self.kb_profile_name = name
        self._write_state()
        set_toml_value(CONFIG_PATH, "profile", "name", '"%s"' % name)
        print("Keyboard profile switched to %s" % name, file=sys.stderr)

    def switch_mouse_profile(self, name):
        if name == self.mouse_profile_name:
            return
        try:
            prof = load_profile(name)
        except Exception as e:
            print("Failed to load profile '%s': %s" % (name, e), file=sys.stderr)
            return
        self.mouse_profile = prof
        self.mouse_profile_name = name
        self._write_state()
        set_toml_value(CONFIG_PATH, "profile", "mouse_name", '"%s"' % name)
        print("Mouse profile switched to %s" % name, file=sys.stderr)

    def switch_profile(self, name):
        """Route a profile switch to keyboard or mouse based on profile type."""
        try:
            prof = load_profile(name)
        except Exception as e:
            print("Failed to load profile '%s': %s" % (name, e), file=sys.stderr)
            return
        if prof.is_mouse:
            self.switch_mouse_profile(name)
        else:
            self.switch_kb_profile(name)

    # -- profile lists / cycling -------------------------------------------

    def list_all_profiles(self):
        return sorted(
            p.name for p in PROFILES_DIR.iterdir()
            if p.is_dir() and (p / "profile.yaml").exists()
        )

    def list_keyboard_profiles(self):
        result = []
        for name in self.list_all_profiles():
            try:
                if not load_profile(name).is_mouse:
                    result.append(name)
            except Exception:
                result.append(name)  # unloadable profiles count as keyboard
        return result

    def cycle_profiles(self):
        kb_list = self.list_keyboard_profiles()
        all_list = self.list_all_profiles()
        if kb_list:
            try:
                idx = kb_list.index(self.kb_profile_name)
            except ValueError:
                idx = -1
            self.switch_kb_profile(kb_list[(idx + 1) % len(kb_list)])
        if all_list:
            try:
                idx = all_list.index(self.mouse_profile_name)
            except ValueError:
                idx = -1
            self.switch_mouse_profile(all_list[(idx + 1) % len(all_list)])
        print("Cycled: keyboard=%s mouse=%s"
              % (self.kb_profile_name, self.mouse_profile_name), file=sys.stderr)

    # -- config reload -----------------------------------------------------

    def check_config_reload(self):
        try:
            mtime = CONFIG_PATH.stat().st_mtime
        except OSError:
            return
        if self.config_mtime is not None and mtime == self.config_mtime:
            return
        self.config_mtime = mtime
        new_cfg = load_config()
        new_name = new_cfg["profile"]["name"]
        if new_name and new_name != self.kb_profile_name:
            self.switch_kb_profile(new_name)
        new_mouse = new_cfg["profile"]["mouse_name"]
        if new_mouse and new_mouse != self.mouse_profile_name:
            self.switch_mouse_profile(new_mouse)
        self.config = new_cfg
        print("Config reloaded", file=sys.stderr)

    # -- control file ------------------------------------------------------

    def process_control(self):
        if not CONTROL_PATH.exists():
            return
        try:
            text = CONTROL_PATH.read_text(encoding="utf-8")
        except OSError:
            return
        if not text.strip():
            return
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            cmd = parts[0]
            try:
                if cmd == "profile" and len(parts) >= 2:
                    self.switch_profile(parts[1])
                elif cmd == "cycle":
                    self.cycle_profiles()
                elif cmd == "volume" and len(parts) >= 3:
                    self.set_volume(parts[1], parts[2])
                elif cmd == "pitch":
                    self.set_pitch(parts[1] if len(parts) >= 2 else "")
                elif cmd == "stop":
                    self.running = False
                else:
                    print("Unknown control command: %s" % line, file=sys.stderr)
            except Exception as e:
                print("Control error (%s): %s" % (line, e), file=sys.stderr)
        try:
            CONTROL_PATH.write_text("", encoding="utf-8")
        except OSError:
            pass

    def set_volume(self, which, value):
        if which not in ("key_down", "key_up", "mouse"):
            return
        try:
            v = float(value)
        except ValueError:
            return
        v = max(0.0, min(2.0, v))
        self.config["volume"][which] = v
        print("Volume %s = %s" % (which, v), file=sys.stderr)

    def set_pitch(self, arg):
        p = self.config["pitch"]
        if arg == "on":
            p["enabled"] = True
        elif arg == "off":
            p["enabled"] = False
        elif "," in arg:
            try:
                lo, hi = arg.split(",", 1)
                p["lower"] = int(lo)
                p["upper"] = int(hi)
                p["enabled"] = True
            except ValueError:
                return
        else:
            return
        print("Pitch: enabled=%s range=%d..%d"
              % (p["enabled"], p["lower"], p["upper"]), file=sys.stderr)

    # -- status ------------------------------------------------------------

    def write_status(self):
        try:
            CACHE_DIR.mkdir(parents=True, exist_ok=True)
            v = self.config["volume"]
            p = self.config["pitch"]
            lines = [
                "running=true",
                "profile=%s" % self.kb_profile_name,
                "mouse_profile=%s" % self.mouse_profile_name,
                "volume_key_down=%g" % v["key_down"],
                "volume_key_up=%g" % v["key_up"],
                "volume_mouse=%g" % v["mouse"],
                "pitch_enabled=%s" % ("true" if p["enabled"] else "false"),
                "pitch_lower=%d" % p["lower"],
                "pitch_upper=%d" % p["upper"],
            ]
            STATUS_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
        except OSError:
            pass

    # -- devices -----------------------------------------------------------

    def scan_devices(self):
        current_paths = set(glob.glob("/dev/input/event*"))

        # Drop devices that disappeared.
        for dev, is_kb in list(self.devices):
            if dev.path not in current_paths:
                try:
                    dev.close()
                except OSError:
                    pass
                self.devices.remove((dev, is_kb))

        # Open new devices.
        for path in sorted(current_paths):
            if any(dev.path == path for dev, _ in self.devices):
                continue
            try:
                dev = evdev.InputDevice(path)
            except Exception:
                continue
            cap = dev.capabilities().get(ec.EV_KEY, [])
            has_letters = any(c in cap for c in (ec.KEY_A, ec.KEY_Q, ec.KEY_Z))
            has_mouse = ec.BTN_MOUSE in cap
            if has_letters:
                self.devices.append((dev, True))
                print("Monitoring keyboard: %s (%s)" % (dev.name, dev.path),
                      file=sys.stderr)
            elif has_mouse:
                self.devices.append((dev, False))
                print("Monitoring mouse: %s (%s)" % (dev.name, dev.path),
                      file=sys.stderr)
            else:
                try:
                    dev.close()
                except OSError:
                    pass

        self.rebuild_poll_map()
        if not self.devices and not self.no_devices_logged:
            print("No input devices found (check /dev/input permissions)",
                  file=sys.stderr)
            self.no_devices_logged = True
        elif self.devices:
            self.no_devices_logged = False

    def rebuild_poll_map(self):
        self.poll_map = {dev.fd: (dev, is_kb) for dev, is_kb in self.devices}

    def remove_device(self, dev):
        for d, is_kb in list(self.devices):
            if d is dev:
                try:
                    d.close()
                except OSError:
                    pass
                self.devices.remove((d, is_kb))
        self.rebuild_poll_map()

    def close_all_devices(self):
        for dev, _ in self.devices:
            try:
                dev.close()
            except OSError:
                pass
        self.devices = []
        self.rebuild_poll_map()

    # -- sound -------------------------------------------------------------

    def play(self, path, volume, profile_name):
        if not path:
            return
        path = Path(path)
        if not path.exists():
            return
        vol = max(0.0, min(2.0, volume))
        target = path
        if self.config["pitch"]["enabled"]:
            target = self.pitch_variant(path, profile_name)
        try:
            subprocess.Popen(
                [PW_PLAY, "--volume", str(vol), str(target)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError as e:
            print("pw-play failed: %s" % e, file=sys.stderr)

    def get_sample_rate(self, path):
        key = (str(path), path.stat().st_mtime)
        if key in self.sample_rates:
            return self.sample_rates[key]
        sr = 44100
        if FFPROBE:
            try:
                out = subprocess.run(
                    [FFPROBE, "-v", "error", "-select_streams", "a:0",
                     "-show_entries", "stream=sample_rate",
                     "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
                    capture_output=True, text=True, timeout=10,
                )
                val = out.stdout.strip()
                if val.isdigit():
                    sr = int(val)
            except Exception:
                pass
        self.sample_rates[key] = sr
        return sr

    def pitch_variant(self, path, profile_name):
        p = self.config["pitch"]
        lower, upper = p["lower"], p["upper"]
        if upper < lower:
            lower, upper = upper, lower
        semitones = random.randint(lower, upper)
        if semitones == 0:
            return path
        src = Path(path)
        cache_dir = CACHE_DIR / "pitch" / profile_name
        try:
            cache_dir.mkdir(parents=True, exist_ok=True)
        except OSError:
            return path
        out = cache_dir / ("%s-%+d.wav" % (src.stem, semitones))
        try:
            if out.exists() and out.stat().st_mtime >= src.stat().st_mtime:
                return out
        except OSError:
            return path
        self.generate_pitch_variant(src, out, semitones)
        return out if out.exists() else path

    def generate_pitch_variant(self, src, out, semitones):
        sr = self.get_sample_rate(src)
        new_rate = int(round(sr * (2 ** (semitones / 12.0))))
        cmd = [FFMPEG, "-y", "-loglevel", "error", "-i", str(src),
               "-af", "asetrate=%d,aresample=%d" % (new_rate, sr), str(out)]
        try:
            subprocess.run(cmd, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=30)
        except Exception as e:
            print("Pitch generation failed for %s: %s" % (src, e),
                  file=sys.stderr)

    # -- events ------------------------------------------------------------

    def handle_event(self, dev, is_keyboard, event):
        if event.type != ec.EV_KEY:
            return
        if event.value not in (0, 1):  # ignore key repeat (2)
            return

        if is_keyboard:
            profile = self.kb_profile
            names = KEY_NAME_MAP.get(event.code, [])
            volume = (self.config["volume"]["key_down"] if event.value == 1
                      else self.config["volume"]["key_up"])
        else:
            profile = self.mouse_profile
            names = MOUSE_BUTTON_MAP.get(event.code, [])
            volume = self.config["volume"]["mouse"]

        sound_id = None
        for n in names:
            if n in profile.other_map:
                sound_id = profile.other_map[n]
                break
        if sound_id is None and profile.default_ids:
            sound_id = random.choice(profile.default_ids)

        if sound_id is None:
            return
        source = profile.sources.get(sound_id)
        if not source:
            return
        path = source.get("press" if event.value == 1 else "release")
        if path is None:
            return
        self.play(path, volume, profile.name)

    # -- main loop ---------------------------------------------------------

    def run(self):
        def _handle_signal(signum, frame):
            self.running = False

        signal.signal(signal.SIGTERM, _handle_signal)
        signal.signal(signal.SIGINT, _handle_signal)
        try:
            CACHE_DIR.mkdir(parents=True, exist_ok=True)
            PID_PATH.write_text(str(os.getpid()) + "\n", encoding="utf-8")
        except OSError:
            pass
        self.scan_devices()
        self.write_status()
        try:
            while self.running:
                now = time.monotonic()
                if now - self.last_scan >= DEVICE_RESCAN_INTERVAL:
                    self.scan_devices()
                    self.last_scan = now
                self.check_config_reload()
                self.process_control()
                if now - self.last_status >= STATUS_INTERVAL:
                    self.write_status()
                    self.last_status = now

                if not self.poll_map:
                    time.sleep(SELECT_TIMEOUT)
                    continue

                try:
                    r, _, _ = select.select(
                        list(self.poll_map.keys()), [], [], SELECT_TIMEOUT)
                except (OSError, ValueError):
                    self.scan_devices()
                    continue

                for fd in r:
                    item = self.poll_map.get(fd)
                    if item is None:
                        continue
                    dev, is_kb = item
                    try:
                        for event in dev.read():
                            self.handle_event(dev, is_kb, event)
                    except OSError:
                        self.remove_device(dev)
                        self.scan_devices()
        except KeyboardInterrupt:
            pass
        finally:
            self.close_all_devices()
            try:
                STATUS_PATH.write_text("running=false\n", encoding="utf-8")
                PID_PATH.unlink(missing_ok=True)
            except OSError:
                pass


def main():
    print("click-sound-daemon starting", file=sys.stderr)
    daemon = Daemon()
    print("Keyboard profile: %s" % daemon.kb_profile_name, file=sys.stderr)
    print("Mouse profile: %s" % daemon.mouse_profile_name, file=sys.stderr)
    print("pw-play: %s" % PW_PLAY, file=sys.stderr)
    daemon.run()


if __name__ == "__main__":
    main()