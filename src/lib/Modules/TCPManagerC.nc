#include "TCPSocketAL.h"
#include "../../transport.h"
#include "../../packet.h"
#include "../../dataStructures/portList.h"
#include "../../dataStructures/receiverBuffer.h"
#include "../../dataStructures/senderBuffer.h"
#define MAX_SOCKS 20

module TCPManagerC{
	provides interface TCPManager<TCPSocketAL, pack>;
	uses interface TCPSocket<TCPSocketAL>;
	uses interface NodeI<transport> as NetLayer;
	uses interface Timer<TMilli> as socketTimer;
	uses interface Timer<TMilli> as shutdownTimer;
}

implementation{
	
	TCPSocketAL socks[MAX_SOCKS];
	portList ports;
	
	transport msg;
	
	bool connectionAlreadyExists(uint8_t srcPort, uint8_t srcAddr);
	bool senderBufferAckBytes(TCPSocketAL *input, transport * msg);
	bool receiverBufferPushBack(receiverBuffer * dest, transport * src);
	bool senderBufferSendNextSegment(TCPSocketAL *input);
	
	
	command void TCPManager.init(){
		uint8_t i;
		
		portListInit(&ports);
		
		for(i = 0; i < MAX_SOCKS; i++)
			call TCPSocket.init(&socks[i]);
		
		call socketTimer.startPeriodic(10);
	}
	
	command TCPSocketAL *TCPManager.socket(){
		uint8_t i;
		for(i = 0; i < MAX_SOCKS; i++) {
			if(socks[i].free && socks[i].state == CLOSED && socks[i].srcPort == 0) {
				socks[i].free = FALSE;
				return &socks[i];
			}
		}
		return NULL;
	}

	command void TCPManager.handlePacket(void *payload){
		pack * myPack;
		transport * myTCP;
		uint8_t i;
		
		myPack = (pack *) payload;
		myTCP = (transport *)((void*)myPack->payload);
		
		dbg_clear("transport", "\n---Received Packet---\n");
		printTransport(myTCP);
		
		for(i = 0; i < MAX_SOCKS; i++) {
			if(socks[i].srcPort == myTCP->destPort) {
				//Received a packet meant for this socket
				switch(myTCP->type) {
					case TRANSPORT_ACK:
						if(myTCP->seq-1 == socks[i].out.lastByteAcked) {
							if(socks[i].out.duplicateAcks == 1) {
								//execute fast retransmit
								dbg("congestionControl", "Fast Retransmit\n");
								call NetLayer.forward(&socks[i].out.reTXQueue.segments[0].segment, socks[i].destAddr);
								socks[i].out.reTXQueue.segments[0].timeSent = call socketTimer.getNow();
								socks[i].out.reTXQueue.segments[0].resent = TRUE;
								socks[i].out.reTXQueue.lastSend = call socketTimer.getNow();
								socks[i].out.congestionWindow /= 2.0;
								socks[i].out.SSThresh = socks[i].out.congestionWindow;
							}
							socks[i].out.duplicateAcks++;
						}	
						if(senderBufferAckBytes(&socks[i], myTCP))
							socks[i].out.duplicateAcks = 0;
						call TCPManager.senderBufferFillWindow(&socks[i]);
						break;
					case TRANSPORT_DATA:
						dbg("Project3", "receiving data\n");
						if(receiverBufferPushBack(&socks[i].in, myTCP)) {
							dbg("Project3", "pushed data\n");
						}
						dbg("Project3", "acking data\n");
						createTransport(&msg, socks[i].srcPort, socks[i].destPort, TRANSPORT_ACK, socks[i].in.advertisedWindow, socks[i].in.nextByteExpected, (uint8_t*)"", 0);
						call NetLayer.forward(&msg, socks[i].destAddr);
						break;
					case TRANSPORT_FIN:
						if(myTCP->seq == socks[i].in.nextByteExpected) {
							createTransport(&msg, socks[i].srcPort, socks[i].destPort, TRANSPORT_ACK, socks[i].in.advertisedWindow, myTCP->seq+1, (uint8_t *)"", 0);
							call NetLayer.forward(&msg, socks[i].destAddr);
						} else if(myTCP->seq == 0) {
							dbg("genDebug", "ABBORTTTT\n");
							call TCPSocket.release(&socks[i]);
						}
						break;
					case TRANSPORT_SYN:
						if(socks[i].state != LISTEN && socks[i].state != SYN_SENT) {
							createTransport(&msg, socks[i].srcPort, myTCP->srcPort, TRANSPORT_FIN, 0, 0, (uint8_t*)"", 0);
							call NetLayer.forward(&msg, myTCP->srcPort);
						}
						break;
				}
				
				switch(socks[i].state) {
					case CLOSED:
						break;
						
					case LISTEN:
						switch(myTCP->type) {
							uint8_t count;
							case TRANSPORT_SYN:
								if(!connectionAlreadyExists(myTCP->srcPort, myPack->src)) {
									if(packListPushBack(&socks[i].acceptQueue, myPack)) //does not packs with duplicate transports
										dbg("TCPHandshake", "Syn pack pushed on acceptQueue\n");
								} else {
									dbg("genDebug", "received repeat syn, acking\n");
									for(count = 0; count < MAX_SOCKS; count++)
										if(socks[count].destPort == myTCP->srcPort && socks[count].destAddr == myPack->src)
											break;
									createTransport(&msg, socks[count].srcPort, socks[count].destPort, TRANSPORT_ACK, socks[count].in.advertisedWindow, socks[count].in.nextByteExpected, (uint8_t *)"", 0);
									call NetLayer.forward(&msg, socks[count].destAddr);
								}
								break;
						}
						break;
						
					case SYN_SENT:
						switch(myTCP->type) {
							case TRANSPORT_ACK:
								dbg("TCPHandshake", "Connection Established\n");
								socks[i].state = ESTABLISHED;
								socks[i].destPort = myTCP->srcPort;
								break;
						}
						break;
						
					case SYN_RCVD:
						switch(myTCP->type) {
							case TRANSPORT_FIN:
								if(myTCP->seq == socks[i].in.nextByteExpected) {
									dbg("genDebug", "Closing\n");
									socks[i].state = CLOSING;
									call shutdownTimer.startOneShot(120000);
								}
								break;
							case TRANSPORT_SYN:
								createTransport(&msg, socks[i].srcPort, socks[i].destPort, TRANSPORT_ACK, socks[i].in.advertisedWindow, socks[i].in.nextByteExpected, (uint8_t *)"", 0);
								call NetLayer.forward(&msg, socks[i].destAddr);
								break;
						}
						break;
						
					case ESTABLISHED:
						break;
						
					case FIN_SENT:
						switch(myTCP->type) {
							case TRANSPORT_ACK:
								if(myTCP->seq - 1 == socks[i].out.lastByteWritten) {
									dbg("genDebug", "Closed\n");
									socks[i].state = CLOSED;
								}
								break;
						}
						break;
				}
				
				return;
			}
		}
	}
	
	command void TCPManager.freeSocket(TCPSocketAL *input){
		if(!portListFreePort(&ports, input->srcPort))
			dbg("TCPError", "ERROR: could not free port\n");
		call TCPSocket.init(input);	
	}
	
	command uint8_t TCPManager.getFreePort() {
		return portListPopBack(&ports);
	}
	
	command bool TCPManager.requestPort(uint8_t port) {
		return portListRequestPort(&ports, port);
	}
	
	bool connectionAlreadyExists(uint8_t srcPort, uint8_t srcAddr) {
		uint8_t i;
		if(srcPort == 0)
			return FALSE;
		for(i = 0; i < MAX_SOCKS; i++) {
			if(socks[i].state != CLOSED && socks[i].destPort == srcPort && socks[i].destAddr == srcAddr)
				return TRUE;
		}
		return FALSE;
	}
	
	async command void TCPManager.senderBufferFillWindow(TCPSocketAL *input) {
		dbg("ReliableTransport", "$$$Filling Window\n"); //TODO persist timer if window is 0
		while(input->out.reTXQueue.numValues < SENDER_WINDOW_SIZE) {
			if(!senderBufferSendNextSegment(input))
				break;
		}
	}
	
	bool senderBufferSendNextSegment(TCPSocketAL *input) {
		transport nextSegment;
		uint16_t length;
		length = min(TRANSPORT_MAX_PAYLOAD_SIZE, input->out.lastByteWritten - input->out.lastByteSent);
		//dbg("genDebug", "length%d firstByte:%d\n", length, input->out.buffer[0]);
		
		if(length == 0)
			return FALSE;
		
		createTransport(&nextSegment, input->srcPort, input->destPort, TRANSPORT_DATA, 0, input->out.lastByteSent+length, &input->out.buffer[0], (uint8_t)length);
		
		if(senderBufferRTXPushBack(&input->out, &nextSegment, call socketTimer.getNow())) {
			call NetLayer.forward(&nextSegment, input->destAddr);
			//dbg("genDebug", "length %d lastWritten%d lastSent%d\n", (input->out.lastByteWritten - input->out.lastByteSent), input->out.lastByteWritten, input->out.lastByteSent);
			memmove(input->out.buffer, &input->out.buffer[length], (input->out.lastByteWritten - input->out.lastByteSent));
			return TRUE;
		} else
			return FALSE;
	}
	
	bool senderBufferAckBytes(TCPSocketAL *sock, transport * msg) {
		uint8_t i, j, newValues;
		bool validRTT = FALSE;
		int16_t seq = msg->seq-1;
		senderBuffer * input = &sock->out;
		input->advertisedWindow = msg->window;
		
		if(seq > input->lastByteSent || seq <= input->lastByteAcked) {
			return FALSE; //acknowledging byte not in queue
		}
		
		if(!input->reTXQueue.segments[0].resent)
			validRTT = TRUE; //no retransmits in ack frame
		
		//find index of the last packet this ack is acking
		i = 0;
		newValues = input->reTXQueue.numValues;
		while(i < input->reTXQueue.numValues) {
			if(input->reTXQueue.segments[i].segment.seq >= seq)
				break;
			i++;
			newValues--;
		}
		
		//update the RTT estimation
		if(validRTT && input->reTXQueue.segments[0].segment.type != TRANSPORT_SYN && input->reTXQueue.segments[0].segment.type != TRANSPORT_FIN) {
			if(input->FIRST_RTT) {
				input->SRTT = ((call socketTimer.getNow())- input->reTXQueue.segments[i].timeSent);
            	input->RTTVAR = input->SRTT/2;
            	input->RTO = input->SRTT + fmax(10.0, 4*input->RTTVAR);
				input->FIRST_RTT = FALSE;
			} else {
				input->RTTVAR = (1.0 - 1.0/BETA)*input->RTTVAR + (1.0/BETA)*abs(input->SRTT-((call socketTimer.getNow())- input->reTXQueue.segments[i].timeSent));
				input->SRTT = (1.0 - 1.0/ALPHA)*input->SRTT + (1.0/ALPHA)*((call socketTimer.getNow())- input->reTXQueue.segments[i].timeSent);
				input->RTO = input->SRTT + fmax(10, 4*input->RTTVAR);
			}
		}	
		
		//increase i to equal the number of segments to be removed
		i++;
		newValues--;
		
		if(input->SSThresh > input->congestionWindow * TRANSPORT_MAX_PAYLOAD_SIZE) {
			//slow start
			input->congestionWindow += i;
		} else {
			input->congestionWindow += i/input->congestionWindow;
		}
		
		//remove the acknowledge Segments
		for(j = 0; j < newValues; j++) {
			input->reTXQueue.segments[j] = input->reTXQueue.segments[i+j];
		}
		input->reTXQueue.numValues = newValues;
		input->lastByteAcked = seq;
		
		dbg("ReliableTransport", "reTXQ size:%d RTO %f RTT %f\n", input->reTXQueue.numValues, input->RTO, input->SRTT);
		//call TCPManager.senderBufferFillWindow(sock);
		return TRUE;
	}
	
	//simple go back N
	bool receiverBufferPushBack(receiverBuffer * input, transport * src) {
		transport nextTCP;
		printTransport(src);
		if(src->seq > input->lastByteRead + RECEIVER_BUFFER_SIZE)
			return FALSE; //will overflow buffer
		if((src->seq - src->length + 1) < input->nextByteExpected)
			return FALSE; //already in buffer
		if((src->seq - src->length + 1) > input->nextByteExpected) {
			if(sortedSegmentListAdd(&input->rcvrWindow, src)) {
				input->advertisedWindow = RECEIVER_BUFFER_SIZE - (input->lastByteRcvd - input->lastByteRead);
				if(src->seq > input->lastByteRcvd)
					input->lastByteRcvd = src->seq;
				return TRUE;
			} else
				return FALSE;
		} else {
			//push payload onto queue
			memcpy(&input->buffer[input->nextByteExpected-1 - input->lastByteRead], src->payload, src->length);
			input->nextByteExpected = src->seq+1;
			if(src->seq > input->lastByteRcvd)
				input->lastByteRcvd = src->seq;
			input->advertisedWindow = RECEIVER_BUFFER_SIZE - (input->lastByteRcvd - input->lastByteRead);
			if(input->rcvrWindow.numValues > 0 && input->nextByteExpected >= sortedSegmentListNextByte(&input->rcvrWindow)) {
				sortedSegmentListPopFront(&input->rcvrWindow, &nextTCP);
				return receiverBufferPushBack(input, &nextTCP);
			}
			return TRUE;
		}
	}

	event void socketTimer.fired(){
		uint8_t i, j;
		bool onlyOnce, sent;
		for(i = 0; i < MAX_SOCKS; i++) {
			onlyOnce = TRUE;
			sent = FALSE;
			if((socks[i].state == ESTABLISHED || socks[i].state == FIN_SENT || socks[i].state == SYN_SENT) && socks[i].out.reTXQueue.numValues > 0) {
				for(j = 0; j < socks[i].out.reTXQueue.numValues; j++) {
					if(socks[i].out.reTXQueue.lastSend + socks[i].out.RTO < (call socketTimer.getNow())) {
						//timeout event
						sent = TRUE;
						call NetLayer.forward(&socks[i].out.reTXQueue.segments[j].segment, socks[i].destAddr);
						socks[i].out.reTXQueue.segments[j].timeSent = call socketTimer.getNow();
						socks[i].out.reTXQueue.segments[j].resent = TRUE;
						if(onlyOnce && congestionEnabled) {
							socks[i].out.SRTT =fmin(500.0, socks[i].out.SRTT*2.0);
							onlyOnce = FALSE;
						}
						socks[i].out.SSThresh = (TRANSPORT_MAX_PAYLOAD_SIZE * socks[i].out.congestionWindow) / 2.0;
						socks[i].out.congestionWindow = 1.0;
					}
				}
				if(sent) {
					socks[i].out.reTXQueue.lastSend = call socketTimer.getNow();
				}
			}	
		}
	}

	event void shutdownTimer.fired(){
		uint8_t i;
		dbg("TCPTeardown", "shutdownFired\n");
		for(i = 0; i < MAX_SOCKS; i++) {
			switch(socks[i].state) {
				case CLOSING:
					dbg("TCPState", "State Transition ->CLOSED port %d\n", socks[i].srcPort);
					socks[i].state = CLOSED;
					break;
			}	
		}
	}
}
