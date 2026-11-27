#!/usr/bin/env python3
"""Summarises an .xcresult bundle (Xcode 16+ xcresulttool) and exports its screenshots with readable names.
Usage: xcresult-report.py <bundle.xcresult> <out dir>"""
import json, os, shutil, subprocess, sys

bundle, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)

def tool(*args):
    return json.loads(subprocess.check_output(["xcrun", "xcresulttool", *args, "--path", bundle, "--compact"]))

summary = tool("get", "test-results", "summary")
print(f"RESULT {summary.get('result')}: passed {summary.get('passedTests')}, failed {summary.get('failedTests')}, "
      f"skipped {summary.get('skippedTests')}, expected failures {summary.get('expectedFailures')}, total {summary.get('totalTestCount')}")
for d in summary.get("devicesAndConfigurations", []):
    dev = d.get("device", {})
    print(f"DEVICE {dev.get('deviceName')} · {dev.get('platform')} {dev.get('osVersion')}")
for f in summary.get("testFailures", []):
    print(f"FAILED {f.get('testIdentifierString') or f.get('testName')}: {(f.get('failureText') or '').strip()[:600]}")

tests = tool("get", "test-results", "tests")
rows = []
def walk(node, path):
    kind = node.get("nodeType")
    name = node.get("name")
    if kind == "Test Case":
        rows.append((node.get("result"), "/".join(path + [name]), node.get("duration", "")))
    for child in node.get("children", []) or []:
        walk(child, path + ([name] if kind in ("Test Suite", "Unit test bundle", "UI test bundle") else []))
for n in tests.get("testNodes", []):
    walk(n, [])
for result, name, duration in sorted(rows, key=lambda r: (r[0] != "Failed", r[1])):
    print(f"TEST {result:8} {name} {duration}")
with open(os.path.join(out, "tests.tsv"), "w") as fh:
    fh.write("\n".join("\t".join(map(str, r)) for r in rows))

att = os.path.join(out, "raw")
subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", bundle, "--output-path", att], check=False)
manifest = os.path.join(att, "manifest.json")
count = 0
if os.path.exists(manifest):
    for test in json.load(open(manifest)):
        for a in test.get("attachments", []):
            src = os.path.join(att, a["exportedFileName"])
            name = a.get("suggestedHumanReadableName") or a["exportedFileName"]
            ext = os.path.splitext(a["exportedFileName"])[1]
            base = name if name.endswith(ext) else name + ext
            shutil.copy(src, os.path.join(out, base.replace("/", "-")))
            count += 1
print(f"ATTACHMENTS exported: {count}")
