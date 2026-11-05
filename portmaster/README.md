## Notes

Thanks to [amiralul](https://github.com/ctanas/musudoku) for creating muSudoku, a Sudoku game whose puzzles are generated on the device and graded by the techniques a person needs to solve them. It also has two more logic puzzles: Solo (shade cells so no number repeats) and Pairlink (join matching numbers with lines). Switch games with L1 / R1 on the title screen.

Puzzle packs (text files of puzzles) go in `ports/musudoku/packs/`. A starter pack is included.

## Controls

| Button | Action |
|--|--|
| D-pad / Left stick | Move |
| A | Open the number pad, place a number |
| B | Erase, close |
| X | Switch pen and pencil |
| Y | Hint (turn on in Settings) |
| L1 / R1 | Previous / next empty cell, or change the number with Number-first input |
| L2 | Undo |
| R2 | Redo |
| Select | Fill or clear all notes |
| Start | Pause menu |
| Menu + Start | Save and quit |

L1 / R1 and L2 / R2 can be swapped in Settings → Shoulder buttons.

Solo: A shades a cell (it turns black), X marks it to keep, B clears it, holding Y shows the numbers under shaded cells, L2 / R2 undo and redo.

Pairlink: A on a number (or a line) starts drawing, the D-pad draws, stepping back along the line takes steps back, and reaching the other number links the pair. A stops drawing, B erases the line under the cursor, L1 / R1 jump to the next unlinked pair, L2 / R2 undo and redo.
