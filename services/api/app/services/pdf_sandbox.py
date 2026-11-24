"""Fail-closed Bubblewrap configuration for untrusted PDF parsing."""
from __future__ import annotations

from functools import lru_cache
import os
from pathlib import Path
import subprocess
import sys
import tempfile

_ALLOWED_SANDBOX_ENV = {
    "HOME": "/nonexistent",
    "TMPDIR": "/tmp",
    "LANG": "C.UTF-8",
    "LC_ALL": "C.UTF-8",
}
_PROBE_PROGRAM = r"""
import os, socket
assert {name for _, name in socket.if_nameindex()} <= {"lo"}
assert not os.path.exists("/etc/passwd")
assert not os.path.exists("/home")
assert not os.path.exists("/workspace")
assert os.path.exists("/work/probe-marker")
try:
    open("/work/probe-marker", "ab").write(b"x")
except OSError:
    pass
else:
    raise RuntimeError("temporary bind mount is writable")
assert set(os.environ) == {"HOME", "TMPDIR", "LANG", "LC_ALL", "PWD"}
assert os.environ == {
    "HOME": "/nonexistent",
    "TMPDIR": "/tmp",
    "LANG": "C.UTF-8",
    "LC_ALL": "C.UTF-8",
    "PWD": "/work",
}
import pypdf
"""


def safe_temp_root() -> Path:
    """Return /tmp only if it is outside this checkout and usable."""
    root = Path("/tmp").resolve(strict=True)
    project_root = Path(__file__).resolve().parents[4]
    if root == project_root or project_root in root.parents:
        raise RuntimeError("Temporary PDF storage must be outside the project")
    if not root.is_dir() or not os.access(root, os.W_OK | os.X_OK):
        raise RuntimeError("Temporary PDF storage is unavailable")
    return root


def _find_bwrap() -> str | None:
    for candidate in ("/usr/bin/bwrap", "/bin/bwrap", "/usr/local/bin/bwrap"):
        path = Path(candidate)
        if path.is_file() and os.access(path, os.X_OK):
            return str(path.resolve())
    return None


def _read_only_runtime_mounts() -> list[Path]:
    mounts: list[Path] = []
    project_root = Path(__file__).resolve().parents[4]
    home_root = Path.home().resolve()
    candidates = [
        Path("/usr"),
        Path("/lib"),
        Path("/lib64"),
        Path(sys.prefix),
        Path(sys.base_prefix),
        Path(sys.executable).parent,
    ]
    for candidate in candidates:
        if not candidate.exists() or not candidate.is_dir():
            continue
        source = Path(os.path.abspath(candidate))
        resolved = source.resolve()
        if any(root == resolved or root in resolved.parents for root in (project_root, home_root)):
            raise RuntimeError("Python runtime must not be mounted from the project or user home")
        if any(source == mounted or mounted in source.parents for mounted in mounts):
            continue
        mounts.append(source)
    return mounts


def _sandbox_prefix(bwrap: str, work_dir: Path) -> list[str]:
    args = [bwrap, "--die-with-parent", "--new-session", "--unshare-all"]
    for mount in _read_only_runtime_mounts():
        args.extend(("--ro-bind", str(mount), str(mount)))
    loader_cache = Path("/etc/ld.so.cache")
    if loader_cache.is_file():
        args.extend(("--ro-bind", str(loader_cache), str(loader_cache)))
    args.extend((
        "--proc", "/proc",
        "--dev", "/dev",
        "--tmpfs", "/tmp",
        "--ro-bind", str(work_dir), "/work",
        "--chdir", "/work",
        "--clearenv",
    ))
    for key, value in _ALLOWED_SANDBOX_ENV.items():
        args.extend(("--setenv", key, value))
    args.append("--")
    return args


def worker_command(bwrap: str, work_dir: Path) -> list[str]:
    """Build a command with isolated namespaces and a read-only work mount."""
    return [
        *_sandbox_prefix(bwrap, work_dir),
        sys.executable,
        "-I",
        "-B",
        "/work/pdf_text_worker.py",
        "/work/input.pdf",
    ]


@lru_cache(maxsize=1)
def sandbox_status() -> tuple[bool, str | None]:
    """Probe the actual namespace, environment, mounts, and PDF runtime once."""
    bwrap = _find_bwrap()
    if not bwrap:
        return False, None
    try:
        with tempfile.TemporaryDirectory(prefix="khazain-pdf-probe-", dir=safe_temp_root()) as temp:
            work_dir = Path(temp)
            (work_dir / "probe-marker").write_bytes(b"probe")
            command = [
                *_sandbox_prefix(bwrap, work_dir),
                sys.executable,
                "-I",
                "-B",
                "-c",
                _PROBE_PROGRAM,
            ]
            completed = subprocess.run(
                command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                env={"LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"},
                timeout=5,
                check=False,
            )
            return (completed.returncode == 0, bwrap if completed.returncode == 0 else None)
    except (OSError, RuntimeError, subprocess.SubprocessError, ValueError):
        return False, None
