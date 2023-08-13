#ifndef KERNEL_H_
#define KERNEL_H_

#include <circle/actled.h>
#include <circle/cputhrottle.h>
#include <circle/devicenameservice.h>
#include <circle/exceptionhandler.h>
#include <circle/interrupt.h>
#include <circle/koptions.h>
#include <circle/logger.h>
#include <circle/screen.h>
#include <circle/serial.h>
#include <circle/startup.h>
#include <circle/timer.h>
#include <circle/usb/usbhcidevice.h>
#include <SDCard/emmc.h>
#include <fatfs/ff.h>
#include "ramdevice.h"

class CKernel
{
public:
	CKernel();
	~CKernel();

	bool Initialize();
	void Run();

	CActLED				ActLED;
	CKernelOptions		Options;
	CCPUThrottle		CpuThrottle;
	CDeviceNameService	DeviceNameService;
	CSerialDevice		Serial;
	CExceptionHandler	ExceptionHandler;
	CInterruptSystem	Interrupt;
	CTimer				Timer;
	CLogger				Logger;

	CUSBHCIDevice		USBHCI;
	CEMMCDevice			EMMC;
	FATFS				FileSystem;
	CRamDevice			RamDevice;
};

extern CKernel gKernel;

#endif // KERNEL_H_
