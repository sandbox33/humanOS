"""Cached HTTP downloads for the ETL (standard library only)."""
from __future__ import annotations

import shutil
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

USER_AGENT = "HumanOS-ETL/3.0 (+https://github.com/sandbox33/humanOS)"


def fetch_text(url: str, timeout: float = 60.0) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return response.read().decode(charset, errors="replace")


def download(url: str, cache_dir: Path, *, retries: int = 4) -> Path:
    """Downloads ``url`` into ``cache_dir`` once and returns the local path.

    Retries with exponential backoff on network errors. A partially written
    file is never left under the final name.
    """
    cache_dir.mkdir(parents=True, exist_ok=True)
    target = cache_dir / url.rsplit("/", 1)[-1]
    if target.exists() and target.stat().st_size > 0:
        return target
    partial = target.with_suffix(target.suffix + ".part")
    delay = 2.0
    for attempt in range(1, retries + 1):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=300) as response, open(
                partial, "wb"
            ) as out:
                shutil.copyfileobj(response, out, length=1 << 20)
            partial.replace(target)
            return target
        except urllib.error.HTTPError as error:
            if error.code == 404:
                raise
            last_error: Exception = error
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            last_error = error
        print(f"[download] intento {attempt} falló para {url}: {last_error}", file=sys.stderr)
        if attempt < retries:
            time.sleep(delay)
            delay *= 2
    raise RuntimeError(f"No se pudo descargar {url}") from last_error
