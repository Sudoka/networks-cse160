#ifndef CHAT_COMMAND_H
#define CHAT_COMMAND_H

enum {
	CHAT_HELLO=1,
	CHAT_MSG=2,
	CHAT_LISTUSR=3,
	CHAT_ERROR=99
};

bool isCHELLO(uint8_t *array, uint16_t size) {
	return (array[0] == 'h' && array[1] == 'e' && array[2] == 'l' && array[3] == 'l' && array[4] == 'o');
}

bool isCMSG(uint8_t *array, uint16_t size) {
	return (array[0] == 'm' && array[1] == 's' && array[2] == 'g');
}

bool isCLISTUSR(uint8_t *array, uint16_t size) {
	return (array[0] == 'l' && array[1] == 'i' && array[2] == 's' && array[3] == 't' && array[4] == 'u' && array[5] == 's' && array[6] == 'r');
}

uint8_t getChatCMD(uint8_t *array, uint16_t size) {
	if(isCHELLO(array, size))
		return CHAT_HELLO;
	if(isCMSG(array,size))
		return CHAT_MSG;
	if(isCLISTUSR(array, size))
		return CHAT_LISTUSR;
		
	return CHAT_ERROR;
}

#endif /* CHAT_COMMAND_H */
