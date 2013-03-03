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
#include "../transport.h"
#include "../dataStructures/packList.h"
#include "../dataStructures/portList.h"
#include "../dataStructures/tcpBuffer.h"

enum TCPSOCKET_STATE{
	CLOSED=0,
	LISTEN=1,
	SYN_SENT=2,
	SYN_RCVD=3,
	ESTABLISHED=4,
	FIN_WAIT_1=5,
	FIN_WAIT_2=6,
	CLOSING=7,
	TIME_WAIT=8,
	CLOSE_WAIT=9,
	LAST_ACK=10
};

enum TCPSOCKET_ERR_MSG{
 
	TCP_ERRMSG_SUCCESS=0,
	TCP_ERRMSG_FOREIGN_SOCKET_NOT_SPECIFIED=1,
	TCP_ERRMSG_CONNECTION_ALREADY_EXISTS=2,
	TCP_ERRMSG_NO_WAITING_CONNECTIONS=3,
	TCP_ERRMSG_CONNECTION_DOES_NOT_EXIST=4,
	TCP_ERRMSG_INVALID=-1
 
};  

typedef struct TCPSocketAL{
	/*Insert Variables Here */
	uint8_t state;
	uint8_t localPort;
	uint8_t destPort;
	uint16_t destAddr;
	uint16_t localAddr;
	receiverBuffer in;
	senderBuffer out;
	packList acceptQueue;
	portList * ports;
}TCPSocketAL;

#endif /* TCP_SOCKET_AL_H */
