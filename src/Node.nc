/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   Apr 28 2012
 */ 
#include <Timer.h>
#include "command.h"
#include "packet.h"
#include "dataStructures/list.h"
#include "dataStructures/pair.h"
#include "packBuffer.h"
#include "dataStructures/hashmap.h"
#include "dataStructures/nodeList.h"
#include "dataStructures/hopList.h"

//Ping Includes
#include "dataStructures/pingList.h"
#include "ping.h"

#define MAX_NUM_NODES 20

typedef struct nodeMap {
	uint8_t seq[20];
	nodeList linkState[20];
} nodeMap;

module Node{
	uses interface Boot;
	uses interface Timer<TMilli> as pingTimeoutTimer;
	
	uses interface Random as Random;
	
	uses interface Packet;
	uses interface AMPacket;
	uses interface AMSend;
	uses interface SplitControl as AMControl;
	uses interface Receive;
	
	uses interface Timer<TMilli> as discoveryTimer;
	
}

implementation{
	uint16_t DISCOVERY_DEST = AM_BROADCAST_ADDR;
	uint16_t DISCOVERY_TIMER_PERIOD = 10003; //dayum, thats one big prime number, o wait i lied
	
	uint16_t sequenceNum = 0, linkStateSeq = 0;//have a second link state sequence to prevent wraping, may need to change this but im rolling with it for now
	uint16_t discoveryCounter = 0;

	bool busy = FALSE;
	
	message_t pkt;
	pack sendPackage;

	sendBuffer packBuffer;	
	arrlist Received;
	
	bool isActive = TRUE;

	//Ping/PingReply Variables
	pingList pings;
	uint32_t discoveryList[MAX_NUM_NODES];
	nodeList neighbors;
	nodeList allNodes;
	nodeMap networkMap;
	hopList confirmed;
	
	error_t send(uint16_t src, uint16_t dest, pack *message);
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint8_t TTL, uint8_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
	void discoverNeighbors();
	void updateNeighbors();
	void printNeighbors(uint16_t nodeID, nodeList nodeNeighbors);
	void sendLSP();
	uint8_t countNodes(nodeMap map);
	void dijkstra();
	void forward(pack *);
	uint32_t NumberOfSetBits(uint32_t i);
	
	task void sendBufferTask();
			
	
	event void Boot.booted(){
		call AMControl.start();
		dbg("genDebug", "Booted\n");
	}

	event void AMControl.startDone(error_t err){
		if(err == SUCCESS){
			call pingTimeoutTimer.startPeriodic(PING_TIMER_PERIOD + (uint16_t) ((call Random.rand16())%200));
			call discoveryTimer.startPeriodic(DISCOVERY_TIMER_PERIOD);
		}else{
			//Retry until successful
			call AMControl.start();
		}
	}

	event void AMControl.stopDone(error_t err){
		
	}

	event void pingTimeoutTimer.fired(){
		checkTimes(&pings, call pingTimeoutTimer.getNow());
	}
	
	event void discoveryTimer.fired() {
		discoverNeighbors();
		discoveryCounter++;
		if(discoveryCounter%5)
			sendLSP();
	}
	
	
	event void AMSend.sendDone(message_t* msg, error_t error){
		//Clear Flag, we can send again.
		pack* dest = (pack*) msg->data;
		if(&pkt == msg){
			//dbg("Project2", "got here \n");
			if(dest->dest != DISCOVERY_DEST)
				dbg("Project1F", "Send Complete src:%d dest:%d seq:%d protocol:%d TTL:%d data:%s\n\n", dest->src, dest->dest, dest->seq, dest->protocol, dest->TTL, dest->payload);
			busy = FALSE;
			post sendBufferTask();
		}
	}

	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
		if(!isActive){
			//dbg("genDebug", "The Node is inactive, packet will not be read.\n");
			return msg;	
		}
		if(len==sizeof(pack)){
			pack* myMsg=(pack*) payload;
			pair tempReceive;
			
			tempReceive.src = myMsg->src;
			tempReceive.seq = myMsg->seq;
			
			if(arrListContains(&Received, myMsg->src, myMsg->seq)) {
				//dbg("Project1F", "Received a previously forwarded, sent, or received packet. Discarding MSG : %s Seq : %d\n\n", myMsg->payload, myMsg->seq);
				return msg;
			} else {
				if(TOS_NODE_ID == myMsg->dest) {
					dbg("Project1F", "Received packet meant for %d(me), receiving \n", TOS_NODE_ID, myMsg->dest);
				} else if (myMsg->dest == DISCOVERY_DEST) {
					//dbg("Project1N", "Received a Neighbor Discovery packet\n");
				} else {
					dbg("Project1F", "Received packet meant for %d, sending to all neighbors %d %d %s \n", myMsg->dest, myMsg->src, myMsg->dest, myMsg->payload);
				}
			}
			
			if(myMsg->dest == DISCOVERY_DEST && myMsg->protocol != PROTOCOL_LINKSTATE) {
				//received a discovery packet
			} else {
				if(arrListPushBack(&Received, tempReceive)) {
					//dbg("Project1F", "Packet Added to list of handled packets, will not reprocess %d\n", arrListSize(&Received));
				} else {
					//empty the list
					pop_front(&Received);
					if(!arrListPushBack(&Received, tempReceive))
						dbg("Project1F", "Unknown failure to add packet to list of handled packets\n");
					//else
						//dbg("Project1F", "Packet Added to list of handled packets, will not reprocess %d\n", arrListSize(&Received));
				}
			}

			if(TOS_NODE_ID==myMsg->dest){
				dbg("genDebug", "Packet from %d has arrived! Msg: %s\n\n", myMsg->src, myMsg->payload);
				switch(myMsg->protocol){
					uint8_t createMsg[PACKET_MAX_PAYLOAD_SIZE];
					uint16_t dest;
					case PROTOCOL_PING:
						dbg("genDebug", "Sending Ping Reply to %d!\n\n", myMsg->src);
						makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, sequenceNum++, myMsg->payload, sizeof(myMsg->payload));
						forward(&sendPackage);
						//sendBufferPushBack(&packBuffer, sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR);
						//post sendBufferTask();
						break;

					case PROTOCOL_PINGREPLY:
						dbg("genDebug", "Received a Ping Reply from %d (%s)!\n\n", myMsg->src, myMsg->payload);
						break;
						
					case PROTOCOL_CMD:
							switch(getCMD((uint8_t *) &myMsg->payload, sizeof(myMsg->payload))){
								uint32_t temp=0;
								case CMD_PING:
									memcpy(&createMsg, (myMsg->payload) + PING_CMD_LENGTH, sizeof(myMsg->payload) - PING_CMD_LENGTH);
									memcpy(&dest, (myMsg->payload)+ PING_CMD_LENGTH-2, sizeof(uint8_t));
									makePack(&sendPackage, TOS_NODE_ID, (dest-48)&(0x00FF), MAX_TTL, PROTOCOL_PING, sequenceNum++, (uint8_t *)createMsg, sizeof(createMsg));
									dbg("genDebug", "Ping packet Sent: %d %d %d %d %s\n\n", sendPackage.src, sendPackage.dest, sendPackage.seq, sendPackage.TTL, sendPackage.payload);
									
									forward(&sendPackage);
									//find the retrieve address of next hop, (what if there isnt one? what if its because list isnt set up? what if its because there is no route to that node?)
									//Place in Send Buffer
									//sendBufferPushBack(&packBuffer, sendPackage, sendPackage.src, 2);
									//post sendBufferTask();
									
									break;
								case CMD_KILL:
									isActive = FALSE;
									break;
								case CMD_ERROR:
									break;
								case CMD_PRINT:
									printNeighbors(TOS_NODE_ID, neighbors);
									break;
								case CMD_LSP:
									for(temp = 0; temp < MAX_NUM_NODES; temp++) {
										if(networkMap.linkState[temp].numValues > 0)
											printNeighbors(temp, networkMap.linkState[temp]);
									}
									dijkstra();
									for(temp = 0; temp < MAX_NUM_NODES; temp++) {
										dbg("Project2", "Node :%d next hop is Node : %d\n", temp, confirmed.entry[temp].nextHop);
									}
									break;
								default:
									break;
							}
						break;
					default:
						break;
				}
			}else if(TOS_NODE_ID==myMsg->src){
				dbg("cmdDebug", "Source is this node: %s\n\n", myMsg->payload);
				return msg;
			} else if(myMsg->dest == DISCOVERY_DEST) {
				uint8_t i;
				nodeList * receivedList;
				switch(myMsg->protocol){
					case PROTOCOL_PING:
						makePack(&sendPackage, TOS_NODE_ID, DISCOVERY_DEST, 1, PROTOCOL_PINGREPLY, sequenceNum++, "", sizeof(myMsg->payload));
						sendBufferPushBack(&packBuffer, sendPackage, sendPackage.src, myMsg->src);
						post sendBufferTask();
						break;
					case PROTOCOL_PINGREPLY:
						discoveryList[myMsg->src] = call pingTimeoutTimer.getNow();
						updateNeighbors();
						break;
					case PROTOCOL_LINKSTATE:
						receivedList = (nodeList *) myMsg->payload;
						//dbg("Project2", "Received a LinkState Packet %d\n", receivedList->numValues);
						if(myMsg->seq >= networkMap.seq[myMsg->src]) {
							memcpy(&networkMap.linkState[myMsg->src], myMsg->payload, MAX_NUM_NODES);
							networkMap.seq[myMsg->src] = myMsg->seq;
							//printNeighbors(myMsg->src, networkMap.linkState[myMsg->src]);
							sendBufferPushBack(&packBuffer, *myMsg, TOS_NODE_ID, AM_BROADCAST_ADDR);
						}
						break;
				}
			} else {
				makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL, myMsg->protocol, myMsg->seq, (uint8_t *) myMsg->payload, sizeof(myMsg->payload));
				forward(myMsg);
				//sendBufferPushBack(&packBuffer, sendPackage, sendPackage.src, AM_BROADCAST_ADDR);
				//post sendBufferTask();
				dbg("Project1F", "Will Broadcast Packet\n\n");
				dbg("Project2", "Forwarding Packet. Src:%d Dest:%d NextHop:%d TTL:%d protocol:%d Seq:%d Payload:%s\n\n", myMsg->src, myMsg->dest, confirmed.entry[myMsg->dest].nextHop, myMsg->TTL, myMsg->protocol, myMsg->seq, myMsg->payload);
			}
			return msg;
		}

		dbg("genDebug", "Unknown Packet Type\n");
		return msg;
	}
	
	void forward(pack * packet) {
		uint8_t nextHop;
		dijkstra();
		nextHop = confirmed.entry[packet->dest].nextHop;
		if(nextHop == 255) {
			dbg("Project2", "---There is no path to the destination---\n\n");
		} else if (nextHop == TOS_NODE_ID) {
			dbg("Project2", "Why are you trying to send to yourself?\n");
		} else {
			sendBufferPushBack(&packBuffer, *packet, TOS_NODE_ID, nextHop);
			post sendBufferTask();
		}
	}
	
	task void sendBufferTask(){
		if(packBuffer.size !=0 && !busy){
			sendInfo info;
			info = sendBufferPopFront(&packBuffer);
			send(info.src,info.dest, &(info.packet));
		}
		
		if(packBuffer.size !=0 && !busy){
			post sendBufferTask();
		}
	}

	/*
	* Send a packet
	*
	*@param
	*	src - source address
	*	dest - destination address
	*	msg - payload to be sent
	*
	*@return
	*	error_t - Returns SUCCESS, EBUSY when the system is too busy using the radio, or FAIL.
	*/
	error_t send(uint16_t src, uint16_t dest, pack *message){
		pair tempSend;
		if(!busy && isActive){
			pack* msg = (pack *)(call Packet.getPayload(&pkt, sizeof(pack) ));			
			*msg = *message;

			//TTL Check
			if(msg->TTL >0)msg->TTL--;
			else return FAIL;

			if(call AMSend.send(dest, &pkt, sizeof(pack)) ==SUCCESS){
				busy = TRUE;
				return SUCCESS;
			}else{
				dbg("genDebug","The radio is busy, or something\n");
				return FAIL;
			}
		}else{
			return EBUSY;
		}
		dbg("genDebug", "FAILED!?");
		return FAIL;
	}	

	void makePack(pack *Package, uint16_t src, uint16_t dest, uint8_t TTL, uint8_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
		Package->src = src;
		Package->dest = dest;
		Package->TTL = TTL;
		Package->seq = seq;
		Package->protocol = protocol;
		memcpy(Package->payload, payload, length);
	}
	
	void discoverNeighbors(){
		pack discoveryPack;
		makePack(&discoveryPack, TOS_NODE_ID, DISCOVERY_DEST, 1, PROTOCOL_PING, sequenceNum++, "", PACKET_MAX_PAYLOAD_SIZE);
		sendBufferPushBack(&packBuffer, discoveryPack, discoveryPack.src, AM_BROADCAST_ADDR);
		post sendBufferTask();
	}
	
	void updateNeighbors() {
		uint16_t i;
		nodeListClear(&neighbors);
		for(i = 0; i < MAX_NUM_NODES; i++) {
			if(discoveryList[i] != 0 && (call pingTimeoutTimer.getNow() - discoveryList[i]) < (20 * DISCOVERY_TIMER_PERIOD)) {
				nodeListPushBack(&neighbors, i);
			}
		}
	}
	
	void sendLSP() {
		pack lspPack;
		//dbg("Project2", "size : %d\n", neighbors.numValues);
		makePack(&lspPack, TOS_NODE_ID, AM_BROADCAST_ADDR, MAX_TTL, PROTOCOL_LINKSTATE, sequenceNum++, &neighbors, sizeof(neighbors));
		sendBufferPushBack(&packBuffer, lspPack, lspPack.src, AM_BROADCAST_ADDR);
		//add one entry per neighbor with their id and seq of this packet to be checked for ack
		post sendBufferTask();
		memcpy(&networkMap.linkState[TOS_NODE_ID], &neighbors, MAX_NUM_NODES);
		networkMap.seq[TOS_NODE_ID] = sequenceNum;
	}
	
	void dijkstra() {
		hopList tenative;
		uint8_t lastNode = TOS_NODE_ID, i, minCost, minNode, curNode, curTenative = 0;
		clearHopList(&tenative);
		clearHopList(&confirmed);
		hopListAdd(&confirmed, TOS_NODE_ID, 0, TOS_NODE_ID);
		tenative.entry[lastNode].confirmed = 1; //add self as best hop to self
		for(i = 0; i < networkMap.linkState[lastNode].numValues; i++) { // add my neighbors as next best hops
			if(nodeListContains(&networkMap.linkState[networkMap.linkState[lastNode].values[i]], lastNode)) {
				hopListAdd(&tenative, networkMap.linkState[lastNode].values[i], 1, networkMap.linkState[lastNode].values[i]);
				curTenative++;
			}
		}
		while(curTenative > 0) {
			minCost = 0xFF;
			for(i = 0; i < MAX_NUM_NODES; i++) {
				if(!tenative.entry[i].confirmed && tenative.entry[i].cost < minCost) {
					minCost = tenative.entry[i].cost; //find node with cheapest cost
					minNode = i;
				}
			}
			hopListAdd(&confirmed, minNode, minCost, tenative.entry[minNode].nextHop);
			tenative.entry[minNode].confirmed = 1; //add cheapest neighbor to confirmed, its garunteed to be best hop to itself
			curTenative--;
			lastNode = minNode;
			for(i = 0; i < networkMap.linkState[lastNode].numValues; i++) {
				curNode = networkMap.linkState[lastNode].values[i]; //go through all of the previous cheapest nodes's neighbors and look for cheaper / new routes to any of the nodes its connected to
				if(nodeListContains(&networkMap.linkState[curNode], lastNode)) {
					if(!tenative.entry[curNode].confirmed && (minCost + 1) < tenative.entry[curNode].cost) {
						hopListAdd(&tenative, curNode, (minCost + 1), confirmed.entry[lastNode].nextHop);
						curTenative++;
					}
				}
			}
		}
	}
	
	uint8_t countNodes(nodeMap map) {
		uint8_t i,j;
		nodeListClear(&allNodes);
		for(i = 0; i < MAX_NUM_NODES; i++) {
			for(j = 0; j < map.linkState[i].numValues; j++) {
				if(!nodeListContains(&allNodes, map.linkState[i].values[j])) {
					nodeListPushBack(&allNodes, map.linkState[i].values[j]);
				}
			}
		}
		return allNodes.numValues;
	}

	//found this here http://stackoverflow.com/questions/109023/best-algorithm-to-count-the-number-of-set-bits-in-a-32-bit-integer
	//just gonna use this for my rolling average i can rewrite my own version later this just saved me 10
	//minutes and is probably better than anything i could write
	uint32_t NumberOfSetBits(uint32_t i) {
	    i = i - ((i >> 1) & 0x55555555);
	    i = (i & 0x33333333) + ((i >> 2) & 0x33333333);
	    return (((i + (i >> 4)) & 0x0F0F0F0F) * 0x01010101) >> 24;
	}
	
	void printNeighbors(uint16_t nodeID, nodeList nodeNeighbors) {
		uint8_t i;
		for(i = 0; i < nodeNeighbors.numValues; i++) {
			dbg("Project2", "%d is connected to Node:%d\n", nodeID, nodeNeighbors.values[i]);
			dbg("Project1N", "Connected to : %d %d\n", i, discoveryList[i]);
		}
	}		
}
