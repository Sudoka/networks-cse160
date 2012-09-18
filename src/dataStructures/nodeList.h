#ifndef NODE_LIST_H
#define NODE_LIST_H

typedef uint16_t ndataType;
#define ARRAYSIZE 30
#define MAXNUMVALS ARRAYSIZE

typedef struct nodeList
{	
	ndataType values[ARRAYSIZE]; //list of values
	uint8_t numValues;			//number of objects currently in the array
}nodeList;

void nodeListInit(nodeList *cur){
	cur->numValues = 0;	
}

bool nodeListPushBack(nodeList* cur, ndataType newVal){
	if(cur->numValues != MAXNUMVALS){
		cur->values[cur->numValues] = newVal;
		++cur->numValues;
		return TRUE;	
	}else return FALSE;
}

bool nodeListPushFront(nodeList* cur, ndataType newVal){
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

ndataType pop_backNode(nodeList* cur){
	--cur->numValues;
	return cur->values[cur->numValues];
}

ndataType pop_frontNode(nodeList* cur){
	ndataType returnVal;
	nx_uint8_t i;	
	returnVal = cur->values[0];
	for(i = 1; i < cur->numValues; ++i)
	{
		cur->values[i-1] = cur->values[i];
	}
	--cur->numValues;
	return returnVal;			
}

ndataType frontNode(nodeList* cur)
{
	return cur->values[0];
}

ndataType backNode(nodeList * cur)
{
	return cur->values[cur->numValues-1];	
}

bool nodeListIsEmpty(nodeList* cur)
{
	if(cur->numValues == 0)
		return TRUE;
	else
		return FALSE;
}

uint8_t nodeListSize(nodeList* cur){	return cur->numValues;}

void nodeListClear(nodeList* cur){	cur->numValues = 0;}

ndataType nodeListGet(nodeList* cur, nx_uint8_t i){	return cur->values[i];}

bool nodeListContains(nodeList* list, ndataType value){
	uint8_t i=0;
	for(i; i<list->numValues; i++){
		if(value == list->values[i]) return TRUE;
	}
	return FALSE;
}

#endif /* NODE_LIST_H */
