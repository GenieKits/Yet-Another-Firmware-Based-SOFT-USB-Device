;; ----------------------------------------------------------------------------
;; Copyright (C) 2019-2020 Zach Lee.
;;
;; Licensed under the MIT License, you may not use this file except in
;; compliance with the License.
;;
;; MIT License:
;;
;; Permission is hereby granted, free of charge, to any person obtaining
;; a copy of this software and associated documentation files (the "Software"),
;; to deal in the Software without restriction, including without limitation
;; the rights to use, copy, modify, merge, publish, distribute, sublicense,
;; and/or sell copies of the Software, and to permit persons to whom the
;; Software is furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be included in
;; all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
;; THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;; FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
;; IN THE SOFTWARE.
;;
;; ----------------------------------------------------------------------------
;;
;; $Date:        11. May 2020
;; $Revision:    V0.0.0
;;
;; Project:      Yet Another Firmware Based USB on Microchip dsPIC33
;; Title:        sie.s The serial transmission processing code.
;;
;;-----------------------------------------------------------------------------
.equ    __24F16KA101, 1
.include "p24F16KA101.inc"

.equ    _PORTU, PORTA
.equ    _TRISU, TRISA
.equ    _LATU,  LATA
.equ    DP,     0                     ; RA0 pin
.equ    DM,     1                     ; RA1 pin
.equ    DPDM,   ((1<<DP)|(1<<DM))

        .bss
        .global __uendpt0
        .global __ucontr0
;;-----------------------------------------------------------------------------
; bit defination of __uendpt0:
; __uendpt0[15-12] - UNUSED
; __uendpt0[11] - BUS RESET from host. =1 means BUS RESET issued
; __uendpt0[10] - REQUEST FLAG. =1 means a request needs to be handled.
; __uendpt0[9-8] - HANDSHAKE (to IN) from host. 00:undef/01:ACK/10:NAK/11:STALL
; __uendpt0[7-4] - BYTES LENGTH from/to host.
; __uendpt0[3] - DATA TOGGLE from host. =0/1 means DATA0/DATA1
; __uendpt0[2] - HANDSHAKE to host. 1:ACK|0:NAK/STALL
; __uendpt0[1-0] - TOKEN TYPE from/to host. 00:undef/01:SETUP/10:IN/11:OUT
;;-----------------------------------------------------------------------------
__uendpt0:  .space  2
;;-----------------------------------------------------------------------------
; bit defination of __ucontr0:
; __ucontr0[15] - SOP ERROR.
; __ucontr0[14] - PID ERROR.
; __ucontr0[13] - DEVICE ADDRESS MATCHED. =1 means address of token is matched
; __ucontr0[12] - DATA TOGGLE expected. =0/1 means DATA1/DATA0
; __ucontr0[11-8] - UNUSED
; __ucontr0[7-4] - BYTES LENGTH to host.
; __ucontr0[3-2] - HANDSHAKE for OUT TOKEN. 00:undef/01:ACK/10:NAK/11:STALL
; __ucontr0[1-0] - HANDSHAKE for IN TOKEN. 00:undef/01:ACK/10:NAK/11:STALL
;;-----------------------------------------------------------------------------
__ucontr0:  .space  2
_addr:      .space  1                   ; device address (SET ADDRESS)
_conf:      .space  1                   ; configuration (SET CONFIGURATION)
;;-----------------------------------------------------------------------------
; internal varibles
_packet:    .space  2                   ; a data buffer pointer points to
                                        ; _token or _datax or _datay
_token:     .space  12
_datax:     .space  12
_datay:     .space  12

;;-----------------------------------------------------------------------------
        .text
        .extern __dbg_die
        .extern __dbg_send_bytes
        .extern __dbg_led_on

        .global __CNInterrupt
;;-----------------------------------------------------------------------------
__CNInterrupt:                          ; cycle-counter (5 cycles latency ISR)
        push.s                          ; 6 (w0-w3 could be used now)
        mov     _PORTU, w0              ; 7 sample D-/D+
        and     #DPDM, w0               ; 8 (is it a SE0?)
        bra     z, __SE0                ; 9 (SE0, BUS RESET or RESUME)
;;-----------------------------------------------------------------------------
__waitJ:
        ; last 3 bits (JKK) of SYNC is important
        ; step 1: make sure the current bit is a J (D-/D+ =10)
        btss    _PORTU, #DM             ; 0 (last cycle of this bit)
        bra     __waitJ
__waitK:
        ; step 2: capture the edge between J & K
        btsc    _PORTU, #DP
        bra     __firstK
        btsc    _PORTU, #DP
        bra     __firstK
        btsc    _PORTU, #DP
        bra     __firstK
        btsc    _PORTU, #DP
        bra     __firstK
        btsc    _PORTU, #DP
        bra     __firstK
;;-----------------------------------------------------------------------------
__SOPError:
        bset    __ucontr0, #15          ; __ucontr0[15] =1 means SOP ERROR
        bra     __IRQExit
;;-----------------------------------------------------------------------------
__SE0:                                  ; 0 (add 1 cycle for 'bra z, __SE0')
        repeat  #2                      ; 1
        nop                             ; 2/3/4
        mov     _PORTU, w0              ; 5 (sample D-/D+)
        and     #DPDM, w0               ; 6 (is it a SE0 yet?)
        bra     nz, __IRQExit           ; 7 (no, just ignore it)
        nop                             ; 8 (2nd SE0 detected, if a J-state is
        nop                             ; 9  following, that would be keep
        nop                             ; 0  alive signal)
;;-----------------------------------------------------------------------------
        repeat  #1                      ; 1
        nop                             ; 2/3
        mov     #(1<<DM), w1            ; 4
        mov     _PORTU, w0              ; 5 (sample D-/D+)
        and     #DPDM, w0               ; 6 (is it a SE0 yet?)
        bra     z, __BUSReset           ; 7 (3rd SE0 detected, a BUS RESET)
        cp      w0, w1                  ; 8 (J-state?)
        bra     z, __keepAlive          ; 9
        bra     __IRQExit               ; 0
