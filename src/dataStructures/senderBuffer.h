#ifndef SENDER_BUFFER_H
#define SENDER_BUFFER_H
#include "../transport.h"

#ifndef max
	#define max( a, b ) ( ((a) > (b)) ? (a) : (b) )
#endif

#ifndef min
	#define min( a, b ) ( ((a) < (b)) ? (a) : (b) )
#endif

#define congestionEnabled 0 //1 on, 0 off

enum {
	SENDER_WINDOW_SIZE = 10,
	SENDER_BUFFER_SIZE = 256,
	MIN_RTT = 100,
	MAX_RTT = 1000,
	ALPHA = 8,
	BETA = 4
};

typedef struct frame {
	transport segment;
	uint32_t timeSent;
	bool resent;
} frame;

typedef struct reTransmitQueue {
	frame segments[SENDER_WINDOW_SIZE];
	uint32_t lastSend;
	uint8_t numValues;
} reTransmitQueue;

void reTransmitQueueInit(reTransmitQueue *input) {
	input->numValues = 0;
}

typedef struct senderBuffer {
	uint8_t buffer[SENDER_BUFFER_SIZE];
	int16_t lastByteAcked;
	int16_t lastByteSent;
	int16_t lastByteWritten;
	uint16_t advertisedWindow;
	
	reTransmitQueue reTXQueue;
	double SRTT;
	double RTO;
	double RTTVAR;
	bool FIRST_RTT;
	
	//congestion control
	uint8_t duplicateAcks;
	double congestionWindow;
	double SSThresh;
} senderBuffer;

//TODO implement here
void senderBufferInit(senderBuffer *input, int16_t ISN) {
	input->lastByteAcked = ISN;
	input->lastByteSent = ISN;
	input->lastByteWritten = ISN;
	input->advertisedWindow = 1;
	
	reTransmitQueueInit(&input->reTXQueue);
	
	input->SRTT = MIN_RTT;
	input->RTTVAR = MIN_RTT/2.0;
	input->RTO = input->SRTT + fmax(10, 4*input->RTTVAR);
	input->FIRST_RTT = TRUE;
	
	input->duplicateAcks = 0;
	input->congestionWindow = 1.0;
	input->SSThresh = 1.0;
}

uint16_t senderBufferPushBack(senderBuffer *input, uint8_t *src, uint16_t length) {
	length = (length < SENDER_BUFFER_SIZE - (input->lastByteWritten - input->lastByteAcked)) ? length : SENDER_BUFFER_SIZE - (input->lastByteWritten - input->lastByteAcked);
	
	memcpy(&input->buffer[input->lastByteWritten - input->lastByteSent], src, length);
	input->lastByteWritten += length;
	
	return length;
}

//should this be a command in tcpmanager?
bool senderBufferRTXPushBack(senderBuffer *input, transport *segment, uint32_t timeSent) {
	frame newFrame;
	if(segment->seq > input->lastByteAcked + SENDER_BUFFER_SIZE)
		return FALSE; //outside of send buffer
	if(input->reTXQueue.numValues >= SENDER_WINDOW_SIZE)
		return FALSE; //outside of send window
	if(input->reTXQueue.numValues >= input->congestionWindow + input->duplicateAcks && congestionEnabled)
		return FALSE; //outside of congestion Window
	if(input->lastByteSent != segment->seq - segment->length)
		return FALSE; //not the next segment of the flow
		
	if(segment->seq > input->lastByteWritten)
		input->lastByteWritten = segment->seq;
	
	newFrame.resent = FALSE;
	memcpy(&newFrame.segment, segment, sizeof(transport));
	newFrame.timeSent = timeSent;
	input->reTXQueue.lastSend = timeSent;
	
	memcpy(&input->reTXQueue.segments[input->reTXQueue.numValues], &newFrame, sizeof(frame));
	input->reTXQueue.numValues++;
	
	input->lastByteSent = segment->seq;
	
	dbg("ReliableTransport", "reTXQ size:%d WINDOWSIZE : %f\n", input->reTXQueue.numValues, input->congestionWindow);
	
	return TRUE;
}

//TODO implement in manager
//sendNextSegment
//is timed out

#endif /* SENDER_BUFFER_H */
