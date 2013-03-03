#include "TCPSocketAL.h"

module TCPSocketC{
	uses interface NodeI<transport> as NetLayer;
	uses interface Random as Random;
	uses interface TCPManager<TCPSocketAL,pack>;
	
	provides{
		interface TCPSocket<TCPSocketAL>;
	}
}
implementation{
	async command void TCPSocket.init(TCPSocketAL *input){
		input->state = CLOSED;
		input->localPort = 0;
		input->localAddr = 0;
		input->destPort = 0;
		input->destAddr = 0;
		packListInit(&input->acceptQueue);
		receiverBufferInit(&input->in, -1);
		senderBufferInit(&input->out, -1);
	}
	
	async command uint8_t TCPSocket.bind(TCPSocketAL *input, uint8_t localPort, uint16_t address){
		//sets socket's information
		if(input->localPort != 0) {
			dbg("TCPError", "ERROR : socket already has a port %d freeing port\n", input->localPort);
			freePort(input->ports, input->localPort);
		} if(requestPort(input->ports, localPort)) { //if local port is not taken
			//reserve localPort
			dbg("TCPHandshake", "Binding port %d and address %d\n", localPort, address);
			input->localPort = localPort;
			input->localAddr = address;
			return 0;
		} else
			return TCP_ERRMSG_INVALID;
	}
	
	async command uint8_t TCPSocket.listen(TCPSocketAL *input, uint8_t backlog){
		//changes state to listen
		//sets backlog
		if(backlog > BUFFSIZE || backlog < 1) {
			dbg("TCPError", "ERROR: Invalid backlog\n");
			return TCP_ERRMSG_INVALID;
		}
		input->state = LISTEN;
		dbg("TCPState", "State Transition ->LISTEN\n");
		input->acceptQueue.backlog = backlog;
		dbg("TCPHandshake", "socket is listening %d\n", input->state);
		return 0;
	}
	
	async command uint8_t TCPSocket.accept(TCPSocketAL *input, TCPSocketAL *output) {
		pack myPack;
		transport * myMsg;
		transport myReply;
		//confirm proper sock state
		if(input->state != LISTEN) {
			dbg("TCPError", "ERROR: Invalid request\n");
			return TCP_ERRMSG_INVALID; //socket not ready to accept packets
		}
		
		//extract connection request (syn packet)
		atomic {
			if(input->acceptQueue.numValues > 0) {
				myPack = packListPopFront(&input->acceptQueue);
				myMsg = (transport *)myPack.payload;
			} else {
				//dbg("TCPError", "ERROR: No waiting connections\n");
				return TCP_ERRMSG_NO_WAITING_CONNECTIONS; //nothing waiting to connect
			}
		}
		
		//create a socket for the connection
		dbg("TCPHandshake", "Initializing output socket\n");
		output->destPort = myMsg->srcPort;
		output->destAddr = myPack.src;
		output->localPort = myMsg->destPort;
		senderBufferInit(&output->out, (uint16_t) ((call Random.rand16()) % 16384));
		receiverBufferInit(&output->in, myMsg->seq);
		
		//send an ACK back
		//Send a Syn Pack to start your half of the connection
		dbg("TCPHandshake", "Sending Syn + ack back to active participant\n");
		createTransport(&myReply, output->localPort, output->destPort, TRANSPORT_ACK, output->in.AdvertisedWindow, output->in.nextByteExpected, (uint8_t *)"", 0);
		call NetLayer.forward(&myReply, output->destAddr);
		createTransport(&myReply, output->localPort, output->destPort, TRANSPORT_SYN, 0, output->out.lastByteSent+1, (uint8_t *)"", 1);
		senderBufferPushBack(&output->out, &myReply);
		
		//state transition
		output->state = SYN_RCVD;
		dbg("TCPState", "State Transition ->SYN_RCVD\n");
		
		//accept is pending
		return TCP_ERRMSG_SUCCESS;
	}

	command uint8_t TCPSocket.connect(TCPSocketAL *input, uint16_t destAddr, uint8_t destPort){
		transport msg;
		
		if(destAddr == 0 || destPort == 0) {
			dbg("TCPError", "ERROR: Foreign socket not specified\n");
			return TCP_ERRMSG_FOREIGN_SOCKET_NOT_SPECIFIED;
		}
			
		if(input->state != CLOSED) {
			dbg("TCPError", "ERROR: Connection already exists\n");
			return TCP_ERRMSG_CONNECTION_ALREADY_EXISTS;
		}
		
		//decide on Initial Sequence Number
		senderBufferInit(&input->out, (uint16_t) ((call Random.rand16()) % 16384));
		
		//modify socket state to point to dest
		input->destAddr = destAddr;
		dbg("TCPHandshake", "dest port %d seq:%d\n", destPort, input->out.lastByteSent);
		
		//Create and send a SYN packet
		createTransport(&msg, input->localPort, destPort, TRANSPORT_SYN, 0, input->out.lastByteSent+1, (uint8_t *)"", 1);
		senderBufferPushBack(&input->out, &msg);
		
		//state transition
		dbg("TCPState", "State Transition ->SYN_SENT\n");
		input->state = SYN_SENT;
		
		//connect is pending
		return TCP_ERRMSG_SUCCESS;
	}
	
	async command uint8_t TCPSocket.close(TCPSocketAL *input){
		transport msg;
		dbg("P3Socket", "Closing Connection \n");
		switch(input->state) {
			case ESTABLISHED:
				createTransport(&msg, input->localPort, input->destPort, TRANSPORT_FIN, 0, input->out.lastByteWritten+1, (uint8_t *)"", 1);
				if(senderBufferPushBack(&input->out, &msg) > 0) {
					//call NetLayer.forward(&msg, input->destAddr);
					dbg("TCPState", "State Transition ->FIN_WAIT_1\n");
					input->state = FIN_WAIT_1; //cheap fix
					return 0;
				} else {
					dbg("TCPError", "ERROR: couldnt push close\n");
					return TCP_ERRMSG_INVALID;
				}
				break;
			case CLOSE_WAIT:
				createTransport(&msg, input->localPort, input->destPort, TRANSPORT_FIN, 0, input->out.lastByteSent+1, (uint8_t *)"", 1);
				senderBufferPushBack(&input->out, &msg);
				dbg("TCPState", "State Transition ->LAST_ACK\n");
				input->state = LAST_ACK;
				return 0;
				break;
		}
		return -1;
	}

//      Abort
//
//        Format:  ABORT (local connection name)
//
//        This command causes all pending SENDs and RECEIVES to be
//        aborted, the TCB to be removed, and a special RESET message to
//        be sent to the TCP on the other side of the connection.
//        Depending on the implementation, users may receive abort
//        indications for each outstanding SEND or RECEIVE, or may simply
//        receive an ABORT-acknowledgment.

	async command uint8_t TCPSocket.release(TCPSocketAL *input){ // this is now known as abort in my mind
		transport msg;
		int16_t abortSeq;
		
		dbg("P3Socket", "CONNECTION ABORTED\n");
		
		if(input->state == CLOSED) {
			dbg("TCPError", "ERROR: Connection does not exist\n");
			return TCP_ERRMSG_CONNECTION_DOES_NOT_EXIST;
		}
		
		//Indicate seq at which you are aborting
		abortSeq = input->out.lastByteAcked;
		
		//empty the send and receive Queues;
		input->out.numValues = 0;
		input->in.lastByteRcvd = input->in.lastByteRead;
		
		//create RST packet and send
		if(input->state != CLOSED) {
			createTransport(&msg, input->localPort, input->destPort, TRANSPORT_RST, 0, abortSeq+1, (uint8_t *)"", 0);
			call NetLayer.forward(&msg, input->destAddr);
		}
		
		//delete the socket / return control of socket to OS
		call TCPManager.freeSocket(input);
		
		return TCP_ERRMSG_SUCCESS;
	}

	async command int16_t TCPSocket.read(TCPSocketAL *input, uint8_t *readBuffer, uint16_t pos, uint16_t len) {
		int16_t bytesRead;
		
		if(input->state == SYN_SENT)
			return 0;
		
		if(input->state != ESTABLISHED && input->state == SYN_RCVD && input->state != FIN_WAIT_1 && input->state != FIN_WAIT_2 && input->state != CLOSE_WAIT)
			return 0; //this might mean its an error
		
		bytesRead = receiverBufferReadBytes(&input->in, &readBuffer[pos], len);
		if(bytesRead < 0) {
			dbg("TCPError", "ERROR: read error, could not read from in buffer\n");
			return TCP_ERRMSG_INVALID;		
		}
		if(input->state == CLOSE_WAIT && input->in.lastByteRead == input->in.lastByteRcvd)
			call TCPSocket.close(input);
		return bytesRead;
	}

	//For reliable transport I plan on implementing some sort of sendbuffertask like in node. The hard part will be that
	//I will have to be able to start the task running for any socket I have with data ready to be writen
	//this is the part that I still havn't figured out. Right now my connect doesnt return a value based on
	//if the connect has successfully finished. It just returns success once It has sent the syn packet
	//the client functions properly though because it checks if the connect is pending, which my socket
	//does appropriately reflect
	async command int16_t TCPSocket.write(TCPSocketAL *input, uint8_t *writeBuffer, uint16_t pos, uint16_t len){
		//put data on the out buffer
		transport msg;
		int16_t length, seq, bytesWritten, totalBytes = 0;
		
		if(input->state != ESTABLISHED && input->state != CLOSE_WAIT && input->state != SYN_RCVD && input->state != SYN_SENT) { //last two states will queue the data until established
			dbg("TCPError", "ERROR: cannot write in current state:%d\n", input->state);
			return -1;
		}
		
		dbg_clear("P3Socket", "\n ---Writing to Buffer --- \n");
		atomic {
				while(len > 0) {
						length = (len < TRANSPORT_MAX_PAYLOAD_SIZE) ? len : TRANSPORT_MAX_PAYLOAD_SIZE;
						seq = input->out.lastByteWritten + length;
						createTransport(&msg, input->localPort, input->destPort, TRANSPORT_DATA, 0, seq, &writeBuffer[pos + totalBytes], length);
						bytesWritten = senderBufferPushBack(&input->out, &msg);
						printTransport(&msg);
						if(bytesWritten < 0) {
							dbg("TCPError", "ERROR: Error with write, could not write to buffer\n");
							return TCP_ERRMSG_INVALID; //error
						}
						else if(bytesWritten == 0)
							break; //filled the buffer
						len -= length;
						totalBytes += length;
				}
		}
		dbg("P3Socket", "wrote %d bytes to buffer\n", totalBytes);
		return totalBytes;
	}

	async command bool TCPSocket.isListening(TCPSocketAL *input){
		return (input->state == LISTEN);
	}

	async command bool TCPSocket.isConnected(TCPSocketAL *input){
		return (input->state == ESTABLISHED || input->state == CLOSE_WAIT || input->state == FIN_WAIT_1 || input->state == FIN_WAIT_2);
	}

	async command bool TCPSocket.isClosing(TCPSocketAL *input){
		return (input->state == CLOSING ||  input->state == LAST_ACK || input->state == TIME_WAIT);
	}

	async command bool TCPSocket.isClosed(TCPSocketAL *input){
		return (input->state == CLOSED);
	}

	async command bool TCPSocket.isConnectPending(TCPSocketAL *input){
		return (input->state == SYN_SENT || input->state == SYN_RCVD);
	}
	
	async command void TCPSocket.copy(TCPSocketAL *input, TCPSocketAL *output) {
		memcpy(output, input, sizeof(TCPSocketAL));
	}
}
