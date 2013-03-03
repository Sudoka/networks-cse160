#ifndef TCP_BUFFER_H
#define TCP_BUFFER_H
#include "../transport.h"
#define MAX_RETRANSMITS 45
#define ALPHA 0.8
#define congestionEnabled 1 //1 for on, 0 for off, turn off in lossy network

enum {
	MAX_SEND_BUFFER = 30, 
	MAX_RCV_BUFFER = 128,//cant fuck with small receiver buffers yet due to silly receiver problem TODO fix silly receivers
	SEND_WINDOW_SIZE = 10,
	RCV_WINDOW_SIZE = 5
};

typedef struct frame {
	transport msg;
	uint32_t timeSent;
	bool resent;
	uint8_t TTL;
} frame;

//upon receiving an out of order ack resend expected frame
//upon receiving in order ack advance the window
//how do we know when an ack is out of order? easiest way is to have the receiver mark all acks it sends back as inorder or out of order
typedef struct senderBuffer {
	//all these byte values are sequence numbers, their differences represent the actual index in the buffer
	frame buffer[MAX_SEND_BUFFER];
	uint16_t lastByteAcked;
	uint16_t lastByteSent;
	uint16_t lastByteWritten;
	uint16_t AdvertisedWindow;
	double congestionWindow;
	uint16_t SSThresh;
	uint8_t duplicateAcks;
	double RTT;
	uint32_t RTObaseTime;
	bool firstRTT;
	uint8_t numValues;
	//LastByteAcked <= LastByteSent
	//LastByteSent <= LastByteWritten
	//nothing left of lastByteAcked needs to be buffered aka LastByteAcked will be position -1
	
	//LastByteSent - LastByteAcked <= AdvertisedWindow
	//EffectiveWindow = AdvertisedWindow - (LastByteSent - LastByteAcked)
	
	//LastByteWritten  − LastByteAcked ≤ MaxSendBuffer
	//If the sending process tries to write y bytes to TCP, but
	//	(LastByteWritten−LastByteAcked) + y > MaxSendBuffer
	// TCP blocks the sending process and does not allow it to generate more data
	
	//If the Advertised window size is 0 the sender will start a persist timer that will periodically send 
	//segments with 1 bytes of data to trigger an ACK so that It knows once the AdvertisedWindow is no longer
	//0
} senderBuffer;

typedef struct sortedSegmentList {
	transport values[RCV_WINDOW_SIZE]; //out of order transports
	uint8_t numValues;
} sortedSegmentList;

typedef struct receiverBuffer {
	//all these byte values are sequence numbers, their differences represent the actual index in the buffer
	uint8_t buffer[MAX_RCV_BUFFER]; //in order bytes
	sortedSegmentList recvWindow;
	uint16_t lastByteRead;
	uint16_t nextByteExpected;
	uint16_t lastByteRcvd;
	uint16_t AdvertisedWindow;
	//LastByteRead < nextByteExpected
	//nextByteExpected <= lastByteRcvd+1
	//nothing left of LastByteRead needs to be buffered so it will actually correspond to position 0
	
	//lastByteRcvd - LastByteRead <= MAX_RCV_BUFFER
	//AdvertisedWindow = MAX_RCV_BUFFER - ((nextByteExpected - 1) - lastByteRead)
	//TCP always sends a segment in response to a received data segment
	// and this response contains the latest values for the Acknowledge and AdvertisedWindow Fields
} receiverBuffer;

//------------------------------
//Sender Buffer Helper Functions
//------------------------------

void senderBufferInit(senderBuffer * input, uint16_t seq) {
	input->lastByteAcked = seq;
	input->lastByteSent = seq;
	input->lastByteWritten = seq;
	input->AdvertisedWindow = 1;
	input->congestionWindow = 1;
	input->SSThresh = 12;
	input->duplicateAcks = 0;
	input->RTT = 50;
	input->firstRTT = TRUE;
	input->RTObaseTime = 0;
	input->numValues = 0;
}

int16_t senderBufferPushBack(senderBuffer * input, transport * msg) {
	frame segment;
	if(input->lastByteWritten != msg->seq - msg->length) {
		dbg("genDebug", "cannot push, invalid, written:%d seq%d length%d\n", input->lastByteWritten, msg->seq, msg->length);
		return -1; //not a valid segment
	}
	if(msg->seq > input->lastByteAcked + (MAX_SEND_BUFFER * TRANSPORT_MAX_PAYLOAD_SIZE)) {
		dbg("genDebug", "cannot push, out of room\n");
		return 0; //wont fit into send buffer
	}
	memcpy(&segment.msg, msg, sizeof(transport));
	segment.timeSent = 0;
	segment.resent = FALSE;
	segment.TTL = MAX_RETRANSMITS;
	input->buffer[input->numValues] = segment;
	input->numValues++;
	input->lastByteWritten = msg->seq;
	dbg("genDebug", "pushed vals %d\n", input->numValues);
	return msg->length;
}

