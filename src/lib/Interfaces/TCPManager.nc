#include "../../dataStructures/portList.h"

interface TCPManager<val_t, val2_t>{
	command void init();
	command val_t *socket();
	command void freeSocket(val_t *);
	command void handlePacket(void *);
	command uint8_t getFreePort();
	command bool requestPort(uint8_t port);
	async command void senderBufferFillWindow(val_t *input);
}
