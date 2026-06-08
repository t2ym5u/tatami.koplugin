# Tatami

> **Status: stub — not yet implemented**

## Description

Fill the grid with 1×2 dominoes so no two dominoes of the same orientation are adjacent and every 2×2 square is covered.

## Files to create

- `board.lua` — game logic, puzzle generator, serialize/load
- `board_widget.lua` — grid rendering and tap gestures
- `screen.lua` — full-screen layout (buttons + board)
- `main.lua` — PluginBase entry point

## Notes

Grid-based logic puzzle — use GridWidgetBase from game-common.
