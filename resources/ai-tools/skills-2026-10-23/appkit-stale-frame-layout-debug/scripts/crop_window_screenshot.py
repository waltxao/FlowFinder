#!/usr/bin/env python3
"""Capture the screen and crop out one app window's region.

Read-only apart from the PNGs it writes. Coordinates come from System Events
(top-left origin, points); the screenshot is in device pixels, so the crop
multiplies by the display scale.

Usage:
  crop_window_screenshot.py --pid 7246 --out /tmp/bar.png
  crop_window_screenshot.py --pid 7246 --out /tmp/bar.png \
      --region 0,500,700,330 --scale 2 --keep-full

--region is left,top,width,height in points, relative to the window origin.
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def window_geom(pid, index):
    # Address the window by index in every accessor: `set w to window 1` binds a
    # specifier that System Events later re-resolves by name and fails on (-1728).
    res = run([
        "osascript", "-e",
        'tell application "System Events" to tell (first process whose unix id is %d)\n'
        "  return {position of window %d, size of window %d, name of window %d}\n"
        "end tell" % (pid, index, index, index),
    ])
    if res.returncode != 0:
        count = run([
            "osascript", "-e",
            'tell application "System Events" to tell (first process whose unix id is %d)\n'
            "  return count of windows\n"
            "end tell" % pid,
        ])
        die("cannot read window %d of pid %d (windows=%s): %s" % (
            index, pid, count.stdout.strip() or "?", res.stderr.strip()))
    fields = [f.strip().strip('"') for f in res.stdout.split(",")]
    nums = [int(float(v)) for v in fields[:4]]
    if len(nums) < 4:
        die("unexpected geometry output: %r" % res.stdout)
    x, y, w, h = nums
    title = ",".join(fields[4:]).strip()
    return x, y, w, h, title


def display_scale(pixel_width):
    res = run([
        "osascript", "-e",
        'tell application "Finder" to get bounds of window of desktop',
    ])
    nums = [int(float(v)) for v in re.findall(r"-?\d+(?:\.\d+)?", res.stdout)] if res.returncode == 0 else []
    if len(nums) >= 4 and nums[2] > 0:
        points_width = nums[2] - nums[0]
        scale = pixel_width / float(points_width)
        if abs(scale - round(scale)) < 0.05 and round(scale) >= 1:
            return int(round(scale))
    die("cannot derive display scale (screenshot is %d px wide). "
        "Re-run with --scale N (e.g. 2 for Retina)." % pixel_width)


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--pid", type=int, required=True, help="unix id of the app to capture")
    ap.add_argument("--window", type=int, default=1, help="1-based window index (default 1)")
    ap.add_argument("--out", required=True, help="output PNG path")
    ap.add_argument("--region", help="left,top,width,height in points, relative to the window origin")
    ap.add_argument("--scale", type=int, help="force device-pixel scale (default: auto-detect)")
    ap.add_argument("--full-screen", help="reuse an existing full-screen PNG instead of capturing")
    ap.add_argument("--keep-full", action="store_true", help="do not delete the full-screen capture")
    args = ap.parse_args()

    try:
        from PIL import Image
    except ImportError:
        die("Pillow is required: python3 -m pip install pillow")

    x, y, w, h, title = window_geom(args.pid, args.window)

    png = args.full_screen
    tmp = None
    if not png:
        tmp = tempfile.mktemp(prefix="ff-full-", suffix=".png")
        res = run(["screencapture", "-x", tmp])
        if res.returncode != 0 or not os.path.exists(tmp):
            die("screencapture failed: %s" % res.stderr.strip())
        png = tmp

    im = Image.open(png)
    scale = args.scale or display_scale(im.size[0])

    left, top, right, bottom = 0, 0, w, h
    if args.region:
        parts = [int(v) for v in args.region.split(",")]
        if len(parts) != 4:
            die("--region needs 4 comma-separated values: left,top,width,height")
        rl, rt, rw, rh = parts
        left, top, right, bottom = rl, rt, rl + rw, rt + rh

    px0 = max(0, x + left) * scale
    py0 = max(0, y + top) * scale
    box = (px0, py0, min((x + right) * scale, im.size[0]), min((y + bottom) * scale, im.size[1]))
    box = (box[0], box[1], min(box[2], im.size[0]), min(box[3], im.size[1]))
    if box[2] <= box[0] or box[3] <= box[1]:
        die("crop box %s falls outside the %dx%d screenshot" % (box, im.size[0], im.size[1]))

    out_dir = os.path.dirname(os.path.abspath(args.out))
    if not os.path.isdir(out_dir):
        os.makedirs(out_dir)
    im.crop(box).save(args.out)
    cropped = Image.open(args.out)
    if tmp and not args.keep_full:
        os.remove(tmp)

    print("OK window=%r pid=%d geom=%d,%d %dx%d pt scale=%d box=%s" % (
        title, args.pid, x, y, w, h, scale, box))
    print("SAVED %s (%dx%d px)" % (os.path.abspath(args.out), cropped.size[0], cropped.size[1]))


if __name__ == "__main__":
    main()
