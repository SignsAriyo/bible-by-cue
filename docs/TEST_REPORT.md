# Bible by Cue — test report

Date: 29 October 2026 · App version 1.0.1 (build 2) · Flutter 3.41.5

## Environment

- Android emulator "Pixel_6": Android 16 (API 36), x86_64, 2 GB RAM, 1080×2400 at 420 dpi.
- Host: 4 logical CPUs, shared with the emulator, Gradle and the Dart tools. The emulator ran under heavy load:
  its load average reached 18, Android's own System UI repeatedly showed "isn't responding", and the system
  Settings app needed 6.0–8.2 s to cold-start. **Timings below come from this overloaded emulator and are not
  estimates for a real phone.**
- **Airplane mode was on for every on-device test.** The release build also has no `INTERNET` permission (checked
  with `aapt2 dump permissions`), so the app cannot reach the network in any case.

## Automated tests

| Suite | How it runs | Result |
| --- | --- | --- |
| `test/reference_test.dart`, `test/import_test.dart` | Host. 12 tests: parser forms, false positives, invalid references, query parsing, book data checked against the bundled text, verse-of-the-day references, reading plans, VPL import parsing, search normalisation | **12/12 pass** |
| `integration_test/app_test.dart` (phase 1) | On the emulator, profile (AOT) build, started from cleared app data | **pass** |
| `integration_test/restart_test.dart` (phase 2) | Same device after `am force-stop`; a new process (PID 6741 → 7830) | **pass** |
| `integration_test/tour_test.dart` (Test H) | Visits every main screen and fails on any layout exception | **pass** in all 4 configurations |

UI steps in these tests use real taps at on-screen positions. A Scripture reference is tapped at the screen
position of its characters in the note editor.

## Acceptance scenarios

| Test | What was checked | Result |
| --- | --- | --- |
| A Offline reading | 31,098 verses and 1,189 chapters; every book's last chapter exists and the next does not; Genesis 1:1 and Revelation 22:21 text; Bible tab → Genesis → chapter 1 → next chapter through the UI | Pass |
| B Scripture preview | Test B note. Tapping each of John 3:16, Romans 8:28–30 and 1 Corinthians 13:4–7: the sheet's top edge is at y = 0; the reference is 8 dp below the status bar; the verse text starts 64 dp below the status bar; the sheet takes 72% of the usable height. Previous/next moves between references without closing. Back closes the sheet and keeps the note open | Pass |
| C Note persistence | 18,746-character sermon with headings, numbered lists, bullets, checklists, bold and italic; 20 edits; autosave; then a process kill and relaunch. The body text matches exactly after restart | Pass |
| D Editing continuity | Cursor in the middle of a note with unsaved inserted text; open a preview by tapping a reference; close it. The text, the cursor offset and the keyboard focus are all restored; autosave then stores the edit | Pass |
| E Search | Word (`shepherd`, 56 verses, includes Psalm 23:1); exact phrase (`Yahweh is my shepherd`); Old/New Testament and single-book filters; curly-quote text (`God’s love`); UI search for "still small voice" opens 1 Kings 19; typed reference offers "Open Romans 8:28" | Pass |
| F Saved content | Bookmark with comment, two highlighted verses, a range bookmark, and a bookmark made by tapping a verse and then "Bookmark". All are intact after restart, and searching by comment finds the bookmark | Pass |
| G Invalid references | `Psalm 151`, `John 3:99`, `Jude 2:1`, `Rom 8:30-28` and `Genesis 51` are flagged with a reason and never open a preview. Ordinary numbers, list points and `10:30` are ignored. 13 false-positive phrases are covered in unit tests | Pass |
| H Device usability | Phone portrait, light mode; phone dark mode at 130% text; tablet 1280×800 dp landscape at 130% text; phone landscape 914×411 dp at 115% text | Pass, after the fixes listed below |
| I Storage and performance | See measurements | Measured (see caveats) |
| J Data recovery | Export, change a note, add a note, then merge-restore: nothing is deleted, the changed note is kept and the backup version is added as a copy. Replace-restore matches the backup and writes a safety copy first. Non-backup files are rejected | Pass |

## System screens (verified on the emulator with the signed 1.0.1 release build)

These were driven through Android's own screens using UI automation over the accessibility tree.

