# In-Class Activity 09 — Local Storage Part II

Blake Cantave • Undergraduate • October 12, 2026

This continues the October 7 Part I Flutter project. The README remains the default Flutter template; assignment documentation and the rubric map are collected here.

## Build and run

Tested with Flutter 3.47.3, Dart 3.13.3, Android 17 / API 37.1 ARM64 on Pixel 10 Pro XL emulators. Application ID: `com.example.local_storage_lab`.

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d DEVICE_ID
flutter build apk --release
```

The recorded analyzer/test runs used `--suppress-analytics` and `--no-pub` after dependency resolution. On this Mac, builds used Android Studio's bundled JDK through `JAVA_HOME=/Applications/Android Studio.app/Contents/jbr/Contents/Home`. Gradle daemon reuse is disabled in `android/gradle.properties`.

`flutter analyze` passed with no issues (`evidence/analysis_output.txt`). The four existing guest widget tests passed (`evidence/widget_test_output.txt`). `tools/verify_schema.py` also checks the extracted SQL on host SQLite; its fixture data is supplemental, not Android evidence.

## Schema and behavior

The same documents-directory `MyDatabase.db` advances from version 1 to 2. Existing `my_table(_id, name, age)` and guest CRUD are preserved. The original helper is in `part_one_source/database_helper.dart.txt`. `onCreate` creates both schemas; `onUpgrade`, gated by `oldVersion < 2`, adds only folders, cards, and the index. There is no launch-time seeding, database replacement, or guest-table drop. sqflite already wraps these callbacks in transactions; each operation is awaited without a nested transaction.

`folders` stores integer ID, unique nonblank name, and ISO-8601 UTC creation time. `cards` stores integer ID, title, suit, notes, nullable image reference, and `folder_id`. `onConfigure` enables foreign keys. The foreign key points to `folders.id` with `ON DELETE CASCADE`, and `idx_cards_folder_id` supports the folder filter.

Typed models convert maps at the repository boundary. Reads filter with bound folder IDs; edits and deletes use bound row IDs. The UI supports folder counts, empty folders, reused Add/Edit forms, cancel feedback, trimmed validation, duplicate-name feedback, named deletion confirmations, busy controls, and read-error retry. A failed read does not retry an insert. Failed writes retain form input.

## Images and deletion

The chosen approach stores a nullable bundled-asset reference. `assets/card_back.png` is registered in pubspec.yaml. Bundling works offline and keeps image bytes out of SQLite, but adds APK size and requires a new build to change artwork. A null, blank, malformed, unsupported, or unavailable reference displays a suit symbol. This implementation supports bundled assets; URL/private-file references fall back rather than being fetched. The null-reference path was exercised on both devices; missing-file/network faults were not induced.

Cards belong to their folder, so confirming a folder deletion cascades its cards. Independently valuable children would call for restriction, reassignment, or archival. A clinic could archive patients while retaining restrictive parent relationships for billing/audit records, instead of silently cascading those records.

## Targets and upgrade evidence

- Original Part I installation: `emulator-5554`, Pixel_10_Pro_XL. Version 2 debug APK installed with `adb install -r`; no uninstall or clear-storage action.
- Separate fresh/release target: `emulator-5556`, Activity09_Fresh, same API/architecture. The exact final release APK was installed here.
- UI actions and screenshots were collected using ADB. The app's read-only **Database evidence** screen reads the same connection used for CRUD.

Before upgrade, version 1 held exactly these guest rows. Every original-target snapshot after upgrade contains the same rows and values:

| Guest ID | Name | Age |
| --- | --- | --- |
| 2 | River | 35 |
| 3 | Acorn | 0 |
| 4 | Oak | 130 |

`T1_before.png` was captured before version 2 installation. `T1_before_database.json` records version 1 and the three guests. `T1a_diagnostics.json` records version 2, foreign_keys = 1, cards.folder_id → folders.id with CASCADE, and idx_cards_folder_id. The fresh target's `T1b_release_diagnostics.json` records the same version/FK/index, with zero guests, folders, and cards. The guest query succeeds there, confirming the original table exists.

## T1–T6 results

All evidence paths below are relative to `evidence/`. Tests were performed in order on the original installation, except T1b, which used the separate fresh target.

| Test | Action and expected behavior | Observed result | Result |
| --- | --- | --- | --- |
| T1a | Upgrade existing v1 installation; retain every guest value and add schema | Guests 2/River/35, 3/Acorn/0, 4/Oak/130 retained; version 2, FK=1, CASCADE and index present. `T1a_diagnostics.json` | PASS |
| T1b | Fresh v2 creates both schemas; empty folder opens | Fresh guest/catalogue queries returned zero rows. Release Lab insert returned folder ID 1; opened with zero cards. `T1b_release_diagnostics.json`, `T1b_empty_folder.png` | PASS |
| T2 | Create Atlas/Harbor, two Compass in Atlas, Signal in Harbor; counts 2/1 | Folder inserts returned Atlas 1 and Harbor 2. Card inserts returned Compass 1, Compass 2, Signal 3. All Hearts, image_ref null. Signal notes Harbor beacon. Correct filtered lists and counts 2/1. `T2_database.json`, `T2_cards.png`, `T2_folders.png`, `T2_Harbor.png` | PASS |
| T3 save | Edit one Compass by ID; exactly one row changes | ID 1 became Compass revised, notes Route checked; affected rows 1. ID 2 remained Compass with empty notes. | PASS |
| T3 cancel | Change second Compass form then Cancel; no write | Canceled title was not saved; ID 2 remained Compass, notes empty. Counts 2/1. `T3_before_restart.json` | PASS |
| T4 | Force stop and relaunch same installation; all values persist | Full before/after diagnostic JSON matches exactly. Same three guests, folders 1/2, cards 1/2/3, counts 2/1. `T4_after_restart.json`, `T4_after.png` | PASS |
| T5 card cancel | Cancel deletion of ID 1; unchanged | `T5_card_cancel.json` equals T4 snapshot. | PASS |
| T5 card confirm | Delete ID 1; one affected row, Atlas count 1 | Affected rows 1; ID 2 remained in Atlas; Signal 3 remained in Harbor. `T5_card_deleted.json` | PASS |
| T5 folder cancel | Cancel deleting Atlas; unchanged | `T5_folder_cancel.json` equals card-deleted snapshot. | PASS |
| T5 folder confirm | Delete Atlas; one parent affected, remaining child cascades | Parent affected rows 1. Folder 1 and card 2 disappeared. Harbor 2 and Signal 3 remained; no card references folder 1. `T5_folder_deleted.json` | PASS |
| T6 fallback | Open Signal with null image_ref; keep card data visible | Hearts fallback, Signal ID 3, notes Harbor beacon, folder 2 visible. `T6_fallback.png` | PASS |
| T6 title | Add a whitespace-only title; visible error, no insert | “Enter a nonblank title.” displayed; form stayed open. `T6_blank_title.png` | PASS |
| T6 blank folder | Create a folder with an empty name; visible error, no insert | “Enter a nonblank folder name.” displayed. `T6_blank_folder.png` | PASS |
| T6 duplicate | Create Harbor again; duplicate feedback, no insert | “That folder name already exists. Choose another name.” displayed and input retained. `T6_duplicate_folder.png` | PASS |

After all three rejected attempts, `T6_after_validation.json` exactly equals `T5_folder_deleted.json`: one folder (Harbor 2), one card (Signal 3), and all three original guests. No invalid write returned an insert ID.

## Pre-restart values and exact T4 procedure

Atlas ID 1 was created at `2026-10-12T23:10:22.576347Z`; Harbor ID 2 at `2026-10-12T23:10:48.868454Z`.

| Card ID | Title | Suit | Notes | image_ref | folder_id |
| --- | --- | --- | --- | --- | --- |
| 1 | Compass revised | Hearts | Route checked | null | 1 |
| 2 | Compass | Hearts | empty string | null | 1 |
| 3 | Signal | Hearts | Harbor beacon | null | 2 |

There was no attached `flutter run` debugging session. On emulator-5554, ADB opened system App info using `android.settings.APPLICATION_DETAILS_SETTINGS` for the package. **Force stop** and **OK** were selected, then `pidof` confirmed the process was absent. The same installation was relaunched with `am start -n com.example.local_storage_lab/.MainActivity`. PID changed from 12644 to 14638. No clear storage, reinstall, hot reload, or hot restart was used. All rows above, folder counts 2/1, folder timestamps, and the three guest rows matched exactly after restart.

## Exact release APK verification

Build command: `flutter --suppress-analytics build apk --release --no-pub`, with the bundled JDK noted above. Build succeeded; `evidence/release_build_output.txt` contains the output. Java native-access warnings appeared but did not prevent the successful build. Machine-specific path prefixes in logs are shortened to `<project>` and `<user>`.

Final file: `Activity09_Cantave_Blake.apk`, 50,266,874 bytes.
SHA-256: `d189b78428f37de0f90e0b54451cf95db64155a28c35cc5ad41a53c4e458ba40`.

The exact copied APK was installed on emulator-5556; the installed package did not have the DEBUGGABLE flag. Release Lab folder insert returned ID 1. Release Signal card insert returned ID 1, Hearts, null image. An edit was corrected to title Release revised and notes Smoke test notes; save returned one affected row. The Hearts fallback and stored values were visible. ADB `am force-stop` followed by `am start` preserved the rows exactly (`release_before_restart.json` = `release_after_restart.json`, screenshot `release_restart.png`). Confirmed card deletion returned one affected row and left the folder at count zero (`release_after_delete.json`). Confirmed folder deletion returned one affected row and left zero folders/cards (`release_final.json`). PASS.

## Rubric map and limits

| Requirement | Source or evidence |
| --- | --- |
| Versioned schema and guest preservation | lib/database_helper.dart; part_one_source/database_helper.dart.txt; T1 snapshots |
| Models, repository, binding and identity | lib/catalogue_models.dart; lib/database_helper.dart; T2/T3 snapshots |
| CRUD, counts, validation and confirmations | lib/catalogue_screen.dart; T2/T3/T5/T6 results |
| Image choice and fallback | CardArtwork; assets/card_back.png; T6_fallback.png |
| Cold persistence | T3_before_restart.json; T4_after_restart.json; T4_after.png |
| Analyzer and installed release | analysis_output.txt; release_build_output.txt; release snapshots |
| Undergraduate reflection | Separate Cantave_Blake_CriticalThinking.docx, prompts 1–3 and U1/U2 |

The UI was tested on Android emulators, not iOS or physical hardware. Read failure, unavailable network images, and every malformed asset variant were not injected. The optional falsification checks in the reflection are proposed tests, not completed results. No iCollege upload or submission was performed.

Assignment reference: https://codd.cs.gsu.edu/~lhenry23/mad/ica/act09/v2/index2.html
