#include <windows.h>
#include <setupapi.h>
#include <stdio.h>
#include <tchar.h>

#include "hidsdi.h"

#define USB_NO_DEVICE_CLASS             0x00000000
#define USB_SPECIFIC_DEVICE_NOT_FOUND   0x00000001
#define USB_SPECIFIC_DEVICE_EXIST       0x00000002
#define USB_UNKNOWN_ERROR               0x000000FF

static int CheckDeviceCapabilities(HANDLE DeviceHandle)
{
  PHIDP_PREPARSED_DATA  preparsedData;
  HIDP_CAPS capabilities;
  int retcode;

  if (HidD_GetPreparsedData(DeviceHandle, &preparsedData) == 0)
  {
    return(-1);
  }

  if (HidP_GetCaps(preparsedData, &capabilities) == 0)
  {
    retcode = -1;
  }
  else
  if (capabilities.FeatureReportByteLength != 0x0041 ||
      capabilities.InputReportByteLength != 0x41 ||
      capabilities.OutputReportByteLength != 0x41)
  {
    retcode = -1;
  }
  else
  {
    retcode = 0;
  }

  if (HidD_FreePreparsedData(preparsedData) == 0)
  {
    retcode = -1;
  }

  return(retcode);
}

static int GetHidDeviceContext(int index,short idVendor,short idProduct,TCHAR *vdrName,TCHAR *devName,TCHAR *devPath)
{
  GUID Guid;
  HANDLE hDevInfo, hDevice;
  SP_DEVICE_INTERFACE_DATA devInfoData;
  PSP_DEVICE_INTERFACE_DETAIL_DATA detailData = NULL;
  HIDD_ATTRIBUTES Attributes;
  int   retcode = 0;
  DWORD length = 0, required;
  char  buffer[256];

  vdrName[0] = devName[0] = devPath[0] = 0;

  HidD_GetHidGuid(&Guid);

  hDevInfo = SetupDiGetClassDevs(&Guid,NULL,NULL,DIGCF_PRESENT|DIGCF_INTERFACEDEVICE);
  if (hDevInfo == INVALID_HANDLE_VALUE)
  {
    return USB_NO_DEVICE_CLASS;
  }

  devInfoData.cbSize = sizeof(devInfoData);

  if (SetupDiEnumDeviceInterfaces(hDevInfo,0,&Guid,index,&devInfoData) == 0)
  {
    return USB_SPECIFIC_DEVICE_NOT_FOUND;
  }

  SetupDiGetDeviceInterfaceDetail(hDevInfo,&devInfoData,NULL,0,&length,NULL);

  if (length > sizeof(buffer))
  {
    SetupDiDestroyDeviceInfoList(hDevInfo);
    return USB_UNKNOWN_ERROR;
  }

  memset(buffer,0,sizeof(buffer));
  detailData = (PSP_DEVICE_INTERFACE_DETAIL_DATA)buffer;
  detailData->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA);
  if (SetupDiGetDeviceInterfaceDetail(hDevInfo,&devInfoData,detailData,length,&required,NULL) == 0)
  {
    SetupDiDestroyDeviceInfoList(hDevInfo);
    return USB_UNKNOWN_ERROR;
  }

  hDevice = CreateFile(detailData->DevicePath,GENERIC_READ|GENERIC_WRITE,FILE_SHARE_WRITE|FILE_SHARE_READ,NULL,OPEN_EXISTING,0,NULL);
  if (hDevice == INVALID_HANDLE_VALUE)
  {
    SetupDiDestroyDeviceInfoList(hDevInfo);
    return USB_UNKNOWN_ERROR;
  }

  Attributes.Size = sizeof(Attributes);
  if (HidD_GetAttributes(hDevice,&Attributes) != 0)
  {
    if (Attributes.VendorID == idVendor && Attributes.ProductID == idProduct)
    {
      if (CheckDeviceCapabilities(hDevice) != 0)
      {
        SetupDiDestroyDeviceInfoList(hDevInfo);
        CloseHandle(hDevice);
        return USB_UNKNOWN_ERROR;
      }

      if (FALSE == HidD_GetManufacturerString(hDevice,vdrName,128))
      {
        SetupDiDestroyDeviceInfoList(hDevInfo);
        CloseHandle(hDevice);
        return USB_UNKNOWN_ERROR;
      }
      if (FALSE == HidD_GetProductString(hDevice,devName,128))
      {
        SetupDiDestroyDeviceInfoList(hDevInfo);
        CloseHandle(hDevice);
        return USB_UNKNOWN_ERROR;
      }
      _tcscpy(devPath,detailData->DevicePath);

      CloseHandle(hDevice);
      SetupDiDestroyDeviceInfoList(hDevInfo);
      return USB_SPECIFIC_DEVICE_EXIST;
    }
    else
    {
      CloseHandle(hDevice);
    }
  }
  else
  {
    CloseHandle(hDevice);
  }

  SetupDiDestroyDeviceInfoList(hDevInfo);
  return USB_UNKNOWN_ERROR;
}

