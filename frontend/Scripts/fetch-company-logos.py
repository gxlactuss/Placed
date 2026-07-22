#!/usr/bin/env python3
"""
Populates PlacementPrep/Resources/Logos with one PNG per bundled company.

Sources are tried in order of how close they are to the company's REAL logo:

  1. Homepage <link rel="apple-touch-icon"> — the actual full-colour brand mark
     the company ships for iOS home screens. Square by design, usually 180px+.
  2. /apple-touch-icon.png at the domain root — same asset, conventional path.
  3. Google favicon service at 256px — the real favicon, resolution varies.
  4. icon.horse / DuckDuckGo icon services — aggregators that sometimes hold
     a larger icon than the site advertises.

Monochrome glyph sets (Simple Icons and friends) are deliberately NOT used:
they render Google as a flat blue "G" rather than the real multicolour mark.
A slightly soft real logo beats a sharp wrong one.

Anything below MIN_PIXELS is rejected as too blurry for a 3x display. A company
with no usable logo gets no file, and the app falls back to an initials mark.

Usage:  python3 Scripts/fetch-company-logos.py
Then:   xcodegen generate
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request

# company name -> (domain, simple-icons slug or None for the last-resort glyph)
COMPANIES = {
    "Adobe":          ("adobe.com",         None),
    "Amazon":         ("amazon.com",        None),
    "Apple":          ("apple.com",         "apple"),
    "Atlassian":      ("atlassian.com",     "atlassian"),
    "Bloomberg":      ("bloomberg.com",     None),
    "ByteDance":      ("bytedance.com",     "bytedance"),
    "Databricks":     ("databricks.com",    None),
    "Flipkart":       ("flipkart.com",      None),
    "Groww":          ("groww.in",          None),
    "Goldman Sachs":  ("goldmansachs.com",  "goldmansachs"),
    "Google":         ("google.com",        "google"),
    "Infosys":        ("infosys.com",       "infosys"),
    "LinkedIn":       ("linkedin.com",      None),
    "Meesho":         ("meesho.com",        None),
    "Meta":           ("meta.com",          "meta"),
    "Myntra":         ("myntra.com",        None),
    "Microsoft":      ("microsoft.com",     None),
    "Morgan Stanley": ("morganstanley.com", None),
    "Netflix":        ("netflix.com",       "netflix"),
    "Nykaa":          ("nykaa.com",         None),
    "Nvidia":         ("nvidia.com",        "nvidia"),
    "Oracle":         ("oracle.com",        None),
    "PayPal":         ("paypal.com",        "paypal"),
    "PhonePe":        ("phonepe.com",       None),
    "Razorpay":       ("razorpay.com",      None),
    "Salesforce":     ("salesforce.com",    None),
    "Samsung":        ("samsung.com",       "samsung"),
    "Swiggy":         ("swiggy.com",        "swiggy"),
    "Uber":           ("uber.com",          "uber"),
    "Visa":           ("visa.com",          "visa"),
    "Zepto":          ("zeptonow.com",      None),
    "Zoho":           ("zoho.com",          "zoho"),
    "Zomato":         ("zomato.com",        "zomato"),
    # On-campus recruiters from the 2025-26 placement list.
    "Accenture":      ("accenture.com",     "accenture"),
    "Deloitte":       ("deloitte.com",      "deloitte"),
    "IDFC First Bank":("idfcfirstbank.com", None),
    "LTIMindtree":    ("ltimindtree.com",   None),
    "Media.net":      ("media.net",         None),
}

# 48px is soft when upscaled to a 36pt chip on a 3x screen, but it is the real
# logo. Below this it turns to mush, so those companies get an initials mark.
MIN_PIXELS = 48

# Curated by hand because every automatic source gave the wrong mark:
#   Microsoft  - sites serve a washed-out tile; this is the four-colour logo
#                from Wikimedia Commons, cropped to just the squares.
#   Samsung    - sites serve a generic blue "S"; this is the SAMSUNG wordmark
#                from Commons, auto-trimmed of its whitespace canvas.
#   Salesforce - only a 32px favicon exists; this is the iOS app icon (cloud).
#   Zomato     - only a 16px favicon exists; this is the iOS app icon.
# The script leaves these files alone so a re-run cannot overwrite them.
MANUAL = {"Microsoft", "Samsung", "Salesforce", "Zomato"}
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"}


def fetch(url, timeout=20):
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read() if r.status == 200 else None
    except Exception:
        return None


def png_size(path):
    try:
        out = subprocess.run(
            ["sips", "-g", "pixelWidth", "-g", "pixelHeight", path],
            capture_output=True, text=True, check=True,
        ).stdout
        return (int(re.search(r"pixelWidth: (\d+)", out).group(1)),
                int(re.search(r"pixelHeight: (\d+)", out).group(1)))
    except Exception:
        return 0, 0


def save_if_good(data, dest):
    """Write image bytes, keep only if it decodes and is large enough."""
    if not data or len(data) < 200:
        return False
    with open(dest, "wb") as f:
        f.write(data)
    w, h = png_size(dest)
    if w < MIN_PIXELS or h < MIN_PIXELS:
        os.remove(dest)
        return False
    # Normalise everything to PNG so the app has one loader path.
    subprocess.run(["sips", "-s", "format", "png", dest, "--out", dest],
                   capture_output=True)
    return True


def icon_links_from_homepage(domain):
    """Parse <link rel=...icon...> tags, biggest declared size first."""
    for base in (f"https://www.{domain}", f"https://{domain}"):
        html = fetch(base)
        if not html:
            continue
        text = html.decode("utf-8", "ignore")
        found = []
        for tag in re.findall(r"<link[^>]+>", text, re.I):
            if not re.search(r'rel=["\'][^"\']*icon', tag, re.I):
                continue
            href = re.search(r'href=["\']([^"\']+)["\']', tag, re.I)
            if not href:
                continue
            sizes = re.search(r'sizes=["\'](\d+)x(\d+)', tag, re.I)
            px = int(sizes.group(1)) if sizes else (
                180 if "apple-touch" in tag.lower() else 0
            )
            found.append((px, urllib.parse.urljoin(base + "/", href.group(1))))
        for px, url in sorted(found, key=lambda t: -t[0]):
            if px and px < MIN_PIXELS:
                continue
            yield url
        return


def from_homepage(domain, dest):
    for url in icon_links_from_homepage(domain) or []:
        if save_if_good(fetch(url), dest):
            return True
    return False


def from_root_apple_icon(domain, dest):
    for host in (f"https://www.{domain}", f"https://{domain}"):
        for path in ("/apple-touch-icon.png", "/apple-touch-icon-precomposed.png"):
            if save_if_good(fetch(host + path), dest):
                return True
    return False


def from_favicon_service(domain, dest):
    return save_if_good(
        fetch(f"https://www.google.com/s2/favicons?domain={domain}&sz=256"), dest
    )


def from_icon_services(domain, dest):
    # DuckDuckGo first: icon.horse silently GENERATES a grey letter placeholder
    # when it finds nothing, which looks like a broken image in the list. Its
    # results are worth spot-checking before trusting them.
    for url in (f"https://icons.duckduckgo.com/ip3/{domain}.ico",
                f"https://icon.horse/icon/{domain}"):
        if save_if_good(fetch(url), dest):
            return True
    return False


def _unused_from_simple_icons(slug, dest, tmp):
    """Monochrome glyph — last resort, not the real logo."""
    if not slug:
        return False
    data = fetch(f"https://cdn.simpleicons.org/{slug}")
    if not data or b"<svg" not in data:
        return False
    svg = os.path.join(tmp, f"{slug}.svg")
    with open(svg, "wb") as f:
        f.write(data)
    subprocess.run(["qlmanage", "-t", "-s", "256", "-o", tmp, svg],
                   capture_output=True)
    rendered = svg + ".png"
    if not os.path.exists(rendered):
        return False
    shutil.move(rendered, dest)
    if png_size(dest)[0] < MIN_PIXELS:
        os.remove(dest)
        return False
    return True


def main():
    if sys.platform != "darwin":
        sys.exit("Needs macOS: uses sips, and qlmanage for SVG fallback.")

    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    out = os.path.join(root, "PlacementPrep", "Resources", "Logos")
    os.makedirs(out, exist_ok=True)

    # Optional name filter: `fetch-company-logos.py Deloitte "Media.net"` only
    # refreshes the named companies, leaving every other logo untouched.
    only = set(sys.argv[1:])
    selected = {n: v for n, v in COMPANIES.items() if not only or n in only}

    rows, missing, glyphs = [], [], []  # glyphs retained for reporting shape
    with tempfile.TemporaryDirectory() as tmp:
        for name, (domain, slug) in sorted(selected.items()):
            dest = os.path.join(out, f"{name}.png")
            if name in MANUAL and os.path.exists(dest):
                w, h = png_size(dest)
                rows.append(f"  {name:<16} {w}x{h:<5} kept (curated by hand)")
                continue
            if os.path.exists(dest):
                os.remove(dest)

            if from_homepage(domain, dest):
                source = "homepage icon"
            elif from_root_apple_icon(domain, dest):
                source = "apple-touch-icon"
            elif from_favicon_service(domain, dest):
                source = "favicon"
            elif from_icon_services(domain, dest):
                source = "icon service"
            else:
                missing.append(name)
                continue

            w, h = png_size(dest)
            soft = "  (soft)" if w < 120 else ""
            rows.append(f"  {name:<16} {w}x{h:<5} {source}{soft}")

    print("\n".join(rows))
    print(f"\n{len(rows)} logos written to Resources/Logos")
    if missing:
        print(f"No logo, falls back to initials: {', '.join(missing)}")
    print("\nNext: cd frontend && xcodegen generate")


if __name__ == "__main__":
    main()
