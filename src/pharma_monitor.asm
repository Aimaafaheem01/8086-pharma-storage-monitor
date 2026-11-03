; ==========================================================================
; PROJECT : 8086 Assembly-Based Pharmaceutical Storage Temperature Monitor
; COURSE  : COAL (Computer Organization and Assembly Language)
; ASSEMBLER: EMU8086 (also assembles with MASM/TASM/JWasm in DOSBox)
; I/O     : only INT 21h (screen) and INT 16h (keyboard)
; KEYS    : U temp+1 | D temp-1 | P power on/off | T advance 1 minute
;           1 status | 2 log | 3 acknowledge (PIN) | Q quit
;           C = TEST HOOK (corrupts one log byte, used for Test Scenario 5)
; ==========================================================================

.MODEL SMALL                          ; small memory model: 1 code + 1 data segment
.STACK 100h                           ; reserve 256 bytes of stack

.DATA                                 ; ---------------- DATA SEGMENT ----------------

; ---------- named constants (change thresholds here only) ----------
SAFE_LOW    EQU 2                     ; lowest safe temperature in degrees C
SAFE_HIGH   EQU 8                     ; highest safe temperature in degrees C
CRIT_HIGH   EQU 12                    ; at or above this temperature = CRITICAL
CRIT_LOW    EQU -2                    ; at or below this temperature = CRITICAL
CRIT_MIN    EQU 10                    ; 10 minutes out of range / power off = CRITICAL
NORMAL_TEMP EQU 5                     ; temperature the fridge drifts back to
TEMP_MIN    EQU -20                   ; simulator lower limit (keeps byte in range)
TEMP_MAX    EQU 40                    ; simulator upper limit
LOG_SIZE    EQU 32                    ; number of records in the event log
REC_SIZE    EQU 6                     ; bytes per record
PIN_LEN     EQU 4                     ; PIN length in digits
ST_NORMAL   EQU 0                     ; state code: NORMAL
ST_WARNING  EQU 1                     ; state code: WARNING
ST_CRIT     EQU 2                     ; state code: CRITICAL
PRI_LOW     EQU 0                     ; priority: low
PRI_MED     EQU 1                     ; priority: medium
PRI_CRIT    EQU 2                     ; priority: critical
EV_HIGH     EQU 1                     ; event 01 temperature high
EV_LOW      EQU 2                     ; event 02 temperature low
EV_PWRFAIL  EQU 3                     ; event 03 power failure
EV_PWRBACK  EQU 4                     ; event 04 power restored
EV_CRITICAL EQU 5                     ; event 05 state changed to CRITICAL
EV_PREDICT  EQU 6                     ; event 06 breach predicted
EV_ACK      EQU 7                     ; event 07 alarm acknowledged
EV_OVERFLOW EQU 8                     ; event 08 log overflow

; ---------- simulation variables ----------
temp        DB NORMAL_TEMP            ; current temperature (signed byte)
power       DB 1                      ; power status: 1 = ON, 0 = OFF
state       DB ST_NORMAL              ; current state (0,1,2)
outMin      DW 0                      ; minutes the temperature has been out of range
pwrOffMin   DW 0                      ; minutes the power has been off
clock       DW 0                      ; simulated time in minutes
score       DW 0                      ; exposure score (degrees out of range x minutes)
prevOut     DB 0                      ; was the temperature out of range last time?
tickFlag    DB 0                      ; 1 = a minute passed during this update
alarmActive DB 0                      ; 1 = unacknowledged alarm exists
hist0       DB NORMAL_TEMP            ; temperature 3 ticks ago (oldest)
hist1       DB NORMAL_TEMP            ; temperature 2 ticks ago
hist2       DB NORMAL_TEMP            ; temperature 1 tick ago
predValid   DB 0                      ; 1 = a breach prediction exists
prevPred    DB 0                      ; previous value of predValid
predMin     DW 0                      ; predicted minutes until breach

; ---------- event log (192 bytes) ----------
logBuf      DB 192 DUP(0)             ; 32 records x 6 bytes: code,priority,time(2),temp,checksum
logSeq      DW 32 DUP(0)              ; age stamp of every record (to find the oldest)
seqCounter  DW 0                      ; next age stamp to hand out
logCount    DB 0                      ; number of records used (0..32)
overflowFlg DB 0                      ; 1 = log overflowed with all-critical records

; ---------- scratch variables used by the log procedures ----------
evCode      DB 0                      ; event code being logged
evPri       DB 0                      ; event priority being logged
evTemp      DB 0                      ; event temperature being logged
slotIdx     DB 0                      ; record slot chosen for the new event
newOverflow DB 0                      ; 1 = overflow flag was just set
bestIdx     DB 0                      ; best victim slot while searching
bestSeq     DW 0                      ; age stamp of the best victim

; ---------- security ----------
pinStored   DB '1','2','3','4'        ; correct 4-digit PIN
wrongFlag   DB 0                      ; 1 = a wrong digit was typed

; ---------- text messages ($ ends each string for INT 21h/09h) ----------
msgBanner   DB 13,10,'=== 8086 PHARMACEUTICAL STORAGE MONITOR ===',13,10
            DB 'U=temp+1 D=temp-1 P=power T=+1 min 1=status 2=log 3=ack C=test Q=quit',13,10,'$'
