/* ----------------------------------------------------------------------------
 * Copyright (C) 2019-2020 Zach Lee.
 *
 * Licensed under the MIT License, you may not use this file except in
 * compliance with the License.
 *
 * MIT License:
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 *
 * ----------------------------------------------------------------------------
 *
 * $Date:        11. May 2020
 * $Revision:    V0.0.0
 *
 * Project:      Yet Another Firmware Based USB on Microchip dsPIC33
 * Title:        usb.c USB control transmission driver and standard
 *                     request handler.
 *
 *---------------------------------------------------------------------------*/
 #include "main.h"

/*-----------------------------------------------------------------------------
** HID REPORT descriptor
**---------------------------------------------------------------------------*/
const BYTE HID_ReportDescriptor[] =
{
    /*  ------------------  ||  ---------------------------------------------*/
    0x06,0x00,0xFF,         /*  Usage Page (vendor defined) ($FF00) global   */
    0x09,0x01,              /*  Usage (vendor defined) ($01) local           */
    0xA1,0x01,              /*   Collection (Application)                    */
    0x75,0x08,              /*    REPORT_SIZE (8)                            */
    0x95,0x40,              /*    REPORT_COUNT (64 fields, 64 bytes)         */

    /* Feature Report                                                        */
    0x09,0x01,              /*    USAGE (Vendor Usage 1)                     */
    0xB1,0x02,              /*    Feature(data,var,absolute)                 */
    /* Input Report                                                          */
    0x09,0x01,              /*    USAGE (Vendor Usage 1)                     */
    0x81,0x02,              /*    Input(data,var,absolute)                   */
    /* Output Report                                                         */
    0x09,0x01,              /*    USAGE (Vendor Usage 1)                     */
    0x91,0x02,              /*    Output(data,var,absolute)                  */

    0xC0                    /*   Application Collection End                  */
    /*  ------------------  ||  ---------------------------------------------*/
};

const static BYTE USB_DeviceDescriptor[] =
{
    0x12,                           /* bDescriptorLen                        */
    0x01,                           /* bDescriptorType                       */
    0x10,                           /* bcdUSBVersionL                        */
    0x01,                           /* bcdUSBVersionH                        */
    0x00,                           /* bDeviceClass                          */
    0x00,                           /* bDeviceSubclass                       */
    0x00,                           /* bDeviceProtocol                       */
    ENDPOINT0_SIZE,                 /* ENDPOINT0_SIZE = 8                    */
    0x6E,                           /* idVendorL (use your own vid&pid)      */
    0x09,                           /* idVendorH                             */
    0x00,                           /* idProductL                            */
    0x01,                           /* idProductH                            */
    0x00,                           /* bcdDeviceL                            */
    0x01,                           /* bcdDeviceH                            */
    0x01,                           /* ManufacturerStringIndex               */
    0x02,                           /* ProductStringIndex                    */
    0x00,                           /* SerialNumberStringIndex               */
    0x01                            /* bNumConfigs                           */
};

const static BYTE USB_ConfigureDescriptor[] =
{
    /* CONFIGURATION descriptor                                              */
    0x09,                           /* CbLength                              */
    0x02,                           /* CbDescriptorType                      */
    0x1B,                           /* CwTotalLengthL                        */
    0x00,                           /* CwTotalLengthH                        */
    0x01,                           /* CbNumInterfaces                       */
    0x01,                           /* CbConfigurationValue                  */
    0x04,                           /* CiConfiguration                       */
    0x80,                           /* CbmAttributes                         */
    0x10,                           /* CMaxPower                             */
    /* INTERFACE descriptor                                                  */
    0x09,                           /* IbLength                              */
    0x04,                           /* IbDescriptorType                      */
    0x00,                           /* IbInterfaceNumber                     */
    0x00,                           /* IbAlternateSetting                    */
    0x00,                           /* IbNumEndpoints                        */
    0x03,                           /* IbInterfaceClass (HID device)         */
    0x00,                           /* IbInterfaceSubclass                   */
    0x00,                           /* IbInterfaceProtocol                   */
    0x05,                           /* IiInterface                           */
    /* HID CLASS descriptor                                                  */
    0x09,                           /* HbLength                              */
    0x21,                           /* HbDescriptorType                      */
    0x10,                           /* HbcdHIDVersionL                       */
    0x01,                           /* HbcdHIDVersionH                       */
    0x00,                           /* HbCountryCode                         */
    0x01,                           /* HbNumOfClassDesc                      */
    0x22,                           /* HbClassDescType (HID REPORT desc)     */
    sizeof(HID_ReportDescriptor),   /* HwReportDescLengthL                   */
    0x00                            /* HwReportDescLengthH                   */
};

const BYTE USB_StringDescriptorI[] =
{
    0x04,
    0x03,
    0x09,
    0x04
};

const BYTE USB_StringDescriptorV[] =
{
    0x0C,
    0x03,
    'G', 0x00,
    'e', 0x00,
    'n', 0x00,
    'i', 0x00,
    'e', 0x00
};

const BYTE USB_StringDescriptorP[] =
{
    0x0A,
    0x03,
    'V', 0x00,
    'U', 0x00,
    'S', 0x00,
    'B', 0x00
};

void USB_vInit(void)
{
    /*-------------------------------------------------------------------------
    ** your own initialization code goes here
    **-----------------------------------------------------------------------*/
}

