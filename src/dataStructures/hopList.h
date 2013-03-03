#ifndef HOP_LIST_H
#define HOP_LIST_H
#define ARRAYSIZE 20
#define MAXNUMVALS ARRAYSIZE

typedef struct hopEntry {
	uint8_t nodeID;
	uint8_t cost;
	uint8_t nextHop;
} hopEntry;

typedef struct hopList
{	
	hopEntry values[ARRAYSIZE]; //list of values
	uint8_t numValues;			//number of objects currently in the array
}hopList;

void hopListInit(hopList *cur){
	cur->numValues = 0;	
}

bool hopListPushBack(hopList* cur, hopEntry newVal){
	if(cur->numValues != MAXNUMVALS){
		cur->values[cur->numValues] = newVal;
		++cur->numValues;
		return TRUE;	
	}else return FALSE;
}

bool hopListPushFront(hopList* cur, hopEntry newVal){
	if(cur->numValues!= MAXNUMVALS){
		uint8_t i;
		for(i = cur->numValues-1; i >= 0; --i){
			cur->values[i+1] = cur->values[i];
		}
		cur->values[0] = newVal;
		++cur->numValues;
		return TRUE;	
	}else	return FALSE;
} 

hopEntry pop_backHop(hopList* cur){
	--cur->numValues;
	return cur->values[cur->numValues];
}

hopEntry pop_frontHop(hopList* cur){
	hopEntry returnVal;
	nx_uint8_t i;	
	returnVal = cur->values[0];
	for(i = 1; i < cur->numValues; ++i)
	{
		cur->values[i-1] = cur->values[i];
	}
	--cur->numValues;
	return returnVal;			
}

hopEntry pop_Hop(hopList* cur, uint8_t indexx) {
	hopEntry returnVal;
	nx_uint8_t i;	
	returnVal = cur->values[indexx];
	for(i = indexx + 1; i < cur->numValues; ++i)
	{
		cur->values[i-1] = cur->values[i];
	}
	--cur->numValues;
	return returnVal;
}

hopEntry frontHop(hopList* cur)
{
	return cur->values[0];
}

hopEntry backHop(hopList * cur)
{
	return cur->values[cur->numValues-1];	
}

bool hopListIsEmpty(hopList* cur)
{
	if(cur->numValues == 0)
		return TRUE;
	else
		return FALSE;
}

uint8_t hopListSize(hopList* cur){	return cur->numValues;}

void hopListClear(hopList* cur){	cur->numValues = 0;}

hopEntry hopListGet(hopList* cur, nx_uint8_t i){	return cur->values[i];}

bool hopListContains(hopList* list, uint8_t value){
	uint8_t i=0;
	for(i; i<list->numValues; i++){
		if(value == list->values[i].nodeID) return TRUE;
	}
	return FALSE;
}
#endif /* HOP_LIST_H */