msgLine     DB '------------------------------------------',13,10,'$'
msgTime     DB 'Time (minutes)    : $'
msgTemp     DB 'Temperature       : $'
msgDegC     DB ' C',13,10,'$'
msgPower    DB 'Power             : $'
msgOn       DB 'ON',13,10,'$'
msgOff      DB 'OFF',13,10,'$'
msgState    DB 'State             : $'
msgNormal   DB 'NORMAL',13,10,'$'
msgWarning  DB 'WARNING',13,10,'$'
msgCritical DB 'CRITICAL',13,10,'$'
msgOutMin   DB 'Minutes out range : $'
msgScore    DB 'Exposure score    : $'
msgPred     DB 'Breach prediction : $'
msgNone     DB 'none',13,10,'$'
msgMin      DB ' min',13,10,'$'
msgAlarm    DB 'Alarm             : $'
msgAlNone   DB 'none',13,10,'$'
msgAlAct    DB 'ACTIVE (press 3 to acknowledge)',13,10,'$'
msgAlAck    DB 'ACKNOWLEDGED',13,10,'$'
msgLogInfo  DB 'Log records       : $'
msgOfString DB ' / 32$'
msgOvf      DB '  [OVERFLOW FLAG SET]$'
msgCrLf     DB 13,10,'$'
msgLogHdr   DB 13,10,'------------- EVENT LOG -------------',13,10,'$'
msgLogEmpty DB 'Log is empty.',13,10,'$'
msgSlot     DB 'Slot $'
msgCode     DB ' | Code $'
msgSep      DB ' | $'
msgPri      DB ' | Pri $'
msgLTime    DB ' | Time $'
msgLTemp    DB ' | Temp $'
msgOk       DB ' | OK',13,10,'$'
msgBad      DB ' | CHECKSUM ERROR',13,10,'$'
msgPinAsk   DB 'Enter 4-digit PIN (ESC cancels): $'
msgPinOk    DB 'PIN accepted. Alarm acknowledged.',13,10,'$'
msgPinBad   DB 'WRONG PIN - acknowledgement rejected.',13,10,'$'
msgPinEsc   DB 'Acknowledge cancelled.',13,10,'$'
msgNoAlarm  DB 'No active alarm to acknowledge.',13,10,'$'
msgCorrupt  DB '[TEST] Log record 1 was corrupted.',13,10,'$'
msgNoRec    DB '[TEST] No log record to corrupt.',13,10,'$'
msgBye      DB 'Monitor stopped. Goodbye.',13,10,'$'

; ---------- name tables for the log display ----------
ev1         DB 'TEMP HIGH$'          ; name of event 01
ev2         DB 'TEMP LOW$'           ; name of event 02
ev3         DB 'POWER FAILURE$'      ; name of event 03
ev4         DB 'POWER RESTORED$'     ; name of event 04
ev5         DB 'STATE CRITICAL$'     ; name of event 05
ev6         DB 'BREACH PREDICTED$'   ; name of event 06
ev7         DB 'ALARM ACKNOWLEDGED$' ; name of event 07
ev8         DB 'LOG OVERFLOW$'       ; name of event 08
evUnknown   DB 'UNKNOWN$'            ; any other code
eventTbl    DW OFFSET ev1, OFFSET ev2, OFFSET ev3, OFFSET ev4   ; pointers to names 1-4
            DW OFFSET ev5, OFFSET ev6, OFFSET ev7, OFFSET ev8   ; pointers to names 5-8
priLow      DB 'LOW$'                ; text for priority 0
priMed      DB 'MEDIUM$'             ; text for priority 1
priCrit     DB 'CRITICAL$'           ; text for priority 2
priTbl      DW OFFSET priLow, OFFSET priMed, OFFSET priCrit     ; pointers to priority names

; ---------- macro: print a '$' string (keeps all registers) ----------
SHOWMSG MACRO m                       ; usage: SHOWMSG label
    push dx                           ; save DX
    mov dx, OFFSET m                  ; DX = address of the string
    call PRINT_STR                    ; print it
    pop dx                            ; restore DX
ENDM

.CODE                                 ; ---------------- CODE SEGMENT ----------------

; ==========================================================================
; MEMBER 1 MODULE : INPUT AND SIMULATION
; ==========================================================================

; READ_INPUT : waits for a valid key. IN: none. OUT: AL = upper-case key.
; Accepts only U D P T 1 2 3 Q C (any case). Everything else is ignored.
READ_INPUT PROC
ri_wait:
    mov ah, 0                         ; INT 16h function 0 = wait for a key
    int 16h                           ; AL = ASCII code of the key
    cmp al, 'a'                       ; is it below 'a'?
    jb ri_chk                         ; yes: not lower case, skip conversion
    cmp al, 'z'                       ; is it above 'z'?
    ja ri_chk                         ; yes: not lower case, skip conversion
    sub al, 20h                       ; convert lower case to upper case
ri_chk:
    cmp al, 'U'                       ; valid key U?
    je ri_ok                          ; yes: accept
    cmp al, 'D'                       ; valid key D?
    je ri_ok                          ; yes: accept
    cmp al, 'P'                       ; valid key P?
    je ri_ok                          ; yes: accept
    cmp al, 'T'                       ; valid key T?
    je ri_ok                          ; yes: accept
    cmp al, '1'                       ; valid key 1?
    je ri_ok                          ; yes: accept
    cmp al, '2'                       ; valid key 2?
    je ri_ok                          ; yes: accept
    cmp al, '3'                       ; valid key 3?
    je ri_ok                          ; yes: accept
    cmp al, 'Q'                       ; valid key Q?
    je ri_ok                          ; yes: accept
    cmp al, 'C'                       ; valid key C (test hook)?
    je ri_ok                          ; yes: accept
    jmp ri_wait                       ; unknown key: ignore it and wait again
ri_ok:
    ret                               ; return with the key in AL
READ_INPUT ENDP

; UPDATE_TEMP : applies the power rule once per simulated minute.
; IN: none (uses temp, power). OUT: temp changed by 1 degree.
UPDATE_TEMP PROC
    push ax                           ; save AX
    mov al, temp                      ; AL = current temperature
    cmp power, 0                      ; is the power OFF?
    je ut_off                         ; yes: temperature rises
    cmp al, NORMAL_TEMP               ; power ON: compare with 5 degrees
    je ut_store                       ; already 5: nothing to do
    jl ut_up                          ; below 5: move up
    dec al                            ; above 5: move down by 1
    jmp ut_store                      ; save the result
ut_up:
    inc al                            ; below 5: move up by 1
    jmp ut_store                      ; save the result
