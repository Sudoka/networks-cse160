#ifndef CHAT_BUFFER_H
#define CHAT_BUFFER_H

enum {
	CHAT_BUFFER_SIZE = 512
};

typedef struct chatBuffer {
	char buffer[CHAT_BUFFER_SIZE];
	uint16_t length;
} chatBuffer;

void chatBufferInit(chatBuffer *input) {
	input->length = 0;
}

int16_t chatBufferNextCmd(chatBuffer *input, uint8_t *dest, uint16_t length) {
	uint16_t i;
	for(i = 0; i < input->length-1; i++) {
		if(input->buffer[i] == '\r' && input->buffer[i+1] == '\n' && (i+1) < length) {
			//dbg("Project4", "i:%d length:%d\n", i, input->length);
			memcpy(dest, input->buffer, i+2);
			memmove(input->buffer, &input->buffer[i+2], input->length - (i+2));
			input->length -= (i+2);
			return (i+2);
		}	
	}
	return 0;
}

#endif /* CHAT_BUFFER_H */
