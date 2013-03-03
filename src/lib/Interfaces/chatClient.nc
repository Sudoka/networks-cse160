interface chatClient<val_t>{
	command void init(val_t *, char* username, uint8_t clientPort);
	
	command int16_t sendMsg(char* msg, int16_t length);
}