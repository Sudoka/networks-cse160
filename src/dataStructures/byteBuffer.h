#ifndef BYTE_BUFFER_H
#define BYTE_BUFFER_H
#include "packList.h"
/*
enum {
	MAX_SEND_BUFFER = 128,
	MAX_RCV_BUFFER = 128, //cant fuck with small receiver buffers yet due to silly receiver problem TODO fix silly receivers
	SEND_WINDOW_SIZE = 10,
	RCV_WINDOW_SIZE = 1
};

typedef struct frame {
	transport msg;
	uint32_t timeoutTime;
} frame;

//upon receiving an out of order ack resend expected frame
//upon receiving in order ack advance the window
//how do we know when an ack is out of order? easiest way is to have the receiver mark all acks it sends back as inorder or out of order
typedef struct senderBuffer {
	//all these byte values are sequence numbers, their differences represent the actual index in the buffer
	uint8_t buffer[MAX_SEND_BUFFER];
	frame sendWindow[SEND_WINDOW_SIZE];
	uint16_t lastByteAcked;
	uint16_t lastByteSent;
	uint16_t lastByteWritten;
	uint16_t AdvertisedWindow;
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



typedef struct receiverBuffer {
	//all these byte values are sequence numbers, their differences represent the actual index in the buffer
	uint8_t buffer[MAX_RCV_BUFFER];
	frame recvWindow[RCV_WINDOW_SIZE];
	uint16_t lastByteRead;
	uint16_t nextByteExpected;
	uint16_t lastByteRcvd;
	uint16_t AdvertisedWindow;
	packList outOfOrderPackets;
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
}

//always assume the seq points to the End byte (LSB)
int16_t senderBufferPushBack(senderBuffer * dest, uint8_t * src, uint16_t seq, uint16_t len) {
	if(dest->lastByteWritten != seq-len)
		return -1; //this data is already within the buffer or something weird has happened or I wrote this wrong to start with
	if(dest->lastByteWritten - dest->lastByteAcked + len > MAX_SEND_BUFFER)
		len = MAX_SEND_BUFFER - (dest->lastByteWritten - dest->lastByteAcked);
	memcpy(&dest->buffer[dest->lastByteWritten - dest->lastByteAcked], src, len);
	dest->lastByteWritten = seq;
	dbg("genDebug", "lastByteWritten %d, buffer length %d\n", dest->lastByteWritten, dest->lastByteWritten - dest->lastByteAcked);
	return len;
}

//TODO Sliding window and Advertised window
//determining last sendable byte
//lastSendableByte = min(lastByteThatWillFitInReceiverBuffer, lastByteThatWillFitInSendWindow, lastByteWritten)
//where
//lastByteThatWillFitInReceiverBuffer = AdvertisedWindow - (LastByteSent - LastByteAcked)
//lastByteThatWillFitInSendWindow = lastByteAcked + sendWindowSize
//sendWindowSize = SEND_WINDOW_SIZE * TRANSPORT_MAX_PAYLOAD_SIZE
int16_t senderBufferSendNextFrame(senderBuffer * src, uint8_t * dest, int16_t startSeq) {
	int16_t len, endSeq;
	if(startSeq > src->lastByteWritten+1 || startSeq <= src->lastByteAcked)
		return -1; //not in buffer
	endSeq = (src->lastByteWritten < src->lastByteAcked + (SEND_WINDOW_SIZE * TRANSPORT_MAX_PAYLOAD_SIZE)) ? src->lastByteWritten : src->lastByteAcked + (SEND_WINDOW_SIZE * TRANSPORT_MAX_PAYLOAD_SIZE);
	endSeq = (endSeq < src->AdvertisedWindow + src->lastByteAcked) ? endSeq : src->AdvertisedWindow + src->lastByteAcked;
	//TODO simpifly equation for advertised window
	len = (TRANSPORT_MAX_PAYLOAD_SIZE < endSeq - (startSeq-1)) ? TRANSPORT_MAX_PAYLOAD_SIZE : endSeq - (startSeq-1);
	memcpy(dest, &src->buffer[startSeq - (src->lastByteAcked+1)], len);
	if(startSeq + (len-1) > src->lastByteSent)
		src->lastByteSent = startSeq + (len-1);
	return len;
}

//seq points to the end byte of the segment you're acking
bool senderBufferAckBytes(senderBuffer * src, uint16_t seq) {
	seq--;
	dbg("genDebug", "seq : %d lastByteAcked : %d\n", seq, src->lastByteAcked);
	if(seq > src->lastByteSent || seq <= src->lastByteAcked)
		return FALSE; //something has gone wrong, trying to ack data that is not in the buffer
	memmove(src->buffer, &src->buffer[seq - src->lastByteAcked], src->lastByteWritten - seq);
	src->lastByteAcked = seq;
	return TRUE;
}

//--------------------------------
//Receiver Buffer Helper Functions
//--------------------------------

void receiverBufferInit(receiverBuffer * input, uint16_t seq) {
	input->lastByteRcvd = seq;
	input->lastByteRead = seq;
	input->nextByteExpected = seq+1;
	input->AdvertisedWindow = MAX_RCV_BUFFER;
}

//Go-Back-N this implementation does not accept out of order packets, window size of 1 is implied and non variable TODO general sliding window
int16_t receiverBufferPushBack(receiverBuffer * dest, transport * src) {
	int16_t startSeq = src->seq - (src->length-1);
	printTransport(src);
	if(startSeq != dest->nextByteExpected)
		return 0; //not the next packet expected, ignore
	if(src->seq > dest->lastByteRead + MAX_RCV_BUFFER)
		return -1; //doesn't fit in buffer, error
	//index = src->seq - (dest->lastByteRead+1)
	memcpy(&dest->buffer[src->seq-(src->length-1) - (dest->lastByteRead+1)], src->payload, src->length);
	dest->lastByteRcvd = src->seq;
	dest->nextByteExpected = src->seq+1;
	dest->AdvertisedWindow = MAX_RCV_BUFFER - (dest->nextByteExpected - 1 - dest->lastByteRead); 
	dbg("genDebug", "window advanced\n");
	return src->length;
}

//reads in the next len bytes of stream, advances pointers accordingly 
int16_t receiverBufferReadBytes(receiverBuffer * src, uint8_t * dest, int16_t len) {
	if(len < 0)
		return -1;
	if((src->nextByteExpected-1) - src->lastByteRead < len)
		len = (src->nextByteExpected-1) - src->lastByteRead;
	memcpy(dest, src->buffer, len);
	memmove(src->buffer, &src->buffer[len], (src->lastByteRcvd - src->lastByteRead)-len);
	src->lastByteRead += len;
	return len;
}

//------------------------------
//SENDER WINDOW HELPER FUNCTIONS
//------------------------------




/*
 * //seq is the last byte of the segment you want to send (retrieve) assume lastByte acked is 300
//you want to send 301 -> 330, you would input seq 330 and len 30
int16_t senderBufferSendBytes(senderBuffer * src, uint8_t * dest, int16_t seq, int16_t len) {
	//TODO choose between advertised window(flow control) and send window(sliding window / congenstion control)
	
	uint16_t window = SEND_WINDOW_SIZE;
	dbg("genDebug", "lastAcked %d\n", src->lastByteAcked);
	if(seq-len < src->lastByteAcked || seq > src->lastByteWritten)
		return -1; //Some portion of this segment is not within the buffer, choose a better fucking segment
	
	if(seq-(len-1) - (src->lastByteAcked+1) >= window)
		return 0; //the segment you're trying to send is outside of the send window	
	
	//seq-(len-1) = seq of first byte in segment
	//lastByteAcked+1 is the seq of the byte in index 0 of the buffer
	//the difference between the two should be the index of the first byte of the segment in the buffer
	if(seq - src->lastByteAcked > window && seq-(len-1) - (src->lastByteAcked+1) < window) {
		//last byte is outside of window but first byte is inside window truncate len and seq to fit
		len = len - (seq - (src->lastByteAcked + window));
		seq = src->lastByteAcked + window;
	}
	dbg("genDebug", "seq:%d len:%d start:%d lastAcked:%d lastSent:%d lastWritten:%d\n", seq, len, seq - src->lastByteAcked, src->lastByteAcked, src->lastByteSent, src->lastByteWritten);
	memcpy(dest, &src->buffer[seq - len - src->lastByteAcked], len);
	if(seq > src->lastByteSent)
		src->lastByteSent = seq;
	return len;
}
 */

#endif /* BYTE_BUFFER_H */