int16_t senderBufferSendLogic(senderBuffer * input, uint8_t indexx, uint32_t currentTime) {
	int16_t maxIndex;
	maxIndex = (congestionEnabled) ? round(input->congestionWindow + input->duplicateAcks) : SEND_WINDOW_SIZE;
	maxIndex = (input->numValues > maxIndex) ? maxIndex : input->numValues;
	if(!congestionEnabled) input->RTT = 100;
	else if(input->RTT > 200) input->RTT = 200;
	if(indexx >= maxIndex)
		return -1; //outside of sender window
	if(input->buffer[indexx].msg.seq > input->AdvertisedWindow + input->lastByteAcked) {
		if(input->buffer[indexx].timeSent + input->RTT*3 > currentTime || indexx == 0) {
			return 1;
		}
		return -1; //can overflow receiver buffer
	} if(input->buffer[0].msg.type == TRANSPORT_SYN && indexx != 0)
		return -1; //there is an un-acked syn pack on the buffer, connection not established cannot send
	if(input->RTObaseTime + input->RTT*2 > currentTime && input->buffer[indexx].timeSent != 0)
		return 0; //data has not timed out return 0 so it can check if later data that may be sendable can send
	if(input->buffer[indexx].TTL <= 0) {
		//give up on pack, remove from queue
		dbg("genDebug", "\n\n\nERROR@@@@@@@@@@ : packet TTL expired\n\n\n");
		memmove(&input->buffer[indexx], &input->buffer[indexx+1], (input->numValues - indexx - 1) * sizeof(frame));
		input->numValues--;
		input->lastByteAcked = input->buffer[0].msg.seq - input->buffer[0].msg.length;
		input->lastByteWritten = input->buffer[input->numValues-1].msg.seq;
		return -1;
	}
	if(input->buffer[indexx].timeSent != 0) {
		input->buffer[indexx].resent = TRUE;
		dbg("congestionControl", "packet Time out\n");
		if(congestionEnabled) input->RTT *= 2;
		input->SSThresh = (TRANSPORT_MAX_PAYLOAD_SIZE * input->congestionWindow) / 2.0;
		input->congestionWindow = 1.0;
	}
	if(input->buffer[indexx].msg.seq > input->lastByteSent)
		input->lastByteSent = input->buffer[indexx].msg.seq;
	input->buffer[indexx].timeSent = currentTime;
	input->RTObaseTime = currentTime;
	input->buffer[indexx].TTL--;
	return 1;
}


bool senderBufferAckSeq(senderBuffer * input, transport * msg, uint32_t currentTime) {
	uint8_t i = 0, j, newValues;
	int16_t seq;
	seq = msg->seq-1;
	input->AdvertisedWindow = msg->window;
	dbg("genDebug", "seq %d lastAcked %d lastSent %d lastWritten %d\n", seq, input->lastByteAcked, input->lastByteSent, input->lastByteWritten);
	if(seq <= input->lastByteAcked || seq > input->lastByteSent) {
		return FALSE; //bytes not in buffer so cant ack it
	}
	newValues = input->numValues;
	while(i < input->numValues) {
		if(input->buffer[i].msg.seq <= seq) {
			//this packet has been acked
			if(input->congestionWindow*TRANSPORT_MAX_PAYLOAD_SIZE < input->SSThresh) {
				input->congestionWindow++;
				dbg("congestionControl","congestion window %f\n", input->congestionWindow);
			} else {
				input->congestionWindow += 1.0/input->congestionWindow; //I sure hope this is right
				dbg("congestionControl","congestion window %f\n", input->congestionWindow);
			}
			if(!input->buffer[i].resent && input->buffer[i].msg.type == TRANSPORT_DATA) {//this packet hasn't been resent
				if(!input->firstRTT)
					input->RTT = ALPHA*input->RTT + (1.0 - ALPHA)*(currentTime - input->buffer[i].timeSent); //add to RTT
				else {
					input->RTT = currentTime - input->buffer[i].timeSent;
					input->firstRTT = FALSE;
				}
			}
			i++;
			newValues--;
		} else
			break;
	}
	for(j = 0; j < newValues; j++) {
		input->buffer[j] = input->buffer[i+j];
	}
	input->numValues = newValues;
	input->lastByteAcked = seq;
	dbg("genDebug", "ack ended RTT = %2.4f\n", input->RTT);
	return TRUE;
}

//-------------------------------------------------
//Sorted Out of Order Segment List Helper Functions
//-------------------------------------------------

void sortedSegmentListInit(sortedSegmentList * input) {
	input->numValues = 0;
}

