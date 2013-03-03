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
#include "dataStructures/hopList.h"

//Ping Includes
#include "dataStructures/pingList.h"
#include "ping.h"

#define MAX_NUM_NODES 20

typedef struct linkReliability {
	uint32_t rollingList;
	uint16_t lastSeq;
} linkReliability;

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
	uses interface Timer<TMilli> as lspTimer;
	
}

implementation{
	uint16_t DISCOVERY_DEST = AM_BROADCAST_ADDR;
	
	uint16_t sequenceNum = 0, linkStateSeq = 0;//have a second link state sequence to prevent wraping, may need to change this but im rolling with it for now

	bool busy = FALSE;
	
	message_t pkt;
	pack sendPackage;

	sendBuffer packBuffer;	
	arrlist Received;
	
	bool isActive = TRUE;

	//Ping/PingReply Variables
	pingList pings;
	uint32_t discoveryList[MAX_NUM_NODES]; //times of last received discovery packet from all nodes
	linkReliability discoveryHitList[MAX_NUM_NODES]; //change to exponential weighted moving average
	double latencyMovingAverage[MAX_NUM_NODES];
	double pHMovingAverage[MAX_NUM_NODES];
	uint8_t costTable[MAX_NUM_NODES][MAX_NUM_NODES];
	uint16_t lastSeq[MAX_NUM_NODES];
	hopList confirmed;
	
	error_t send(uint16_t src, uint16_t dest, pack *message);
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint8_t TTL, uint8_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
	void updateNeighbors();
	void dijkstra();
	void forward(pack *);
	uint32_t NumberOfSetBits(uint32_t i);
	hopEntry getNextHop(hopList * list, uint8_t nodeID);
	
	task void sendBufferTask();
			
	
	event void Boot.booted(){
		call AMControl.start();
		dbg("genDebug", "Booted\n");
		dbg("genDebug", "testest");
	}

	event void AMControl.startDone(error_t err){
		if(err == SUCCESS){
			call pingTimeoutTimer.startPeriodic(PING_TIMER_PERIOD + (uint16_t) ((call Random.rand16())%200));
			call discoveryTimer.startPeriodic(PING_TIMER_PERIOD + (uint16_t) ((call Random.rand16())%200));
			call lspTimer.startPeriodic(PING_TIMER_PERIOD + (uint16_t) ((call Random.rand16())%200));
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
		pack discoveryPack;
		uint32_t curTime = call pingTimeoutTimer.getNow();
		if(TOS_NODE_ID == 3) linkStateSeq += 3; //emulates a lossy link
		makePack(&discoveryPack, TOS_NODE_ID, DISCOVERY_DEST, 1, PROTOCOL_PING, linkStateSeq++, &curTime, sizeof(curTime));
		sendBufferPushBack(&packBuffer, discoveryPack, discoveryPack.src, AM_BROADCAST_ADDR);
		post sendBufferTask();
		updateNeighbors();
	}
	
	event void lspTimer.fired() {
		pack lspPack;
		makePack(&lspPack, TOS_NODE_ID, AM_BROADCAST_ADDR, MAX_TTL, PROTOCOL_LINKSTATE, sequenceNum++, costTable[TOS_NODE_ID], MAX_NUM_NODES);
		sendBufferPushBack(&packBuffer, lspPack, lspPack.src, AM_BROADCAST_ADDR);
		post sendBufferTask();
	}
	
	
	event void AMSend.sendDone(message_t* msg, error_t error){
		//Clear Flag, we can send again.
		pack* dest = (pack*) msg->data;
		if(&pkt == msg){
			if(dest->dest != DISCOVERY_DEST)
				dbg("Project1F", "Send Complete src:%d dest:%d seq:%d protocol:%d TTL:%d data:%s\n\n", dest->src, dest->dest, dest->seq, dest->protocol, dest->TTL, dest->payload);
			busy = FALSE;
			post sendBufferTask();
		}
	}

	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
		if(!isActive){
			dbg("cmdDebug", "The Node is inactive, packet will not be read.\n");
			return msg;	
		}
		if(len==sizeof(pack)){
			pack* myMsg=(pack*) payload;
			pair tempReceive;
			
			tempReceive.src = myMsg->src;
			tempReceive.seq = myMsg->seq;
			
			if(myMsg->protocol == PROTOCOL_LINKSTATE) { //not even regulating non flooded packet types awe yea
				if(arrListContains(&Received, myMsg->src, myMsg->seq)) {
					return msg; //If you've already received, throw it away
				} else {
					if(Received.numValues == MAXNUMVALS)
						pop_front(&Received); //if its full pop the front
					if(!arrListPushBack(&Received, tempReceive)) //try to add to back
						dbg("Project1F", "Unknown failure to add packet to list of handled packets\n");
				}
			}

			if(TOS_NODE_ID==myMsg->dest){
				dbg("genDebug", "Packet from %d has arrived! Msg: %s\n\n", myMsg->src, myMsg->payload);
				switch(myMsg->protocol){
					uint8_t createMsg[PACKET_MAX_PAYLOAD_SIZE];
					uint16_t dest;
					case PROTOCOL_PING:
						makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, sequenceNum++, myMsg->payload, sizeof(myMsg->payload));
						forward(&sendPackage);
						dbg("genDebug", "Sending Ping Reply Src:%d Dest:%d NextHop:%d cost:%d TTL:%d protocol:%d Seq:%d Payload:%s\n\n", sendPackage.src, sendPackage.dest, getNextHop(&confirmed, sendPackage.dest).nextHop, getNextHop(&confirmed, sendPackage.dest).cost, sendPackage.TTL, sendPackage.protocol, sendPackage.seq, sendPackage.payload);
						break;

					case PROTOCOL_PINGREPLY:
						dbg("genDebug", "Received a Ping Reply from %d (%s)!\n\n", myMsg->src, myMsg->payload);
						break;
						
					case PROTOCOL_CMD:
							switch(getCMD((uint8_t *) &myMsg->payload, sizeof(myMsg->payload))){
								case CMD_PING:
									memcpy(&createMsg, (myMsg->payload) + PING_CMD_LENGTH, sizeof(myMsg->payload) - PING_CMD_LENGTH);
									memcpy(&dest, (myMsg->payload)+ PING_CMD_LENGTH-2, sizeof(uint8_t));
									makePack(&sendPackage, TOS_NODE_ID, (dest-48)&(0x00FF), MAX_TTL, PROTOCOL_PING, sequenceNum++, (uint8_t *)createMsg, sizeof(createMsg));
									forward(&sendPackage);
									dbg("genDebug", "Ping packet Sent: Src:%d Dest:%d NextHop:%d cost:%d TTL:%d protocol:%d Seq:%d Payload:%s\n\n", sendPackage.src, sendPackage.dest, getNextHop(&confirmed, sendPackage.dest).nextHop, getNextHop(&confirmed, sendPackage.dest).cost, sendPackage.TTL, sendPackage.protocol, sendPackage.seq, sendPackage.payload);
									break;
									
								case CMD_KILL:
									isActive = FALSE;
									break;
									
								case CMD_ERROR:
									break;
									
								case CMD_PRINT:
									//printNeighbors(TOS_NODE_ID, neighbors);
									break;
									
								case CMD_LSP:
									//gotta reimplement this later
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
			} else if(myMsg->dest == DISCOVERY_DEST) { //heres the meat of the program
				uint8_t i, temp;
				float alpha = 0.80;
				uint32_t latency;
				switch(myMsg->protocol){
					case PROTOCOL_PING: //broadcasts from neighbors
						//this is the next place to improve, add current time to when you do a ping broadcast
						//when you get back the reply you check the current time against it and you set that
						//to the latancy, use an exponential weighted moving average or some shit
						//also switch to moving average for lsp cost adverts
						temp = myMsg->seq - discoveryHitList[myMsg->src].lastSeq;
						if(discoveryHitList[myMsg->src].lastSeq == 0) {
							pHMovingAverage[myMsg->src] = 1.0;
							discoveryHitList[myMsg->src].rollingList = 0xFFFFFFFF;
							discoveryHitList[myMsg->src].lastSeq = myMsg->seq;
						} else {
							for(i = 0; i < temp; i++) {
								discoveryHitList[myMsg->src].rollingList = discoveryHitList[myMsg->src].rollingList << 1;
							}
							discoveryHitList[myMsg->src].rollingList += 0x1;
							pHMovingAverage[myMsg->src] = pHMovingAverage[myMsg->src]*alpha + (1.0/temp)*(1.0-alpha);
							discoveryHitList[myMsg->src].lastSeq = myMsg->seq;
						}
						makePack(&sendPackage, TOS_NODE_ID, DISCOVERY_DEST, 1, PROTOCOL_PINGREPLY, myMsg->seq, myMsg->payload, sizeof(myMsg->payload));
						sendBufferPushBack(&packBuffer, sendPackage, sendPackage.src, myMsg->src);
						post sendBufferTask();
						break;
						
					case PROTOCOL_PINGREPLY: //broadcast responses from neighbors
						discoveryList[myMsg->src] = call pingTimeoutTimer.getNow();
						latency = discoveryList[myMsg->src] - *(uint32_t *)myMsg->payload;
						if(latencyMovingAverage[myMsg->src] == 0.0) latencyMovingAverage[myMsg->src] = 12.0;
						latencyMovingAverage[myMsg->src] = latencyMovingAverage[myMsg->src]*0.95 + 0.05*latency;
						//dbg("Project2", "latency %f %d %d\n", latencyMovingAverage[myMsg->src], latency, myMsg->src);
						break;
						
					case PROTOCOL_LINKSTATE: //link state info from other nodes on the network
						if(myMsg->seq > lastSeq[myMsg->src]) {
							memcpy(costTable[myMsg->src], myMsg->payload, MAX_NUM_NODES);
							lastSeq[myMsg->src] = myMsg->seq;
							sendBufferPushBack(&packBuffer, *myMsg, TOS_NODE_ID, AM_BROADCAST_ADDR);
							post sendBufferTask();
						}
						break;
						
				}
			} else {
				makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL, myMsg->protocol, myMsg->seq, (uint8_t *) myMsg->payload, sizeof(myMsg->payload));
				forward(myMsg);
				dbg("Project1F", "Will Broadcast Packet\n\n");
				dbg("Project2", "Forwarding Packet. Src:%d Dest:%d NextHop:%d cost:%d TTL:%d protocol:%d Seq:%d Payload:%s mySeq:%d\n\n", myMsg->src, myMsg->dest, getNextHop(&confirmed, myMsg->dest).nextHop, getNextHop(&confirmed, myMsg->dest).cost, myMsg->TTL, myMsg->protocol, myMsg->seq, myMsg->payload, linkStateSeq);
			}
			return msg;
		}

		dbg("genDebug", "Unknown Packet Type\n");
		return msg;
	}
	
	void forward(pack * packet) {
		uint8_t i = 0;
		hopEntry nextHop;
		dijkstra();
		nextHop = getNextHop(&confirmed, packet->dest);
		if(nextHop.cost == 0xFF) {
			dbg("Project2", "---There is no path to the destination---\n\n");
			for(i = 0; i < MAX_NUM_NODES; i++)
				if(costTable[TOS_NODE_ID][i] < 0xFF) dbg("Project2", "my neighbor %d\n", i);
		} else {
			sendBufferPushBack(&packBuffer, *packet, TOS_NODE_ID, nextHop.nextHop);
			post sendBufferTask();
		}
	}
	
	hopEntry getNextHop(hopList * list, uint8_t nodeID) {
		uint8_t i;
		hopEntry temp;
		temp.cost = 0xFF; temp.nodeID = 0xFF; temp.nextHop = 0xFF;
		while(i < list->numValues) {
			if(list->values[i].nodeID == nodeID) {
				return confirmed.values[i];
			}
			i++;
		}
		return temp;
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
	
	void updateNeighbors() {
		uint16_t i;
		uint8_t testCost;
		for(i = 0; i < MAX_NUM_NODES; i++) {
			if(discoveryList[i] != 0 && (call pingTimeoutTimer.getNow() - discoveryList[i]) < (20 * PING_TIMER_PERIOD)) {
				testCost = 32.0 / NumberOfSetBits(discoveryHitList[i].rollingList);
				costTable[TOS_NODE_ID][i] = testCost;
				if(TOS_NODE_ID == 1 && i == 3) dbg("genDebug", "cost is %f %f\n", 32.0 / NumberOfSetBits(discoveryHitList[i].rollingList), 1.0/pHMovingAverage[i]);
			} else {
				costTable[TOS_NODE_ID][i] = 0xFF; //set unconnected neighbors i havnt received from (maybe they exist maybe they dont but they arnt connected to me so cost infinity)
			}
		}
	}
	
	void dijkstra() {
		hopList tenative;
		hopEntry temp;
		uint8_t i, j, curNode, curCost, minCost;
		hopListClear(&tenative);
		hopListClear(&confirmed);
		for(i = 0; i < MAX_NUM_NODES; i++) {
			for(j = 0; j < MAX_NUM_NODES; j++) {
				if(costTable[i][j] == 0) costTable[i][j] = 0xFF; //set unconnected (lists from nonconnected nodes (maybe they exist maybe they dont))
				if(!hopListContains(&tenative, j) && j != TOS_NODE_ID && costTable[i][j] < 0xFF) {
					temp.nodeID = j; temp.cost = 0xFF; temp.nextHop = 0xFF;
					hopListPushBack(&tenative, temp);
				}
			}
		}
		temp.nodeID = TOS_NODE_ID; temp.cost = 0x0; temp.nextHop = 0xFF;
		hopListPushBack(&confirmed, temp);
		while(tenative.numValues > 0) {
			for(i = 0; i < tenative.numValues; i++) {
				curNode = tenative.values[i].nodeID;
				curCost = tenative.values[i].cost;
				if(curCost > (temp.cost + costTable[temp.nodeID][curNode]) && costTable[temp.nodeID][curNode] != 0xFF) {
					tenative.values[i].cost = (temp.cost + costTable[temp.nodeID][curNode]);
					if(temp.nextHop != 0xFF)
						tenative.values[i].nextHop = temp.nextHop;
					else
						tenative.values[i].nextHop = curNode;
				}
			}
			minCost = 0;
			for(i = 0; i < tenative.numValues; i++) {
				if(tenative.values[i].cost < tenative.values[minCost].cost) {
					minCost = i;
				}
			}
			hopListPushBack(&confirmed, tenative.values[minCost]);
			temp.nodeID = tenative.values[minCost].nodeID; temp.cost = tenative.values[minCost].cost; temp.nextHop = tenative.values[minCost].nextHop;
			pop_Hop(&tenative, minCost);
		}
	}

	//found this here http://stackoverflow.com/questions/109023/best-algorithm-to-count-the-number-of-set-bits-in-a-32-bit-integer
	//just gonna use this for my rolling average i can rewrite my own version later this just saved me 10
	//minutes and is probably better than anything i could write
	uint32_t NumberOfSetBits(uint32_t i) {
	    i = i - ((i >> 1) & 0x55555555);
	    i = (i & 0x33333333) + ((i >> 2) & 0x33333333);
	    return (((i + (i >> 4)) & 0x0F0F0F0F) * 0x01010101) >> 24;
	}
}
