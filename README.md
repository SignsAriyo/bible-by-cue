# Bible by Cue

*Created by Cue.* A complete, private, fully offline Bible for Android with sermon notes and instant Scripture previews.

## What's inside

| Area | Implementation |
| --- | --- |
| Bible text | World English Bible (WEB), 2020 stable edition, public domain, 66 books / 1,189 chapters / 31,098 verses, unmodified |
| Cross references | OpenBible.info (CC BY), filtered to ≥ 5 votes, ≤ 12 per verse (94,658 links) |
| Storage | SQLite via `sqflite` (the platform's SQLite, nothing bundled). Scripture and user data live in separate database files |
| Bundled data | `assets/bible/web.db.gz` (2.4 MB): verses + cross references as a ready SQLite file, unpacked once on first launch |
| Search | SQLite FTS4 index (contentless), built on the device by one native SQL statement during first launch |
| Notes | Light Markdown stored as plain text, rendered live in the editor; Scripture references detected by a tokenizing parser and validated against the installed versification |
| Native services | One Kotlin method channel: share sheet, Storage Access Framework save/open, daily reminder (AlarmManager), so no extra plugins are needed |
| Permissions | `POST_NOTIFICATIONS` (only requested when the reminder is turned on) and `RECEIVE_BOOT_COMPLETED` (to restore the reminder). **No `INTERNET` permission in release builds.** |

## Layout

```
lib/core/books.dart            66-book metadata, verse id scheme (book*1e6 + chapter*1e3 + verse)
lib/core/reference.dart        reference tokenizer/parser, validation, query parsing
lib/core/bible_repository.dart translation databases: build, read, search, cross references, VPL import
lib/core/user_store.dart       notes, folders, bookmarks, highlights, history, plans, backup/restore
lib/core/content.dart          verse of the day, reading plans
lib/core/platform.dart         Dart side of the native bridge
lib/ui/…                       screens; note_text.dart (editor rendering), scripture_preview.dart (top sheet)
android/…/MainActivity.kt      share, document picker, reminder permission
android/…/Reminder.kt          daily reminder + boot receiver
tools/build_data.py            converts the upstream sources into tools/data/*.gz
tools/build_db.py              builds the bundled database assets/bible/web.db.gz from tools/data
test/                          parser, versification, plans (host)
integration_test/              on-device acceptance tests (phase 1 + restart phase 2)
```

## Rebuilding the Bible assets

```
curl -LO https://ebible.org/Scriptures/eng-web_vpl.zip && unzip eng-web_vpl.zip -d web
curl -LO https://a.openbible.info/data/cross-references.zip && unzip cross-references.zip -d xref
python tools/build_data.py web/eng-web_vpl.txt xref/cross_references.txt tools/data
python tools/build_db.py tools/data/web.txt.gz tools/data/xref.bin.gz assets/bible/web.db.gz
```

## Adding translations

Settings › Bible translations › *Install from file* accepts verse-per-line text (eBible.org `*_vpl.txt` format, or
`id<TAB>text`). Each translation becomes its own `bible_<code>.db`; bookmarks, highlights and note links use
verse ids, so they carry across translations. The app never downloads anything itself.

## Building and testing

```
flutter test                                              # host unit tests

# On-device acceptance tests. Use `flutter drive` with --keep-app-running: it does not uninstall
# the app afterwards, so phase 2 can check persistence after the process is killed.
adb shell pm clear com.cue.bible_by_cue
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart --keep-app-running --profile
adb shell am force-stop com.cue.bible_by_cue
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/restart_test.dart --keep-app-running --profile
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/tour_test.dart --dart-define=TOUR=phone

flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
```

Keep `build/symbols` for each release; it is needed to read crash stack traces from obfuscated builds.
See `docs/TEST_REPORT.md` for the latest results and measured sizes.

### Release signing

Release builds are signed with the upload key named in `android/key.properties` (git-ignored, never commit it):

```
storePassword=…
keyPassword=…
keyAlias=upload
storeFile=C:/path/to/upload-keystore.jks
```

Without that file, release builds fall back to the debug key so anyone can build the project. Keep the keystore and
its password backed up somewhere safe: every future update must be signed with the same key.

## Licence

The source code is released under the [MIT License](LICENSE). The bundled data keeps its own terms: the World
English Bible is public domain ("World English Bible" is a trademark of eBible.org, so a modified text must not use
that name), and the cross references come from OpenBible.info under CC BY, which requires credit.

## Privacy

No account, analytics, ads or network access. Android cloud backup is disabled for the app so notes never leave the
device unless the user exports them. Data is protected by the Android app sandbox and device encryption; the app does
not add its own database encryption.