;;-----------------------------------------------------------------------------
__BUSReset:
        repeat  #8                      ; 10 cycles for 1 bits
        nop
        mov     _PORTU, w0              ; resample D-/D+ after 38 cycles(2.5uS)
        and     #DPDM, w0               ; is it still a SE0?
        bra     nz, __IRQExit           ; not a SE0, just exit
        mov     #_token, w0             ; vars reinitializing for BUS RESET
        mov     w0, _packet             ; prepare for first SETUP token
        mov     #0, w0                  ; clear some vars
        mov.b   WREG, _addr             ; usb device address must be cleared
        mov     WREG, __uendpt0
        mov     #0x000A, w0             ; __ucontr0[1-0] =10, NAK to IN token
        mov     WREG, __ucontr0         ; __ucontr0[3-2] =10, NAK to OUT token
        bset    __uendpt0, #11          ; __uendpt0[11] =1 means BUS RESET
        bset    __uendpt0, #10          ; REQUEST FLAG =1, inform the app
        bra     __IRQExit               ; a BUS RESET issued
;;-----------------------------------------------------------------------------
__keepAlive:                            ; nothing should do now
        bra     __IRQExit
;;-----------------------------------------------------------------------------
__firstK:                               ; (4 cycles maximum latency)
        nop                             ; 5
        nop                             ; 6
        mov     _packet, w2             ; 7 (w2 points to the rx buffer)
        setm.b  [w2]                    ; 8 (the SYNC byte will be 0x7F)
        bset    w1, #DP                 ; 9 (w1.0 =D+ =1, 1st K)
        bset    w0, #DP                 ; 0 (w0.0 =D+ =1, 2nd K)
;;-----------------------------------------------------------------------------
        push    w4                      ; 1 (second K)
        push    w5                      ; 2 (we need more registers)
        setm    w5                      ; 3 (for bit unstuff)
        mov     #0x003f, w3             ; 4
        btsc    _PORTU, #DP             ; 5 (capture the second K)
        bra     __SyncEnd               ; 6 (add 1 cycle if 'bra' is taken)
        pop     w5                      ; 7 (current bit is J, not 2nd K)
        pop     w4                      ; 8
        bra     __waitK                 ; 9
                                        ; 0
;;-----------------------------------------------------------------------------
__SyncEnd:                              ; 7 (add 1 cycle for 'bra __SyncEnd')
        push    w6                      ; 8 (more register)
        nop                             ; 9 (maximum 12 bytes received, last
        nop                             ; 0  bit of SYNC will be processed)
;;-----------------------------------------------------------------------------
__bit7:                                 ; w1.DP & w0.DP capture the level of DP
        xor     w0, w1, w1              ; 1 (if w1.DP =0, means 'no_switched')
        btst.c  w1, #DP                 ; 2 (move w1.DP into SR.C. it's bit7)
        rlc.b   w5, w5                  ; 3 (then shift this bit into w5)
        btst.c  w5, #0                  ; 4 (move this bit into SR.C again)
        mov     _PORTU, w1              ; 5 (bit0 or a stuff-bit is sampled)
        rrc.b   [w2], [w2++]            ; 6 (gather bit7, w2 =the next byte)
        and.b   w1, #DPDM, w4           ; 7 (terminate the RX loop if this bit
        bra     z, __EOPHit             ; 8  is the 1st SE0 of EOP)
        and.b   w3, w5, w4              ; 9 (is there a 6-b-1 in lsb of w5?)
        bra     z, __unstuff0           ; 0 (add 1 cycle if 'bra z' is taken)
;;-----------------------------------------------------------------------------
__bit0:                                 ; now w0.DP is prev sample of DP
        xor     w0, w1, w0              ; 1 (if w0.DP =0, means 'no_switched')
        btst.c  w0, #DP                 ; 2 (move w0.DP into SR.C. it's bit0)
        rlc.b   w5, w5                  ; 3 (then shift this bit into w5)
        btst.c  w5, #0                  ; 4 (move this bit into SR.C again)
        mov     _PORTU, w0              ; 5 (bit1 or a stuff-bit is sampled)
        rrc.b   [w2], [w2]              ; 6 (gather this bit)
        and.b   w0, #DPDM, w4           ; 7 (terminate the RX loop if this bit
        bra     z, __EOPHit             ; 8  is the 1st SE0 of EOP)
        and.b   w3, w5, w4              ; 9 (is there a 6-b-1 in lsb of w5?)
        bra     z, __unstuff1           ; 0 (add 1 cycle if 'bra z' is taken)
;;-----------------------------------------------------------------------------
__bit1:                                 ; now w1.DP is prev sample of DP
        xor     w0, w1, w1              ; 1 (if w1.DP =0, means 'no_switched')
        btst.c  w1, #DP                 ; 2 (move w1.DP into SR.C)
        rlc.b   w5, w5                  ; 3 (shift bit1 into w5)
        btst.c  w5, #0                  ; 4 (gather this bit if it is not a
        mov     _PORTU, w1              ; 5 (bit2 or a stuff-bit is sampled)
        rrc.b   [w2], [w2]              ; 6  stuff-bit)
        nop                             ; 7
        nop                             ; 8
        and.b   w3, w5, w4              ; 9 (prev D-/D+ is in w0)
        bra     z, __unstuff2           ; 0 (add 1 cycle if 'bra z' is taken)
;;-----------------------------------------------------------------------------
__bit2:
        xor     w0, w1, w0              ; 1 (if w0.DP =0, means 'no_switched')
        btst.c  w0, #DP                 ; 2 (move w0.DP into SR.C)
        rlc.b   w5, w5                  ; 3 (shift bit2 into w5)
        btst.c  w5, #0                  ; 4 (gather this bit if it is not a
        mov     _PORTU, w0              ; 5 (bit3 or a stuff-bit is sampled)
        rrc.b   [w2], [w2]              ; 6  stuff-bit)
        nop                             ; 7
        nop                             ; 8
        and.b   w3, w5, w4              ; 9 (prev D-/D+ is in w1)
        bra     z, __unstuff3           ; 0 (add 1 cycle if 'bra z' is taken)
;;-----------------------------------------------------------------------------
__bit3:
        xor     w0, w1, w1              ; 1 (if w1.DP =0, means 'no_switched')
        btst.c  w1, #DP                 ; 2 (move w1.DP into SR.C)
        rlc.b   w5, w5                  ; 3 (shift bit3 into w5)
        btst.c  w5, #0                  ; 4 (gather this bit if it is not a
        mov     _PORTU, w1              ; 5 (bit4 or a stuff-bit is sampled)
        rrc.b   [w2], [w2]              ; 6  stuff-bit)
        nop                             ; 7
        nop                             ; 8
        and.b   w3, w5, w4              ; 9 (prev D-/D+ is in w0)
        bra     z, __unstuff4           ; 0 (add 1 cycle if 'bra z' is taken)
