# 8086 Assembly-Based Pharmaceutical Storage Monitor (COAL Project)

Console prototype of the firmware logic of a medicine-fridge temperature monitor, written in 8086 assembly
(only INT 21h and INT 16h). It classifies the storage as NORMAL / WARNING / CRITICAL, counts minutes out of range,
predicts a breach, computes an exposure score and keeps a checksum-protected, priority-preserving event log
(32 records x 6 bytes = 192 bytes). Acknowledging an alarm needs the PIN **1234**.

## Folder layout
```
Pharma_Monitor_8086/
  src/pharma_monitor.asm     <- the complete source code (every line commented)
  build/pharma_monitor.exe   <- ready-made EXE (runs in DOSBox)
  docs/TEST_SCENARIOS.md     <- 6 test scenarios with exact keys and expected screen output
  docs/CODE_GUIDE.md         <- what every procedure does (use it for the report and viva)
  screenshots/               <- put your test screenshots here
```

## Keys
| Key | Action |
|---|---|
| U / D | temperature +1 / -1 |
| P | power ON/OFF (logs event 03 / 04) |
| T | advance one simulated minute |
| 1 | show status |
| 2 | show event log |
| 3 | acknowledge alarm (PIN 1234, ESC cancels) |
| C | TEST HOOK: corrupts one log byte (only for Test Scenario 5) |
| Q | quit |

Upper or lower case both work. Any other key is ignored.

## How to run

### Option A - EMU8086 (the course tool, recommended)
1. Open VS Code and use **File > Open Folder** to open `Pharma_Monitor_8086` (VS Code is just your editor/Git tool).
2. Open **EMU8086**, then **File > Open** and choose `src/pharma_monitor.asm`.
3. Click **Emulate**, then **Run**. Click inside the "emulator screen" window and press the keys.

### Option B - run inside VS Code (needs DOSBox)
1. Install **DOSBox** and, in VS Code, the extension **MASM/TASM** (author xsro). VS Code will suggest it automatically.
2. Open `src/pharma_monitor.asm`, right-click and choose **Run ASM code** (or press the extension's run button).
   DOSBox opens and runs the program. Menu names can differ slightly between extension versions.

### Option C - just run the EXE in DOSBox
```
mount c C:\path\to\Pharma_Monitor_8086\build
c:
pharma_monitor.exe
```

## Note about testing
The program was assembled with JWasm (MASM compatible, 0 errors, 0 warnings) and every scenario in
`docs/TEST_SCENARIOS.md` was run on an 8086 emulator. It was not run inside EMU8086 itself, so run all 6
scenarios in EMU8086 on your own PC and take your own screenshots before you write results in the report.