ut_off:
    cmp al, TEMP_MAX                  ; already at simulator maximum?
    jge ut_store                      ; yes: do not go higher
    inc al                            ; power OFF: temperature rises 1 degree
ut_store:
    mov temp, al                      ; store the new temperature
    pop ax                            ; restore AX
    ret                               ; return
UPDATE_TEMP ENDP

; ADJUST_TEMP : manual change from the U / D keys (input validated by limits).
; IN: AL = +1 or -1 (0FFh). OUT: temp changed only if inside TEMP_MIN..TEMP_MAX.
ADJUST_TEMP PROC
    push ax                           ; save AX
    push bx                           ; save BX
    mov bl, al                        ; BL = step (+1 or -1)
    mov al, temp                      ; AL = current temperature
    add al, bl                        ; AL = proposed temperature
    cmp al, TEMP_MAX                  ; above the simulator maximum?
    jg at_skip                        ; yes: reject
    cmp al, TEMP_MIN                  ; below the simulator minimum?
    jl at_skip                        ; yes: reject
    mov temp, al                      ; accept the new temperature
at_skip:
    pop bx                            ; restore BX
    pop ax                            ; restore AX
    ret                               ; return
ADJUST_TEMP ENDP

; TOGGLE_POWER : P key. Switches power and logs event 03 or 04.
; IN: none. OUT: power flipped, event logged.
TOGGLE_POWER PROC
    push ax                           ; save AX
    push dx                           ; save DX
    mov al, power                     ; AL = current power value
    xor al, 1                         ; flip 1 <-> 0
    mov power, al                     ; store the new power value
    cmp al, 0                         ; is the power now OFF?
    jne tp_on                         ; no: power was restored
    mov pwrOffMin, 0                  ; power just failed: restart its minute counter
    mov al, EV_PWRFAIL                ; event code 03
    mov ah, PRI_MED                   ; medium priority
    mov dl, temp                      ; temperature at the time
    call LOG_EVENT                    ; record the power failure
    jmp tp_done                       ; finish
tp_on:
    mov al, EV_PWRBACK                ; event code 04
    mov ah, PRI_LOW                   ; low priority
    mov dl, temp                      ; temperature at the time
    call LOG_EVENT                    ; record the power restored event
tp_done:
    pop dx                            ; restore DX
    pop ax                            ; restore AX
    ret                               ; return
TOGGLE_POWER ENDP

; ==========================================================================
; MEMBER 2 MODULE : DETECTION ENGINE
; ==========================================================================

; UPDATE_STATE : duration counters, state NORMAL/WARNING/CRITICAL, events.
; IN: AL = 1 if one minute passed, 0 if only a key changed the inputs.
; OUT: state, outMin, pwrOffMin, alarmActive updated; events logged.
UPDATE_STATE PROC
    push ax                           ; save AX
    push bx                           ; save BX
    push dx                           ; save DX
    mov tickFlag, al                  ; remember whether time passed
    mov al, temp                      ; AL = current temperature
    mov bh, EV_HIGH                   ; BH = event code to use if out of range (default high)
    cmp al, SAFE_HIGH                 ; temperature above 8?
    jg us_high                        ; yes: out of range (high)
    cmp al, SAFE_LOW                  ; temperature below 2?
    jl us_low                         ; yes: out of range (low)
    xor bl, bl                        ; BL = 0 : inside the safe range
    jmp us_dur                        ; go to the duration counter
us_high:
    mov bl, 1                         ; BL = 1 : out of range
    mov bh, EV_HIGH                   ; event 01 temperature high
    jmp us_dur                        ; go to the duration counter
us_low:
    mov bl, 1                         ; BL = 1 : out of range
    mov bh, EV_LOW                    ; event 02 temperature low
us_dur:
    cmp bl, 0                         ; inside the range?
    jne us_isout                      ; no: count the minutes
    mov outMin, 0                     ; back in range: reset the duration counter
    jmp us_evt                        ; continue
us_isout:
    cmp tickFlag, 0                   ; did a minute pass?
    je us_evt                         ; no: do not count
    inc outMin                        ; one more minute out of range
us_evt:
    cmp bl, 0                         ; inside the range?
    je us_noevt                       ; yes: no excursion event
    cmp prevOut, 0                    ; was it already out of range before?
    jne us_noevt                      ; yes: the event was already logged
    mov al, bh                        ; AL = event code (01 or 02)
    mov ah, PRI_MED                   ; medium priority
    mov dl, temp                      ; DL = temperature
    call LOG_EVENT                    ; record the start of the excursion
us_noevt:
    mov prevOut, bl                   ; remember the out-of-range status
    cmp power, 0                      ; is the power OFF?
    jne us_pon                        ; no: power is ON
    cmp tickFlag, 0                   ; did a minute pass?
    je us_state                       ; no: do not count
    inc pwrOffMin                     ; one more minute without power
    jmp us_state                      ; continue
us_pon:
    mov pwrOffMin, 0                  ; power is ON: reset its counter
us_state:
    mov dl, ST_NORMAL                 ; DL = new state, assume NORMAL
    cmp bl, 0                         ; inside the range?
    je us_critchk                     ; yes: keep NORMAL for now
    mov dl, ST_WARNING                ; out of range: at least WARNING
us_critchk:
    mov al, temp                      ; AL = current temperature
    cmp al, CRIT_HIGH                 ; temperature 12 or above?
    jge us_crit                       ; yes: CRITICAL
    cmp al, CRIT_LOW                  ; temperature -2 or below?
    jle us_crit                       ; yes: CRITICAL
    cmp outMin, CRIT_MIN              ; out of range 10 minutes or more?
    jae us_crit                       ; yes: CRITICAL
    cmp pwrOffMin, CRIT_MIN           ; power off 10 minutes or more?
    jae us_crit                       ; yes: CRITICAL
    jmp us_set                        ; no critical condition
us_crit:
    mov dl, ST_CRIT                   ; new state = CRITICAL
