/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   October 1 2012
 * 
 */ 

#ifndef CLIENT_H
#define CLIENT_H
#include "TCPSocketAL.h"


enum{
	CLIENT_TIMER_PERIOD=500, //500 ms
	CLIENTAL_BUFFER_SIZE=256	//64 bytes
};


typedef struct clientAL{
	TCPSocketAL *socket;
	uint32_t startTime;
	uint16_t amount; //Amount of bytes to be sent.
	
	uint16_t position;
	uint8_t buffer[CLIENTAL_BUFFER_SIZE];
}clientAL;

#endif /* CLIENT_H */
