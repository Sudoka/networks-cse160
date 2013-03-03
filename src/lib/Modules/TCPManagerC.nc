#include "TCPSocketAL.h"
#include "../packet.h"
#include "../dataStructures/portList.h"
#define MAXSOCKETS 20

module TCPManagerC{
	provides interface TCPManager<TCPSocketAL, pack>;
	uses interface TCPSocket<TCPSocketAL>;
	uses interface NodeI<transport> as NetLayer;
	uses interface Timer<TMilli> as socketTimer;
	uses interface Timer<TMilli> as shutdownTimer;
}

implementation{
	
	TCPSocketAL socks[MAXSOCKETS];
	portList ports;
	transport msg;
	
	command void TCPManager.init(){
		uint8_t i;
		portListInit(&ports);
		for(i = 0; i < MAXSOCKETS; i++) {
			call TCPSocket.init(&socks[i]);
			socks[i].ports = &ports;
		}
		call socketTimer.startPeriodic(10);
	}
	
	command TCPSocketAL * TCPManager.socket(){
		//should these sockets be given a port already? and if so does binding them free the port they were 
		//initially given and tie them to the new port they asked for?
		uint8_t i;
		for(i = 0; i < MAXSOCKETS; i++)
			if(socks[i].state == CLOSED && socks[i].localPort == 0) {
				call TCPSocket.init(&socks[i]);
				return &socks[i];
			}
		return (TCPSocketAL *) 0;
	}

	//TODO improve the connection setup, particularly general case of what to do when you receive a syn
	command void TCPManager.handlePacket(void *payload){
		uint8_t i;
		pack * myMsg;
		transport * data;
		
		myMsg = (pack *) payload;
		data = (transport *) myMsg->payload;
		
		dbg_clear("genDebug", "\n--- Received Tcp Packet @time:%d---\n", call socketTimer.getNow());
		printTransport(data);
		
		for(i = 0; i < MAXSOCKETS; i++)
			if(data->destPort == socks[i].localPort) {
				dbg("TCPState", "-state = %d\n", socks[i].state);
				switch(data->type) {
					case TRANSPORT_DATA:
						receiverBufferPushBack(&socks[i].in, data);
						createTransport(&msg, socks[i].localPort, socks[i].destPort, TRANSPORT_ACK, socks[i].in.AdvertisedWindow, socks[i].in.nextByteExpected, (uint8_t *)"", 0);
						call NetLayer.forward(&msg, socks[i].destAddr);
						break;
					case TRANSPORT_ACK:
						if(data->seq - 1 == socks[i].out.lastByteAcked && data->seq-1 != socks[i].out.lastByteSent) {
							//received duplicate ack, assume loss
							dbg("congestionControl", "@@@$$$ Received Duplicate Ack %d\n", socks[i].out.duplicateAcks);
							if(socks[i].out.duplicateAcks < 1);
							else if(socks[i].out.duplicateAcks == 1) {
								dbg("congestionControl", "preforming fast retransmit\n");
								socks[i].out.SSThresh = (TRANSPORT_MAX_PAYLOAD_SIZE * socks[i].out.congestionWindow) / 2.0;
								socks[i].out.congestionWindow /= 2.0;
								call NetLayer.forward(&socks[i].out.buffer[0].msg, socks[i].destAddr);
								socks[i].out.buffer[0].timeSent = call socketTimer.getNow();
								socks[i].out.buffer[0].resent = TRUE;
								socks[i].out.buffer[i].TTL--;
							}
							socks[i].out.duplicateAcks++;
						} else {
							socks[i].out.duplicateAcks = 0;
							socks[i].out.RTObaseTime = call socketTimer.getNow();
						}
						senderBufferAckSeq(&socks[i].out, data, call socketTimer.getNow());
						break;
					case TRANSPORT_FIN:
						if(socks[i].in.nextByteExpected == data->seq) {
							dbg("TCPTeardown","Received in order FIN, acking\n");
							createTransport(&msg, socks[i].localPort, socks[i].destPort, TRANSPORT_ACK, socks[i].in.AdvertisedWindow, data->seq+1, (uint8_t *)"", 0);
							call NetLayer.forward(&msg, socks[i].destAddr);
						}
						break;
					case TRANSPORT_SYN: //TODO general case for syn receives
						break;
					case TRANSPORT_RST:
						if(socks[i].state != LISTEN)
							call TCPSocket.release(&socks[i]);
						break;
				}
				switch(socks[i].state) {
					case CLOSED:
						if(data->type != TRANSPORT_RST && data->type != TRANSPORT_FIN) {
							createTransport(&msg, socks[i].localPort, socks[i].destPort, TRANSPORT_RST, 0, data->seq+1, (uint8_t *)"", 1);
							call NetLayer.forward(&msg, socks[i].destAddr);
						}
						break;
					case LISTEN:
						switch(data->type) {
							uint8_t j;
							case TRANSPORT_SYN: //TODO clean this shit up
								dbg("TCPHandshake", "Received a Syn on listening node\n");
								for(j = 0; j < MAXSOCKETS; j++) {
									if(socks[j].state == SYN_RCVD || socks[j].destPort == data->srcPort) {
										dbg("TCPError", "@@@@@@@@@@@@@@@@@@@@@@@@@@@@ state = %d src:%d dest:%d \n", socks[j].state, socks[j].localPort, socks[i].destPort);
										createTransport(&msg, socks[j].localPort, socks[j].destPort, TRANSPORT_ACK, socks[j].in.AdvertisedWindow, socks[j].in.nextByteExpected, (uint8_t *)"", 0);
										call NetLayer.forward(&msg, socks[j].destAddr);
										dbg("TCPHandshake", "Duplicate Syn, Connection already forked, ignore syn\n");
										return; //don't handle packets I've already accepted connection from
									}
								}
								if(socks[i].acceptQueue.numValues < socks[i].acceptQueue.backlog) {
									atomic {
										for(j = 0; j < socks[i].acceptQueue.numValues; j++) {
											if(((transport *)socks[i].acceptQueue.values[j].payload)->srcPort == data->srcPort) {
												dbg("TCPHandshake", "Duplicate Syn already on accept Queue\n");
												return;
											}
										}
										dbg("TCPHandshake", "valid Syn, adding to accept queue\n");
										((transport*)myMsg->payload)->destPort = portListPopBack(&ports);
										packListPushBack(&socks[i].acceptQueue, *myMsg);
									}
								} else
									dbg("TCPHandshake", "Too many connects pending\n");
								break;
						}
						break;
					case SYN_SENT:
						switch(data->type) {
							case TRANSPORT_SYN:
								dbg("TCPHandshake", "Received a Syn while in syn sent, go to syn received\n");
								receiverBufferInit(&socks[i].in, data->seq);
								socks[i].destPort = data->srcPort;
								dbg("TCPState", "State Transition ->SYN_RCVD\n");
								socks[i].state = SYN_RCVD;
								createTransport(&msg, socks[i].localPort, socks[i].destPort, TRANSPORT_ACK, socks[i].in.AdvertisedWindow, socks[i].in.nextByteExpected, (uint8_t *)"", 0);
								call NetLayer.forward(&msg, socks[i].destAddr);
								break;
							case TRANSPORT_ACK:
								dbg("TCPHandshake", "Received ack while in syn sent, connection established!\n");
								dbg("TCPState", "State Transition ->ESTABLISHED\n");
								socks[i].destPort = data->srcPort;
								socks[i].state = ESTABLISHED;
								break;
						}
						break;
					case SYN_RCVD:
						switch(data->type) {
							case TRANSPORT_ACK:
								dbg("TCPHandshake", "Received an ack while in syn received, connection established!\n");
								dbg("TCPState", "State Transition ->ESTABLISHED\n");
								socks[i].destPort = data->srcPort;
								socks[i].state = ESTABLISHED;
								break;
							case TRANSPORT_SYN:
								dbg("TCPHandshake", "Received Syn while in syn received, ack was lost, resend ack\n");
								createTransport(&msg, socks[i].localPort, socks[i].destPort, TRANSPORT_ACK, socks[i].in.AdvertisedWindow, socks[i].in.nextByteExpected, (uint8_t *)"", 0);
								call NetLayer.forward(&msg, socks[i].destAddr);
								break;
							case TRANSPORT_DATA:
								dbg("TCPState", "\n\n\n\n @@@@@@@@@@@@@@@@@@@@@@@@@@\nCheater state transition ->ESTABLISHED\n@@@@@@@@@@@@@@@@@@@\n");
								dbg("TCPHandshake", "Received a Data while in syn_rcvd, ack received, syn or ack of syn droped, skip to established, in real tcp data would have ack field for the receiver's syn\n");
								socks[i].destPort = data->srcPort;
								socks[i].state = ESTABLISHED;
								senderBufferAckSeq(&socks[i].out, &socks[i].out.buffer[0].msg, call socketTimer.getNow());
								break;
						}
						break;
					case ESTABLISHED:
						switch(data->type) {
							case TRANSPORT_ACK:
								break;
							case TRANSPORT_SYN:
								dbg("TCPHandshake", "received syn while established, ack was dropped, resend ack\n");
								receiverBufferInit(&socks[i].in, data->seq);
								createTransport(&msg, socks[i].localPort, socks[i].destPort, TRANSPORT_ACK, socks[i].in.AdvertisedWindow, socks[i].in.nextByteExpected, (uint8_t *)"", 0);
								call NetLayer.forward(&msg, socks[i].destAddr);
								break;
							case TRANSPORT_FIN:
								if(socks[i].in.nextByteExpected == data->seq) {
									dbg("TCPTeardown","received in order fin while in established, wait for all byte to be read from buffer\n");
									dbg("TCPState", "State Transition ->CLOSE_WAIT\n");
									socks[i].state = CLOSE_WAIT;
									if(socks[i].in.lastByteRead == socks[i].in.lastByteRcvd) {
										dbg("TCPTeardown","received in order fin and all bytes have been read by application, close connection\n");
										call TCPSocket.close(&socks[i]);
									}
								}
								break;
						}
						break;
					case FIN_WAIT_1:
						switch(data->type) {
							case TRANSPORT_ACK:
								if(data->seq-1 == socks[i].out.lastByteWritten) {
									dbg("TCPTeardown","Received ack of my fin, move to fin_wait_2\n");
									dbg("TCPState", "State Transition ->FIN_WAIT_2\n");
									socks[i].state = FIN_WAIT_2;
								}
								break;
							case TRANSPORT_FIN:
								if(socks[i].in.nextByteExpected == data->seq) {
									dbg("TCPTeardown","received a simultanious close, go to closing (wait for ack and be ready to re ack)\n");
									dbg("TCPState", "State Transition ->CLOSING\n");
									socks[i].state = CLOSING;
								}
								break;
						}
						break;
					case FIN_WAIT_2:
						switch(data->type) {
							case TRANSPORT_FIN:
								if(socks[i].in.nextByteExpected == data->seq) {
									dbg("TCPTeardown","other TCP has closed, give time to handle droped ack's\n");
									dbg("TCPState", "State Transition ->TIME_WAIT\n");
									socks[i].state = TIME_WAIT;
									call shutdownTimer.startOneShot(5000);
								}
								break;
							case TRANSPORT_ACK:
								break;
						}
						break;
					case CLOSING:
						switch(data->type) {
							case TRANSPORT_ACK:
								dbg("TCPTeardown","both directions have closed, and mine has been acked, allow for retransmits from other TCP if the ack is dropped\n");
								dbg("TCPState", "State Transition ->TIME_WAIT\n");
								if(data->seq-1 == socks[i].out.lastByteWritten) {
									socks[i].state = TIME_WAIT;
									call shutdownTimer.startOneShot(5000);
								}
								break;
						}
						break;
					case TIME_WAIT:
						switch(data->type) {
							case TRANSPORT_FIN:
								break;
							default:
								dbg("genDebug", "Received packet while in TIME_WAIT\n");
								break;
						}
						break;
					case CLOSE_WAIT:
						switch(data->type) {
							case TRANSPORT_ACK:
								dbg("TCPError", "#### does this ever happen \n");
								if(socks[i].out.lastByteAcked + 1 == data->seq)
									call NetLayer.forward(&socks[i].out.buffer[0].msg, socks[i].destAddr);
								break;
						}
						break;
					case LAST_ACK:
						switch(data->type) {
							case TRANSPORT_ACK:
								if(data->seq-1 == socks[i].out.lastByteAcked) {
									dbg("TCPTeardown", "Received ack for FIN while in LAST_ACK\n");
									dbg("TCPState", "State Transition ->CLOSED\n");
									socks[i].state = CLOSED;
								}
						}
						break;
					default:
						break;
				}
			}
	}
	
	command void TCPManager.freeSocket(TCPSocketAL *input){
		//Called by application to return control of a socket to the OS
		
		if(!freePort(&ports, input->localPort))
			dbg("TCPError", "ERROR: could not free port\n");
		call TCPSocket.init(input);
	}

	event void socketTimer.fired(){
		uint8_t i, j;
		int16_t returnVal;
		for(i = 0; i < MAXSOCKETS; i++) {
			if(socks[i].state != CLOSED)
				while(j < socks[i].out.numValues && (returnVal = senderBufferSendLogic(&socks[i].out, j, call socketTimer.getNow())) >= 0) {
					if(returnVal > 0) {
						dbg("genDebug", "Sending Pack @ index:%d at time %d\n", j, call socketTimer.getNow());
						call NetLayer.forward(&socks[i].out.buffer[j].msg, socks[i].destAddr);
					}
					j++;
				}
		}
	}

	event void shutdownTimer.fired(){
		uint8_t i;
		dbg("TCPTeardown", "shutdownFired\n");
		for(i = 0; i < MAXSOCKETS; i++) {
			switch(socks[i].state) {
				case TIME_WAIT:
					dbg("TCPState", "State Transition ->CLOSED\n");
					call TCPManager.freeSocket(&socks[i]);
					break;
			}	
		}
	}
}
