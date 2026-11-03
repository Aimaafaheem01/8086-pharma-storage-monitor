# Code Guide (for the report and viva)

## Data
- Constants (EQU): SAFE_LOW 2, SAFE_HIGH 8, CRIT_HIGH 12, CRIT_LOW -2, CRIT_MIN 10, LOG_SIZE 32, REC_SIZE 6.
- Log record (6 bytes): byte0 code, byte1 priority, bytes2-3 time, byte4 temperature, byte5 checksum (XOR of bytes 0-4).
- `logSeq` keeps an age stamp per record so the "oldest" record can be found even when several events happen in the same minute.

## Procedures
| Procedure | Input -> Output |
|---|---|
| READ_INPUT | waits for key -> AL = U D P T 1 2 3 Q C (upper case); unknown keys ignored |
| UPDATE_TEMP | power OFF: temp +1; power ON: temp moves 1 toward 5 |
| ADJUST_TEMP | AL = +1/-1 -> changes temp only inside -20..40 (input validation) |
| TOGGLE_POWER | flips power, logs event 03 or 04 |
| UPDATE_STATE | AL = 1 if a minute passed -> duration counters, state, alarm flag, events 01/02/05 |
| CALC_RATE | change over last 3 ticks -> minutes to breach = ceil((8-temp)*3 / change); event 06 when it first appears |
| CALC_SCORE | adds degrees outside 2..8 to the 16-bit exposure score (saturates at 65535) |
| DO_TICK | one simulated minute: UPDATE_TEMP, clock+1, UPDATE_STATE, CALC_RATE, CALC_SCORE |
| CHECKSUM | SI = record -> AL = XOR of first 5 bytes |
| FIND_VICTIM | log full -> slot of the oldest record with the lowest priority; critical only if all are critical (sets overflow flag) |
| LOG_EVENT | AL code, AH priority, DL temp -> writes a record (only procedure that writes the log, bounds-checked) |
| SHOW_LOG | prints all records, "CHECKSUM ERROR" for altered ones |
| ACK | asks 4-digit PIN, compares all 4 digits, logs event 07, never deletes records |
| PRINT_NUM / PRINT_NUM2 / PRINT_SIGNED / PRINT_STR | printing helpers (16-bit unsigned / 2 digits / signed byte / string) |
| SHOW_STATUS | prints the status screen |
| MAIN | read key, act, redraw status |

## Design decisions worth explaining
- Prediction only when temperature is rising and between 2 and 7 C; division happens only when the change is > 0 (no divide-by-zero).
- Manual U/D/P keys clear the prediction because they break the trend; time-based counters change only on `T`.
- When the log is full of critical records the overflow event (08) is stored first, then the new event; both overwrite the oldest critical records.
- Key `C` is an extra test hook (not in the proposal) so the tampering test can be shown without editing emulator memory.
