#include "ramdevice.h"
#include "mem.h"
#include <circle/devicenameservice.h>
#include <circle/new.h>

#if 0
class CRamDevice : CDevice
{
public:
	CRamDevice(u64 iSize = RD_DEFAULT_SIZE);
	virtual ~CRamDevice (void);

	/// \param pBuffer Buffer, where read data will be placed
	/// \param nCount Maximum number of bytes to be read
	/// \return Number of read bytes or < 0 on failure
	virtual int Read (void *pBuffer, size_t nCount) override;

	/// \param pBuffer Buffer, from which data will be fetched for write
	/// \param nCount Number of bytes to be written
	/// \return Number of written bytes or < 0 on failure
	virtual int Write (const void *pBuffer, size_t nCount) override;

	/// \param ullOffset Byte offset from start
	/// \return The resulting offset, (u64) -1 on error
	/// \note Supported by block devices only
	virtual u64 Seek (u64 ullOffset) override;

	/// \return Total byte size of a block device, (u64) -1 on error
	/// \note Supported by block devices only
	virtual u64 GetSize (void) const override;

	/// \return TRUE on successful device removal
	virtual boolean RemoveDevice (void) override;

	virtual u8 *GetBuffer();

protected:
	i32		Index;
	i64		CurOffset;
	u64		Size;
	u8		*Buffer;
};
#endif

CRamDevice::CRamDevice(u64 iSize, int iNum)
{
	Size = iSize;
	Index = iNum;
	Buffer = new (HEAP_HIGH) u8[Size];
	CDeviceNameService::Get()->AddDevice("ram", Index+1, this, true);
}

CRamDevice::~CRamDevice()
{
	CDeviceNameService::Get()->RemoveDevice("ram", Index+1, true);
	delete[] Buffer;
}

u8* CRamDevice::GetBuffer()
{
	return Buffer;
}


int CRamDevice::Read (void *buffer, size_t count)
{
	u8* start = Buffer + CurOffset;
	u8* end   = start + count;
	if (end > Buffer + Size)
	{
		end = Buffer + Size;
	}
	u64 toCopy = end - start;
	memcpy(buffer, start, toCopy);
	return (int)toCopy;
}

int CRamDevice::Write(const void *buffer, size_t count)
{
	u8* start = Buffer + CurOffset;
	u8* end   = start + count;
	if (end > Buffer + Size)
	{
		end = Buffer + Size;
	}
	u64 toCopy = end - start;
	memcpy(start, buffer, toCopy);
	return (int)toCopy;
}

u64 CRamDevice::Seek(u64 offset)
{
	if (offset >= Size)
	{
		return (u64)-1;
	}

	CurOffset = offset;
	return CurOffset;
}

u64 CRamDevice::GetSize() const
{
	return Size;
}

bool CRamDevice::RemoveDevice()
{
	return true;
}
