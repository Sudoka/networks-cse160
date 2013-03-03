/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   October 1 2012
 * 
 */ 

#ifndef SERVER_WORKER_LIST_H
#define SERVER_WORKER_LIST_H

#include "../lib/serverAL.h"

typedef serverWorkerAL workerType;
enum{
	SERVER_WORKER_LIST_MAX_SIZE = 5
};

typedef struct serverWorkerList{	
	workerType values[SERVER_WORKER_LIST_MAX_SIZE]; //list of values
	uint8_t numValues;			//number of objects currently in the array
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
	for(; i<list->numValues-1; i++){
		list->values[i]=list->values[i+1];
	}
	list->numValues--;
}

void serverWorkerListRemoveValue(serverWorkerList *list, workerType val) {
	uint8_t i;
	for(i = 0; i < list->numValues; i++)
		if(list->values[i].socket == val.socket)
			serverWorkerListRemoveKey(list, i);
}

#endif /* SERVER LIST_H */