us_set:
    mov al, state                     ; AL = old state
    cmp al, dl                        ; did the state change?
    je us_done                        ; no: nothing more to do
    mov state, dl                     ; store the new state
    mov alarmActive, 1                ; a new alarm is waiting for acknowledgement
    cmp dl, ST_NORMAL                 ; is the new state NORMAL?
    jne us_chkcrit                    ; no: keep the alarm active
    mov alarmActive, 0                ; back to NORMAL: no alarm any more
us_chkcrit:
    cmp dl, ST_CRIT                   ; did we just become CRITICAL?
    jne us_done                       ; no: nothing to log
    mov al, EV_CRITICAL               ; event code 05
    mov ah, PRI_CRIT                  ; critical priority
    mov dl, temp                      ; DL = temperature
    call LOG_EVENT                    ; record the state change
us_done:
    pop dx                            ; restore DX
    pop bx                            ; restore BX
    pop ax                            ; restore AX
    ret                               ; return
UPDATE_STATE ENDP

; CALC_RATE : prediction from the change over the last 3 ticks.
; minutes to breach = ceil( (8 - temp) * 3 / (temp - temp3ticksAgo) )
; Only when the temperature is rising and between 2 and 7. Division by zero is
; impossible because we divide only when the change is greater than zero.
; IN: none. OUT: predValid, predMin; event 06 when a prediction first appears.
CALC_RATE PROC
    push ax                           ; save AX
    push bx                           ; save BX
    push cx                           ; save CX
    push dx                           ; save DX
    mov al, predValid                 ; AL = previous prediction flag
    mov prevPred, al                  ; remember it
    mov predValid, 0                  ; assume no prediction
    mov al, temp                      ; AL = current temperature
    cmp al, SAFE_LOW                  ; below the safe range?
    jl cr_shift                       ; yes: no breach to predict
    cmp al, SAFE_HIGH                 ; already at or above 8?
    jge cr_shift                      ; yes: nothing to predict
    cbw                               ; AX = signed temperature
    mov bx, ax                        ; BX = current temperature
    mov al, hist0                     ; AL = temperature 3 ticks ago
    cbw                               ; AX = signed old temperature
    sub bx, ax                        ; BX = change over 3 ticks
    jle cr_shift                      ; not rising: no prediction
    mov al, temp                      ; AL = current temperature again
    cbw                               ; AX = signed temperature
    mov cx, SAFE_HIGH                 ; CX = 8
    sub cx, ax                        ; CX = degrees left until 8
    mov ax, cx                        ; AX = degrees left
    mov cx, 3                         ; CX = 3 ticks
    mul cx                            ; DX:AX = degrees left x 3
    add ax, bx                        ; add change ...
    dec ax                            ; ... minus 1 so the division rounds up
    xor dx, dx                        ; clear DX for 16-bit division
    div bx                            ; AX = minutes to breach
    mov predMin, ax                   ; store the prediction
    mov predValid, 1                  ; a prediction exists
    cmp prevPred, 0                   ; was there one before?
    jne cr_shift                      ; yes: do not log it again
    mov al, EV_PREDICT                ; event code 06
    mov ah, PRI_MED                   ; medium priority
    mov dl, temp                      ; DL = temperature
    call LOG_EVENT                    ; record the predicted breach
cr_shift:
    mov al, hist1                     ; shift history: hist0 <- hist1
    mov hist0, al                     ; store
    mov al, hist2                     ; shift history: hist1 <- hist2
    mov hist1, al                     ; store
    mov al, temp                      ; newest temperature
    mov hist2, al                     ; hist2 <- current temperature
    pop dx                            ; restore DX
    pop cx                            ; restore CX
    pop bx                            ; restore BX
    pop ax                            ; restore AX
    ret                               ; return
CALC_RATE ENDP

; CALC_SCORE : adds the degrees outside 2..8 C to the 16-bit exposure score.
; IN: none. OUT: score increased (saturates at 65535).
CALC_SCORE PROC
    push ax                           ; save AX
    push bx                           ; save BX
    mov al, temp                      ; AL = current temperature
    cmp al, SAFE_HIGH                 ; above 8?
    jg cs_above                       ; yes
    cmp al, SAFE_LOW                  ; below 2?
    jl cs_below                       ; yes
    jmp cs_end                        ; inside range: add nothing
cs_above:
    sub al, SAFE_HIGH                 ; AL = degrees above 8
    jmp cs_add                        ; add to the score
cs_below:
    mov bl, al                        ; BL = temperature
    mov al, SAFE_LOW                  ; AL = 2
    sub al, bl                        ; AL = degrees below 2
cs_add:
    xor ah, ah                        ; AX = degrees outside the range
    add score, ax                     ; add to the 16-bit total
    jnc cs_end                        ; no carry: fine
    mov score, 0FFFFh                 ; overflow: stay at the maximum
cs_end:
    pop bx                            ; restore BX
    pop ax                            ; restore AX
    ret                               ; return
CALC_SCORE ENDP

; DO_TICK : one simulated minute (T key). Runs all modules in the right order.
DO_TICK PROC
    call UPDATE_TEMP                  ; apply the power rule to the temperature
    inc clock                         ; one more simulated minute
    mov al, 1                         ; tell UPDATE_STATE a minute passed
    call UPDATE_STATE                 ; update counters, state and events
    call CALC_RATE                    ; update the breach prediction
    call CALC_SCORE                   ; update the exposure score
    ret                               ; return
DO_TICK ENDP

; ==========================================================================
; MEMBER 3 MODULE : EVENT LOG (only LOG_EVENT writes to logBuf)
; ==========================================================================

; CHECKSUM : XOR of the first five bytes of a record.
; IN: SI = address of the record. OUT: AL = checksum. SI unchanged.
CHECKSUM PROC
    push cx                           ; save CX
    push si                           ; save SI
    xor al, al                        ; AL = 0 (running XOR)
    mov cx, 5                         ; five bytes to XOR