;;-----------------------------------------------------------------------------
__bit4:
        xor     w0, w1, w0              ; 1 (if w0.DP =0, means 'no_switched')
        btst.c  w0, #DP                 ; 2 (move w0.DP into SR.C)
        rlc.b   w5, w5                  ; 3 (shift bit4 into w5)
        btst.c  w5, #0                  ; 4 (gather this bit if it is not a
        mov     _PORTU, w0              ; 5 (bit5 or a stuff-bit is sampled)
        rrc.b   [w2], [w2]              ; 6  stuff-bit)
        nop                             ; 7
        nop                             ; 8
        and.b   w3, w5, w4              ; 9 (prev D-/D+ is in w1)
        bra     z, __unstuff5           ; 0 (add 1 cycle if 'bra z' is taken)
;;-----------------------------------------------------------------------------
__bit5:
        xor     w0, w1, w1              ; 1 (if w1.DP =0, means 'no_switched')
        btst.c  w1, #DP                 ; 2 (move w1.DP into SR.C)
        rlc.b   w5, w5                  ; 3 (shift bit5 into w5)
        btst.c  w5, #0                  ; 4 (gather this bit if it is not a
        mov     _PORTU, w1              ; 5 (bit6 or a stuff-bit is sampled)
        rrc.b   [w2], [w2]              ; 6  stuff-bit)
        nop                             ; 7
        nop                             ; 8
        and.b   w3, w5, w4              ; 9 (prev D-/D+ is in w0)
        bra     z, __unstuff6           ; 0 (add 1 cycle if 'bra z' is taken)
;;-----------------------------------------------------------------------------
__bit6:
        xor     w0, w1, w0              ; 1 (if w0.0 =DP, means 'no_switched')
        btst.c  w0, #DP                 ; 2 (move w0.DP into SR.C. it's bit6)
        rlc.b   w5, w5                  ; 3 (then shift this bit into w5)
        btst.c  w5, #0                  ; 4 (move this bit into SR.C again)
        mov     _PORTU, w0              ; 5 (bit7 or a stuff-bit is sampled)
        rrc.b   [w2], [w2]              ; 6 (gather this bit)
        and.b   w3, w5, w4              ; 7 (is there a 6-b-1 in lsb of w5?)
        bra     z, __unstuff7           ; 8 (add 1 cycle if 'bra z' is taken)
        bra     __bit7                  ; 9
                                        ; 0
;;-----------------------------------------------------------------------------
__unstuff0:                             ; 1 (+1 cycle for 'bra z,__unstuff0')
        xor     w0, w1, w0              ; 2 (10 cycles of the next-bit)
        btst.c  w0, #DP                 ; 3 (w0.DP should be 1)
        rlc.b   w5, w5                  ; 4 (shift this 1 into w5)
        mov     w1, w0                  ; 5 (discard sample of the stuff-bit)
        mov     _PORTU, w1              ; 6 (sample the next bit)
        and.b   w1, #DPDM, w4           ; 7 (terminate the RX loop if this bit
        bra     z, __EOPHit             ; 8  is the 1st SE0 of EOP)
        bra     __bit0                  ; 9
                                        ; 0
;;-----------------------------------------------------------------------------
__unstuff1:                             ; 1 (+1 cycle for 'bra z,__unstuff1')
        xor     w0, w1, w1              ; 2 (10 cycles of the next-bit)
        btst.c  w1, #DP                 ; 3 (w1.DP should be 1)
        rlc.b   w5, w5                  ; 4 (shift this 1 into w5)
        mov     w0, w1                  ; 5 (discard sample of the stuff-bit)
        mov     _PORTU, w0              ; 6 (sample the next bit)
        and.b   w0, #DPDM, w4           ; 7 (terminate the RX loop if this bit
        bra     z, __EOPHit             ; 8  is the 1st SE0 of EOP)
        bra     __bit1                  ; 9
                                        ; 0
;;-----------------------------------------------------------------------------
__unstuff2:                             ; 1 (+1 cycle for 'bra z,__unstuff2')
        xor     w0, w1, w0              ; 2 (10 cycles of the next-bit)
        btst.c  w0, #DP                 ; 3 (w0.DP should be 1)
        rlc.b   w5, w5                  ; 4 (shift this 1 into w5)
        mov     w1, w0                  ; 5 (discard sample of the stuff-bit)
        mov     _PORTU, w1              ; 6 (sample the next bit)
        nop                             ; 7
        nop                             ; 8
        bra     __bit2                  ; 9
                                        ; 0
;;-----------------------------------------------------------------------------
__unstuff3:                             ; 1 (+1 cycle for 'bra z,__unstuff3')
        xor     w0, w1, w1              ; 2 (10 cycles of the next-bit)
        btst.c  w1, #DP                 ; 3 (w1.DP should be 1)
        rlc.b   w5, w5                  ; 4 (shift this 1 into w5)
        mov     w0, w1                  ; 5 (discard sample of the stuff-bit)
        mov     _PORTU, w0              ; 6 (sample the next bit)
        nop                             ; 7
        nop                             ; 8
        bra     __bit3                  ; 9
                                        ; 0
;;-----------------------------------------------------------------------------
__unstuff4:                             ; 1 (+1 cycle for 'bra z,__unstuff4')
        xor     w0, w1, w0              ; 2 (10 cycles of the next-bit)
        btst.c  w0, #DP                 ; 3 (w0.DP should be 1)
        rlc.b   w5, w5                  ; 4 (shift this 1 into w5)
        mov     w1, w0                  ; 5 (discard sample of the stuff-bit)
        mov     _PORTU, w1              ; 6 (sample the next bit)
        nop                             ; 7
        nop                             ; 8
        bra     __bit4                  ; 9
                                        ; 0
;;-----------------------------------------------------------------------------
__unstuff5:                             ; 1 (+1 cycle for 'bra z,__unstuff5')
        xor     w0, w1, w1              ; 2 (10 cycles of the next-bit)
        btst.c  w1, #DP                 ; 3 (w1.DP should be 1)
        rlc.b   w5, w5                  ; 4 (shift this 1 into w5)
        mov     w0, w1                  ; 5 (discard sample of the stuff-bit)
        mov     _PORTU, w0              ; 6 (sample the next bit)
        nop                             ; 7
        nop                             ; 8
        bra     __bit5                  ; 9
                                        ; 0
