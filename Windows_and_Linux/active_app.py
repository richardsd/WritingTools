"""
Active Application Detection
-----------------------------

Detects the currently focused application on Windows and Linux.
Returns an ActiveAppContext dataclass with app_name, process_name, and window_title.
Falls back gracefully to empty values on any error.
"""

import logging
import platform
import subprocess
from dataclasses import dataclass, field

_system = platform.system()


@dataclass
class ActiveAppContext:
    """Context about the currently active (foreground) application."""
    app_name: str = ""
    process_name: str = ""
    window_title: str = ""


def get_active_app_context() -> ActiveAppContext:
    """
    Detect the active foreground application.

    - Windows: uses ctypes (user32) + psutil for process name.
    - Linux (X11): uses xdotool for window name and PID, then /proc/<pid>/comm.
    - Other platforms: returns an empty context.
    """
    try:
        if _system == "Windows":
            return _get_active_app_windows()
        elif _system == "Linux":
            return _get_active_app_linux()
    except Exception as e:
        logging.warning(f"Failed to detect active application: {e}")
    return ActiveAppContext()


def _get_active_app_windows() -> ActiveAppContext:
    import ctypes
    import ctypes.wintypes

    user32 = ctypes.windll.user32

    hwnd = user32.GetForegroundWindow()
    if not hwnd:
        return ActiveAppContext()

    # Window title
    length = user32.GetWindowTextLengthW(hwnd)
    buf = ctypes.create_unicode_buffer(length + 1)
    user32.GetWindowTextW(hwnd, buf, length + 1)
    window_title = buf.value

    # Process ID → process name via psutil
    pid = ctypes.wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))

    process_name = ""
    app_name = ""
    try:
        import psutil
        proc = psutil.Process(pid.value)
        process_name = proc.name()
        app_name = process_name.rsplit(".", 1)[0] if "." in process_name else process_name
    except Exception as e:
        logging.debug(f"Could not resolve process name for PID {pid.value}: {e}")

    return ActiveAppContext(
        app_name=app_name,
        process_name=process_name,
        window_title=window_title,
    )


def _get_active_app_linux() -> ActiveAppContext:
    window_title = ""
    process_name = ""
    app_name = ""

    try:
        wid = subprocess.check_output(
            ["xdotool", "getactivewindow"], stderr=subprocess.DEVNULL, timeout=2
        ).decode().strip()

        window_title = subprocess.check_output(
            ["xdotool", "getwindowname", wid], stderr=subprocess.DEVNULL, timeout=2
        ).decode().strip()

        pid_str = subprocess.check_output(
            ["xdotool", "getwindowpid", wid], stderr=subprocess.DEVNULL, timeout=2
        ).decode().strip()

        if pid_str:
            try:
                with open(f"/proc/{pid_str}/comm", "r") as f:
                    process_name = f.read().strip()
                    app_name = process_name
            except OSError:
                pass
    except FileNotFoundError:
        logging.debug("xdotool not found — active app detection unavailable on this system")
    except subprocess.TimeoutExpired:
        logging.debug("xdotool timed out")
    except Exception as e:
        logging.debug(f"Linux active app detection error: {e}")

    return ActiveAppContext(
        app_name=app_name,
        process_name=process_name,
        window_title=window_title,
    )