cks_loop:
    xor al, [si]                      ; XOR in the next byte
    inc si                            ; point to the following byte
    loop cks_loop                     ; repeat 5 times
    pop si                            ; restore SI
    pop cx                            ; restore CX
    ret                               ; return with the checksum in AL
CHECKSUM ENDP

; FIND_VICTIM : the log is full - choose the slot to overwrite.
; Rule: oldest record among the LOWEST priority. A critical record is chosen
; only when every record is critical (then the overflow flag is set).
; IN: none. OUT: AL = slot number 0..31 (always inside the buffer).
FIND_VICTIM PROC
    push bx                           ; save BX
    push cx                           ; save CX
    push dx                           ; save DX
    push si                           ; save SI
    push di                           ; save DI
    mov dl, 3                         ; DL = lowest priority found (3 = none yet)
    xor si, si                        ; SI = slot counter
    mov di, OFFSET logBuf             ; DI = address of record 0
fv_p1:
    mov al, [di+1]                    ; AL = priority of this record
    cmp al, dl                        ; lower than the lowest so far?
    jae fv_p1n                        ; no: keep old value
    mov dl, al                        ; yes: new lowest priority
fv_p1n:
    add di, REC_SIZE                  ; next record
    inc si                            ; next slot number
    cmp si, LOG_SIZE                  ; all 32 slots checked?
    jb fv_p1                          ; no: continue
    mov bestIdx, 0FFh                 ; no victim chosen yet
    mov bestSeq, 0FFFFh               ; start with the largest age stamp
    xor si, si                        ; SI = slot counter again
    mov di, OFFSET logBuf             ; DI = address of record 0
fv_p2:
    mov al, [di+1]                    ; AL = priority of this record
    cmp al, dl                        ; same as the lowest priority?
    jne fv_p2n                        ; no: skip it
    mov bx, si                        ; BX = slot number
    shl bx, 1                         ; BX = slot x 2 (word table index)
    mov cx, logSeq[bx]                ; CX = age stamp of this record
    cmp bestIdx, 0FFh                 ; first candidate?
    je fv_take                        ; yes: take it
    cmp cx, bestSeq                   ; older than the best so far?
    jae fv_p2n                        ; no: skip it
fv_take:
    mov bestSeq, cx                   ; remember its age stamp
    mov ax, si                        ; AX = slot number
    mov bestIdx, al                   ; remember the slot
fv_p2n:
    add di, REC_SIZE                  ; next record
    inc si                            ; next slot number
    cmp si, LOG_SIZE                  ; all slots checked?
    jb fv_p2                          ; no: continue
    cmp dl, PRI_CRIT                  ; was the lowest priority CRITICAL?
    jne fv_done                       ; no: normal overwrite
    cmp overflowFlg, 0                ; flag already set?
    jne fv_done                       ; yes: nothing new
    mov overflowFlg, 1                ; every record is critical: set OVERFLOW flag
    mov newOverflow, 1                ; ask LOG_EVENT to also log event 08
fv_done:
    mov al, bestIdx                   ; AL = chosen slot
    cmp al, LOG_SIZE                  ; safety bounds check
    jb fv_ret                         ; inside the buffer: fine
    xor al, al                        ; otherwise use slot 0
fv_ret:
    pop di                            ; restore DI
    pop si                            ; restore SI
    pop dx                            ; restore DX
    pop cx                            ; restore CX
    pop bx                            ; restore BX
    ret                               ; return
FIND_VICTIM ENDP

; LOG_EVENT : stores a 6-byte record using the overwrite policy.
; IN: AL = event code, AH = priority, DL = temperature. OUT: record stored.
LOG_EVENT PROC
    push ax                           ; save AX
    push bx                           ; save BX
    push cx                           ; save CX
    push dx                           ; save DX
    push si                           ; save SI
    push di                           ; save DI
    mov evCode, al                    ; keep the event code
    mov evPri, ah                     ; keep the priority
    mov evTemp, dl                    ; keep the temperature
    mov newOverflow, 0                ; no overflow event yet
    mov al, logCount                  ; AL = records used so far
    cmp al, LOG_SIZE                  ; is the log full?
    jae le_full                       ; yes: choose a victim
    mov slotIdx, al                   ; use the next free slot
    inc logCount                      ; one more record in use
    jmp le_write                      ; write the record
le_full:
    call FIND_VICTIM                  ; AL = slot to overwrite (may set newOverflow)
    cmp newOverflow, 1                ; did the overflow flag just get set?
    jne le_setslot                    ; no: use the slot we found
    mov newOverflow, 0                ; handle the overflow event now
    mov al, evCode                    ; AL = code of the event we are logging
    mov ah, evPri                     ; AH = its priority
    push ax                           ; save code and priority on the stack
    mov al, evTemp                    ; AL = its temperature
    push ax                           ; save the temperature on the stack
    mov al, EV_OVERFLOW               ; event code 08
    mov ah, PRI_CRIT                  ; critical priority
    mov dl, evTemp                    ; temperature
    call LOG_EVENT                    ; log the overflow first (flag is set, so no loop)
    pop ax                            ; restore the temperature
    mov evTemp, al                    ; put it back in the variable
    pop ax                            ; restore code and priority
    mov evCode, al                    ; put the code back
    mov evPri, ah                     ; put the priority back
    call FIND_VICTIM                  ; AL = slot for the real event
le_setslot:
    mov slotIdx, al                   ; remember the slot
le_write:
    mov al, slotIdx                   ; AL = slot number
    cmp al, LOG_SIZE                  ; bounds check: never index outside the buffer
    jb le_ok                          ; inside: continue
    jmp le_exit                       ; outside: refuse to write
