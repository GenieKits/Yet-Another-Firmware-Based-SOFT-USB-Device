# Yet Another Firmware Based SOFT USB Device
 This project is similar as V-USB. I use a dsPIC33 MCU to implement a low speed USB device. Two GPIO pins are used to capture the signals of USB and all signals are decoded by the firmware.

----

### Schematic ###

![image](https://github.com/Geniekits/Yet-Another-Firmware-Based-SOFT-USB-Device/raw/master/Docs/Images/ya-vusb-sch.png)

The major controller IC1 is dsPIC33FJ12MC201. This chip provides small SSOP package with 20 pins and 40MIPS maximum running speed. I use two pins (RA0/RA1) of GPIO-A to capture the level of USB D+/D-. Because the "Change Notification" interrupt can be triggered by RA0 or RA1 directly, we don't have to use the INT0 pin. We MUST connect USB D+/D- to two pins within one GPIO group. It's not allowed to connect D+ to RAx and D- to RBx. The pull-up resistor R7 on USB D- is NOT connected to 3.3v directly. I use RB4 to control this pull-up resistor. There is a LED connected to RB15. I will send some data through USB port to control this LED. MCLR/PGC1/PGD1 are used as an ICSP port. We can use some burner, such as PICKit3, to program the chip through it. RB7 is connected to the PIN6 of ICSP connector J2. It is used to send some  debugging messages when we need to. The PIN6 of ICSP port has been used as the LVP signal of PICKit3. Because I have never used PICKit3, I don't know if this connection (RB7 to PIN6 of ICSP) will make PICKit3 fail or not. There is a NPN transistor T1 which is used as a 3.3V power regulator. On my experimental board it is replaced by an AMS1117-33. I think it will work if you try to connect a red LED at VBUS in series instead of transistor T1, reducing the +5V to 3.2V. The resistor R4 could be replaced by a solder bridge. If you want to use PIC24F16KA101 to instead dsPIC33FJ12MC201, you can just omit R4 and C3 and replace X1 with a 30MHz crystal.

----

### Coding Environment ###

This project is implemented and tested on WINDOWS platform. I use the XC16 compiler suit version 1.25 which is developed by Microchip. Unless the compiler I don't use any integrated development environment (MPLAB IDE) and debug probe (ICD4 or PICKit). I haven’t bought any commercial license as well. Without commercial license the GCC compiler only supports -O1 level optimization. It's enough for this project. The program running on the host for testing are coded and compiled with Microsoft Visual Studio 2008.

----

### Known BUG ###

When the device is plugged into an USB HUB, the communication fails occasionally when the host sends data to the device. The frequency of failure is related to the data sent by the host. Specifically if the host sends random data to the device repeatedly, the frequency of failure is very low. If the host sends all bytes with same value, such as 64 bytes 0xFF, the frequency of failure is higher. This bug is triggered only when the device is connected to a HUB. It's never been triggered when the device is connected to the host directly.

----

### Details of Source Codes ###

Please read the PDF files in the folder [/Docs](https://github.com/GenieKits/Yet-Another-Firmware-Based-SOFT-USB-Device/tree/master/Docs) or visit [my website](http://wiki.geniekits.com/doku.php?id=usb_express:ya-vusb) .



