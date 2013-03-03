#ifndef CLIENT_JL_H
#define CLIENT_JL_H

#include "TCPSocketAL.h"
#include "../dataStructures/chatBuffer.h"

enum{
	CHAT_CLIENT_TIMER_PERIOD=500, //500 ms
};

typedef struct clientJL{
	TCPSocketAL *outSocket;
	TCPSocketAL *inSocket;
	uint32_t startTime;
	char username[20];
	chatBuffer cmdBuff;
	char nextCmd[128];
	int16_t cmdLen;
}clientJL;

#endif /* CLIENT_JL_H */
