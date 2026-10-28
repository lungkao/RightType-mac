# RightType for macOS (menu-bar app)

ภาพรวมและวิธีติดตั้งอยู่ใน [README หลัก](../README.md) · ☕ [Buy me a coffee](https://buymeacoffee.com/cheuachatchai)

พิมพ์ผิดภาษา แก้ให้เอง — เวอร์ชัน macOS แบบแอปเมนูบาร์

A macOS menu-bar port of [RightType](https://github.com/k-affan-th/RightType)
by **k-affan-th and the RightType contributors**.

## Credits

- **All correction logic is the original RightType Rust core** by
  [k-affan-th](https://github.com/k-affan-th/RightType) and contributors: the
  Thai ↔ English layout conversion, wrong-layout detection, dictionaries,
  Thai word segmentation and the common-misspelling list (`src/` and `assets/`
  at the repository root, unmodified). This port would not exist without it.
- Dictionaries and data keep their original licences; see
  [`THIRD_PARTY.md`](../THIRD_PARTY.md) and the font licence in `assets/fonts/`.
- What this port adds (the `macos/` directory only): a C-ABI wrapper
  (`ffi/`), a Swift menu-bar app (`App/main.swift`) that watches keystrokes
  and delivers fixes, an icon generator (`tools/make_icons.swift`) and the
  build/install scripts.

Licensed under **MIT OR Apache-2.0**, the same as upstream; see
[`LICENSE-MIT`](../LICENSE-MIT) and [`LICENSE-APACHE`](../LICENSE-APACHE).

## Use

| Action | How |
|---|---|
| Fix the last word | `⇧⌫` (press again to undo) |
| Fix selected text | `⌃⌥Space` |
| Modes | menu **Aก** → Manual / Suggest (hint, press `Tab`) / Auto |
| Thai spelling hints | menu **Aก** → แก้คำไทยสะกดผิด |
| Start at login | menu **Aก** → เปิดอัตโนมัติตอนเข้าเครื่อง |

Grant **Accessibility** (and Input Monitoring if asked) in System Settings →
Privacy & Security on first launch.

## Build

Needs Rust and the Xcode command-line tools.

```bash
macos/build.sh      # builds macos/build/RightType.app
macos/install.sh    # builds, copies to /Applications and launches
```

Not notarized: on another Mac, right-click the app → Open the first time.

## Not ported yet

Settings window, per-app modes, command palette, multi-word undo, practice
and stats screens (the Windows app has these).
