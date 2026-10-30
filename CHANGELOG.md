# Changelog

All notable changes to this project will be documented in this file.

Reconstructed from this repository's git history: each release lists the
feature and fix commits it carried. Version bumps, screenshot additions
and CI syncs are left out.

## [1.3.0] - 2026-10-30

### Added
- "Daily Challenge" in the menu, right after "New game": today's puzzle at
  your size and difficulty, the same grid for everyone playing it today.
  Needs game-common 1.7.0.

## [1.2.0] - 2026-10-30

### Changed
- Redesigned play screen: the board is larger, filling the room the controls
  leave, with a full-width action bar under the status line and a single
  frame around the board.
- A domino is drawn as a bar joining the centres of its two cells, with a dot
  on each end. It used to be a bar along their shared edge, which read as a
  wall between the cells, the opposite of a domino.
- The rules describe this game. They used to describe a different puzzle
  (numbers 1 to N, 1×3 dominoes); they now explain the cross-joint rule and
  how to join, move and remove dominoes.
- The status line reads "6×6 · Medium · Dominoes: 4/18" and wraps in
  landscape instead of being cut off. The selected cell is shaded on the
  board, so the status no longer spells out "tap adjacent cell to connect".
- The title-bar menu shows "Difficulty: …" (was "Diff: …"), like every other
  game.
- Once the puzzle is solved (or revealed), the action bar shows "New game" in
  place of Undo/Clear/Reveal, so the next round no longer needs the menu.

### Fixed
- A given domino could be overwritten: selecting one of its cells and tapping
  a neighbour re-paired it, breaking the clue.
- The grid's right and bottom border lines were drawn past the board's edge.

## [1.1.15] - 2026-10-07

### Fixed
- The Tools menu entry is translated again. `main.lua` took `_` from
  KOReader's `gettext`, which knows nothing of this plugin's strings, so the
  menu label stayed English while the game's own screen, which goes through
  `i18n`, was translated. `_` now comes from `i18n` here too.


## [1.1.14] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.1.13] - 2026-08-05

### Added
- Add ES and DE translations

### Changed
- Add issue/PR templates and CONTRIBUTING.md

## [1.1.12] - 2026-08-04

### Changed
- Symlink common/ to shared game-common

## [1.1.10] - 2026-07-29

### Fixed
- Drop deprecated name field from _meta.lua

## [1.1.7] - 2026-07-28

### Changed
- Add GPL-3.0 LICENSE

## [1.1.4] - 2026-07-21

### Changed
- Correct README to describe the actual rule and controls

## [1.1.3] - 2026-07-21

### Added
- Own translations locally instead of via game-common

### Fixed
- Correct cross-junction rule, replace retry loop with constructive pinwheel generator

## [1.1.1] - 2026-07-15

### Added
- Adopt TitleBar header, sync common/ with game-common

### Changed
- Remove ../game-common/ fallback from package.path

## [1.1.0] - 2026-07-08

### Added
- I18n FR/EN translation + bump to 1.1.0
