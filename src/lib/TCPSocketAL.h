/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   October 1 2012
 * 
 */ 

#ifndef TCP_SOCKET_AL_H
#define TCP_SOCKET_AL_H

#include "../packet.h"
#include "../transport.h"
#include "../dataStructures/packList.h"
#include "../dataStructures/senderBuffer.h"
#include "../dataStructures/receiverBuffer.h"

enum TCPSOCKET_STATE{
	CLOSED=0, 		//universal state
	LISTEN=1,		//receiver state
	SYN_SENT=2,		//sender state
	SYN_RCVD=3,		//receiver state
	ESTABLISHED=4,	//sender state
	FIN_SENT=5,		//sender state
	CLOSING=6		//receiver state
};

enum TCPSOCKET_ERR_MSG{
 
	TCP_ERRMSG_SUCCESS = 0
 
};  

typedef struct TCPSocketAL{
	/*Insert Variables Here */
	uint8_t srcPort;
	uint16_t srcAddr;
	uint8_t destPort;
	uint16_t destAddr;
	
	bool free;
	
	uint8_t state;
	
	packList acceptQueue;
	
	senderBuffer out;
	receiverBuffer in;
}TCPSocketAL;

#endif /* TCP_SOCKET_AL_H */
