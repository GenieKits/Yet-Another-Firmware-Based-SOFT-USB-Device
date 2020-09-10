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
;; Title:        dbg.s Send messages via UART for debugging.
;;
;;-----------------------------------------------------------------------------
.equ    __33FJ12MC201, 1
.include "p33FJ12MC201.inc"

        .bss
_bytes: .space  2
_start: .space  1

        .text
        .global __dbg_init

__dbg_init:
        bclr    TRISB, #7
        bset    PORTB, #7               ; RB7 is TxD, gen a high level
        bclr    TRISB, #15              ; RB15 drives the LED
        bset    PORTB, #15              ; LED off

        ; allocate pins for UART1
        mov     #OSCCONL, w1
        mov     #0x45, w2
        mov     #0x67, w3
        mov.b   w2, [w1]
        mov.b   w3, [w1]
        bclr    OSCCON, #IOLOCK

        mov     #0x0300, w0
        mov     w0, RPOR3               ; U1TX=RP7
        mov     #14, w0
        mov     w0, RPINR18             ; U1RX=RP14

        mov.b   w2, [w1]
        mov.b   w3, [w1]
        bset    OSCCON, #IOLOCK

        ; initialize UART
        mov     #7, w0                  ; 115200 @ 15MIPS, BRGH=0
        mov     w0, U1BRG
        bset    U1MODE, #UARTEN
        bset    U1STA, #UTXEN

        ; waiting for the U1TX pin to be driven to HIGH
        repeat  #4160                   ; 104uS (1/9600 S)
        nop

        clr.b   _start

        return

;;-----------------------------------------------------------------------------
        .global __dbg_led_on

__dbg_led_on:
        bclr    PORTB, #15
        return

        .global __dbg_send_bytes

__dbg_send_bytes:
        mov     WREG, _bytes
        bset    _start, #1
        rcall   __dbg_loop
        return

        .global __dbg_die

__dbg_die:
        bclr    PORTB, #15
        mov     #64, w0
        rcall   __dbg_delay
        bset    PORTB, #15
        mov     #64, w0
        rcall   __dbg_delay
        bra     __dbg_die

        .global __dbg_delay

__dbg_delay:
        repeat  #16383
        nop
        dec     w0, w0
        bra     nz, __dbg_delay
        return
;;-----------------------------------------------------------------------------
        .global __dbg_loop

__dbg_loop:
        push    w0
        push    w1

        cp0.b   _start
        bra     z, __dbg_loop_end

        clr.b   _start
        mov     #_bytes, w0
        mov     #U1TXREG, w1

        ; check if transmit buffer is full, if so
        ;  wait before adding next character
_wait0: btst    U1STA, #UTXBF
        bra     nz, _wait0

        ; transmit the character
        mov.b   [w0++],[w1]

        ; check if transmit buffer is full, if so
        ;  wait before adding next character
_wait1: btst    U1STA, #UTXBF
        bra     nz, _wait1

        ; transmit the character
        mov.b   [w0++],[w1]

        ; wait for transmit buffer to be empty
__dbg_send_end:
        btst    U1STA, #TRMT
        bra     z, __dbg_send_end

__dbg_loop_end:
        pop     w1
        pop     w0
        return
;;-----------------------------------------------------------------------------
        .global __DefaultInterrupt

__DefaultInterrupt:
        bra     __dbg_die

        .end
