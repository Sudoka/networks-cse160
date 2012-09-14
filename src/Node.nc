/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   Apr 28 2012
 * 
 * 
 * for the broadcast how do we send it to all neighbors (with broadcast address) while still having a specific
 * node be the destination, do we have to put in another self made frame with a destination address.
 * 
 * does the sequence number change when its rebroadcasted?
 * 
 * for future projects are we going to need to be able to send some packets using flooding and some packets
 * with routing, i feel like the setup of the receive event is going to change for each of them
 */ 
#include <Timer.h>
#include "command.h"
#include "packet.h"
#include "dataStructures/list.h"
#include "dataStructures/pair.h"
#include "packBuffer.h"
#include "dataStructures/hashmap.h"
#include "dataStructures/nodeList.h"

//Ping Includes
#include "dataStructures/pingList.h"
#include "ping.h"





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
	uint16_t DISCOVERY_TIMER_PERIOD = 10003; //dayum, thats one big prime number
	
	uint16_t sequenceNum = 0;
	uint16_t discoveryCounter = 0;

	bool busy = FALSE;
	
	message_t pkt;
	pack sendPackage;

	sendBuffer packBuffer;	
	arrlist Received;
	
	bool isActive = TRUE;

	//Ping/PingReply Variables
	pingList pings;
	uint32_t discoveryList[20];
	nodeList neighbors;
	
	error_t send(uint16_t src, uint16_t dest, pack *message);
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint8_t TTL, uint8_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
	void discoverNeighbors();
	void updateNeighbors();
	void printNeighbors();
	
	task void sendBufferTask();
			
	
	event void Boot.booted(){
		call AMControl.start();
		
		dbg("genDebug", "Booted\n");
		//if(TOS_NODE_ID == 2)
		//	discoverNeighbors(PACKET_MAX_PAYLOAD_SIZE);	
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
	}
	
	
	event void AMSend.sendDone(message_t* msg, error_t error){
		//Clear Flag, we can send again.
		if(&pkt == msg){
			//dbg("Project1F", "Send Done\n\n");
			busy = FALSE;
			post sendBufferTask();
		}
	}

	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
		if(!isActive){
			dbg("genDebug", "The Node is inactive, packet will not be read.\n");
			return msg;	
		}
		if(len==sizeof(pack)){
			pack* myMsg=(pack*) payload;
			pair tempReceive;
			
			tempReceive.src = myMsg->src;
			tempReceive.seq = myMsg->seq;
			
			//dbg("Project1F", "Packet Received. Status : ");
			
			if(arrListContains(&Received, myMsg->src, myMsg->seq)) {
				dbg("Project1F", "Received a previously forwarded, sent, or received packet. Discarding MSG : %s Seq : %d\n\n", myMsg->payload, myMsg->seq);
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
			
			if(myMsg->dest != DISCOVERY_DEST) {
				if(arrListPushBack(&Received, tempReceive)) {
					dbg("Project1F", "Packet Added to list of handled packets, will not reprocess %d\n", arrListSize(&Received));
				} else {
					//dbg("Project1F", "---List is full, making room---\n");
					//empty the list
					pop_front(&Received);
					if(!arrListPushBack(&Received, tempReceive))
						dbg("Project1F", "Unknown failure to add packet to list of handled packets\n");
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
						sendBufferPushBack(&packBuffer, sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR);
						post sendBufferTask();
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
									
									//Place in Send Buffer
									sendBufferPushBack(&packBuffer, sendPackage, sendPackage.src, AM_BROADCAST_ADDR);
									post sendBufferTask();
									
									break;
								case CMD_KILL:
									isActive = FALSE;
									break;
								case CMD_ERROR:
									break;
								case CMD_PRINT:
									printNeighbors();
									break;
								default:
									break;
							}
						break;
					default:
						break;
				}
			}else if(TOS_NODE_ID==myMsg->src){
				dbg("genDebug", "Source is this node: %s\n\n", myMsg->payload);
				return msg;
			} else if(myMsg->dest == DISCOVERY_DEST) {
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
				}
			} else {
				makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL, myMsg->protocol, myMsg->seq, (uint8_t *) myMsg->payload, sizeof(myMsg->payload));
				sendBufferPushBack(&packBuffer, sendPackage, sendPackage.src, AM_BROADCAST_ADDR);
				post sendBufferTask();
				dbg("Project1F", "Packet broadcasted\n\n");
			}
			return msg;
		}

		dbg("genDebug", "Unknown Packet Type\n");
		return msg;
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

				
				/*
				 * 
				 * 
				tempSend.src = message->src;
				tempSend.seq = message->seq;
				
				if(!arrListContains(&Received, tempSend.src, tempSend.seq)){
					if(arrListPushBack(&Received, tempSend)) {
						dbg("Project1F", "Packet Added to list of handled packets, will not reprocess %d\n\n", arrListSize(&Received));
					} else {
						dbg("Project1F", "packet could not be added to list\n\n");
						//empty the list
						pop_front(&Received);
						if(!arrListPushBack(&Received, tempSend))
							dbg("Project1F", "Unknown failure to add packet to list of handled packets\n");
					}
				} else {
					//you should reach this part of the if statement when you are rebroadcasting a packet that you just received.
				}
				*/
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
		//dbg("Project1N", "Updating neighbor list\n");
		nodeListClear(&neighbors);
		for(i = 0; i < HASH_MAX_SIZE; i++) {
			if(discoveryList[i]+100009 < call pingTimeoutTimer.getNow()) {
				//node is not a neighbor or has timed out
			} else {
				nodeListPushBack(&neighbors, i);
			}
		}
	}
	
	void printNeighbors() {
		uint8_t i;
		for(i = 0; i < neighbors.numValues; i++) {
			dbg("Project1N", "Connected to : %d %d\n", neighbors.values[i], discoveryList[neighbors.values[i]]);
		} 
	}		
}
