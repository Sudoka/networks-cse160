#ifndef HOP_LIST_H
#define HOP_LIST_H

typedef struct hopEntry {
	float cost;
	uint8_t nextHop;
	uint8_t confirmed;
} hopEntry;

typedef struct hopList {
	hopEntry entry[20];
} hopList;

void hopListAdd(hopList * list, uint8_t nodeID, float cost, uint8_t nextHop) {
	list->entry[nodeID].cost = cost;
	list->entry[nodeID].nextHop = nextHop;
}

void clearHopList(hopList * list) {
	uint8_t i;
	for(i = 0; i < 20; i++) {
		list->entry[i].cost = 144.0;
		list->entry[i].nextHop = -1;
		list->entry[i].confirmed = 0;
	}
}
#endif /* HOP_LIST_H */
