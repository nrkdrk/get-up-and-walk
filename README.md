# Get Up and Walk

[![build](https://github.com/nrkdrk/get-up-and-walk/actions/workflows/build.yml/badge.svg)](https://github.com/nrkdrk/get-up-and-walk/actions/workflows/build.yml)

A macOS menu-bar app that breaks a desk-bound day into healthy intervals — and keeps a record so you can see the trend. No dependencies, one command to build.

<p align="center">
  <img src="assets/icon.png" width="180" alt="Get Up and Walk">
</p>

## Why

Sitting for hours slows circulation, pools blood in the legs, and wears down the neck and shoulders. Most break reminders nag you about one thing and keep no record. This one manages several reminders from a single place, logs every outcome, and charts what you measure.

The interface and the spoken reminders come in Turkish and English. Everything else — code, comments, build output — is English.

## What it does

**Reminders.** A small card appears near the top of the screen, plays a soft chime, then speaks your name: *"Berk, you need to stand up and walk."* It closes itself after 20 seconds. **Done** logs a completion, timing out logs a miss, **10 min** snoozes.

| Reminder | Schedule | On by default |
|---|---|---|
| Time to move | hourly | yes |
| Drink water | every 2h | yes |
| Compression socks | daily 07:45 | depends on profile |
| Legs up | daily 21:30 | depends on profile |
| Weekly weigh-in | Sunday 08:30 | yes |
| Weekly calf measurement | Sunday 09:00 | depends on profile |
| Ankle pumps | every 30 min | depends on profile |
| Eye break (20-20-20) | every 20 min | no |

Each can be toggled independently from the menu bar or the dashboard.

**Stays out of the way.** Interval reminders never fire outside your active hours (default 08:00–23:00). Nothing fires while the screen is locked, or after ten minutes without keyboard or mouse input — you are already away from the desk, so logging a "miss" would be wrong. The reminder window is a non-activating panel: it never steals focus while you type.

**Measurement tracking.** The weekly weigh-in and calf measurement prompt for numbers instead of a plain acknowledgement. The calf chart plots left, right, and the difference between them, with a dashed threshold line at 3 cm — asymmetry is the number worth watching, so the chart shows it directly rather than making you subtract.

**Dashboard.** ⌘D opens a window with today's summary, your day streak, calf and weight trends, a 12-week consistency heatmap, and a table of every reminder with its next fire time.

**Your data stays local.** Everything lives in `~/Library/Application Support/GetUpAndWalk/log.json`. No network calls, no account, no telemetry. One menu click exports a CSV to the Desktop, which is handy to bring to a doctor's appointment.

## Install

Requires Xcode Command Line Tools (`xcode-select --install`). Nothing else.

```bash
git clone https://github.com/nrkdrk/get-up-and-walk.git
cd get-up-and-walk
./build.sh
open GetUpAndWalk.app
```

To keep it running, move `GetUpAndWalk.app` to `/Applications` and add it under **System Settings → General → Login Items**.

The binary is ad-hoc signed, not notarized by Apple. If macOS blocks the first launch, allow it under **System Settings → Privacy & Security**.

On first launch you fill in a short profile: language, name, height, weight, and — optionally — whether you have varicose or leg vein complaints. That last answer decides which leg-circulation reminders start switched on. Every reminder stays individually adjustable afterwards.

The app lives entirely in the menu bar and never appears in the Dock. If you cannot find its icon on a MacBook Pro, the menu bar is probably full and the icon is hidden behind the notch — remove another icon to make room.

## Project layout

```
src/Model.swift       reminder kinds, profile, localization
src/Store.swift       scheduling engine, log, speech
src/Reminder.swift    reminder panel and card
src/Charts.swift      hand-drawn charts, heatmap
src/Onboarding.swift  profile setup screen
src/Dashboard.swift   dashboard window
src/App.swift         menu bar, app entry point
build.sh              compile, icon, bundle
make_icon.py          icon generation (needs Pillow)
assets/icon.png       source icon, converted to .icns at build time
```

`build.sh` compiles every `.swift` under `src/`, converts `assets/icon.png` into an `.icns` with `sips` and `iconutil`, writes `Info.plist`, and ad-hoc signs the bundle. GitHub Actions runs the same script on every push.

Charts are drawn by hand with `Path` rather than Swift Charts. That keeps the build dependency-free and makes room for things a stock chart will not give you, like the threshold line.

## Adding a reminder

Add a case to the `Kind` enum in `src/Model.swift` and fill in its title, spoken sentence, icon, colour, and schedule. The scheduler, the reminder panel, the dashboard row, the CSV export, and both languages pick it up automatically.

## Disclaimer

This is a software tool, not a medical device. Its reminders and thresholds come from general health guidance; it does not diagnose or treat anything. The 3 cm calf-asymmetry line is a widely cited clinical rule of thumb, included as a prompt to seek advice — not as a diagnosis.

If you have swelling, pain, warmth, discoloration, or one-sided asymmetry in a leg, see a doctor. Sudden one-sided calf swelling with pain warrants same-day attention. The records this app keeps are data you can bring to a consultation, never a substitute for one.

## License

MIT
