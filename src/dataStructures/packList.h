#ifndef PACK_LIST_H
#define PACK_LIST_H
#include "../packet.h"
#include "../transport.h"
#define BUFFSIZE 30

typedef struct packList {
	pack values[BUFFSIZE]; //list of values
	uint8_t numValues;	//number of objects currently in the array
	uint8_t backlog;
} packList;

void packListInit(packList * cur) {
	cur->numValues = 0;
	cur->backlog = 0;
}

bool packListContains(packList * list, pack * val) {
	transport *cur, *value;
	uint8_t i = 0;
	value = (transport*) val->payload;
	for(i; i < list->numValues; i++)  {
		cur = (transport*) list->values[i].payload;
		if(value->srcPort == cur->srcPort && value->destPort == cur->destPort && val->src == list->values[i].src) 
			return TRUE;
	}
	return FALSE;
}

bool packListPushBack(packList * cur, pack * newVal) {
	if(packListContains(cur, newVal) || cur->numValues == BUFFSIZE || cur->numValues == cur->backlog)
		return FALSE;
	else {
		memcpy(&cur->values[cur->numValues], newVal, sizeof(pack));
		++cur->numValues;
		return TRUE;
	}
}

pack packListPopFront(packList * cur) {
	pack returnVal;
	nx_uint8_t i;
	returnVal = cur->values[0];
	for(i = 1; i < cur->numValues; ++i) 
		cur->values[i - 1] = cur->values[i];
	--cur->numValues;
	return returnVal;
}
#endif /* PACK_LIST_H */
