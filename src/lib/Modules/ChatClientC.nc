#include "TCPSocketAL.h"
#include "clientJL.h"
#include "../packet.h"
#include <stdio.h>

module ChatClientC{
	uses{
		interface TCPSocket<TCPSocketAL>;
		
		interface Timer<TMilli> as ChatClientTimer;
		interface Random;
		interface TCPManager<TCPSocketAL,pack>;
	}
	provides{
		interface chatClient<TCPSocketAL>;
	}
}
implementation{
	clientJL mClient;
	
	command void chatClient.init(TCPSocketAL *socket, char* username, uint8_t clientPort){
		// TODO pass output socket and port for listener for input
		mClient.outSocket = socket;
		mClient.startTime = 0;
		chatBufferInit(&mClient.cmdBuff);
		strcpy(mClient.username, username);
		//dbg("Project4", "name:%s\n", mClient.username);
		
		mClient.inSocket = call TCPManager.socket();
		call TCPSocket.bind(mClient.inSocket, clientPort, TOS_NODE_ID);
		call TCPSocket.listen(mClient.inSocket, 1); //TODO see if you use the listening socket as the dest for accept it will properly fork the connection onto itself and stop listening, might requre a tiny amount of legwork 
		
		call ChatClientTimer.startPeriodic(CHAT_CLIENT_TIMER_PERIOD + (uint16_t) ((call Random.rand16())%200));
	}
	
	command int16_t chatClient.sendMsg(char* msg, int16_t length) {
		return call TCPSocket.write(mClient.outSocket, msg, 0, length);
	}

	event void ChatClientTimer.fired() {
		char tempMsg[64];
		//Output socket states
		if(call TCPSocket.isConnectPending(mClient.outSocket)) {
			dbg("Project4", "Initial connect pending...\n");
		} else if(call TCPSocket.isConnected(mClient.outSocket)) {
			if(mClient.startTime == 0) { // First Iteration
				mClient.startTime = call ChatClientTimer.getNow();
				dbg("Project4", "Chat Client - Connection established at time: %lu\n\n", mClient.startTime);
				sprintf(tempMsg, "hello %s %d\r\n", mClient.username, mClient.inSocket->srcPort);
				//dbg("Project4", "made a string %s", tempMsg);
				//TODO send the hello cmd
				call TCPSocket.write(mClient.outSocket, tempMsg, 0, strlen(tempMsg));
			}
			//TODO once you connect, start accepting
			if(call TCPSocket.isListening(mClient.inSocket)) {
				if(call TCPSocket.accept(mClient.inSocket, mClient.inSocket) == TCP_ERRMSG_SUCCESS){
					dbg("Project4", "insocket accept success\n\n");
				}
			}
		} else if(call TCPSocket.isClosing(mClient.outSocket)) {
			//Debugging statements
			//dbg("clientAL", "clientAL ----- CLOSING!\n");
		} else if(call TCPSocket.isClosed(mClient.outSocket)) {
			uint32_t endTime = call ChatClientTimer.getNow();
			
			dbg("clientAL", "clientAL - Conection Closed at time: %lu \n", endTime);
			//TODO close connection in the IN direction, might need to be done by server
			call TCPSocket.release(mClient.outSocket);
			call ChatClientTimer.stop();
			return;
		}
		
		//Input socket states
		if(call TCPSocket.isConnected(mClient.inSocket)) {
			int16_t count;
			
			count = call TCPSocket.read(mClient.inSocket, mClient.cmdBuff.buffer, mClient.cmdBuff.length, CHAT_BUFFER_SIZE - mClient.cmdBuff.length);
			mClient.cmdBuff.length += count;
			
			if(count == -1){
				// Socket unable to read, release socket
				dbg("Project4", "Chat Client - Releasing socket\n");
				call TCPSocket.release(mClient.inSocket);
				return;
			}
			if(count > 0 ){
				dbg("Project4d", "read data\n");
				memset(mClient.nextCmd, 0, sizeof(mClient.nextCmd));
				mClient.cmdLen = chatBufferNextCmd(&mClient.cmdBuff, mClient.nextCmd, 128);
				if(mClient.cmdLen > 0) {
					dbg("Project4", "%s", mClient.nextCmd);	
				}
			}
		}
	}
}