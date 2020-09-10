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
 * Title:        hid.c HID requests processing.
 *
 *---------------------------------------------------------------------------*/
#include "main.h"

static BYTE State;
#define RESPONSE			0
#define COMMAND				1

static BYTE RequestPkt[64];
static BYTE FeatureRpt[64];

void HID_vInit(BYTE Mode)
{
    BYTE i;

    /* driver initialization */
    USB_vInit();

    /* vars initialization */
    State = COMMAND;
    for (i=0; i<sizeof(FeatureRpt); i++)
    {
        FeatureRpt[i] = 0;
    }
}

BYTE HID_bRxRequest(void *Req, WORD siz)
{
    BYTE ret;
    WORD len,rxl;
    DWORD adr;

    if (Req != NULL && siz == 2)
    {
        *((BYTE*)Req+0) = 0;
        *((BYTE*)Req+1) = 0;
    }

    /* get 8 bytes of SETUP */
    ret = USB_bRxRequest(RequestPkt);

    switch(ret)
    {
    case USB_REQ_SETUP:
        /*---------------------------------------------------------------------
        ** data length in the SETUP packet.
        **-------------------------------------------------------------------*/
        len = RequestPkt[7]*256+RequestPkt[6];

        if (RequestPkt[0] == 0xA1 && RequestPkt[1] == 0x01)
        {
            if (RequestPkt[3] == 0x03)	/* HidD_GetFeature() */
            {
                if (State != RESPONSE)
                {
                    /*---------------------------------------------------------
                    ** there isn't any data to be sent to the host.
                    ** here we just send a zero length packet to the host.
                    ** a simple protocol could be defined here instead of zlp.
                    **-------------------------------------------------------*/
                    USB_bSendCtrlData(FeatureRpt, 0, len);
                }
                else
                {
                    USB_bSendCtrlData(FeatureRpt, 64, len);
                }

                State = COMMAND;
            }
            else
            if (RequestPkt[3] == 0x01)	/* HidD_GetInputReport() */
            {
                USB_bSendCtrlData(FeatureRpt, 64, len);
            }
            else
            {
                /*-------------------------------------------------------------
                ** DEBUG Code if needed
                **-----------------------------------------------------------*/
            }
            break;
        }
        else
        if (RequestPkt[0] == 0x21 && RequestPkt[1] == 0x09)
        {
            if (RequestPkt[3] == 0x03)	// HidD_SetFeature
            {
                State = COMMAND;
                if ((rxl=USB_bGetCtrlData(RequestPkt, 64, len)) == len)
                {
                    /*---------------------------------------------------------
                    ** if you transmit secret data, decipher it here.
                    **-------------------------------------------------------*/
                    while(rxl)
                    {
                        rxl--;
                        FeatureRpt[rxl] = RequestPkt[rxl] ^ 0xFF;
                    }
                    if (Req != NULL && siz == 2)
                    {
                        *((BYTE*)Req+0) = RequestPkt[0];
                        *((BYTE*)Req+1) = RequestPkt[1];
                        return 1;
                    }
                    State = RESPONSE;
                }
                else
                {
                    /*---------------------------------------------------------
                    ** DEBUG Code if needed
                    **-------------------------------------------------------*/
                }
            }
            else
            if (RequestPkt[3] == 0x02)	/* HidD_SetOutputReport() */
            {
                if ((rxl=USB_bGetCtrlData(FeatureRpt, 64, len)) == len)
                {
                    State = RESPONSE;
                }
            }
            else
            {
                /*-------------------------------------------------------------
                ** DEBUG Code if needed
                **-----------------------------------------------------------*/
            }
            break;
        }
        else
        if (RequestPkt[0] == 0x21 && RequestPkt[1] == 0x0A)
        {
            /*-----------------------------------------------------------------
            ** just send a STATUS packet
            **---------------------------------------------------------------*/
            USB_bSendCtrlData(NULL, 0, 0);
            break;
        }
        else
        {
            /*-----------------------------------------------------------------
            ** DEBUG Code if needed
            **---------------------------------------------------------------*/
        }
        break;

    case USB_REQ_INTRO:
        break;

    default:
        /*---------------------------------------------------------------------
        ** DEBUG Code iff needed
        **-------------------------------------------------------------------*/
        break;
    }

    return 0;
}

BYTE HID_bTxResult(void *dat, WORD siz)
{
    State = RESPONSE;
    return 1;
}