| Flow | What happened | Result |
| --- | --- | --- |
| Back up | The system "save" picker opens in Downloads with a dated name; the saved `.json` parses and contains the note | Pass |
| Never overwrite silently | Choosing an existing backup's name makes Android ask "Overwrite …?"; cancelling leaves the file untouched (same size and time) | Pass |
| Restore | A note was deleted permanently (trash, then empty trash). Restoring via the system "open" picker showed the file's date and contents and Merge/Replace options; Merge brought the note back | Pass |
| Export note | "Export as Markdown" saved `Backup-test-sermon.md` with headings and bold intact | Pass |
| Share text | Android's share sheet opens with the note as plain text | Pass |
| Share verse image | The share sheet shows a thumbnail of the rendered verse card (proves the FileProvider grant works) | Pass |
| Install a translation | The public-domain KJV (`eng-kjv2006_vpl.txt`, 31,102 verses) was picked from Downloads; Install stays disabled until the rights box is ticked; installed in about 24 s offline; the reader then shows KJV text | Pass |
| Upgrade in place | Installing 1.0.1 over itself kept notes, the imported KJV and settings | Pass |
| Reminder permission | Switching the reminder on asks for notification permission. "Don't allow" leaves it off with no alarm; "Allow" turns it on | Pass |
| Reminder scheduling | Alarm registered for the chosen time with a 15-minute delivery window; changing the time to 7 PM moved it; turning it off removed it | Pass |
| Reminder notification | Firing the receiver posts the notification on the "Daily reading" channel and schedules the next day | Pass |
| Reminder after reboot | After a real reboot, the alarm was re-registered by the app's boot receiver (about 110 s after boot on this slow emulator) | Pass |

Also verified by accident: when the first launch was killed partway through building the search index, the next
launch discarded the temporary file and rebuilt it cleanly.

## Measurements

| Item | Value |
| --- | --- |
| Release APK 1.0.1, arm64-v8a (most phones) | **19,682,060 bytes (18.8 MiB)** |
| Release APK 1.0.1, armeabi-v7a | 17,033,928 bytes |
| Release APK 1.0.1, x86_64 | 21,125,498 bytes |
| App bundle (all ABIs; Play delivers one ABI per device) | 43,588,291 bytes |
| What makes up the arm64 APK | Flutter engine 11.3 MB (stored uncompressed so it is memory-mapped, not extracted); app code 5.4 MB; Bible database asset 2.4 MB; everything else under 1 MB |
| On-device Bible database (verses, search index, cross references) | 13,684,736 bytes |
| User database after the test run | 143,360 bytes |
| First-launch setup in release and profile builds (unpack, index, optimise) | 3.7 s at best, up to 10.8 s under load |
| Cold start in a release build (`am start -W`) | 7.5–8.6 s; system Settings app on the same emulator: 6.0–8.2 s |
| Loading Psalm 119 (176 verses), profile build | 25–248 ms |
| Search, profile build: word / exact phrase | 0.45–1.3 s / 0.1–0.5 s |
| Tapping a reference until the preview is fully on screen (260 ms animation) | 0.65–11 s, depending on emulator load |
| Memory (PSS) after a cold start | 74 MB |

## Defects found by testing and fixed

1. The verse count included the four verses the WEB omits on textual grounds (31,102 instead of 31,098).
2. Merge restore reported conflicting highlights as "added": Android returns −1, not 0, for an ignored insert.
3. First-launch setup took 21–27 s. It now ships a prebuilt database and builds the index natively: 3.7 s at best, for 0.66 MB more APK.
4. Search labels wrapped mid-word ("Bookmar / ks") at large font sizes.
5. Bottom sheets (reading settings and others) overflowed in landscape and at large font sizes; they now scroll.
6. The navigation rail overflowed on landscape phones; it switches to a compact, icon-only form on short screens.
7. The reader title said "Psalms 23" while the rest of the app said "Psalm 23".
8. The note editor re-analysed the whole note on every keystroke; analysis is now cached per line.
9. The reminder switch stayed "off" after permission was granted, although the reminder was set: the tile was a
   `const` widget that never rebuilt. The Home sections had the same flaw (verse of the day, continue reading, plan
   progress and recent items could go stale until you left the screen); they now listen for changes.
10. The reminder used an inexact daily repeating alarm, which Android may deliver up to 18 hours late. It now uses a
    15-minute window and schedules the next day each time it fires.
11. Counts read "1 notes", "1 changed notes"; wording is now singular or plural as appropriate.

## Not verified, or known limitations

- **Typing speed in very long notes.** On this emulator one edit to an 18.7k-character note took about 0.3–0.75 s in
  profile builds. The test harness also keeps the accessibility tree on, which adds work per frame. How fast this
  feels on a real mid-range phone has **not** been measured; it is the first thing to check on hardware.
- **No real phone was tested.** Everything above ran on an x86_64 emulator.
- The reminder notification was triggered by sending its broadcast directly; it was not left to fire at the scheduled
  time (Android delivers it within the 15-minute window).
- Installing a large translation takes about 24 s on the emulator; it uses the general import path, not the faster
  bundled-database path used for the WEB.
- No database encryption beyond Android's app sandbox and device encryption. The app says so in Privacy.
- No Bible dictionary or glossary: there is no bundled, clearly licensed source.
- Release 1.0.0 on GitHub is signed with the debug key; 1.0.1 and later are signed with the project's upload key (certificate `CN=Cue, O=Cue`, SHA-256 `c4197bc9…fe23f`).
