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
	
	uint16_t sequenceNum = 0, beaconSeq = 1;
	
	double pForward[MAX_NUM_NODES], pBackward[MAX_NUM_NODES];
	uint16_t lastBeaconSeq[MAX_NUM_NODES];

	bool busy = FALSE;
	bool triggerUpdate = FALSE;
	
	message_t pkt;
	pack sendPackage;

	sendBuffer packBuffer;	
	arrlist Received;
	
	bool isActive = TRUE;

	//Ping/PingReply Variables
	pingList pings;
	uint32_t discoveryList[MAX_NUM_NODES]; //times of last received discovery packet from all nodes
	uint8_t nextHop[MAX_NUM_NODES], costTable[MAX_NUM_NODES];
	uint16_t lastSeq[MAX_NUM_NODES];
	
	error_t send(uint16_t src, uint16_t dest, pack *message);
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint8_t TTL, uint8_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
	void updateNeighbors();
	void poisonHops(uint8_t * costList, uint8_t * tempList, uint16_t dest);
	void forward(pack *);
	task void sendBufferTask();
			
	
	event void Boot.booted(){
		uint8_t i;
		call AMControl.start();
		dbg("genDebug", "Booted\n");
		for(i = 0; i < MAX_NUM_NODES; i++) {
			pForward[i] = pBackward[i] = 1.0;
			lastBeaconSeq[i] = 0;
			nextHop[i] = costTable[i] = 0xFF;
		}
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
		if(TOS_NODE_ID == 3) beaconSeq += 3;
		makePack(&discoveryPack, TOS_NODE_ID, DISCOVERY_DEST, 1, PROTOCOL_PING, beaconSeq++, "", 0);
		sendBufferPushBack(&packBuffer, discoveryPack, discoveryPack.src, AM_BROADCAST_ADDR);
		post sendBufferTask();
	}
	
	void lspCall() {
		pack lspPack;
		uint8_t i;
		uint8_t tempCostTable[MAX_NUM_NODES];
		updateNeighbors();
		for(i = 0; i < MAX_NUM_NODES; i++) {
			if(nextHop[i] == i && i != TOS_NODE_ID) {
				poisonHops(costTable, tempCostTable, i);
				makePack(&lspPack, TOS_NODE_ID, i, MAX_TTL, PROTOCOL_LINKSTATE, sequenceNum++, tempCostTable, MAX_NUM_NODES);
				sendBufferPushBack(&packBuffer, lspPack, lspPack.src, i);
				post sendBufferTask();
			}
		}
	}
	
	event void lspTimer.fired() {
		lspCall();
	}
	
	
	event void AMSend.sendDone(message_t* msg, error_t error){
		//Clear Flag, we can send again.
		if(&pkt == msg){
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
			
			tempReceive.src = myMsg->src; tempReceive.seq = myMsg->seq;
			
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

			if(TOS_NODE_ID==myMsg->dest && myMsg->protocol != PROTOCOL_LINKSTATE){
				dbg("genDebug", "Packet from %d has arrived! Msg: %s\n\n", myMsg->src, myMsg->payload);
				switch(myMsg->protocol){
					uint8_t createMsg[PACKET_MAX_PAYLOAD_SIZE];
					uint16_t dest;
					case PROTOCOL_PING:
						dbg("genDebug", "Sending Ping Reply to %d! \n\n", myMsg->src);
						makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, sequenceNum++, myMsg->payload, sizeof(myMsg->payload));
						forward(&sendPackage);
						break;

					case PROTOCOL_PINGREPLY:
						dbg("genDebug", "Received a Ping Reply Src:%d Dest:%d TTL:%d protocol:%d Seq:%d Payload:(%s)!\n\n", myMsg->src, myMsg->dest, myMsg->TTL, myMsg->protocol, myMsg->seq, myMsg->payload);
						break;
						
					case PROTOCOL_CMD:
							switch(getCMD((uint8_t *) &myMsg->payload, sizeof(myMsg->payload))){
								case CMD_PING:
									memcpy(&createMsg, (myMsg->payload) + PING_CMD_LENGTH, sizeof(myMsg->payload) - PING_CMD_LENGTH);
									memcpy(&dest, (myMsg->payload)+ PING_CMD_LENGTH-2, sizeof(uint8_t));
									dbg("genDebug", "Sending Ping to node %d\n\n", (dest-48)&(0x00FF));
									makePack(&sendPackage, TOS_NODE_ID, (dest-48)&(0x00FF), MAX_TTL, PROTOCOL_PING, sequenceNum++, (uint8_t *)createMsg, sizeof(createMsg));
									forward(&sendPackage);
									break;
									
								case CMD_KILL:
									isActive = FALSE;
									break;
									
								case CMD_ERROR:
									break;
									
								default:
									break;
									
							}
						break;
						
					default:
						break;
						
				}
			} else if(TOS_NODE_ID == myMsg->src) {
				dbg("cmdDebug", "Source is this node: %s\n\n", myMsg->payload);
				return msg;
			} else if(myMsg->dest == DISCOVERY_DEST || myMsg->protocol == PROTOCOL_LINKSTATE) {
				switch(myMsg->protocol){
					double sample;
					uint8_t i;
					case PROTOCOL_PING: //broadcasts from neighbors
						//calculate the percentage of packets received from source (pBackward)
						sample = 1.0 / (myMsg->seq - lastBeaconSeq[myMsg->src]);
						pBackward[myMsg->src] = (pBackward[myMsg->src] + sample)/2.0;
						lastBeaconSeq[myMsg->src] = myMsg->seq;
						//send pBackward back to source to confirm neighbor and inform them of their probability of successful send (pForward)
						makePack(&sendPackage, TOS_NODE_ID, DISCOVERY_DEST, 1, PROTOCOL_PINGREPLY, myMsg->seq, (uint8_t *) &(pBackward[myMsg->src]), sizeof(double));
						sendBufferPushBack(&packBuffer, sendPackage, sendPackage.src, myMsg->src);
						post sendBufferTask();
						break;
						
					case PROTOCOL_PINGREPLY: //neighbors responses to my broadcasts
						pForward[myMsg->src] = *(double *)myMsg->payload; //neighbors pBackward = my pForward
						discoveryList[myMsg->src] = call pingTimeoutTimer.getNow(); //record time of most recently received beacon
						break;
						
					case PROTOCOL_LINKSTATE: //link state info from other nodes on the network
						if(myMsg->seq > lastSeq[myMsg->src]) {
							triggerUpdate = FALSE;
							lastSeq[myMsg->src] = myMsg->seq;
							updateNeighbors();
							for(i = 0; i < MAX_NUM_NODES; i++) {
								if((myMsg->payload[i] + costTable[myMsg->src]) < costTable[i]) {
									costTable[i] = myMsg->payload[i] + costTable[myMsg->src];
									nextHop[i] = myMsg->src;
									triggerUpdate = TRUE;
								} else if(nextHop[i] == myMsg->src) {
									costTable[i] = myMsg->payload[i] + costTable[myMsg->src];
								}
							}
							if(triggerUpdate) lspCall();;
						}
						break;
						
				}
			} else {
				forward(myMsg); //get outta here fka
			}
			return msg;
		}

		dbg("genDebug", "Unknown Packet Type\n");
		return msg;
	}
	
	void forward(pack * packet) {
		uint8_t i;
		if(costTable[packet->dest] == 0xFF) {
			dbg("Project2F", "---There is no path to the destination---\n\n");
			for(i = 0; i < MAX_NUM_NODES; i++)
				if(nextHop[i] < i) dbg("Project2F", "my neighbor %d\n", i);
		} else {
			sendBufferPushBack(&packBuffer, *packet, TOS_NODE_ID, nextHop[packet->dest]);
			post sendBufferTask();
			dbg("Project2F", "Forwarding Packet. Src:%d Dest:%d NextHop:%d cost:%d TTL:%d protocol:%d Seq:%d Payload:%s mySeq:%d\n\n", packet->src, packet->dest, nextHop[packet->dest], costTable[packet->dest], packet->TTL, packet->protocol, packet->seq, packet->payload, packet->seq);
		}
	}
		
	task void sendBufferTask(){
		if(packBuffer.size !=0 && !busy){
			sendInfo info;
			info = sendBufferPopFront(&packBuffer);
			send(info.src,info.dest, &(info.packet));
		}

		if(packBuffer.size !=0 && !busy)
			post sendBufferTask();
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
	error_t send(uint16_t src, uint16_t dest, pack * message){
		if(!busy && isActive){
			pack* msg = (pack *)(call Packet.getPayload(&pkt, sizeof(pack)));			
			*msg = *message;

			//TTL Check
			if(msg->TTL > 0)
				msg->TTL--;
			else
				return FAIL;

			if(call AMSend.send(dest, &pkt, sizeof(pack)) ==SUCCESS) {
				busy = TRUE;
				return SUCCESS;
			} else {
				dbg("genDebug","The radio is busy, or something\n");
				return FAIL;
			}
		} else
			return EBUSY;
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
		uint16_t i, j;
		uint8_t tempCost;
		triggerUpdate = FALSE;
		for(i = 0; i < MAX_NUM_NODES; i++) {
			if(discoveryList[i] != 0 && (call pingTimeoutTimer.getNow() - discoveryList[i]) < (20 * PING_TIMER_PERIOD))  {
				tempCost = 1.0/(pBackward[i]*pForward[i]); //connected, cost(based on ETX by De Couto in this case) corresponds to expected number of transmits needed to get an acknowledgment (irrelevant for project 2 but calculating cost of a path with no ARQ is more complicated and would have to be redone for project 3 (I think))
				if(nextHop[i] == i) {
					if(costTable[i] != tempCost) {
						costTable[i] = tempCost;
					}
				} else if(tempCost < costTable[i]) {
					costTable[i] = tempCost;
					nextHop[i] = i;
				}
			} else if(i == TOS_NODE_ID) {
				costTable[i] = 0; //self
				nextHop[i] = TOS_NODE_ID;
			} else if(nextHop[i] == i) {
				costTable[i] = 0xFF;
				nextHop[i] = 0xFF;
				for(j = 0; j < MAX_NUM_NODES; j++) {
					if(nextHop[j] == i) {
						costTable[j] = 0xFF;
						nextHop[j] = 0xFF;
					}
				}
			}
		}
	}
	
	void poisonHops(uint8_t * costList, uint8_t * tempList, uint16_t dest) {
			uint8_t i;
			for(i = 0; i < MAX_NUM_NODES; i++) {
				if(nextHop[i] == dest) {
					tempList[i] = 0xFF;
				} else {
					tempList[i] = costList[i];
				}
			}
	}
}
