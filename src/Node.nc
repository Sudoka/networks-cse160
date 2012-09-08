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
	uint16_t sequenceNum = 0;
	uint16_t discoveryCounter = 0;

	bool busy = FALSE;
	
	message_t pkt;
	pack sendPackage;

	sendBuffer packBuffer;	
	arrlist Received;
	pair tempReceive;
	pair tempSend;
	
	bool isActive = TRUE;

	//Ping/PingReply Variables
	pingList pings;

	error_t send(uint16_t src, uint16_t dest, pack *message);
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
	task void sendBufferTask();
			
	
	event void Boot.booted(){
		call AMControl.start();
		
		dbg("genDebug", "Booted\n");
	}

	event void AMControl.startDone(error_t err){
		if(err == SUCCESS){
			call pingTimeoutTimer.startPeriodic(PING_TIMER_PERIOD + (uint16_t) ((call Random.rand16())%200));
			call discoveryTimer.startPeriodic(PING_TIMER_PERIOD + (uint16_t) ((call Random.rand16())%200));
		}else{
			//Retry until successful
			call AMControl.start();
		}
	}

	event void AMControl.stopDone(error_t err){}

	event void pingTimeoutTimer.fired(){
		checkTimes(&pings, call pingTimeoutTimer.getNow());
		dbg("Project1N", "checking ping timers\n");
	}
	
	event void discoveryTimer.fired() {
		dbg("Project1N", "fireeee %d %d\n", TOS_NODE_ID, discoveryCounter++);
	}
	
	
	event void AMSend.sendDone(message_t* msg, error_t error){
		//Clear Flag, we can send again.
		if(&pkt == msg){
			//dbg("Project1F", "---Packet Sent---\n\n");
			busy = FALSE;
			post sendBufferTask();
		}
	}

	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
		if(!isActive){
			dbg("genDebug", "The Node is inactive, packet will not be read.");
			return msg;	
		}
		if(len==sizeof(pack)){
			pack* myMsg=(pack*) payload;
			
			tempReceive.src = myMsg->src;
			tempReceive.seq = myMsg->seq;
			
			if(arrListContains(&Received, myMsg->src, myMsg->seq)) {
				dbg("Project1F", "Received a previously forwarded, sent, or received packet. Discarding\n\n");
				return msg;
			} else {
				if(TOS_NODE_ID == myMsg->dest) {
					dbg("Project1F", "Received packet ment for %d(me), receiving \n", TOS_NODE_ID, myMsg->dest);
				} else {
					dbg("Project1F", "Received packet ment for %d, sending to all neighbors \n", myMsg->dest);
				}
			}
			
			if(arrListPushBack(&Received, tempReceive)) {
				dbg("Project1F", "Packet Added to list of handled packets, It will not be reprocessed %d\n", arrListSize(&Received));
			} else {
				dbg("Project1F", "\n\n\npacket could not be added to list\n\n\n");
				//empty the list
			}

			if(TOS_NODE_ID==myMsg->dest){
				dbg("genDebug", "Packet from %d has arrived! Msg: %s\n", myMsg->src, myMsg->payload);
				switch(myMsg->protocol){
					uint8_t createMsg[PACKET_MAX_PAYLOAD_SIZE];
					uint16_t dest;
					//cases are named by the packet that was received, so the ping case is when you recieve a ping case, not when you send a ping case
					case PROTOCOL_PING:
						dbg("genDebug", "Sending Ping Reply to %d! \n\n", myMsg->src);
						makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, sequenceNum++, (uint8_t *) myMsg->payload, sizeof(myMsg->payload));
						sendBufferPushBack(&packBuffer, sendPackage, sendPackage.src, AM_BROADCAST_ADDR);
						post sendBufferTask();
						break;

					case PROTOCOL_PINGREPLY:
						dbg("genDebug", "Received a Ping Reply from %d (%s)!\n\n", myMsg->src, myMsg->payload);
						break;
						
					case PROTOCOL_CMD:
							switch(getCMD((uint8_t *) &myMsg->payload, sizeof(myMsg->payload))){
								uint32_t temp=0;
								case CMD_PING:
								    dbg("genDebug", "Ping packet received: %lu\n", temp);
									memcpy(&createMsg, (myMsg->payload) + PING_CMD_LENGTH, sizeof(myMsg->payload) - PING_CMD_LENGTH);
									memcpy(&dest, (myMsg->payload)+ PING_CMD_LENGTH-2, sizeof(uint8_t));
									makePack(&sendPackage, TOS_NODE_ID, (dest-48)&(0x00FF), MAX_TTL, PROTOCOL_PING, sequenceNum++, (uint8_t *)createMsg,
									sizeof(createMsg));	
									
									//Place in Send Buffer
									sendBufferPushBack(&packBuffer, sendPackage, sendPackage.src, sendPackage.dest);
									post sendBufferTask();
									
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
			}else if(TOS_NODE_ID==myMsg->src){
				dbg("cmdDebug", "Source is this node: %s\n", myMsg->payload);
				return msg;
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
		if(!busy && isActive){
			pack* msg = (pack *)(call Packet.getPayload(&pkt, sizeof(pack) ));			
			*msg = *message;

			//TTL Check
			if(msg->TTL >0)msg->TTL--;
			else return FAIL;

			if(call AMSend.send(dest, &pkt, sizeof(pack)) ==SUCCESS){
				busy = TRUE;
				
				tempSend.src = msg->src;
				tempSend.seq = msg->seq;
				
				if(arrListPushBack(&Received, tempSend)) {
					//dbg("Project1F", "packet recorded as previously sent %d\n\n", arrListSize(&Received));
				} else {
					//dbg("Project1F", "packet could not be added to list\n\n");
					//empty the list
				}
				
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

	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
		Package->src = src;
		Package->dest = dest;
		Package->TTL = TTL;
		Package->seq = seq;
		Package->protocol = protocol;
		memcpy(Package->payload, payload, length);
	}
}
