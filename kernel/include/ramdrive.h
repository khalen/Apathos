#ifndef RAMDRIVE_H_
#define RAMDRIVE_H_

#include "base_defs.h"
#include <circle/device.h>

#define RD_BLOCKSIZE	512

#define RD_DEFAULT_SIZE	(512 * MB)

class CRamDevice : CDevice
{
public:
	CRamDevice (u64 iSize = RD_DEFAULT_SIZE);
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
}

#endif // RAMDRIVE_H_
