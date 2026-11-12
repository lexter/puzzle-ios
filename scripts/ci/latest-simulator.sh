#!/usr/bin/env bash
# Prints the UDID of the newest available iPhone simulator on the newest installed iOS runtime,
# so CI always tests on the latest image the runner has.
set -euo pipefail

xcrun simctl list devices available --json | python3 -c '
import json, re, sys

devices = json.load(sys.stdin)["devices"]

def version(runtime):
    match = re.search(r"iOS-(\d+)-(\d+)(?:-(\d+))?$", runtime)
    return tuple(int(part or 0) for part in match.groups()) if match else None

runtimes = sorted((v, r) for r in devices if (v := version(r)) and any(d["name"].startswith("iPhone") for d in devices[r]))
if not runtimes:
    sys.exit("no iOS simulator runtime with an iPhone is installed")
version_tuple, runtime = runtimes[-1]
iphones = [d for d in devices[runtime] if d["name"].startswith("iPhone")]
# Prefer the newest model number, then a Pro model.
def model(device):
    number = re.search(r"iPhone (\d+)", device["name"])
    return (int(number.group(1)) if number else 0, "Pro" in device["name"], device["name"])
iphones.sort(key=model)
chosen = iphones[-1]
name = chosen["name"]
label = ".".join(map(str, version_tuple))
print(f"{name} (iOS {label})", file=sys.stderr)
print(chosen["udid"])
'
