/**
 * ANDES Lab - University of California, Merced
 * This class provides a list of workers needed by the server.
 *
 * @author UCM ANDES Lab
 * @date   Novemeber 3 2012
 * 
 */
#ifndef SERVER_WORKER_LIST_H
#define SERVER_WORKER_LIST_H

#include "serverJL.h"

typedef serverWorkerJL workerType;
enum{
	SERVER_WORKER_LIST_MAX_SIZE = 5
};

typedef struct serverWorkerList{	
	workerType values[SERVER_WORKER_LIST_MAX_SIZE];
	uint8_t numValues;
}serverWorkerList;

void serverWorkerListInit(serverWorkerList *cur){
	cur->numValues = 0;	
}

bool serverWorkerListPushBack(serverWorkerList* cur, workerType newVal){
	if(cur->numValues != SERVER_WORKER_LIST_MAX_SIZE){
		cur->values[cur->numValues] = newVal;
		++cur->numValues;
		return TRUE;	
	}else return FALSE;
}


bool serverWorkerListIsEmpty(serverWorkerList* cur){
	if(cur->numValues == 0)
		return TRUE;
	else
		return FALSE;
}

uint8_t serverWorkerListSize(serverWorkerList* cur){	return cur->numValues;}

workerType *serverWorkerListGet(serverWorkerList* cur, nx_uint8_t i){	return &(cur->values[i]);}

void serverWorkerListRemoveKey(serverWorkerList *list, uint8_t i){
	for(i=0; i<list->numValues-1; i++){
		list->values[i]=list->values[i+1];
	}
	list->numValues--;
}

bool serverWorkerListRemoveValue(serverWorkerList *list, workerType newVal){
	uint8_t i=0;

	for(i=0; i<list->numValues; i++){
		if(list->values[i].inSocket->destPort == newVal.inSocket->destPort &&
		list->values[i].inSocket->srcPort == newVal.inSocket->srcPort){
			serverWorkerListRemoveKey(list, i);
			return TRUE;
		}
	}
	return FALSE;
}

#endif /* SERVER WORKER LIST_H */