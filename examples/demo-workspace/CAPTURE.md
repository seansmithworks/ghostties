# Ghostties Screen-Capture Runbook

Concrete, copy-paste instructions for recording the Ghostties demo workspace. Designed to be executed in ~30 minutes and reshootable on any future session. This same setup and shotlist feeds both the portfolio case study and social-media promo clips.

---

## 1. Scene Setup

Consistency matters because reshoots need to line up with earlier frames — same window position, same chrome, same wallpaper — so clips cut together cleanly without visible jumps.

### Load the fixture

Ghostties discovers any directory that contains a `.ghostties/tasks/` subfolder. Open each of the seven project folders individually in Ghostties (navigate to or open each path):

```
examples/demo-workspace/atlas-api/
examples/demo-workspace/pendulum/
examples/demo-workspace/silo/
examples/demo-workspace/wren/
examples/demo-workspace/switchboard/
examples/demo-workspace/fieldwork/
examples/demo-workspace/trove/
```

When loaded correctly you should see:
- 7 named pixel-art ghosts in the project rail
- All six zones populated: Inbox, Backlog, Running, Needs You, Review, Graveyard
- 6 tasks in "Needs You" — cards appear in terracotta (#C97350)
- 5 running tasks with branch/worktree/files-staged metadata

### Window and environment

| Setting | Target |
|---------|--------|
| Window size | 1440 x 900 pt logical (renders 2880 x 1800 at 2x retina) |
| Color mode | Light |
| Desktop wallpaper | Solid neutral — cool stone `#E8E4DE` or plain white; no patterns |
| Desktop icons | Hidden — `defaults write com.apple.finder CreateDesktop false; killall Finder` |
| Menu bar | Notification badges cleared; other app icons hidden or minimal; Ghostties status item visible |
| Terminal theme | Cool stone palette: dark-on-light, no bright syntax colors competing with Ghostties chrome |
| Dock | Autohide on, or slide off-screen before recording |

**Window position:** top-left corner snapped to `(0, 25)` (below menu bar). Exact position reproducible with:

```bash
# Set Ghostties window to 1440x900 at top-left (adjust app name if different)
osascript -e 'tell application "Ghostties" to set bounds of front window to {0, 25, 1440, 925}'
```

---

## 2. The Shotlist

Five shots minimum. Capture in this order — the hero last, after you have verified all zones look right.

---

### Shot 1 — HERO (motion, 8-12s silent loop)

**What is on screen:** Full Ghostties workspace. Ghost rail on the left with all 7 project ghosts visible and labeled. The active project (use `switchboard` — it has a running task, a needs-you card, and a review task) shows all six zone columns with cards. A Needs You card sits terracotta in the center column. The right panel shows a terminal pane with a `gt` command running. The menu bar status item is lit.

**Why it earns its place:** This is the thesis in one frame. Rail + zones + terracotta + live terminal = the whole product story before anyone reads a word.

**How to capture:**

1. Open a terminal pane inside Ghostties showing the `switchboard` project.
2. Run `gt list` (or whatever the CLI command is to list tasks) so the terminal has live output visible.
3. Trigger a "Needs You" card flip if the app supports it (or ensure `replay-dead-letter.md` is visible in the Needs You zone).
4. Use `Cmd-Shift-5`, choose "Record Selected Portion", drag to the Ghostties window (1440 x 900), click Record.
5. Let it run 10-15 seconds while you slowly hover across ghost rail icons.
6. Stop recording. Trim to 8-12s in QuickTime (Edit > Trim) and export as `.mp4`.

**Capture command (scripted alternative with ffmpeg):**

```bash
# Capture region x=0,y=25,w=1440,h=900 for 15 seconds at 30fps
ffmpeg -f avfoundation -framerate 30 -capture_cursor 1 \
  -video_size 1440x900 -i "1:none" \
  -vf "crop=1440:900:0:25" \
  -t 15 -c:v libx264 -crf 18 -preset slow \
  ~/Desktop/ghostties-hero-raw.mp4
```

> Note: `avfoundation` device index `1` is typically the built-in display. Run `ffmpeg -f avfoundation -list_devices true -i ""` first to confirm your display index.

**Output:** `ghostties-hero-raw.mp4` on Desktop. Trim and rename to `ghostties-hero.mp4`.

---

### Shot 2 — The Terracotta "Needs You" Moment (motion 3-5s, or sharp still)

**What is on screen:** Tight crop on the sidebar/zone panel. A task card in the Needs You column is rendered in terracotta (`#C97350`). The Ghostties menu bar status item is simultaneously lit with a count badge. The two signals in sync — this is the core loop.

**Why it earns its place:** Shows the blocking-question mechanic and the ambient status item working together. The color is the signal.

**Still (clean, fast):**

```bash
# Single window capture with shadow — click the Ghostties window when prompted
screencapture -iw ~/Desktop/ghostties-needs-you.png
```

**Region crop (if you want tighter framing on just the zone panel, e.g. 600x500 crop starting at left-center):**

```bash
# Adjust x,y,w,h to frame just the Needs You column + menu bar
screencapture -o -R 720,25,480,500 ~/Desktop/ghostties-needs-you-crop.png
```

**Motion (if capturing the card flip in the app):**

```bash
ffmpeg -f avfoundation -framerate 60 -capture_cursor 0 \
  -video_size 480x500 -i "1:none" \
  -vf "crop=480:500:720:25" \
  -t 5 -c:v libx264 -crf 16 -preset slow \
  ~/Desktop/ghostties-needs-you-raw.mp4
```

---

### Shot 3 — The Ghost Rail Isolated (still)

**What is on screen:** Only the project rail — the 7 named pixel-art ghosts stacked vertically with project labels. Crop tight so each ghost and its label is readable. No zone columns in frame.

**Why it earns its place:** The brand IP in one frame. The ghost rail is the visual identity of the product. One still can carry a blog post, a tweet, or an App Store screenshot.

**Capture:**

```bash
# Tight region crop — adjust x,y to match your exact rail width (~60px) and height
screencapture -o -R 0,25,80,900 ~/Desktop/ghostties-rail.png
```

Or use the interactive picker to click and drag just the rail:

```bash
screencapture -si ~/Desktop/ghostties-rail.png
```

---

### Shot 4 — Status Without Focus (still or 4s clip)

**What is on screen:** Ghostties window is behind another app (e.g. push a Finder window or a terminal in front of it). The Ghostties window is visible but unfocused. The macOS menu bar status item still shows the terracotta count badge in the menu bar.

**Why it earns its place:** This is the key ambient-mode pitch. Ghostties tells you something needs your attention even when you're not looking at it. The status item in the menu bar does the work.

**Still:**

```bash
screencapture -iw ~/Desktop/ghostties-unfocused.png
```

Click the window behind Ghostties (not the Ghostties window itself) so you capture the frontmost app, but the menu bar with Ghostties' status item is still visible.

**Region crop to get menu bar + status item zoomed:**

```bash
# Capture just the menu bar strip where the status item lives (~200px wide, 25px tall)
screencapture -o -R 1200,0,240,25 ~/Desktop/ghostties-menubar-status.png
```

---

### Shot 5 — One Source of Truth, Three Ways In (still)

**What is on screen:** The same task visible simultaneously in three places — (1) the task card in the Ghostties sidebar, (2) a `gt` CLI invocation in a terminal pane showing the same task's details, and (3) the underlying Markdown task file (`replay-dead-letter.md` or `confirm-token-expiry.md`) open in a text editor or `cat`-ed in a second terminal pane.

**Why it earns its place:** The thesis of the underlying data model in one frame. No proprietary sync cloud — it's a Markdown file in your project folder. This is the differentiator shot for the case study.

**Suggested layout before capturing:**
- Left third: Ghostties sidebar showing the task card
- Center third: Terminal running `gt show replay-dead-letter` (or equivalent)
- Right third: Another terminal running `cat examples/demo-workspace/switchboard/.ghostties/tasks/replay-dead-letter.md`

**Capture:**

```bash
# Full window capture of the composed layout
screencapture -iw ~/Desktop/ghostties-three-ways.png
```

---

## 3. Capture Commands Reference

### Stills

```bash
# Single window with drop shadow (click the target window when crosshair appears)
screencapture -iw ~/Desktop/out.png

# Interactive drag selection (no shadow, exact region)
screencapture -si ~/Desktop/out.png

# Tight region by coordinates — no click required
# Format: x=left-edge, y=top-edge, w=width, h=height (all in logical points)
screencapture -o -R 0,25,1440,900 ~/Desktop/ghostties-full.png

# Practical example: just the zone columns area (right of the rail)
screencapture -o -R 80,25,1360,900 ~/Desktop/ghostties-zones.png

# Practical example: menu bar status item (far right)
screencapture -o -R 1200,0,240,25 ~/Desktop/ghostties-menubar.png
```

### Motion

**Built-in (no dependencies):** `Cmd-Shift-5` > Record Selected Portion > drag to Ghostties window > Record. Produces a `.mov` in `~/Desktop`. Trim in QuickTime (Edit > Trim).

**ffmpeg region capture (one concrete example):**

```bash
# Prerequisites: brew install ffmpeg
# List available capture devices first:
ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -E "\[AVFoundation"

# Capture full Ghostties window (1440x900 at top-left below menu bar) for 15s
ffmpeg -f avfoundation \
  -framerate 30 \
  -capture_cursor 1 \
  -video_size 2880x1800 \
  -i "1:none" \
  -vf "crop=2880:1800:0:50,scale=1440:900" \
  -t 15 \
  -c:v libx264 -crf 18 -preset slow \
  -pix_fmt yuv420p \
  ~/Desktop/ghostties-hero-raw.mp4
```

> The `-video_size 2880x1800` captures at retina resolution; the `scale=1440:900` brings it back to logical pixels for a clean 1x output. Omit the scale step if you want the full retina master.

Capture 10-15s, then trim/loop in QuickTime or iMovie. Target 8-12s for the hero loop.

---

## 4. Encode and Wire into the Portfolio

The encode pipeline lives in the **portfolio repo** (`~/Code/seansmithdesign.com/`), not here. Move your raw captures there:

```bash
# Move raw captures to the portfolio repo
mv ~/Desktop/ghostties-hero.mp4 ~/Code/seansmithdesign.com/public/videos/ghostties-hero.mp4
mv ~/Desktop/ghostties-needs-you.png ~/Code/seansmithdesign.com/public/images/ghostties/ghostties-needs-you.webp
mv ~/Desktop/ghostties-rail.png ~/Code/seansmithdesign.com/public/images/ghostties/ghostties-rail.webp
mv ~/Desktop/ghostties-unfocused.png ~/Code/seansmithdesign.com/public/images/ghostties/ghostties-unfocused.webp
mv ~/Desktop/ghostties-three-ways.png ~/Code/seansmithdesign.com/public/images/ghostties/ghostties-three-ways.webp
```

Convert PNGs to WebP before moving (saves ~70% file size):

```bash
# Requires: brew install webp
for f in ~/Desktop/ghostties-*.png; do
  cwebp -q 90 "$f" -o "${f%.png}.webp"
done
```

**Encode the WebM sibling** (required for Chrome/Firefox) then verify all media in the portfolio repo:

```bash
cd ~/Code/seansmithdesign.com
./scripts/encode-video.sh public/videos/ghostties-hero.mp4
npm run check:media
```

### Asset framing spec (Ghostties is a Landscape demo)

Per `docs/ASSETS.md`, Ghostties is a **macOS desktop app** — use the **Landscape demo** safe frame, NOT phone-bezel framing:

| Property | Value |
|----------|-------|
| Frame | **1200 x 900** (4:3) |
| `fit` | `"contain"` |
| Letterbox color | Cool stone (`--color-stone` or `#E8E4DE`) with terracotta (`#C97350`) as spot accent |
| Window chrome | macOS shadow from `-iw` is the frame — no artificial device bezels |
| Poster | First frame of the loop, exported as `ghostties-hero-poster.jpg` |

### Naming convention (mirrors Brukas pattern)

```
public/videos/ghostties-hero.mp4          # hero loop
public/videos/ghostties-hero.webm         # WebM sibling (auto-generated)
public/images/ghostties/ghostties-hero-poster.jpg     # first-frame poster
public/images/ghostties/ghostties-needs-you.webp      # Shot 2
public/images/ghostties/ghostties-rail.webp           # Shot 3
public/images/ghostties/ghostties-unfocused.webp      # Shot 4
public/images/ghostties/ghostties-three-ways.webp     # Shot 5
```

### Wire into project data

In `src/data/projects.ts`, update the Ghostties entry:

```ts
video: {
  sources: [
    { src: "/videos/ghostties-hero.webm", type: "video/webm" },
    { src: "/videos/ghostties-hero.mp4",  type: "video/mp4"  },
  ],
  poster: "/images/ghostties/ghostties-hero-poster.jpg",
  fit: "contain",
},
```

---

## 5. Reuse Note

This fixture and runbook are the source for social-media promo clips — the same scene, same terracotta moment, same three-ways shot. Keep `examples/demo-workspace/` task content and this CAPTURE.md in sync as the app evolves so every reseed produces consistent captures.
