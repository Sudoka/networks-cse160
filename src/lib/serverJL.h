#ifndef SERVER_JL_H
#define SERVER_JL_H

#include "TCPSocketAL.h"
#include "../dataStructures/chatBuffer.h"

typedef struct serverJL{
	TCPSocketAL *socket;
	uint8_t numofWorkers;
}serverJL;

typedef struct serverWorkerJL {
	TCPSocketAL *inSocket;
	TCPSocketAL *outSocket;
	uint8_t username[20];
	uint8_t id;
	chatBuffer cmdBuff;
	char nextCmd[128];
	int16_t cmdLen;
} serverWorkerJL;

enum{
	SERVER_TIMER_PERIOD=500, //500 ms
	WORKER_TIMER_PERIOD=533 //533 ms
};

#endif /* SERVER_JL_H */
