#!/usr/bin/env python3
"""Open this project with the Mac's existing HTTPS proxy in Xcode's process.

--check only probes the pinned public package tags. It never launches Xcode, resolves
packages, builds the app, changes Git configuration, or deletes caches.
"""

import os
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parent
PROJECT = ROOT / "FLTiya.xcodeproj"
PACKAGE_CHECKS = (
    ("https://github.com/supabase/supabase-swift.git", "refs/tags/v2.55.6",
     "63fa5a8c650fad12a14543186024bd3214a65d9c"),
    ("https://github.com/livekit/client-sdk-swift.git", "refs/tags/2.18.0^{}",
     "93a7251057bdb6a80a7b1f6d11464d578ebdc09b"),
)


def proxy_environment():
    settings = subprocess.run(["/usr/sbin/scutil", "--proxy"],
                              capture_output=True, text=True, check=True).stdout
    values = dict(re.findall(r"^\s*(HTTPS(?:Enable|Proxy|Port))\s*:\s*(\S+)\s*$",
                             settings, re.MULTILINE))
    if values.get("HTTPSEnable") != "1":
        raise ValueError("Enable your existing HTTPS system proxy, then try again.")
    host = values.get("HTTPSProxy", "")
    port = int(values.get("HTTPSPort", "0"))
    if not host or not 1 <= port <= 65535 or any(char in host for char in "/@?#\r\n"):
        raise ValueError("The Mac HTTPS proxy address is incomplete.")
    if ":" in host and not host.startswith("["):
        host = "[" + host + "]"
    proxy = "http://" + host + ":" + str(port)
    changes = {key: proxy for key in ("http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY")}
    # Git subprocesses do not reliably inherit macOS System Settings proxies.
    # Append a process-scoped Git setting; existing credentials/config stay intact.
    count = int(os.environ.get("GIT_CONFIG_COUNT", "0"))
    if count < 0:
        raise ValueError("The inherited Git environment is invalid.")
    changes.update({"GIT_CONFIG_COUNT": str(count + 1),
                    "GIT_CONFIG_KEY_" + str(count): "http.https://github.com/.proxy",
                    "GIT_CONFIG_VALUE_" + str(count): proxy})
    return changes


def check_connection(changes):
    environment = dict(os.environ, **changes)
    environment.update(GIT_TERMINAL_PROMPT="0", GIT_ASKPASS="/usr/bin/false")
    for url, tag, commit in PACKAGE_CHECKS:
        result = subprocess.run(
            ["/usr/bin/git", "-c", "credential.helper=", "-c", "core.askPass=",
             "ls-remote", url, tag], env=environment,
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0 or result.stdout.split()[:1] != [commit]:
            raise ValueError("GitHub package access failed through the system proxy. Check the proxy connection.")
    print("GitHub connection verified: Supabase 2.55.6 and LiveKit 2.18.0 match their pinned commits.")


def main():
    if sys.argv[1:] not in ([], ["--check"]):
        raise ValueError("Usage: OpenFLTiyaWithProxy.command [--check]")
    if not PROJECT.is_dir():
        raise ValueError("Keep this launcher beside FLTiya.xcodeproj.")
    changes = proxy_environment()
    if sys.argv[1:] == ["--check"]:
        check_connection(changes)
        print("Check only: Xcode was not launched and no packages were resolved.")
        return
    if subprocess.run(["/usr/bin/pgrep", "-x", "Xcode"],
                      stdout=subprocess.DEVNULL).returncode == 0:
        raise ValueError("Save your work and quit Xcode (Command-Q), then double-click this launcher again.")
    # Cached dependencies can be used without a fresh GitHub round-trip. Keep
    # the optional network probe in --check so an intermittent remote timeout
    # does not prevent opening an already resolved project.
    arguments = ["/usr/bin/open", "-a", "Xcode"]
    for key, value in changes.items():
        arguments.extend(["--env", key + "=" + value])
    arguments.append(str(PROJECT))
    subprocess.run(arguments, check=True)
    print("Opened FL-Tiya with the existing system proxy for this Xcode process.")
    print("In Xcode, choose File > Packages > Resolve Package Versions.")
    print("Choose FLTiyaPreview when you are ready to preview the app.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError):
        # Fixed copy avoids printing inherited environment or credential errors.
        print("Unable to open the project with the proxy.")
        if sys.argv[1:] != ["--check"]:
            print("Save and quit Xcode first. Keep your HTTPS system proxy enabled, then try again.")
        else:
            print("Check your HTTPS system proxy and GitHub connection.")
        raise SystemExit(1)