typedef struct _hid_context {
  TCHAR     vendor_name[64];
  TCHAR     device_name[64];
  TCHAR     device_path[128];
} hid_context;

int main(int argc, char *argv[])
{
  int idx, rv, round;
  hid_context hctx;
  HANDLE hDevice;

  for(idx=0;idx<128;idx++)
  {
    rv = GetHidDeviceContext(idx,0x096E,0x0100,hctx.vendor_name,hctx.device_name,hctx.device_path);
    if (USB_SPECIFIC_DEVICE_EXIST == rv)
    {
      _tprintf(_T("%s\n"),hctx.device_path);
      break;
    }
    else
    if (USB_SPECIFIC_DEVICE_NOT_FOUND == rv)
    {
      _tprintf(_T("Device not found!\n"));
      return -1;
    }
  }

  round = 1;
  hDevice = CreateFile(hctx.device_path,GENERIC_READ|GENERIC_WRITE,FILE_SHARE_WRITE|FILE_SHARE_READ,NULL,OPEN_EXISTING,0,NULL);

  while(hDevice != INVALID_HANDLE_VALUE)
  {
    BYTE FeatureReport[65], InputReport[65], i;
    BOOL ret;

    for (i=1; i<65; i++)
    {
      //FeatureReport[i] = (BYTE)0x01;
      //FeatureReport[i] = (BYTE)round;
      FeatureReport[i] = (BYTE)rand();
    }
    FeatureReport[0] = 0;

    if (HidD_SetFeature(hDevice,FeatureReport,65))
    {
      InputReport[0] = 0;
      _tprintf(_T("test round: %d - "),round++);
      ret = HidD_GetFeature(hDevice,InputReport,65);
      if (ret)
      {
        for (i=1; i<65; i++)
        {
          if ((FeatureReport[i]^InputReport[i]) != 0xFF)
          {
            _tprintf(_T("FeatureReport[%d] - %02X.%02X.%02X\n"), i,FeatureReport[i-1],FeatureReport[i],FeatureReport[i+1]);
            _tprintf(_T("InputReport[%d] - %02X.%02X.%02X\n"), i,InputReport[i-1],InputReport[i],InputReport[i+1]);
          }
        }
        _tprintf(_T("success!\n"));
      }
      else
      {
        DWORD err = GetLastError();
        _tprintf(_T("test round: %d - DATA recv ERROR!\n"), round);
        _tprintf(_T("GetLastError: %08X\n"), err);
        return -2;
      }
    }
    else
    {
      DWORD err = GetLastError();
      _tprintf(_T("test round: %d - DATA send ERROR!\n"), round);
      _tprintf(_T("GetLastError: %08X\n"), err);
      return -3;
    }
  }

  return 0;
}
