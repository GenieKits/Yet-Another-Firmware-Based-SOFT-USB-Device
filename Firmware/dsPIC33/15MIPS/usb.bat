xc16-gcc -mcpu=33FJ12MC201 -O1 main.c hid.c usb.c sie.s dbg.s -o main.elf -T p33FJ12MC201.gld -Wl,--defsym,__has_user_init=1,-Map=main.map
xc16-bin2hex main.elf
xc16-objdump -D main.elf >main.txt
pause
