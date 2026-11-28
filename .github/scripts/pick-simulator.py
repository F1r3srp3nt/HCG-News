#!/usr/bin/env python3
"""Prints the UDID and name of an available simulator on the newest iOS runtime.
Usage: pick-simulator.py iphone|ipad"""
import json, subprocess, sys, re

kind = sys.argv[1]
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
runtimes = sorted((r for r in data["devices"] if "iOS" in r),
                  key=lambda r: [int(x) for x in re.findall(r"\d+", r.split("iOS")[-1])], reverse=True)
prefs = (["iPhone 17 Pro Max", "iPhone 16 Pro Max", "iPhone 17 Pro", "iPhone"] if kind == "iphone"
         else ["iPad Pro 13-inch", "iPad Pro (12.9-inch)", "iPad Air 13-inch", "iPad"])
for runtime in runtimes:
    devices = data["devices"][runtime]
    for pref in prefs:
        for d in devices:
            if d["name"].startswith(pref):
                print(f'{d["udid"]}\t{d["name"]}\t{runtime.split(".")[-1]}')
                sys.exit(0)
sys.exit(f"No {kind} simulator available")
