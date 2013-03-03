#include "TCPSocketAL.h"
#include "../../dataStructures/portList.h"
#include "../../dataStructures/senderBuffer.h"

module TCPSocketC{
	provides{
		interface TCPSocket<TCPSocketAL>;
	}
	
	uses interface TCPManager<TCPSocketAL, pack>;
	uses interface NodeI<transport> as NetLayer;
	uses interface Timer<TMilli> as tcpTimer;
}
implementation{
	
	transport msg;
	
	async command void TCPSocket.init(TCPSocketAL *input){
		input->state = CLOSED;
		input->free = TRUE;
		input->srcPort = 0;
		packListInit(&input->acceptQueue);
	}
	
	async command uint8_t TCPSocket.bind(TCPSocketAL *input, uint8_t srcPort, uint16_t address){
		if(call TCPManager.requestPort(srcPort)) {
			dbg("Project3", "bind successful port:%d addr:%d\n", srcPort, address);
			input->srcPort = srcPort;
			input->srcAddr = address;
			return 0;
		} else
			return -1;
	}
	
	async command uint8_t TCPSocket.listen(TCPSocketAL *input, uint8_t backlog) {
		dbg("TCPHandshake", "State ->LISTEN\n");
		input->acceptQueue.backlog = backlog;
		input->state = LISTEN;
		return 0;
	}
	
	async command uint8_t TCPSocket.accept(TCPSocketAL *input, TCPSocketAL *output){
		uint8_t freePort;
		pack myPack;
		transport * myTCP;
		
		if(input->acceptQueue.numValues <= 0) {
			//dbg("TCPHandshake", "no connections waiting\n");
			return -1; //no connection available to accept
		}
		
		//retrieve SYN pack
		myPack = packListPopFront(&input->acceptQueue);
		myTCP = (transport*)((void*) myPack.payload);
		
		//initialize the connection tuples
		if(output->state != LISTEN)
			output->srcPort = call TCPManager.getFreePort();
		output->free = FALSE;
		output->srcAddr = input->srcAddr;
		output->destPort = myTCP->srcPort;
		output->destAddr = myPack.src;
		receiverBufferInit(&output->in, myTCP->seq);
		createTransport(&msg, output->srcPort, output->destPort, TRANSPORT_ACK, output->in.advertisedWindow, output->in.nextByteExpected, (uint8_t*)"", 0);
		call NetLayer.forward(&msg, output->destAddr);
		
		dbg("TCPHandshake", "SYN Received\n");
		//ready to receive data two way handshake essentially done
		output->state = SYN_RCVD;
		
		return 0;
	}

	async command uint8_t TCPSocket.connect(TCPSocketAL *input, uint16_t destAddr, uint8_t destPort) {
		input->destAddr = destAddr;
		input->destPort = destPort;
		
		senderBufferInit(&input->out, 1);
		
		//Send syn packet
		createTransport(&msg, input->srcPort, input->destPort, TRANSPORT_SYN, 0, input->out.lastByteSent+1, (uint8_t*)"", 1);
		if(senderBufferRTXPushBack(&input->out, &msg, call tcpTimer.getNow()))
			call NetLayer.forward(&msg, input->destAddr);
		
		dbg("TCPHandshake", "SYN Sent @:%d\n", call tcpTimer.getNow());
		input->state = SYN_SENT;
		
		return 0;
	}

	async command uint8_t TCPSocket.close(TCPSocketAL *input){
		dbg("P3Socket", "Closing Connection \n");
		switch(input->state) {
			case ESTABLISHED:
				createTransport(&msg, input->srcPort, input->destPort, TRANSPORT_FIN, 0, input->out.lastByteWritten+1, (uint8_t *)"", 1);
				if(senderBufferRTXPushBack(&input->out, &msg, call tcpTimer.getNow())) {
					call NetLayer.forward(&msg, input->destAddr);
					dbg("TCPState", "State Transition ->FIN_WAIT_1 %d\n", input->srcPort);
					input->state = FIN_SENT; //cheap fix
					return 0;
				} else {
					dbg("TCPError", "ERROR: couldnt push close\n");
					return -1;
				}
				break;
		}
		return -1;
	}

	async command uint8_t TCPSocket.release(TCPSocketAL *input){
		dbg("P3Socket", "CONNECTION ABORTED\n");
		
		if(input->state == CLOSED) {
			dbg("TCPError", "ERROR: Connection does not exist\n");
			return -1;
		}
		
		//empty the send and receive Queues;
		input->out.reTXQueue.numValues = 0;
		
		//create RST packet and send
		if(input->state != CLOSED) {
			createTransport(&msg, input->srcPort, input->destPort, TRANSPORT_FIN, 0, 0, (uint8_t *)"", 0);
			call NetLayer.forward(&msg, input->destAddr);
		}
		
		//delete the socket / return control of socket to OS
		call TCPManager.freeSocket(input);
		
		return TCP_ERRMSG_SUCCESS;
	}

	async command int16_t TCPSocket.read(TCPSocketAL *input, uint8_t *readBuffer, uint16_t pos, uint16_t len){
		int16_t bytesRead;
		
		if(input->state != SYN_RCVD && input->state != CLOSING)
			return 0; //cannot read in this state
		
		bytesRead = receiverBufferReadBytes(&input->in, &readBuffer[pos], len);
		if(bytesRead < 0) {
			dbg("TCPError", "ERROR: read error, could not read from in buffer\n");
			return -1;		
		}
		return bytesRead;
	}

	async command int16_t TCPSocket.write(TCPSocketAL *input, uint8_t *writeBuffer, uint16_t pos, uint16_t len){
		int16_t bytesWritten;
		
		//dbg("genDebug", "got here write\n");
		
		if(input->state != ESTABLISHED)
			return 0; //cannot write in this state
		
		bytesWritten = senderBufferPushBack(&input->out, &writeBuffer[pos], len);
		if(bytesWritten < 0) {
			dbg("TCPError", "ERROR: write error, could not write to out buffer\n");
			return -1;		
		}
		//dbg("genDebug", "wrote %d bytes to buffer\n", bytesWritten);
		call TCPManager.senderBufferFillWindow(input);
		return bytesWritten;
	}

	async command bool TCPSocket.isListening(TCPSocketAL *input){
		return (input->state == LISTEN);
	}

	async command bool TCPSocket.isConnected(TCPSocketAL *input){
		return (input->state == ESTABLISHED || input->state == SYN_RCVD);
	}

	async command bool TCPSocket.isClosing(TCPSocketAL *input){
		return (input->state == FIN_SENT || input->state == CLOSING);
	}

	async command bool TCPSocket.isClosed(TCPSocketAL *input){
		return (input->state == CLOSED);
	}

	async command bool TCPSocket.isConnectPending(TCPSocketAL *input){
		return (input->state == SYN_SENT);
	}
	
	async command void TCPSocket.copy(TCPSocketAL *input, TCPSocketAL *output) {
		memcpy(output, input, sizeof(TCPSocketAL));	
	}

	event void tcpTimer.fired(){
	}
}
