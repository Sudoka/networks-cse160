#ifndef RECEIVER_BUFFER_H
#define RECEIVER_BUFFER_H
#include "../transport.h"

enum {
	RECEIVER_BUFFER_SIZE = 128,
	RECEIVER_WINDOW_SIZE = 10
};

typedef struct sortedSegmentList {
	transport values[RECEIVER_WINDOW_SIZE]; //out of order transports
	uint8_t numValues;
} sortedSegmentList;

typedef struct receiverBuffer {
	int16_t lastByteRead;
	int16_t lastByteRcvd;
	int16_t nextByteExpected;
	uint16_t advertisedWindow;
	
	uint8_t buffer[RECEIVER_BUFFER_SIZE];
	sortedSegmentList rcvrWindow;
} receiverBuffer;

void sortedSegmentListInit(sortedSegmentList * input) {
	input->numValues = 0;
}

void receiverBufferInit(receiverBuffer * input, int16_t seq) {
	input->lastByteRcvd = seq;
	input->lastByteRead = seq;
	input->nextByteExpected = seq+1;
	input->advertisedWindow = RECEIVER_BUFFER_SIZE;
	sortedSegmentListInit(&input->rcvrWindow);
}

//reads in the next len bytes of stream, advances pointers accordingly 
int16_t receiverBufferReadBytes(receiverBuffer * src, uint8_t * dest, int16_t len) {
	if(len < 0)
		return -1;
	if((src->nextByteExpected-1) - src->lastByteRead < len)
		len = (src->nextByteExpected-1) - src->lastByteRead;
	memcpy(dest, src->buffer, len);
	memmove(src->buffer, &src->buffer[len], (src->nextByteExpected - 1 - src->lastByteRead)-len);
	src->lastByteRead += len;
	//dbg("genDebug", "rcvd:%d expected-1:%d read:%d newlength:%d\n", src->lastByteRcvd, src->nextByteExpected-1, src->lastByteRead, (src->lastByteRcvd - src->lastByteRead));
	return len;
}

bool sortedSegmentListAdd(sortedSegmentList * input, transport * value) {
	uint8_t i = 0;
	if(input->numValues == RECEIVER_WINDOW_SIZE-1)
		return FALSE;
	while(i < input->numValues) {
		if(input->values[i].seq > value->seq)
			break;
		i++;
	}
	memmove(&input->values[i+1], &input->values[i], (input->numValues-i)*sizeof(transport));
	memcpy(&input->values[i], value, sizeof(transport));
	input->numValues++;
	return TRUE;
}

bool sortedSegmentListPopFront(sortedSegmentList * input, transport *out) {
	if(input->numValues <= 0)
		return FALSE;
	
	memcpy(out, &input->values[0], sizeof(transport));
	input->numValues--;
	memmove(&input->values[0], &input->values[1], input->numValues * sizeof(transport));
	return TRUE;
}

int16_t sortedSegmentListNextByte(sortedSegmentList * input) {
	uint8_t i;
	for(i = 0; i<input->numValues; i++)
		printTransport(&input->values[i]);
	return (input->values[0].seq - input->values[0].length + 1);
}

#endif /* RECEIVER_BUFFER_H */
