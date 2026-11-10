#!/usr/bin/env python3
"""Provision the installed FL-Tiya Social Test simulator app from a private Xcode scheme."""

import argparse
import base64
import json
import os
import plistlib
import re
import stat
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from uuid import UUID

BUNDLE_ID = "com.fltiya.ios.development.community"
SCHEME = (
    Path.home()
    / ".codex/private/fl-tiya-ios/xcode-schemes/FLTiyaCommunityTesting-Local.xcscheme"
)
ENVIRONMENT_KEY = "FLTIYA_COMMUNITY_TEST_ACCOUNTS"
CONFIGURATION_NAME = "CommunityTestAccounts.json"
MAX_CONFIGURATION_BYTES = 16_384


class ConfigurationError(Exception):
    pass


def run_simctl(*arguments):
    try:
        return subprocess.run(
            ["xcrun", "simctl", *arguments], check=True, capture_output=True,
            text=True, timeout=15,
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        raise ConfigurationError("Could not query the installed simulator apps.") from None


def booted_device(requested):
    try:
        runtimes = json.loads(run_simctl("list", "devices", "booted", "-j"))["devices"]
        devices = [
            device for group in runtimes.values() for device in group
            if device["state"] == "Booted" and device.get("isAvailable", False)
            and (requested is None or device["udid"].lower() == requested.lower())
        ]
    except (KeyError, TypeError, ValueError, AttributeError):
        raise ConfigurationError("Could not read the booted simulator list.") from None
    if not devices:
        raise ConfigurationError("The requested simulator must already be booted.")
    if len(devices) != 1:
        raise ConfigurationError("More than one simulator is booted. Pass the intended device UDID.")
    return devices[0]


def installed_data_container(device):
    try:
        container = Path(run_simctl("get_app_container", device["udid"], BUNDLE_ID, "data"))
    except ConfigurationError:
        raise ConfigurationError("Install FL-Tiya Social Test on the selected simulator first.") from None
    try:
        udid = UUID(device["udid"])
        data_root = Path(device["dataPath"]).resolve(strict=True)
        registered_root = data_root / "Containers" / "Data" / "Application"
        if (
            data_root.name != "data" or UUID(data_root.parent.name) != udid
            or data_root.parent.parent.name != "Devices"
            or container.parent != registered_root or container.resolve(strict=True) != container
            or not container.is_dir()
        ):
            raise ValueError
        UUID(container.name)
        metadata_file = container / ".com.apple.mobile_container_manager.metadata.plist"
        if metadata_file.is_symlink():
            raise ValueError
        with metadata_file.open("rb") as file:
            if plistlib.load(file).get("MCMMetadataIdentifier") != BUNDLE_ID:
                raise ValueError
    except (KeyError, OSError, RuntimeError, TypeError, ValueError, AttributeError, plistlib.InvalidFileException):
        raise ConfigurationError("Could not verify the FL-Tiya Social Test data container.") from None
    return container


def valid_email(email):
    if not isinstance(email, str) or len(email) > 254 or email.count("@") != 1:
        return False
    local, domain = email.split("@")
    labels = domain.split(".")
    return (
        re.fullmatch(r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]{1,64}", local) is not None
        and not local.startswith(".") and not local.endswith(".") and ".." not in local
        and len(labels) >= 2 and len(labels[-1]) >= 2
        and all(re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label) for label in labels)
    )


def read_accounts(scheme_path):
    try:
        descriptor = os.open(scheme_path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(descriptor, "rb") as file:
            properties = os.fstat(file.fileno())
            if (
                not stat.S_ISREG(properties.st_mode) or properties.st_uid != os.getuid()
                or properties.st_mode & 0o077 or properties.st_size > 65_536
            ):
                raise ValueError
            scheme = ET.fromstring(file.read(65_537))
        launch = scheme.find("LaunchAction")
        if launch is None or launch.get("buildConfiguration") != "CommunityTesting":
            raise ValueError
        entries = [
            entry for entry in launch.findall("./EnvironmentVariables/EnvironmentVariable")
            if entry.get("key") == ENVIRONMENT_KEY
        ]
        if len(entries) != 1 or entries[0].get("isEnabled") != "YES":
            raise ValueError
        encoded = entries[0].get("value", "")
        if len(encoded) > MAX_CONFIGURATION_BYTES:
            raise ValueError
        accounts = json.loads(base64.b64decode(encoded, validate=True).decode("utf-8"))
        if not isinstance(accounts, list) or not accounts:
            raise ValueError
        emails, codes = set(), set()
        rows = []
        for account in accounts:
            if not isinstance(account, dict):
                raise ValueError
            name, email, code = (account.get(key) for key in ("displayName", "email", "accessCode"))
            if (
                not isinstance(name, str) or not name.strip() or not valid_email(email)
                or email.lower() in emails or not isinstance(code, str)
                or not 1 <= len(code.encode("utf-8")) <= 256
                or any(character.isspace() for character in code) or code in codes
            ):
                raise ValueError
            emails.add(email.lower())
            codes.add(code)
            rows.append({"displayName": name, "email": email, "accessCode": code})
        return json.dumps(rows, ensure_ascii=False, separators=(",", ":")).encode("utf-8"), len(rows)
    except (OSError, ValueError, TypeError, ET.ParseError):
        raise ConfigurationError(
            "The private FLTiyaCommunityTesting-Local scheme is missing or its enabled test account configuration is invalid."
        ) from None


def install_accounts(container, data):
    library = container / "Library"
    support = library / "Application Support"
    temporary_path = None
    try:
        if not library.is_dir() or library.is_symlink():
            raise ValueError
        support.mkdir(mode=0o700, exist_ok=True)
        if not support.is_dir() or support.is_symlink():
            raise ValueError
        destination = support / CONFIGURATION_NAME
        if destination.is_symlink() or (destination.exists() and not destination.is_file()):
            raise ValueError
        descriptor, name = tempfile.mkstemp(prefix=".community-test-accounts-", dir=support)
        temporary_path = Path(name)
        with os.fdopen(descriptor, "wb") as file:
            os.fchmod(file.fileno(), 0o600)
            file.write(data)
        os.replace(temporary_path, destination)
        temporary_path = None
    except (OSError, ValueError):
        raise ConfigurationError("Could not write the private configuration to FL-Tiya Social Test.") from None
    finally:
        if temporary_path is not None:
            try:
                temporary_path.unlink(missing_ok=True)
            except OSError:
                pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("simulator_udid", nargs="?", help="a booted simulator UDID (omit when exactly one is booted)")
    arguments = parser.parse_args()
    try:
        device = booted_device(arguments.simulator_udid)
        container = installed_data_container(device)
        accounts, count = read_accounts(SCHEME)
        install_accounts(container, accounts)
    except ConfigurationError as error:
        parser.exit(1, f"Error: {error}\n")
    print(f"Configured {count} test account(s) in FL-Tiya Social Test.")


if __name__ == "__main__":
    main()
