# Deztype

[![Download for Windows](https://img.shields.io/badge/Download-Windows-2ea44f?style=for-the-badge)](https://github.com/domrein/deztype/releases/latest/download/Deztype-windows-x86_64.zip)
[![Download for Mac](https://img.shields.io/badge/Download-macOS-2ea44f?style=for-the-badge)](https://github.com/domrein/deztype/releases/latest/download/Deztype-macos-universal.zip)
[![Download for Linux](https://img.shields.io/badge/Download-Linux-2ea44f?style=for-the-badge)](https://github.com/domrein/deztype/releases/latest/download/Deztype-linux-x86_64.zip)

The buttons download Deztype 0.0.1. On Mac, unzip and open Deztype. It is a universal app for macOS 13 and later, signed and notarized. On Windows, unzip and run Deztype.exe. On Linux, unzip, and run `./Deztype`. That build needs glibc 2.31 or newer and a display server.

Deztype is a Deseret-alphabet editor. Deseret is a phonemic alphabet, so the app types sounds rather than English spelling. The same Zig code builds a native window and a page you can host.

The caret moves with the keyboard. Clicking in the text does not place it. Copy copies the whole page.

## Ways to type

**Compose.** Type a sound and the letter appears when the sequence is complete. `th` is eth (𐑃). In the Respelling preset, `ee` is the vowel in *beet* and `ey` or `ai` is the vowel in *bait*. `a` then `y` is short a plus yee, not the vowel in *ice*; that sound is `ie`. A consonant that can still grow, such as `t` before `th`, waits. `\` commits the short letter, so `e\a` is short e and then short a. Shift capitalizes the next letter, including the first letter of a two-letter book-alphabet spelling.

The Keyman preset follows the names used by the SIL Keyman Deseret keyboard: `ee` is the vowel in *bait*, `oo` is the vowel in *coat*, and `uu` is the vowel in *boot*.

**Map.** Each key is one letter. Shift types the capital. Option (Alt) types that key's Latin character, so Option-1 is the digit. Two layouts:

- Mnemonic. Letter keys are the nearest English consonant or short vowel. Long vowels and the letters English spells with two characters sit on the digit row.
- Book of Mormon 1869. This is the frequency layout published by the Illinois Deseret Consortium for the 1869 Deseret Book of Mormon. Oi and ew were not in that book; they sit on the bracket keys.

**Translate.** Spell an English word. On a space or punctuation, Deztype looks it up in the CMU Pronouncing Dictionary and writes the Deseret. A word with more than one pronunciation is inserted with the first and listed above the text; click another to replace that word. An unknown word stays in Latin. An all-caps word comes out in capitals, and a capitalized word capitalizes the first letter.

Deseret has no schwa. Both the unstressed AH in *the* and the vowel in *strut* are written with short o (𐐲). The vowel in *bird* is short o plus er. In the 40-letter alphabet, Y followed by UW is the letter ew; in the 38-letter book alphabet it is yee plus long oo. Oi is one letter, or long ah plus short i in the book alphabet.

*Cot* and *caught* are one vowel for many speakers. The dictionary still lists a separate AO pronunciation for *caught*. "Merge cot and caught" writes that AO with long a. It does not change the AA pronunciation, which is already long a.

The 38-letter book alphabet applies when you type in Compose or Translate. Text already on the page is left as it is. The chart on the right still inserts oi and ew themselves.

## Build

Requires Zig 0.16.

```
zig build test
zig build run
```

`zig build test` covers the composer, the key maps, the translator, and the packed dictionary. It does not link SDL.

`zig build release` writes the desktop builds, the same shape as the Dez Games:

| Host | Artifacts |
| --- | --- |
| Mac | `zig-out/release/macos-universal/Deztype.app`, `zig-out/release/windows-x86_64/Deztype.exe`, and `zig-out/release/linux-x86_64/Deztype` |
| Linux | the Linux binary and the Windows exe |

The Mac app is universal (Apple Silicon and Intel) and its minimum system version is 13.0. The Windows file is a 64-bit GUI program. The Linux file is x86_64, built for glibc 2.31, and opens X11 or Wayland when it runs. SDL's Zig package vendors its libraries, so the Linux binary cross-compiles from a Mac.

Each of those folders includes `CMUdict.txt` and `OFL-Deseret.txt`. A published Mac build is Developer ID signed, notarized, and stapled. Rebuilds have to be signed again, because Zig leaves an ad-hoc signature. The Windows exe is Authenticode signed. Linux is unsigned.

The web app is the same program, compiled for the browser:

```
zig build web
zig build serve
```

`zig build web` writes `zig-out/web/` (`index.html`, `web.js`, and `deztype.wasm`). `zig build serve` builds that and serves it at http://127.0.0.1:8080.

## Dictionary

`src/data/cmudict.dzd` is the CMU Pronouncing Dictionary packed for a binary search. Words are lowercase and match `^[a-z][a-z']*$`. Variant numbers such as `(2)` are removed and kept as extra pronunciations of the same word. To rebuild it from a CMUdict file:

```
zig run --dep dict -Mpack=tools/pack_dict.zig -Mdict=src/dict.zig -- cmudict.dict src/data/cmudict.dzd
```

The packer refuses a phone it does not know.

## Fonts and licenses

Deseret letters are drawn with Noto Sans Deseret, which contains only the Deseret block. Latin text uses the interface font. The two are drawn as separate runs.

- Noto Sans Deseret is copyright 2022 The Noto Project Authors (https://github.com/notofonts/deseret) and is licensed under the SIL Open Font License 1.1. See `LICENSES/OFL-Deseret.txt`.
- The CMU Pronouncing Dictionary is copyright 1993–2015 Carnegie Mellon University. See `LICENSES/CMUdict.txt`. The packed file in this repository is derived from that dictionary.

## Later: system-wide typing

System-wide input is not part of this app. Do not write a macOS Input Method Kit extension for it. The sequence tables in `src/compose.zig` are the source of truth. When those sequences are settled, generate a Keyman keyboard (`.kmn`) from the same table so the composer can be installed on macOS, Windows, and Linux.

[Keyman Deseret 1.2](https://keyman.com/keyboards/deseret) from SIL already does a system-wide digraph keyboard and is MIT licensed. Its composition is invisible, which is the main thing this app is for: you can see the letter you are about to commit, and you can translate English. A macOS `.keylayout` file cannot turn `th` into 𐑃, because it maps one key to one character. A global hotkey around a web view is not the plan.