bool sortedSegmentListAdd(sortedSegmentList * input, transport * value) {
	uint8_t i = 0;
	dbg("genDebug", "numValues %d +1?\n", input->numValues);
	if(input->numValues == RCV_WINDOW_SIZE-1)
		return FALSE;
	while(i < input->numValues) {
		if(input->values[i].seq > value->seq)
			break;
		i++;
	}
	dbg("genDebug", "i:%d \n", i);
	memmove(&input->values[i+1], &input->values[i], (input->numValues-i)*sizeof(transport));
	memcpy(&input->values[i], value, sizeof(transport));
	input->numValues++;
	return TRUE;
}

bool sortedSegmentListPopFront(sortedSegmentList * input, transport * out) {
	if(input->numValues <= 0)
		return FALSE;
	
	dbg("genDebug", "popping front %d\n", input->numValues);
	memcpy(out, &input->values[0], sizeof(transport));
	input->numValues--;
	memmove(&input->values[0], &input->values[1], input->numValues * sizeof(transport));
	dbg("genDebug", "%d again\n", input->numValues);
	return TRUE;
}

int16_t sortedSegmentListNextByte(sortedSegmentList * input) {
	uint8_t i;
	dbg("genDebug", "numValues %d\n", input->numValues);
	for(i = 0; i<input->numValues; i++)
		printTransport(&input->values[i]);
	return (input->values[0].seq - input->values[0].length + 1);
}

//--------------------------------
//Receiver Buffer Helper Functions
//--------------------------------

void receiverBufferInit(receiverBuffer * input, uint16_t seq) {
	input->lastByteRcvd = seq;
	input->lastByteRead = seq;
	input->nextByteExpected = seq+1;
	input->AdvertisedWindow = MAX_RCV_BUFFER;
	sortedSegmentListInit(&input->recvWindow);
}

int16_t receiverBufferPushBack(receiverBuffer * dest, transport * src) {
	transport nextSegment;
	int16_t startSeq = src->seq - (src->length-1);
	if(src->type == TRANSPORT_FIN) {
		if(dest->lastByteRcvd+1 == dest->nextByteExpected) {
			if(src->seq > dest->lastByteRcvd)
				dest->lastByteRcvd = src->seq;
			dest->nextByteExpected = src->seq+1;
			dest->AdvertisedWindow = MAX_RCV_BUFFER - (dest->nextByteExpected - 1 - dest->lastByteRead); 
			return 1;
		} else
			return -1;
	}	
	dbg("genDebug", "lastRead:%d nextExpected:%d lastReceived:%d\n", dest->lastByteRead, dest->nextByteExpected, dest->lastByteRcvd);
	if(src->seq > dest->lastByteRead + MAX_RCV_BUFFER)
		return -1; //doesn't fit in buffer, error
	if(startSeq <= dest->nextByteExpected-1) {
		//packet is already received and acked do not buffer
		return 0;
	}
	if(src->seq > dest->lastByteRcvd)
		dest->lastByteRcvd = src->seq;
	if(startSeq != dest->nextByteExpected) {
		sortedSegmentListAdd(&dest->recvWindow, src);
		return 0; //not the next packet expected
	}
	//index = src->seq - (dest->lastByteRead+1)
	memcpy(&dest->buffer[src->seq-(src->length-1) - (dest->lastByteRead+1)], src->payload, src->length);
	dest->nextByteExpected = src->seq+1;
	dest->AdvertisedWindow = MAX_RCV_BUFFER - (dest->nextByteExpected - 1 - dest->lastByteRead); 
	dbg("genDebug", "window advanced ");
	dbg_clear("genDebug", "lastRead:%d nextExpected:%d lastReceived:%d\n", dest->lastByteRead, dest->nextByteExpected, dest->lastByteRcvd);
	if(sortedSegmentListNextByte(&dest->recvWindow) <= dest->nextByteExpected) {
		sortedSegmentListPopFront(&dest->recvWindow, &nextSegment);
		return src->length + receiverBufferPushBack(dest, &nextSegment);
	} else
		return src->length;
}

//reads in the next len bytes of stream, advances pointers accordingly 
int16_t receiverBufferReadBytes(receiverBuffer * src, uint8_t * dest, int16_t len) {
	if(len < 0)
		return -1;
	if((src->nextByteExpected-1) - src->lastByteRead < len)
		len = (src->nextByteExpected-1) - src->lastByteRead;
	memcpy(dest, src->buffer, len);
	dbg("genDebug", "rcvd:%d expected-1:%d read:%d newlength:%d\n", src->lastByteRcvd, src->nextByteExpected-1, src->lastByteRead, (src->lastByteRcvd - src->lastByteRead));
	memmove(src->buffer, &src->buffer[len], (src->nextByteExpected - 1 - src->lastByteRead)-len);
	src->lastByteRead += len;
	return len;
}

#endif /* TCP_BUFFER_H */