;;-----------------------------------------------------------------------------
__unstuff6:                             ; 1 (+1 cycle for 'bra z,__unstuff6')
        xor     w0, w1, w0              ; 2 (10 cycles of the next-bit)
        btst.c  w0, #DP                 ; 3 (w0.DP should be 1)
        rlc.b   w5, w5                  ; 4 (shift this 1 into w5)
        mov     w1, w0                  ; 5 (discard sample of the stuff-bit)
        mov     _PORTU, w1              ; 6 (sample the next bit)
        nop                             ; 7
        nop                             ; 8
        bra     __bit6                  ; 9
                                        ; 0
;;-----------------------------------------------------------------------------
__unstuff7:                             ; 9 (+1 cycle for 'bra z,__unstuff7')
        nop                             ; 0 (stuff-bit cycle ends here)
;;-----------------------------------------------------------------------------
        xor     w0, w1, w1              ; 1 (10 cycles of the next-bit)
        btst.c  w1, #DP                 ; 2 (w1.DP should be 1)
        rlc.b   w5, w5                  ; 3 (shift this 1 into w5)
        mov     w0, w1                  ; 4 (discard sample of the stuff-bit)
        mov     _PORTU, w0              ; 5 (sample the next bit)
        nop                             ; 6
        nop                             ; 7
        nop                             ; 8
        bra     __bit7                  ; 9
                                        ; 0
;;-----------------------------------------------------------------------------
__EOPHit:                               ; 9 (+1 cycle for 'bra    z, __EOPHit')
        mov     _packet, w1             ; 0
;;-----------------------------------------------------------------------------
        nop                             ; 1 (first cycle of 2nd SE0)
        com.b   [++w1], w0              ; 2 (we need to check the PID byte)
        and     w0, #0xF, w0            ; 3 (discard nPID at high nibble)
        bra     w0                      ; 4/5
__BranchTable0:                         ; 6/7
        bra     __PIDError              ; (undefined PID)
        bra     __isOut                 ; PID = 0001 (OUT)
        bra     __isAck                 ; PID = 0010 (ACK)
        bra     __isData0               ; PID = 0011 (DATA0)
        bra     __PIDError              ; (undefined PID)
        bra     __PIDError              ; PID = 0101 (SOF) not supported
        bra     __PIDError              ; (undefined PID)
        bra     __PIDError              ; (undefined PID)
        bra     __PIDError              ; (undefined PID)
        bra     __isIn                  ; PID = 1001 (IN)
        bra     __isNak                 ; PID = 1010 (NAK)
        bra     __isData1               ; PID = 1011 (DATA1)
        bra     __PIDError              ; PID = 1100 (PRE) not supported
        bra     __isSetup               ; PID = 1101 (SETUP)
        bra     __isStall               ; PID = 1110 (STALL)
        bra     __PIDError              ; (undefined  PID)
;;-----------------------------------------------------------------------------
__PIDError:                             ; continue 2nd SE0 of EOP
        bset    __ucontr0, #14          ; 8 (__ucontr0[14] =1 means PID ERROR)
        bra     __CNIntEnd              ; 9
                                        ; 0 (last cycle of 2nd SE0)
;;-----------------------------------------------------------------------------
__isSetup:
        mov     #_token, w0             ; 8 (buffer '_token' will be also used
        mov     WREG, _packet           ; 9  to gather UNRELATED packet)
        com.b   [++w1], w0              ; 0 (fetch the device address byte)
;;-----------------------------------------------------------------------------
        and     #0x7F, w0               ; 1 (first cycle of 1st J-state)
        cp.b    _addr                   ; 2 (device address MUST be matched)
        bra     nz, __CNIntEnd          ; 3 (+1 cycle if address not matched)
        bset    __ucontr0, #13          ; 4 (__ucontr0[13] =1, address matched)
        mov     #_datax, w0             ; 5 (buffer '_datax' will be used to 
        mov     WREG, _packet           ; 6  gather SETUP packet)
        clr.b   __uendpt0               ; 7 (clear the length/toggle/handshake)
        bclr    __ucontr0, #12          ; 8 (__ucontr0[12] =0,DATA1 for IN/OUT)
        bra     __CNIntEnd              ; 9 (__uendpt0[1-0] is 00 now. it will
                                        ; 0  be 01. means a SETUP TOKEN)
;;-----------------------------------------------------------------------------
__isOut:                                ; continue 2nd SE0 of EOP
        mov     #_token, w0             ; 8 (buffer '_token' will be also used
        mov     WREG, _packet           ; 9  to gather UNRELATED packet)
        com.b   [++w1], w0              ; 0 (fetch the device address byte)
;;-----------------------------------------------------------------------------
        and     #0x7F, w0               ; 1 (first cycle of 1st J-state)
        cp.b    _addr                   ; 2 (device address MUST be matched)
        bra     nz, __CNIntEnd          ; 3 (+1 cycle if address not matched)
        bset    __ucontr0, #13          ; 4 (__ucontr0[13] =1, address matched)
        mov     #_datax, w0             ; 5 (buffer '_datax' is used for DATA0)
        btss    __uendpt0, #3           ; 6 (buffer '_datay' is used for DATA1)
        mov     #_datay, w0             ; 7 (use _datay if DATA TOGGLE is 0)
        mov     w0, _packet             ; 8 (prepare to gather the DATA packet)
        bra     __CNIntEnd              ; 9 (__uendpt0[1-0] will be switched to
                                        ; 0  11 when we respond an ACK to the
                                        ;    host)
;;-----------------------------------------------------------------------------
__isData1:                              ; continue 2nd SE0 of EOP
        btss    __ucontr0, #13          ; 8 (device address MUST be matched)
        bra     __CNIntEnd              ; 9 (+1 cycle if address not matched)
        nop                             ; 0 (last cycle of 2nd SE0)
;;-----------------------------------------------------------------------------
        mov     __ucontr0, w3           ; 1 (continue if dev addr is matched)
        and     #0x0C, w3               ; 2 (fetch __ucontr0[3-2])
        mov     #0x03, w0               ; 3 (TOKEN TYPE =11, it is OUT)
        ior     w0, w3, w4              ; 4 (response and TOKEN TYPE in w4)
        cp.b    w3, #0x04               ; 5 (is it an ACK?)
        btsc    _SR, #Z                 ; 6 (not an ACK, skip toggle bit)
        bset    __uendpt0, #3           ; 7 (__uendpt0[3] =1, DATA1)
        mov     #_token+1, w6           ; 8 (w6 points to the PID byte)
        bra     __HandShake             ; 9 (send handshake to the host)
                                        ; 0 (last cycle of 1st J-state)
