from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import threading
import time


SERVER_DIR = Path(__file__).resolve().parent
REQUIREMENTS = SERVER_DIR / "requirements.txt"
VENV_DIR = SERVER_DIR / ".venv"
DEPS_DIR = SERVER_DIR / ".deps"


def _is_unwanted_python(executable: str | Path) -> bool:
    """Return True for bundled application Pythons unsuitable for the server.

    In particular, Inkscape ships its own Python. It may be first on PATH, but it
    is not the Python installation intended for installing/running D&D Hub's
    server dependencies.
    """
    path = str(executable).replace("\\", "/").lower()
    return "/inkscape/" in path or path.endswith("/inkscape/python.exe")


def _run_capture(command: list[str]) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(
            command,
            cwd=SERVER_DIR,
            env=os.environ.copy(),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
    except OSError:
        return None


def _find_python_command() -> list[str] | None:
    """Find a normal CPython installation and avoid bundled app Pythons.

    Prefer the Windows Python Launcher (`py -3`) because PATH may contain an
    application's private Python first (for example Inkscape's Python).
    """
    if os.name == "nt":
        py = shutil.which("py")
        if py:
            result = _run_capture([py, "-3", "-c", "import sys; print(sys.executable)"])
            if result and result.returncode == 0:
                resolved = result.stdout.strip().splitlines()[-1].strip()
                if resolved and not _is_unwanted_python(resolved):
                    # Return the real interpreter path, not the Python Launcher.
                    # The launcher can exit with code 0 after spawning Python, which
                    # makes Flutter think the server process has already terminated.
                    return [resolved]

        # Check every python.exe visible on PATH rather than only the first one.
        try:
            where = subprocess.run(
                ["where.exe", "python"],
                cwd=SERVER_DIR,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            candidates = [line.strip() for line in where.stdout.splitlines() if line.strip()]
        except OSError:
            candidates = []
    else:
        candidates = []
        for name in ("python3", "python"):
            found = shutil.which(name)
            if found:
                candidates.append(found)

    current = Path(sys.executable).resolve()
    candidates.insert(0, str(current))

    seen: set[str] = set()
    for candidate in candidates:
        try:
            key = str(Path(candidate).resolve()).lower()
        except OSError:
            key = str(candidate).lower()
        if key in seen:
            continue
        seen.add(key)
        if _is_unwanted_python(candidate):
            continue
        result = _run_capture([candidate, "-c", "import sys; print(sys.executable)"])
        if result and result.returncode == 0:
            return [candidate]

    return None


def _reexec_with_supported_python() -> None:
    """Re-launch this script with a regular Python if a bundled Python started it."""
    current = Path(sys.executable).resolve()
    if not _is_unwanted_python(current):
        return

    command = _find_python_command()
    if command is None:
        raise RuntimeError(
            "D&D Hub server запущен встроенным Python от Inkscape, а обычный Python 3 "
            "не найден. Установите Python 3 для Windows или добавьте его в PATH."
        )

    launcher = command[0]
    args = [*command[1:], str(Path(__file__).resolve()), *sys.argv[1:]]
    print(
        f"DNDHUB_SERVER_BOOTSTRAP switching from bundled Python to {launcher}...",
        flush=True,
    )
    completed = subprocess.run([launcher, *args], cwd=SERVER_DIR)
    raise SystemExit(completed.returncode)


def _venv_python() -> Path:
    if os.name == "nt":
        return VENV_DIR / "Scripts" / "python.exe"
    return VENV_DIR / "bin" / "python"


def _dependencies_ready(
    python_executable: str | Path,
    python_path: Path | None = None,
) -> bool:
    """Check FastAPI/Uvicorn in the exact Python environment we plan to run."""
    env = os.environ.copy()
    if python_path is not None:
        existing = env.get("PYTHONPATH", "")
        env["PYTHONPATH"] = str(python_path) if not existing else f"{python_path}{os.pathsep}{existing}"
    try:
        result = subprocess.run(
            [
                str(python_executable),
                "-c",
                "import fastapi, uvicorn; import websockets",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env,
            check=False,
        )
        return result.returncode == 0
    except OSError:
        return False


def _run_bootstrap_command(command: list[str], label: str) -> None:
    print(f"DNDHUB_SERVER_BOOTSTRAP {label}", flush=True)
    try:
        subprocess.run(command, check=True, cwd=SERVER_DIR)
    except subprocess.CalledProcessError as exc:
        pretty = " ".join(f'"{arg}"' if " " in arg else arg for arg in command)
        raise RuntimeError(
            f"D&D Hub server bootstrap failed (exit code {exc.returncode}): {pretty}"
        ) from exc


def _add_local_deps_to_sys_path() -> None:
    path = str(DEPS_DIR.resolve())
    if DEPS_DIR.exists() and path not in sys.path:
        sys.path.insert(0, path)


def _bootstrap_dependencies() -> None:
    """Prepare project-local dependencies without requiring a venv."""
    current_python = Path(sys.executable).resolve()
    venv_python = _venv_python()

    if _dependencies_ready(current_python):
        return

    if venv_python.exists() and _dependencies_ready(venv_python):
        if current_python != venv_python.resolve():
            print(
                "DNDHUB_SERVER_BOOTSTRAP using existing private Python environment...",
                flush=True,
            )
            completed = subprocess.run(
                [str(venv_python), str(Path(__file__).resolve()), *sys.argv[1:]],
                cwd=SERVER_DIR,
            )
            raise SystemExit(completed.returncode)
        return

    DEPS_DIR.mkdir(parents=True, exist_ok=True)

    if not _dependencies_ready(current_python, DEPS_DIR):
        try:
            _run_bootstrap_command(
                [str(current_python), "-m", "pip", "--version"],
                "checking pip...",
            )
        except RuntimeError:
            _run_bootstrap_command(
                [str(current_python), "-m", "ensurepip", "--upgrade"],
                "preparing pip...",
            )

        _run_bootstrap_command(
            [
                str(current_python),
                "-m",
                "pip",
                "install",
                "--disable-pip-version-check",
                "--no-input",
                "--upgrade",
                "--target",
                str(DEPS_DIR),
                "-r",
                str(REQUIREMENTS),
            ],
            "installing server dependencies into project-local .deps...",
        )

    if not _dependencies_ready(current_python, DEPS_DIR):
        raise RuntimeError(
            "Server dependencies were installed, but FastAPI/Uvicorn still cannot be imported."
        )

    _add_local_deps_to_sys_path()


_reexec_with_supported_python()
_bootstrap_dependencies()

# Third-party imports intentionally happen only after bootstrap.
import uvicorn  # noqa: E402

from app.server import HubServer, build_app, PROTOCOL  # noqa: E402


DISCOVERY_PORT = 42817
DISCOVERY_QUERY = b"DNDHUB_DISCOVER_V1"


def private_ipv4() -> str:
    candidates: list[str] = []
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            candidates.append(info[4][0])
    except socket.gaierror:
        pass
    for ip in candidates:
        if ip.startswith(("10.", "192.168.", "172.")):
            return ip
    return candidates[0] if candidates else "127.0.0.1"


def discovery_loop(hub: HubServer, host: str, stop: threading.Event) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("0.0.0.0", DISCOVERY_PORT))
        sock.settimeout(1.0)
        while not stop.is_set():
            try:
                data, addr = sock.recvfrom(2048)
            except socket.timeout:
                continue
            if data != DISCOVERY_QUERY:
                continue
            advertisement = hub.advertisement(host)
            advertisement["timestamp"] = time.time()
            payload = json.dumps(advertisement, ensure_ascii=False).encode("utf-8")
            try:
                sock.sendto(payload, addr)
            except OSError:
                pass
    finally:
        sock.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="D&D Hub v0.5 local GM Server")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--campaign-id", required=True)
    parser.add_argument("--campaign-name", required=True)
    parser.add_argument("--gm-name", required=True)
    parser.add_argument("--invite-token", required=True)
    parser.add_argument("--max-players", type=int, default=5)
    args = parser.parse_args()

    hub = HubServer(
        campaign_id=args.campaign_id,
        campaign_name=args.campaign_name,
        gm_name=args.gm_name,
        invite_token=args.invite_token,
        max_players=args.max_players,
    )
    hub.port = args.port
    app = build_app(hub, port=args.port)
    stop = threading.Event()
    thread = threading.Thread(target=discovery_loop, args=(hub, private_ipv4(), stop), daemon=True)
    thread.start()
    try:
        print(f"DNDHUB_SERVER_STARTING host={args.host} port={args.port} protocol={PROTOCOL}", flush=True)
        uvicorn.run(app, host=args.host, port=args.port, log_level="warning")
    finally:
        stop.set()


if __name__ == "__main__":
    main()
