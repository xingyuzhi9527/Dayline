# Dayline Real Device Smoke QA Report

Date: 2026-05-09
Device: V2154A, Android 14 API 34, serial `3432033034001K3`
App package: `com.example.dayline_app`
Build: debug APK, `versionName=0.1.0`, `versionCode=1`
Artifact directory: `docs/qa/2026-05-09-device-smoke`

## Scope

Tested the currently routed mobile sections on a real Android device:

- `记`: flash record, voice fallback/test record, text input save, todo memory panel.
- `线`: timeline list, saved record visibility, edit sheet entry.
- `盘`: dashboard summaries, tracker/todo sync.
- Header buttons: menu and settings tap behavior.

Also ran local verification:

- `flutter analyze`: passed.
- `flutter test`: 137 tests passed.
- `flutter build apk --debug`: passed.
- `final_crash_buffer.txt`: empty.

## Environment Notes

- Device system time is `Mon May 27 07:33:37 CST 2024`.
- Automatic time and time zone are disabled: `auto_time=0`, `auto_time_zone=0`.
- This differs from the QA date `2026-05-09`, so "today" data in the app is filed under the device date, not the desktop/session date.

## Result Summary

Overall smoke result: pass with issues.

Core data flow works:

- App installs and launches.
- Voice/test-mode record can be generated, confirmed, and saved.
- Saved tracker appears in timeline and dashboard.
- Text-created todo appears in the record panel, timeline/dashboard, and can be completed.
- Timeline edit sheet opens for a saved tracker.
- No app crash was observed.

## Issues

### P1 - Real-device speech recognition unavailable

Evidence:

- Screenshot: `01_launch_record.png`
- Logs: `final_app_logcat.txt`
- Log line: `SpeechToTextPlugin: Speech recognition not available on this device`

Observed:

- On a real V2154A Android 14 device, the record page shows `模拟器语音不可用 · 使用测试模式`.
- Tapping the mic generates a mock/test record rather than using real speech.
- `RECORD_AUDIO` permission is granted for the active user according to `package_summary.txt`.

Impact:

- The main voice-recording experience cannot be validated as real speech input on this device.
- Users may receive emulator wording on an actual phone.

### P2 - Dashboard summary cards overflow vertically

Evidence:

- Screenshots: `05_dashboard_after_save.png`, `10_dashboard_final.png`

Observed:

- The four dashboard metric cards show Flutter overflow warnings:
  `BOTTOM OVERFLOWED BY 0.645 PIXELS`.
- Affected cards include `待办进度`, `专注时长`, `当前心情`, and `能量消耗`.

Impact:

- User-visible debug overflow stripes appear in debug builds.
- Layout is very close to clipping and may be fragile across font scale, display size, or release rendering differences.

### P2 - Menu and settings buttons have no visible behavior

Evidence:

- UI dumps: `11_menu_tap_ui.xml`, `12_settings_tap_ui.xml`

Observed:

- Tapping the hamburger menu does not open a drawer, sheet, menu, or navigation destination.
- Tapping settings does not open a settings screen, sheet, or route.
- UI tree remained unchanged after each tap.

Impact:

- Header controls look actionable but behave like placeholders.

### P3 - Test text injection is affected by system input method

Evidence:

- Screenshots: `07_record_todo_panel.png`, `10_dashboard_final.png`

Observed:

- ADB input text `todo buy_milk` was entered through the real device input stack and appeared as `不要——milk`.
- The app still classified it as a todo and saved it.

Impact:

- This is likely a QA input-method artifact rather than an app parser defect.
- Future text-input QA should use a controlled keyboard/IME or paste mechanism before judging exact text preservation.

## Verified Flows

### Record Section

- Initial screen renders with title, mic/test mode, todo panel entry, text input, and bottom navigation.
- Mic tap creates mock recognized text: `聚会 跟老同学吃饭`.
- Confirm card appears with parsed type `打卡`, content `聚会`, tag `社交`.
- Save succeeds and returns to record screen.
- Text todo save succeeds; todo panel count updates from empty to `1 个待办事项`.
- Todo memory panel opens with daily and todo columns.
- Tapping todo card toggles status to `已完成`.

### Timeline Section

- Saved tracker appears as `打卡 / 聚会`.
- Saved todo appears as a second timeline item.
- Timeline count updates to `2 条记录`.
- Edit sheet opens for a tracker item with editable fields and save/cancel actions.

### Dashboard Section

- Saved tracker appears in `今日打卡`.
- Todo progress updates from `0/0` to `1/1` after completion.
- Completed todo appears in `今日待办`.
- Dashboard remains scrollable and does not crash.

## Artifacts

Key screenshots:

- `01_launch_record.png`
- `03_record_confirm_card.png`
- `04_timeline_after_save.png`
- `05_dashboard_after_save.png`
- `07_record_todo_panel.png`
- `08_record_todo_panel_complete.png`
- `09_timeline_edit_sheet.png`
- `10_dashboard_final.png`

Key logs:

- `final_app_logcat.txt`
- `final_crash_buffer.txt`
- `package_summary.txt`
- `flutter_analyze.txt`
- `flutter_test.txt`
- `flutter_build_apk_debug.txt`

## Not Covered

- Real speech recognition, because the plugin/device reported speech recognition unavailable.
- Export buttons or downstream export files; visible export controls are below the first dashboard viewport and were not exercised in this smoke pass.
- Long-session performance and memory behavior.
- Different display sizes, font scales, landscape orientation, or release APK.