BYTE USB_bRxRequest(void* Request)
{
    BYTE ret = USB_REQ_IGNOR;
    BYTE* setup = (BYTE*)Request;
    BYTE* desc;
    WORD exLength,txLength;

    /* invoke API func in sie.s */
    if (_usbGetSetup(setup) == ENDPOINT0_SIZE)
    {
        switch(setup[1])
        {
        case 0x06:  /* Get Descriptor */
            /*-----------------------------------------------------------------
            ** data length in the SETUP packet.
            **---------------------------------------------------------------*/
            exLength = (((WORD)setup[7] << 8) | (WORD)setup[6]);

            if (setup[3]==0x01) /* Devcie Descriptor */
            {
                desc = (BYTE*)USB_DeviceDescriptor;
                txLength = sizeof(USB_DeviceDescriptor);
            }
            else
            if (setup[3]==0x02) /* Configure Descriptor */
            {
                desc = (BYTE*)USB_ConfigureDescriptor;
                txLength = sizeof(USB_ConfigureDescriptor);
            }
            else
            if (setup[3]==0x03) /* String Descriptor */
            {
                if (setup[2]==USB_DeviceDescriptor[14])
                {
                    desc = (BYTE*)USB_StringDescriptorV;
                    txLength = sizeof(USB_StringDescriptorV);
                }
                else
                if (setup[2]==USB_DeviceDescriptor[15])
                {
                    desc = (BYTE*)USB_StringDescriptorP;
                    txLength = sizeof(USB_StringDescriptorP);
                }
                else
                {
                    desc = (BYTE*)USB_StringDescriptorI;
                    txLength = sizeof(USB_StringDescriptorI);
                }
            }
            else
            if (setup[3]==0x22) /* HID Report Descriptor */
            {
                desc = (BYTE*)HID_ReportDescriptor;
                txLength = sizeof(HID_ReportDescriptor);
            }
            else
            {
                desc = NULL; txLength = 0;
            }

            USB_bSendCtrlData(desc, txLength, exLength);
            break;
        case 0x05:  /* Set Address */
            _usbSetAddress(setup[2]);
            break;
        case 0x09:  /* Set Configuration or HID Set Report */
            if (setup[0] == 0)
            {
                _usbSetConfig(setup[2]);
            }
            else
            {
                /* 21 09 00 00 00 00 40 00 */
                ret = USB_REQ_SETUP;
            }
            break;
        case 0x0A:  /* HID Set Idle: 21 0A 00 00 00 00 00 00 */
        case 0x01:  /* Clear Feature or HID Get Report */
            /* A1 01 00 00 00 00 40 00 */
            ret = USB_REQ_SETUP;
            break;
        default:
            ret = USB_REQ_DEBUG;  /* Just for debugging */
            break;
        }
    }

    /* default value of ret is "USB_REQ_IGNOR" */
    return ret;
}

BYTE USB_bGetCtrlData(BYTE * dat, WORD siz, WORD exLength)
{
    BYTE* ptr = dat, total = 0, rlen;
    WORD rxLength;

    /*-------------------------------------------------------------------------
    ** 'exLength' is the data length in the SETUP packet. 'siz' is the length
    ** of 'dat'.
    **-----------------------------------------------------------------------*/
    rxLength = siz <= exLength? siz:exLength;

    while(rxLength >= ENDPOINT0_SIZE)
    {
        rlen = _usbReadData(ptr, ENDPOINT0_SIZE);
        if (rlen < ENDPOINT0_SIZE)
        {
            /* send a zlp via 'DATA1'. STATUS stage of control write */
            _usbSendZLP();
            total += rlen;
            return total;
        }
        ptr += ENDPOINT0_SIZE; rxLength -= ENDPOINT0_SIZE;
        total += ENDPOINT0_SIZE;
    }
    if (rxLength > 0)
    {
        rlen = _usbReadData(ptr, rxLength);
        total += rlen <= rxLength? rlen:rxLength;
    }

    _usbSendZLP();

    return total;
}

BYTE USB_bSendCtrlData(BYTE* dat, WORD siz, WORD exLength)
{
    BYTE* ptr = dat, zlp;
    WORD txLength;

    /*-------------------------------------------------------------------------
    ** 'exLength' is the data length in the SETUP packet. 'siz' is the length
    ** of data stored in 'dat'.
    **-----------------------------------------------------------------------*/
    if (siz == 0 && exLength == 0)
    {
        _usbSendZLP();
        return 0;
    }

    if (siz < exLength)
    {
        /*---------------------------------------------------------------------
        ** here zlp=1 means send a ZERO LENGTH packet via 'DATA0' or 'DATA1'
        ** to terminate current transmission. it doesn't mean the STATUS stage
        ** of control write.
        **-------------------------------------------------------------------*/
        zlp = (siz&(ENDPOINT0_SIZE-1))==0? 1:0;
        txLength = siz;
    }
    else
    {
        zlp = 0;
        txLength = exLength;
    }

    while(txLength >= ENDPOINT0_SIZE)
    {
        _usbLoadData(ptr, ENDPOINT0_SIZE);
        ptr += ENDPOINT0_SIZE; txLength -= ENDPOINT0_SIZE;
    }
    if (txLength > 0)
    {
        _usbLoadData(ptr, txLength);
    }
    if (zlp)
    {
        _usbLoadData(NULL, 0);
    }

    /* STATUS stage of control read */
    _usbWaitZLP();

    return (BYTE)txLength;
}
