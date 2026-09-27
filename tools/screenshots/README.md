# Safe terminal screenshot capture

Replaces the earlier `screencapture -l<wid>` workflow that read a **cached** window id from
`wid.txt`. Window ids are recycled by macOS: when the cached id went stale, the capture silently
saved whatever window had inherited it. That happened three times and captured private content
(a WhatsApp call, browser history, personal messages), which had to be deleted.

This version cannot do that. Every capture:

1. re-enumerates on-screen windows and resolves the target **fresh** (no cached id),
2. requires the window's **owning application** to be `Terminal` and its pid to match `TERM_PID`,
3. requires **exactly one** match — if two windows match it refuses rather than guessing,
4. re-checks after the capture that the id still belongs to the same Terminal window,
5. checks the PNG's pixel dimensions equal the window's bounds at 1x/2x/3x — a mismatch means
   something else was captured,
6. deletes the file and exits non-zero on any failure.

It only ever captures a single window id. It never captures the screen (`-l` only, no full-screen
or `-R` region capture), so nothing outside the target window can be recorded.

## Build

```bash
swiftc -O -o winlist winlist.swift
```

`winlist` prints, tab-separated: window id, owning app, pid, layer, x, y, width, height.
Owning-app names need no Screen Recording permission (unlike window *titles*).

## Use

Open a dedicated capture window at a distinctive size so it can never be confused with your own
Terminal windows:

```bash
osascript <<'AS'
tell application "Terminal"
  activate
  do script "clear; export PS1='$ '"
  set the number of columns of front window to 132
  set the number of rows of front window to 38
  set bounds of front window to {60, 80, 1160, 700}
end tell
AS
```

Then capture, pinning both the pid and that window's size:

```bash
TERM_PID=$(./winlist | awk -F'\t' '$2=="Terminal"{print $3; exit}')
TERM_PID=$TERM_PID TERM_GEOM=1100,620 ./shot.sh ../../artifacts/lab-27/screenshots/01-quota.png
```

`TERM_GEOM` is `width,height` of the capture window and is what distinguishes it from any other
Terminal window you have open. Omit it only if that is your sole Terminal window.

## Verified

Both paths were exercised on macOS 26 (2026-09-27):

- **positive** — `ok verified.png 2200x1240 (wid=278384 Terminal pid=87295 scale=2x)`; the image is
  the target Terminal window and nothing else.
- **negative** — pointed at the Claude app's pid: `REFUSED: no on-screen Terminal window for pid
  79535`, and no file was written.

> Note: `screencapture` silently refuses to write to a **leading-dot filename**
> (`screencapture: cannot write file to intended destination, .../.raw.png`). The scratch file is
> therefore `raw.png`, not `.raw.png`. This cost an hour of false "capture produced nothing"
> failures — don't reintroduce it.

## Still to capture

Labs **26**, **27** and **29** have no screenshots. Each lab carries a
"📷 Screenshots outstanding" note and embeds no image, so nothing is fabricated — the evidence
transcripts under `artifacts/lab-NN/evidence/` are the proof in the meantime.
