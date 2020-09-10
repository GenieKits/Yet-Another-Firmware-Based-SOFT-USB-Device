xc16-gcc -mcpu=24F16KA101 -O1 main.c hid.c usb.c sie.s dbg.s -o main.elf -T p24F16KA101.gld -Wl,--defsym,__has_user_init=1,-Map=main.map
xc16-bin2hex main.elf
xc16-objdump -D main.elf >main.txt
pause