le_ok:
    mov bl, REC_SIZE                  ; BL = 6 bytes per record
    mul bl                            ; AX = slot x 6
    mov si, OFFSET logBuf             ; SI = start of the buffer
    add si, ax                        ; SI = address of the record
    mov al, evCode                    ; AL = event code
    mov [si], al                      ; byte 0 = code
    mov al, evPri                     ; AL = priority
    mov [si+1], al                    ; byte 1 = priority
    mov ax, clock                     ; AX = current simulated time
    mov [si+2], ax                    ; bytes 2-3 = time
    mov al, evTemp                    ; AL = temperature
    mov [si+4], al                    ; byte 4 = temperature
    call CHECKSUM                     ; AL = XOR of bytes 0-4
    mov [si+5], al                    ; byte 5 = checksum
    mov al, slotIdx                   ; AL = slot number
    xor ah, ah                        ; AX = slot number
    shl ax, 1                         ; AX = slot x 2
    mov bx, ax                        ; BX = word index
    mov ax, seqCounter                ; AX = next age stamp
    mov logSeq[bx], ax                ; stamp this record
    inc seqCounter                    ; next record gets a newer stamp
le_exit:
    pop di                            ; restore DI
    pop si                            ; restore SI
    pop dx                            ; restore DX
    pop cx                            ; restore CX
    pop bx                            ; restore BX
    pop ax                            ; restore AX
    ret                               ; return
LOG_EVENT ENDP

; SHOW_LOG : prints every stored record, flags checksum errors.
; IN: none. OUT: text on screen (read only, never writes to the log).
SHOW_LOG PROC
    push ax                           ; save AX
    push bx                           ; save BX
    push cx                           ; save CX
    push dx                           ; save DX
    push si                           ; save SI
    SHOWMSG msgLogHdr                 ; print the heading
    cmp logCount, 0                   ; any records?
    jne sl_go                         ; yes: print them
    SHOWMSG msgLogEmpty               ; say the log is empty
    jmp sl_exit                       ; finish
sl_go:
    mov si, OFFSET logBuf             ; SI = first record
    xor cx, cx                        ; CX = row counter
sl_row:
    SHOWMSG msgSlot                   ; print "Slot "
    mov ax, cx                        ; AX = row number
    inc al                            ; make it 1-based
    call PRINT_NUM2                   ; print the slot number (2 digits)
    SHOWMSG msgCode                   ; print " | Code "
    mov al, [si]                      ; AL = event code
    call PRINT_NUM2                   ; print the code (2 digits)
    SHOWMSG msgSep                    ; print " | "
    mov al, [si]                      ; AL = event code
    cmp al, 1                         ; below 1?
    jb sl_unk                         ; unknown code
    cmp al, 8                         ; above 8?
    ja sl_unk                         ; unknown code
    dec al                            ; make it 0-based
    xor ah, ah                        ; AX = index
    shl ax, 1                         ; AX = index x 2
    mov bx, ax                        ; BX = table offset
    mov dx, eventTbl[bx]              ; DX = address of the event name
    jmp sl_pe                         ; print the name
sl_unk:
    mov dx, OFFSET evUnknown          ; DX = "UNKNOWN"
sl_pe:
    call PRINT_STR                    ; print the event name
    SHOWMSG msgPri                    ; print " | Pri "
    mov al, [si+1]                    ; AL = priority
    cmp al, 2                         ; valid priority 0..2?
    jbe sl_pok                        ; yes
    mov al, 0                         ; invalid: show as LOW
sl_pok:
    xor ah, ah                        ; AX = priority
    shl ax, 1                         ; AX = priority x 2
    mov bx, ax                        ; BX = table offset
    mov dx, priTbl[bx]                ; DX = address of the priority name
    call PRINT_STR                    ; print the priority name
    SHOWMSG msgLTime                  ; print " | Time "
    mov ax, [si+2]                    ; AX = record time
    call PRINT_NUM                    ; print it
    SHOWMSG msgLTemp                  ; print " | Temp "
    mov al, [si+4]                    ; AL = record temperature
    call PRINT_SIGNED                 ; print it (can be negative)
    call CHECKSUM                     ; AL = recalculated checksum
    cmp al, [si+5]                    ; same as the stored checksum?
    jne sl_bad                        ; no: record was altered
    SHOWMSG msgOk                     ; print " | OK"
    jmp sl_next                       ; next row
sl_bad:
    SHOWMSG msgBad                    ; print " | CHECKSUM ERROR"
sl_next:
    add si, REC_SIZE                  ; SI = next record
    inc cx                            ; next row
    mov al, logCount                  ; AL = number of records
    xor ah, ah                        ; AX = number of records
    cmp cx, ax                        ; all rows printed?
    jae sl_exit                       ; yes: finish
    jmp sl_row                        ; no: print the next row
sl_exit:
    pop si                            ; restore SI
    pop dx                            ; restore DX
    pop cx                            ; restore CX
    pop bx                            ; restore BX
    pop ax                            ; restore AX
    ret                               ; return
SHOW_LOG ENDP

; CORRUPT_LOG : TEST HOOK (key C). Flips the temperature byte of record 1 so
; that Test Scenario 5 (tampering check) can be shown. Does not fix the checksum.
CORRUPT_LOG PROC
    push ax                           ; save AX
    cmp logCount, 0                   ; any record to corrupt?
    je cl_none                        ; no
    xor logBuf+4, 0FFh                ; flip all bits of the temperature byte in record 1
    SHOWMSG msgCorrupt                ; tell the tester
    jmp cl_exit                       ; finish
cl_none:
    SHOWMSG msgNoRec                  ; tell the tester there is no record
cl_exit:
    pop ax                            ; restore AX
    ret                               ; return
CORRUPT_LOG ENDP

; ==========================================================================
; MEMBER 4 MODULE : USER INTERFACE AND INTEGRATION
; ==========================================================================

; PRINT_STR : prints a '$' terminated string. IN: DX = address. Registers kept.
PRINT_STR PROC
    push ax                           ; save AX
    mov ah, 9                         ; INT 21h function 9 = print string
    int 21h                           ; print the string at DS:DX
    pop ax                            ; restore AX
    ret                               ; return
PRINT_STR ENDP

