import subprocess, os, sys
SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256, 512]
# Aufruf: python3 Rendere-Symbol.py <Ordner mit SVG> <Zielordner>; braucht Chromium und ImageMagick.
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
CH = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"
for th in ["hell", "dunkel"]:
    for s in SIZES:
        f = f"atlas-symbol-{th}{'-klein' if s <= 24 else ''}.svg"
        svg = open(f"{src}/{f}").read().replace('viewBox="0 0 64 64"', f'viewBox="0 0 64 64" width="{s}" height="{s}"')
        html = f'<html><body style="margin:0;background:transparent">{svg}</body></html>'
        open("tmp.html", "w").write(html)
        png = f"{out}/atlas-{th}-{s}.png"
        W = max(s, 64)
        subprocess.run([CH, "--headless", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
                        "--force-device-scale-factor=1", "--default-background-color=00000000",
                        f"--window-size={max(W,500)},{max(W,500)}", f"--screenshot={os.path.abspath('tmp.png')}",
                        "file://" + os.path.abspath("tmp.html")], capture_output=True)
        subprocess.run(["convert", "tmp.png", "-crop", f"{s}x{s}+0+0", "+repage", f"PNG32:{png}"], check=True)
    subprocess.run(["convert"] + [f"{out}/atlas-{th}-{s}.png" for s in SIZES if s <= 256] + [f"{out}/atlas-{th}.ico"], check=True)
