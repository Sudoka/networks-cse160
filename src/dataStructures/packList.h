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

bool packListPushBack(packList * cur, pack newVal) {
	if(cur->numValues != BUFFSIZE) {
		cur->values[cur->numValues] = newVal;
		++cur->numValues;
		return TRUE;
	}
	else 
		return FALSE;
}

pack packListPopBack(packList * cur) {
	--cur->numValues;
	return cur->values[cur->numValues];
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

//TODO add a packListPopIndex function which will then be leveraged in packListPopPack and packListPopLowest

pack packListPopPack(packList * cur, uint16_t src, uint16_t seq) {
	pack returnVal;
	nx_uint8_t i, indexx;
	for(i = 0, indexx = 0; src != cur->values[indexx].src && seq != cur->values[indexx].seq && i < cur->numValues; i++) 
		indexx++;
	returnVal = cur->values[indexx];
	for(i = indexx + 1; i < cur->numValues; ++i) 
		cur->values[i - 1] = cur->values[i];
	--cur->numValues;
	return returnVal;
}

bool packListContains(packList * list, uint16_t src, uint16_t seq) {
	uint8_t i = 0;
	for(i; i < list->numValues; i++) 
		if(seq == list->values[i].seq && src == list->values[i].src) 
		return TRUE;
	return FALSE;
}

//pops packet with lowest transport sequence number used for checking moving nextByteExpected
pack packListPopLowest(packList * list) {
	uint8_t i;
	pack low = list->values[0];
	for(i = 0; i < list->numValues; i++)
		low = (((transport *)low.payload)->seq > ((transport *)list->values[i].payload)->seq) ? list->values[i] : low;

	return packListPopPack(list, low.src, low.seq);
}

#endif /* PACK_LIST_H */