;;-----------------------------------------------------------------------------
__isData0:                              ; data packet for SETUP or OUT ?
        btss    __ucontr0, #13          ; 8 (device address MUST be matched)
        bra     __CNIntEnd              ; 9 (+1 cycle if address not matched)
        nop                             ; 0 (last cycle of 2nd SE0)
;;-----------------------------------------------------------------------------
        mov     __ucontr0, w3           ; 1 (continue if dev addr is matched)
        and     #0x0C, w3               ; 2 (fetch __ucontr0[3-2])
        mov     #0x03, w0               ; 3 (TOKEN TYPE =11, it is OUT)
        ior     w0, w3, w4              ; 4 (response and TOKEN TYPE in w4)
        btss    __uendpt0, #0           ; 5 (change response and TOKEN TYPE
        mov     #0x05, w4               ; 6  if current token is SETUP)
        cp.b    w3, #0x04               ; 7 (is it an ACK for OUT?)
        btsc    _SR, #Z                 ; 8 (not ACK, skip 'bclr __uendpt0, #3)
        bclr    __uendpt0, #3           ; 9 (clear toggle bit)
        mov     #_token+1, w6           ; 0 (w6 points to the PID byte)
;;-----------------------------------------------------------------------------
__HandShake:                            ; handshake according to w4[3-2]
        sub     w2, w1, w2              ; 1 (1st cycle of 2nd J-state)
        mov     #2, w1                  ; 2 (w1 =2 means 2 bytes will be sent)
        and     w4, #0x0C, w0           ; 3 (w4[3-2] =handshake)
        cp.b    w0, #0x04               ; 4 (is it an ACK? w0[3-0] =0100?)
        btsc    _SR, #Z                 ; 5 (not ACK, skip 'bclr w0, #2')
        bclr    w0, #2                  ; 6 (w0[3-0] =0000 now)
        bset    w0, #1                  ; 7 (this bit is always 1)
__SendBytes:                            ; now w0 =PID, w1 =bytes length
        com     w0, w5                  ; 8 (w5 will be the PID sent to host)
        swap.b  w0                      ; 9 (calclate 4 bits nPID)
        and     #0x0F, w5               ; 0 (last cycle of 2nd J-state)
;;-----------------------------------------------------------------------------
        ior     w0, w5, w5              ; 1 (first cycle of 3rd J-state)
        mov.b   w5, [w6--]              ; 2 (w5 is the PID sent to the host)
        setm.b  [w6]                    ; 3 (w6 points to the SYNC byte)
        bclr.b  [w6], #7                ; 4 (clear bit7 of SYNC, so SYNC =7F)
        dec     w2, [w15++]             ; 5 (w2 -PID, then push into stack)
        bclr    _LATU, #DP              ; 6 (D- =0 and D+ =0, a SE0)
        bclr    _LATU, #DM              ; 7 (they are not sent, _TRISU =1 now)
        push    _LATU                   ; 8 (push a SE0 on the top of stack)
        bset    _LATU, #DM              ; 9 (D- =1 and D+ =0, a J-state)
        mov     #~DPDM, w0              ; 0 (set pins D-/D+ to OUTPUT mode)
;;-----------------------------------------------------------------------------
__Sending:                              ; start to output all signals
        and     _TRISU                  ; 1 (now output a J-state first)
        and     w4, #0x0C, w0           ; 2 (is it an ACK sent to host?)
        cp.b    w0, #0x04               ; 3 (yes, we need to clear the low
        mov     #0xFF08, w0             ; 4  byte of __uendpt0 except bit3)
        btsc    _SR, #Z                 ; 5 (now w6 points to the SYNC byte)
        and     __uendpt0               ; 6 (clear __uendpt0[7-4,2-0])
        mov     #0xFFFF, w5             ; 7 (w5 is initialized for bit-stuff)
        mov     #DPDM, w0               ; 8 (D-/D+ xor w0, make J-K flipping)
        rrc.b   [w6++], w3              ; 9 (fetch the first byte to be sent,
        rlc.b   w5, w5                  ; 0  bit0 is in SR.C, shift it into w5)