; PRINT_NUM : prints a 16-bit UNSIGNED number. IN: AX. Registers kept.
PRINT_NUM PROC
    push ax                           ; save AX
    push bx                           ; save BX
    push cx                           ; save CX
    push dx                           ; save DX
    mov bx, 10                        ; BX = divisor 10
    xor cx, cx                        ; CX = digit counter
pn_div:
    xor dx, dx                        ; clear DX for the division
    div bx                            ; AX = quotient, DX = remainder (a digit)
    push dx                           ; save the digit on the stack
    inc cx                            ; one more digit
    cmp ax, 0                         ; any quotient left?
    jne pn_div                        ; yes: keep dividing
pn_out:
    pop dx                            ; DX = next digit (most significant first)
    add dl, '0'                       ; convert to ASCII
    mov ah, 2                         ; INT 21h function 2 = print character
    int 21h                           ; print it
    loop pn_out                       ; repeat for every digit
    pop dx                            ; restore DX
    pop cx                            ; restore CX
    pop bx                            ; restore BX
    pop ax                            ; restore AX
    ret                               ; return
PRINT_NUM ENDP

; PRINT_NUM2 : prints AL (0..99) as exactly two digits. Registers kept.
PRINT_NUM2 PROC
    push ax                           ; save AX
    push dx                           ; save DX
    xor ah, ah                        ; AX = value
    mov dl, 10                        ; DL = divisor 10
    div dl                            ; AL = tens, AH = units
    mov dh, ah                        ; DH = units digit
    add al, '0'                       ; tens digit to ASCII
    mov dl, al                        ; DL = character to print
    mov ah, 2                         ; INT 21h function 2
    int 21h                           ; print tens digit
    mov dl, dh                        ; DL = units digit
    add dl, '0'                       ; to ASCII
    mov ah, 2                         ; INT 21h function 2
    int 21h                           ; print units digit
    pop dx                            ; restore DX
    pop ax                            ; restore AX
    ret                               ; return
PRINT_NUM2 ENDP

; PRINT_SIGNED : prints AL as a signed number (-128..127). Registers kept.
PRINT_SIGNED PROC
    push ax                           ; save AX
    push dx                           ; save DX
    cmp al, 0                         ; negative?
    jge ps_pos                        ; no
    push ax                           ; keep AL, INT 21h will change it
    mov dl, '-'                       ; minus sign
    mov ah, 2                         ; INT 21h function 2
    int 21h                           ; print '-'
    pop ax                            ; restore the value
    neg al                            ; make it positive
ps_pos:
    xor ah, ah                        ; AX = 0..128
    call PRINT_NUM                    ; print the digits
    pop dx                            ; restore DX
    pop ax                            ; restore AX
    ret                               ; return
PRINT_SIGNED ENDP

; SHOW_STATUS : prints temperature, power, state, minutes, score, prediction.
; IN: none. OUT: text on screen (read only).
SHOW_STATUS PROC
    push ax                           ; save AX
    push bx                           ; save BX
    push dx                           ; save DX
    SHOWMSG msgLine                   ; separator line
    SHOWMSG msgTime                   ; "Time (minutes)"
    mov ax, clock                     ; AX = simulated time
    call PRINT_NUM                    ; print it
    SHOWMSG msgCrLf                   ; new line
    SHOWMSG msgTemp                   ; "Temperature"
    mov al, temp                      ; AL = temperature
    call PRINT_SIGNED                 ; print it (may be negative)
    SHOWMSG msgDegC                   ; " C"
    SHOWMSG msgPower                  ; "Power"
    cmp power, 0                      ; power OFF?
    je ss_off                         ; yes
    SHOWMSG msgOn                     ; print ON
    jmp ss_state                      ; continue
ss_off:
    SHOWMSG msgOff                    ; print OFF
ss_state:
    SHOWMSG msgState                  ; "State"
    cmp state, ST_CRIT                ; CRITICAL?
    je ss_crit                        ; yes
    cmp state, ST_WARNING             ; WARNING?
    je ss_warn                        ; yes
    SHOWMSG msgNormal                 ; print NORMAL
    jmp ss_out                        ; continue
ss_warn:
    SHOWMSG msgWarning                ; print WARNING
    jmp ss_out                        ; continue
ss_crit:
    SHOWMSG msgCritical               ; print CRITICAL
ss_out:
    SHOWMSG msgOutMin                 ; "Minutes out range"
    mov ax, outMin                    ; AX = minutes out of range
    call PRINT_NUM                    ; print it
    SHOWMSG msgCrLf                   ; new line
    SHOWMSG msgScore                  ; "Exposure score"
    mov ax, score                     ; AX = exposure score
    call PRINT_NUM                    ; print it
    SHOWMSG msgCrLf                   ; new line
    SHOWMSG msgPred                   ; "Breach prediction"
    cmp predValid, 0                  ; is there a prediction?
    je ss_nopred                      ; no
    mov ax, predMin                   ; AX = predicted minutes
    call PRINT_NUM                    ; print it
    SHOWMSG msgMin                    ; " min"
    jmp ss_alarm                      ; continue
ss_nopred:
    SHOWMSG msgNone                   ; "none"
ss_alarm:
    SHOWMSG msgAlarm                  ; "Alarm"
    cmp alarmActive, 0                ; unacknowledged alarm?
    jne ss_alact                      ; yes
    cmp state, ST_NORMAL              ; no alarm: is the state NORMAL?
    je ss_alnone                      ; yes: no alarm at all
    SHOWMSG msgAlAck                  ; state not normal but acknowledged
    jmp ss_log                        ; continue
ss_alact:
    SHOWMSG msgAlAct                  ; ACTIVE
    jmp ss_log                        ; continue
ss_alnone:
    SHOWMSG msgAlNone                 ; none
ss_log:
    SHOWMSG msgLogInfo                ; "Log records"
    mov al, logCount                  ; AL = records used
    xor ah, ah                        ; AX = records used
    call PRINT_NUM                    ; print it
    SHOWMSG msgOfString               ; " / 32"
    cmp overflowFlg, 0                ; overflow flag set?
    je ss_end                         ; no
    SHOWMSG msgOvf                    ; show the overflow flag
