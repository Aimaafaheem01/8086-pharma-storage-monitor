# Test Scenarios (keys to press and expected output)

Start every test from a fresh run (temperature 5 C, power ON). Status block shows: Time, Temperature, Power,
State, Minutes out range, Exposure score, Breach prediction, Alarm, Log records.

| # | Scenario | Keys to press | Expected result |
|---|---|---|---|
| 1 | Normal operation | `T T T T` then `2` | Temp stays 5 C, State NORMAL, Exposure 0, "Log is empty." |
| 2 | Door-open blip | `U` x6, then `T T T` | After the U keys: 11 C, WARNING, alarm ACTIVE. After T1: 10 C, out 1 min. After T2: 9 C, out 2 min, still WARNING (never CRITICAL). After T3: 8 C, State NORMAL, exposure score 3. Log (key 2) has only event 01 TEMP HIGH |
| 3 | Power failure | `P`, then `T` x11 | T1: 6 C, prediction 6 min. T2: 7 C, prediction 2 min. T3: 8 C, prediction gone. T4: 9 C, WARNING. T7: 12 C, CRITICAL. T11: 16 C, exposure 36. Log (key 2): 03 POWER FAILURE, 06 BREACH PREDICTED, 01 TEMP HIGH, 05 STATE CRITICAL |
| 4 | Log overflow | `U` x7 (makes a critical event), then `P` x40, then `2` | "Log records 32 / 32". The 05 STATE CRITICAL record is still in the log; the oldest LOW / MEDIUM power records were overwritten first |
| 5 | Tampering check | `U U U U`, `C`, then `2` | "[TEST] Log record 1 was corrupted." and the log row shows **CHECKSUM ERROR** |
| 6 | Wrong PIN | `U` x6, `3`, `9 9 9 9`, then `3`, `1 2 3 4`, then `2` | First try: "WRONG PIN - acknowledgement rejected." (nothing changes). Second try: "PIN accepted", log gets event 07 ALARM ACKNOWLEDGED. No record is ever deleted |

## Extra checks
| Check | Keys | Expected |
|---|---|---|
| Power-off rule | `P`, then `D T` repeated 11 times | Temp stays 5 C but after 10 minutes without power State becomes CRITICAL |
| Low-temperature rule | `D` x8, then `T` | Temp reaches -2 C, State CRITICAL, event 02 TEMP LOW and 05 logged |
| Unknown keys | `x y z ! ?` | Ignored, nothing happens |
| All-critical overflow | (log full of critical records) then any event | OVERFLOW FLAG SET, event 08 logged, oldest critical records overwritten |
| Wrong key in PIN | letters while entering the PIN | Ignored; only digits count; ESC cancels |

Write your own results (PASS/FAIL + screenshot name) in the report after running them in EMU8086.