;;-----------------------------------------------------------------------------
__bit0_:xor     _LATU                   ; 1 (send bit0, lsb sent first)
        mov     #(__bit1s-__done)/2, w2 ; 2 (return here when __dostuff done)
        and     #0x3F, w5               ; 3 (bit-stuff checking)
        bra     z, __dostuff            ; 4 (w5[5-0] =000000, need a stuff-bit
__bit1s:mov     #DPDM, w0               ; 5
        btss    w3, #0                  ; 6 (if next bit is 1, D-/D+ will not
        mov     #0x0000, w0             ; 7  be switched)
        rrc.b   w3, w3                  ; 8
        rlc.b   w5, w5                  ; 9 (w5[5-0] is for bit-stuff checking)
        mov     #(__bit2s-__done)/2, w2 ; 0 (return here when __dostuff done)
;;-----------------------------------------------------------------------------
__bit1_:xor     _LATU                   ; 1 (send bit1)
        mov     #DPDM, w0               ; 2
        and     #0x3F, w5               ; 3
        bra     z, __dostuff            ; 4
__bit2s:btss    w3, #0                  ; 5
        mov     #0x0000, w0             ; 6
        rrc.b   w3, w3                  ; 7
        rlc.b   w5, w5                  ; 8
        mov     #(__bit3s-__done)/2, w2 ; 9 (return here when __dostuff done)
        nop                             ; 0
;;-----------------------------------------------------------------------------
__bit2_:xor     _LATU                   ; 1 (send bit2)
        mov     #DPDM, w0               ; 2
        and     #0x3F, w5               ; 3
        bra     z, __dostuff            ; 4
__bit3s:btss    w3, #0                  ; 5
        mov     #0x0000, w0             ; 6
        rrc.b   w3, w3                  ; 7
        rlc.b   w5, w5                  ; 8
        mov     #(__bit4s-__done)/2, w2 ; 9 (return here when __dostuff done)
        nop                             ; 0
;;-----------------------------------------------------------------------------
__bit3_:xor     _LATU                   ; 1 (send bit3)
        mov     #DPDM, w0               ; 2
        and     #0x3F, w5               ; 3
        bra     z, __dostuff            ; 4
__bit4s:btss    w3, #0                  ; 5
        mov     #0x0000, w0             ; 6
        rrc.b   w3, w3                  ; 7
        rlc.b   w5, w5                  ; 8
        mov     #(__bit5s-__done)/2, w2 ; 9 (return here when __dostuff done)
        nop                             ; 0
;;-----------------------------------------------------------------------------
__bit4_:xor     _LATU                   ; 1 (send bit4)
        mov     #DPDM, w0               ; 2
        and     #0x3F, w5               ; 3
        bra     z, __dostuff            ; 4
__bit5s:btss    w3, #0                  ; 5
        mov     #0x0000, w0             ; 6
        rrc.b   w3, w3                  ; 7
        rlc.b   w5, w5                  ; 8
        mov     #(__bit6s-__done)/2, w2 ; 9 (return here when __dostuff done)
        nop                             ; 0
;;-----------------------------------------------------------------------------
__bit5_:xor     _LATU                   ; 1 (send bit5)
        mov     #DPDM, w0               ; 2
        and     #0x3F, w5               ; 3
        bra     z, __dostuff            ; 4
__bit6s:btss    w3, #0                  ; 5
        mov     #0x0000, w0             ; 6
        rrc.b   w3, w3                  ; 7
        rlc.b   w5, w5                  ; 8
        mov     #(__bit7s-__done)/2, w2 ; 9 (return here when __dostuff done)
        nop                             ; 0
;;-----------------------------------------------------------------------------
__bit6_:xor     _LATU                   ; 1 (send bit6)
        mov     #DPDM, w0               ; 2
        and     #0x3F, w5               ; 3
        bra     z, __dostuff            ; 4
__bit7s:btss    w3, #0                  ; 5
        mov     #0x0000, w0             ; 6
        rrc.b   w3, w3                  ; 7 (shift last bit of w3 into w5.
        rlc.b   w5, w5                  ; 8  now w3 is empty. we can load next
        mov     #(__bit0s-__done)/2, w2 ; 9
        rrc.b   [w6++], w3              ; 0  byte into w3 and bit0 into SR.C)
;;-----------------------------------------------------------------------------
__bit7_:xor     _LATU                   ; 1 (SR.C will not be affected)
        mov     #DPDM, w0               ; 2 (SR.C will not be affected)
        and     #0x3F, w5               ; 3 (SR.C will not be affected)
        bra     z, __dostuff            ; 4 (SR.C MUST NOT be affected when
__bit0s:btss    SR, #C                  ; 5  __dostuff is executed)
        mov     #0x0000, w0             ; 6 (SR.C will not be affected)
        rlc.b   w5, w5                  ; 7 (shift bit0 of next byte into w5)
        dec     w1, w1                  ; 8 (are all bytes sent?)
        bra     nz, __bit0_             ; 9 (+1 cycle if 'bra nz' is taken)
        and     w4, #0x0C, w0           ; 0 (get the HANDSHAKE to host)
;;-----------------------------------------------------------------------------
__bytes:                                ; all bytes are sent completely
        pop     _LATU                   ; 1 (generate first SE0 on the BUS)
        dec2    [--w15], w2             ; 2 (w2 -CRC, clac real bytes length)
        sl      w2, #4, w2              ; 3 (w2[7-4] =real bytes length)
        ior     w4, w2, w4              ; 4 (w4[1-0] =TOKEN TYPE)
        cp.b    w0, #0x04               ; 5 (w0[3-2] =HANDSHAKE. is it a ACK?)
        mov     w4, w0                  ; 6 (w4[7-4] =real bytes length)
        btsc    _SR, #Z                 ; 7 (not ACK, skip 'bset __uendpt0,#10)
        bset    __uendpt0, #10          ; 8 (set REQUEST flag)
        btsc    _SR, #Z                 ; 9 (not ACK, skip 'ior.b __uendpt0')
        ior.b   __uendpt0               ; 0 (__uendpt0[7-0] has been cleared)
;;-----------------------------------------------------------------------------
__nextSE0:
        mov     #_token, w1             ; 1 (prepare to receive next TOKEN)
        mov     w1, _packet             ; 2
        mov     __ucontr0, w1           ; 3
        mov     #0xD000, w0             ; 4 (device address NOT matched now)
        and     w1, w0, w1              ; 5
        ior     w1, #0xA, w1            ; 6 (NAK to OUT and IN)
        mov     w1, __ucontr0           ; 7
        mov     #DPDM, w0               ; 8 (last cycle of 2nd SE0)
        ior     _TRISU                  ; 9 (D-/D+ are on INPUT mode now)
        bra     __CNIntEnd              ; 0 (+1 cycle for 'bra __CNIntEnd')
;;-----------------------------------------------------------------------------
__dostuff:                              ; 5 (+1 cycle for 'bra z, __dostuff')
        nop                             ; 6 (SR.C MUST NOT be affected)
        nop                             ; 7
        nop                             ; 8 (insert a 1 at w5.0, that means we
        bset    w5, #0                  ; 9  will insert a stuff-bit)
        mov     #DPDM, w0               ; 0 (w0 is #DPDM, make J-K flipping)
;;-----------------------------------------------------------------------------
        xor     _LATU                   ; 1 (generate stuff-bit)
        nop                             ; 2
        bra     w2                      ; 3/4
__done:                                 ; branch to '__done + w2 * 2'
;;-----------------------------------------------------------------------------
__isIn:
        com.b   [++w1], w0              ; 8 (device address byte)
        and     #0x7F, w0               ; 9
        cp.b    _addr                   ; 0 (device address MUST be matched)
;;-----------------------------------------------------------------------------
        bra     nz, __CNIntEnd          ; 1 (+1 cycle if address not matched)
        mov     __ucontr0, w0           ; 2 (check __ucontr0[1-0])
        and     #0x03, w0               ; 3 (w0[1-0] =PID sent to host)
        sl      w0, #2, w4              ; 4 (w4[3-2] =PID on __uendpt0)
        cp.b    w0, #0x01               ; 5 (is it ACK?)
        bra     z, __respond            ; 6 (yes, send DATA packet to host)
        nop                             ; 7
        mov     #_token+1, w6           ; 8 (w6 points to the PID byte)
        bra     __HandShake             ; 9
                                        ; 0 (last cycle of 1st J-state)
;;-----------------------------------------------------------------------------
__respond:                              ; 7 (+1 cycle for 'bra z, __respond')
        ior.b   w4, #2, w4              ; 8 (w4[1-0] =TOKEN TYPE, =10, IN)
        mov.b   #0x03, w0               ; 9 (2nd cycle of 2nd J-state,w0=DATA0)
        btss    __ucontr0, #12          ; 0 (if __ucontr0[12]==0, then set
;;-----------------------------------------------------------------------------
        mov.b   #0x0B, w0               ; 1  w0 =1011, DATA1)
        mov     __ucontr0, w1           ; 2 (__ucontr0[7-4] =bytes length)
        lsr     w1, #4, w1              ; 3
        and     w1, #0xF, w1            ; 4 (w1 =bytes length)
        add     w1, #4, w1              ; 5 (+SYNC, +PID, +CRC16)
        dec     w1, w2                  ; 6 (w2 is for '__uendpt0[7-4]')
        mov     #_datay+1, w6           ; 7 (w6 points to the PID byte)
        repeat  #6                      ; 8/9/0
;;-----------------------------------------------------------------------------
        nop                             ; 1/2/3/4/5
        bra     __SendBytes             ; 6
                                        ; 7
;;-----------------------------------------------------------------------------
__isStall:
        mov     #0x0007, w0             ; 8
        and     __uendpt0, WREG         ; 9 (check __uendpt0[2-0])
        cp      w0, #6                  ; 0 (it MUST be 110, ACK & IN)
;;-----------------------------------------------------------------------------
        bra     nz, __CNIntEnd          ; 1 (no, this STALL is not sent to us)
        nop                             ; 2
        mov     #0x0700, w1             ; 3 (REQUEST FLAG & STALL from host)
        bra     __hostHandShake         ; 4 (w1[9-8] =11, STALL. w1[10] =1, set
                                        ; 5  REQUEST flag)
;;-----------------------------------------------------------------------------
__isAck:
        mov     #0x0007, w0             ; 8
        and     __uendpt0, WREG         ; 9 (check __uendpt0[2-0])
        cp      w0, #6                  ; 0 (it must be 110, ACK & IN)
;;-----------------------------------------------------------------------------
        bra     nz, __CNIntEnd          ; 1 (no, this ACK is not sent to us)
        btg     __ucontr0, #12          ; 2 (switch DATA TOGGLE)
        mov     #0x0500, w1             ; 3 (REQUEST FLAG & ACK from host)
        bra     __hostHandShake         ; 4 (w1[9-8] =01, ACK. w1[10] =1, set
                                        ; 5  REQUEST flag)
;;-----------------------------------------------------------------------------
__isNak:
        mov     #0x0007, w0             ; 8
        and     __uendpt0, WREG         ; 9 (check __uendpt0[2-0])
        cp      w0, #6                  ; 0 (it must be 110, ACK & IN)
;;-----------------------------------------------------------------------------
        bra     nz, __CNIntEnd          ; 1 (no, this NAK is not sent to us)
        nop                             ; 2
        bset    __ucontr0, #0           ; 3 (set an ACK to next IN token, then
        bclr    __ucontr0, #1           ; 4  DATA packet will be resent)
        mov     #0x0600, w1             ; 5 (REQUEST FLAG & NAK from host)
;;-----------------------------------------------------------------------------
__hostHandShake:                        ; +1 cycle for 'bra __hostHandShake'
        mov     #0xF8FF, w0             ; 6
        and     __uendpt0               ; 7
        mov     w1, w0                  ; 8
        ior     __uendpt0               ; 9
;;-----------------------------------------------------------------------------
__CNIntEnd:                             ; 8 cycles total
        pop     w6                      ;
        pop     w5                      ;
        pop     w4                      ;
__IRQExit:                              ; 5 cycles total
        bclr    _IFS1, #CNIF            ;
        pop.s                           ;
        retfie                          ;
;;-----------------------------------------------------------------------------
__CRC16:                                ; w0 =buffer, w1 =bytes length
        mov     #0xFFFF, w5             ; initial value
        mov     #_datay+2, w3           ; copy the data from buffer to _datay
        cp0.b   w1                      ; zero length?
        bra     z, __CRCEnd             ; yes, only CRC
        mov     #0xA001, w4
__CRCbytes:
        mov.b   [w0++], w6              ; fetch a byte
        com.b   w6, [w3++]              ; copy this byte into _datay
        mov     #8, w2                  ; 8 bits
__CRCbits:
        xor.b   w5, w6, w7              ; lsb (w7.0) is a flag
        lsr     w5, w5
        btsc    w7, #0
        xor     w5, w4, w5
        rrnc.b  w6, w6
        dec     w2, w2
        bra     nz, __CRCbits
        dec     w1, w1
        bra     nz, __CRCbytes
__CRCEnd:
        mov.b   w5, [w3++]
        swap    w5
        mov.b   w5, [w3++]
        return
;;-----------------------------------------------------------------------------
; APIs for application

        .global __usbGetSetup
        .global __usbLoadData
        .global __usbReadData
        .global __usbSendZLP
        .global __usbWaitZLP
        .global __usbSetAddress
        .global __usbSetConfig

__usbGetSetup:                          ; w0 =output buffer.
        cp0     w0
        bra     z, __GetSetupExit
        push    w0
        mov     #0x04FF, w0
        and     __uendpt0, WREG
        mov     #0x0485, w1
        cp      w0, w1
        pop     w0
        bra     nz, __GetSetupExit
        mov     #_datax+2, w1
        mov     #8, w2
__GetSetupLoop:
        com.b   [w1++], [w0++]          ; w0 is allowed to point to odd address
        dec     w2, w2
        bra     nz, __GetSetupLoop
        mov     #0xF808, w0             ; clear '__uendpt0[1-0]', next 'OUT'+
        and     __uendpt0               ; 'DATA1' will set it to '11'
        mov     #8, w0
        return
__GetSetupExit:
        mov     #0, w0
        return
;;-----------------------------------------------------------------------------
__usbSendZLP:
        bclr    __ucontr0, #12          ; must send a DATA1 packet
        mov     #0, w0
        mov     #0, w1
__usbLoadData:                          ; w0 =output buffer, w1 =bytes length
        bclr    __uendpt0, #10          ; clear REQUEST FLAG
        bclr    __uendpt0, #2           ; clear response bit
        mov     __ucontr0, w2           ; __ucontr0[7-4] =bytes length
        and.b   #0xC, w2                ; clear bytes length and NAK
        and     w1, #0xF, w1            ; w1[3-0] =bytes length
        sl      w1, #4, w3
        ior.b   w3, w2, w2
        ior.b   #0x01, w2               ; ACK to IN request
        push    w2
        rcall   __CRC16                 ; copy data and CRC into datax
        pop     __ucontr0
        mov     #0x0506, w1
__waitA:
        mov     #0x0707, w0             ; __uendpt0[10-8] & __uendpt0[2-0]
        and     __uendpt0, WREG
        cp      w1, w0
        bra     nz, __waitA

        mov     #0xF8F8, w0
        and     __uendpt0
        return
;;-----------------------------------------------------------------------------
__usbWaitZLP:
        mov     #0, w0
        mov     #0, w1
__usbReadData:                          ; w0 =input buffer, w1 =bytes length
        cp0     w0
        bra     nz, __valid
        cp0     w1
        bra     nz, __invalid
__valid:
        push    w0
        bclr    __uendpt0, #10          ; DO NOT modify '__uendpt0[1-0]' accidentally
        bclr    __uendpt0, #2           ; this 2 bits are useful when we receive 'DATA0'
        mov.b   __ucontr0, WREG
        bclr    w0, #3
        bset    w0, #2                  ; __ucontr0[3-2] =01, means ACK to OUT
        mov.b   WREG, __ucontr0         ; DO NOT modify '__ucontr0[13]' accidentally!!!
        mov     #0x0407, w2             ; __uendpt0[10] =1 & __uendpt0[2-0] =111
__waitU:
        mov     #0x0407, w0
        and     __uendpt0, WREG
        cp      w0, w2
        bra     nz, __waitU

        mov     __uendpt0, w2
        lsr     w2, #4, w2
        and     #0xF, w2                ; bytes length from host
        cp      w2, w1
        bra     GEU, __unload
        mov     w2, w1
__unload:
        pop     w0
        mov     #_datax+2, w2           ; DATA0 or DATA1?
        btsc    __uendpt0, #3           ; __uendpt0[3]==0, means DATA0
        mov     #_datay+2, w2
        push    w1
__UnloadLoop:
        cp0     w1
        bra     z, __UnloadEnd
        com.b   [w2++], [w0++]
        dec     w1, w1
        bra     __UnloadLoop
__UnloadEnd:
        pop     w0                      ; bytes length return to caller
        return                          ; it can be zero
__invalid:
        setm    w0
        return
;;-----------------------------------------------------------------------------
__usbSetAddress:                        ; w0[7-0] =Device Address
        push    w0
        rcall   __usbSendZLP
        pop     _addr                   ; store the new address
        return
;;-----------------------------------------------------------------------------
__usbSetConfig:                         ; w0[7-0] =Configuration Value
        mov.b   WREG, _conf
        bra     __usbSendZLP
;;-----------------------------------------------------------------------------

        .extern __dbg_init
        .global __user_init

__user_init:
        ; initialize PLL, Fpllout = 30MHz, Fcy = 15MHz
        ;mov     #28, w0                 ; PLLDIV=30 for 8MHz crystal
        ;mov     w0, PLLFBD              ; please refer to DS70186A-page-7-12
        ;mov     #0x40, w0               ; PLLPRE=2, PLLPOST=4
        ;mov     w0, CLKDIV              ; please refer to DS70186A-page-7-11

        ; initialize OSCCON for clock switching. please refer to
        ; DS70186A-page-7-27 and DS70186A-page-7-9.
        ;mov     #3, w2                  ; set OSCCON<NOSC> to 011
        ;mov     #120, w1                ; unlock sequence. DS70186A-page-7-29
        ;mov     #154, w0                ; we don't use __builtin_write_OSCCONH
        ;mov     #OSCCONH, w3
        ;mov.b   w1, [w3]
        ;mov.b   w0, [w3]
        ;mov.b   w2, [w3]

        ;mov     #1, w2                  ; set OSCCON<OSWEN>, start switching
        ;mov     #70, w1                 ; unlock sequence
        ;mov     #87, w0
        ;mov     #OSCCONL, w3
        ;mov.b   w1, [w3]
        ;mov.b   w0, [w3]
        ;mov.b   w2, [w3]

wait_lock:                              ; waiting for the PLL locked
        ;btst    OSCCON, #LOCK
        ;bra     z, wait_lock

wait_switching:                         ; waiting for clock switching done
        ;btst    OSCCON, #OSWEN
        ;bra     nz, wait_switching

        ; disable all analog input and OD output
        ; please refer to DS39927C-page-114
        mov     #0x000f, w0
        mov     w0, AD1PCFGL
        mov     #0, w0
        mov     w0, ODCB

wait_attached:
        mov.b   _PORTU, WREG
        and     #DPDM, w0               ; usb host D+/D- was pulled down by
        bra     nz, wait_attached       ; two 15k resistors

        ; enable 1.5k pullup resistor on D-.
        ; if you connect 1.5k pullup resistor to 3.3V directly, please
        ; omit next 2 instructions (bclr/bset).
        bclr    TRISB, #4
        bset    PORTB, #4

        mov     #(1<<DM), w1
waitJ:  ; waiting until D-(RA1)=1 & D+(RA0)=0
        mov     _PORTU, w0
        and     #DPDM, w0
        cp      w0, w1
        bra     nz, waitJ

        ; initialize some global varibles
        mov     #_token, w0
        mov     w0, _packet             ; prepare to receive first token
        mov     #0, w0
        mov.b   WREG, _addr             ; usb device address is zero
        mov     WREG, __uendpt0
        mov     #0x000A, w0             ; __ucontr0[1-0] =10, NAK to IN token
        mov     WREG, __ucontr0         ; __ucontr0[3-2] =10, NAK to OUT token

        ; enable interrupt of CN3 (D-/RA1)
        bclr    IFS1, #CNIF
        bset    CNEN1, #CN3IE
        bset    IEC1, #CNIE

        ; initialize DEBUG func
        rcall   __dbg_init
        rcall   __dbg_led_on

        return

;;-----------------------------------------------------------------------------
; main task

        .extern _setup
        .extern _loop
        .global _main

_main:
        rcall   _setup

_taskloop:
        rcall   _loop
        bra     _taskloop

        .end
