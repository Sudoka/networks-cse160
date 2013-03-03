interface TCPManager<val_t, val2_t>{
	command void init();
	command val_t *socket();
	command void freeSocket(val_t *);
	command void handlePacket(void *);
}