ss_end:
    SHOWMSG msgCrLf                   ; new line
    pop dx                            ; restore DX
    pop bx                            ; restore BX
    pop ax                            ; restore AX
    ret                               ; return
SHOW_STATUS ENDP

; ACK : acknowledge an alarm with the 4-digit PIN. Never deletes log records.
; All 4 digits are always compared (no early exit). ESC cancels.
; IN: none. OUT: event 07 logged on success.
ACK PROC
    push ax                           ; save AX
    push dx                           ; save DX
    push si                           ; save SI
    cmp alarmActive, 0                ; is there an alarm to acknowledge?
    jne ack_ask                       ; yes: ask for the PIN
    SHOWMSG msgNoAlarm                ; nothing to acknowledge
    jmp ack_done                      ; finish
ack_ask:
    SHOWMSG msgPinAsk                 ; ask for the PIN
    xor si, si                        ; SI = number of digits typed
    mov wrongFlag, 0                  ; no wrong digit yet
ack_read:
    mov ah, 0                         ; INT 16h function 0 = wait for a key
    int 16h                           ; AL = key (not echoed)
    cmp al, 1Bh                       ; ESC pressed?
    je ack_esc                        ; yes: cancel
    cmp al, '0'                       ; below '0'?
    jb ack_read                       ; ignore non-digits
    cmp al, '9'                       ; above '9'?
    ja ack_read                       ; ignore non-digits
    cmp al, pinStored[si]             ; compare with the stored digit
    je ack_same                       ; correct digit
    mov wrongFlag, 1                  ; remember that a digit was wrong
ack_same:
    mov dl, '*'                       ; show a star instead of the digit
    mov ah, 2                         ; INT 21h function 2
    int 21h                           ; print '*'
    inc si                            ; one more digit typed
    cmp si, PIN_LEN                   ; all 4 digits typed?
    jb ack_read                       ; no: read the next one
    SHOWMSG msgCrLf                   ; new line
    cmp wrongFlag, 0                  ; was every digit right?
    jne ack_bad                       ; no: wrong PIN
    mov alarmActive, 0                ; alarm acknowledged
    mov al, EV_ACK                    ; event code 07
    mov ah, PRI_MED                   ; medium priority
    mov dl, temp                      ; temperature
    call LOG_EVENT                    ; log the acknowledgement
    SHOWMSG msgPinOk                  ; tell the user
    jmp ack_done                      ; finish
ack_bad:
    SHOWMSG msgPinBad                 ; wrong PIN: rejected, nothing changes
    jmp ack_done                      ; finish
ack_esc:
    SHOWMSG msgCrLf                   ; new line
    SHOWMSG msgPinEsc                 ; cancelled
ack_done:
    pop si                            ; restore SI
    pop dx                            ; restore DX
    pop ax                            ; restore AX
    ret                               ; return
ACK ENDP

; AFTER_MANUAL : called after U, D or P. Old trend is invalid, re-check state.
AFTER_MANUAL PROC
    push ax                           ; save AX
    mov predValid, 0                  ; manual change breaks the trend: clear prediction
    xor al, al                        ; AL = 0 : no minute passed
    call UPDATE_STATE                 ; re-evaluate the state
    pop ax                            ; restore AX
    ret                               ; return
AFTER_MANUAL ENDP

; MAIN : read key, act, redraw status.
MAIN PROC
    mov ax, @data                     ; AX = data segment address
    mov ds, ax                        ; DS points to our data
    mov es, ax                        ; ES points to our data
    SHOWMSG msgBanner                 ; show title and key help
    call SHOW_STATUS                  ; show the first status screen
m_loop:
    call READ_INPUT                   ; AL = validated key
    cmp al, 'Q'                       ; quit?
    jne m_u                           ; no: test the next key
    jmp m_quit                        ; yes: leave the program
m_u:
    cmp al, 'U'                       ; temperature up?
    jne m_d                           ; no
    mov al, 1                         ; step = +1
    call ADJUST_TEMP                  ; change the temperature
    call AFTER_MANUAL                 ; re-check the state
    jmp m_draw                        ; redraw
m_d:
    cmp al, 'D'                       ; temperature down?
    jne m_p                           ; no
    mov al, 0FFh                      ; step = -1
    call ADJUST_TEMP                  ; change the temperature
    call AFTER_MANUAL                 ; re-check the state
    jmp m_draw                        ; redraw
m_p:
    cmp al, 'P'                       ; toggle power?
    jne m_t                           ; no
    call TOGGLE_POWER                 ; flip power and log the event
    call AFTER_MANUAL                 ; re-check the state
    jmp m_draw                        ; redraw
m_t:
    cmp al, 'T'                       ; advance one minute?
    jne m_2                           ; no
    call DO_TICK                      ; run one simulated minute
    jmp m_draw                        ; redraw
m_2:
    cmp al, '2'                       ; show the log?
    jne m_3                           ; no
    call SHOW_LOG                     ; print the log
    jmp m_draw                        ; redraw
m_3:
    cmp al, '3'                       ; acknowledge?
    jne m_c                           ; no
    call ACK                          ; ask for the PIN
    jmp m_draw                        ; redraw
m_c:
    cmp al, 'C'                       ; test hook?
    jne m_draw                        ; no: only key '1' is left, just redraw
    call CORRUPT_LOG                  ; corrupt one log byte for the tamper test
m_draw:
    call SHOW_STATUS                  ; redraw the status screen
    jmp m_loop                        ; wait for the next key
m_quit:
    SHOWMSG msgBye                    ; goodbye message
    mov ah, 4Ch                       ; INT 21h function 4Ch = exit
    mov al, 0                         ; return code 0
    int 21h                           ; end the program
MAIN ENDP

END MAIN                              ; end of file, start at MAIN
