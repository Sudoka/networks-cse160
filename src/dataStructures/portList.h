#ifndef PORT_LIST_H
#define PORT_LIST_H
#include "../transport.h"
#define TOTALPORTS TRANSPORT_MAX_PORT

typedef struct portList {
	uint8_t portID[TOTALPORTS];
	uint16_t numValues;
} portList;

void portListInit(portList * input){
	uint8_t i;
	for(i = 0; i < TOTALPORTS; i++)
		input->portID[i] = (uint8_t)(i+1);
	input->numValues = TOTALPORTS;
}

bool portListContains(portList * input, uint8_t port) {
	uint8_t i;
	for(i = 0; i < input->numValues; i++)
		if(input->portID[i] == port)
			return TRUE;
	return FALSE;
}

bool portListFreePort(portList * input, uint8_t port) {
	if(portListContains(input, port) || input->numValues > TOTALPORTS || port <= 0 || port > TOTALPORTS)
		return FALSE; //invalid port
	input->portID[input->numValues] = port;
	//dbg("genDebug", "freed port %d %d\n",input->portID[input->numValues], port);
	input->numValues++;
	return TRUE;
}

bool portListRequestPort(portList * input, uint8_t port) {
	uint8_t i;
	for(i = 0; i < input->numValues; i++)
		if(input->portID[i] == port) {
			memmove(&(input->portID[i]), &(input->portID[i+1]), (input->numValues-1)-i);
			input->numValues--;
			return TRUE;
		}
	return FALSE;
}

uint8_t portListPopBack(portList * input) {
	uint8_t port = input->portID[input->numValues-1];
	//dbg("genDebug", "giving port:%d\n", port);
	input->numValues--;
	return port;
}

#endif /* PORT_LIST_H */
