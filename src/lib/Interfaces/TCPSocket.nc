interface TCPSocket<val_t>{
	async command void init(val_t *input);

	async command uint8_t bind(val_t *input, uint8_t localPort, uint16_t address);
	
	async command uint8_t listen(val_t *input, uint8_t backlog);
	
	async command uint8_t accept(val_t *input, val_t *output);
	
	async command uint8_t connect(val_t *input, uint16_t destAddr, uint8_t destPort);
	
	async command uint8_t close(val_t *input);
	
	async command uint8_t release(val_t *input);
	
	async command int16_t read(val_t *input, uint8_t *readBuffer, uint16_t pos, uint16_t len);
	
	async command int16_t write(val_t *input, uint8_t *writeBuffer, uint16_t pos, uint16_t len);
	
	//Checks
	async command bool isConnectPending(val_t *input);
	async command bool isConnected(val_t *input);
	async command bool isListening(val_t *input);
	async command bool isClosed(val_t *input);
	async command bool isClosing(val_t *input);
	
	async command void copy(val_t *input, val_t *output);
}
