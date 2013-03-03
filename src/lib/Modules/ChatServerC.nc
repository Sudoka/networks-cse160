#include "serverJL.h"
#include "TCPSocketAL.h"
#include "serverWorkerList.h"
#include "../packet.h"
#include "chatCommand.h"
#include "../../dataStructures/chatBuffer.h"
#include <stdio.h>

module ChatServerC{
	uses{
		interface TCPSocket<TCPSocketAL>;
		interface Timer<TMilli> as ChatServerTimer;
		interface Timer<TMilli> as ChatWorkerTimer;
		interface Random;
		interface TCPManager<TCPSocketAL,pack>;
	}
	provides{
		interface chatServer<TCPSocketAL>;
		interface chatServerWorker<serverWorkerJL, TCPSocketAL>;
	}
}
implementation{
	//Local Variables Variables
	serverJL mServer;	
	serverWorkerList workers;

	void echoToAll(char *msg);

	command void chatServer.init(TCPSocketAL *socket){
		if(socket->srcPort != 41 || TOS_NODE_ID != 1) {
			dbg("Project4", "Set up server on improper node %d port %d\n", TOS_NODE_ID, socket->srcPort);
		}
		mServer.socket = socket;
		mServer.numofWorkers=0;	
			
		call ChatServerTimer.startPeriodic(SERVER_TIMER_PERIOD + (uint16_t) ((call Random.rand16())%200));
		call ChatWorkerTimer.startPeriodic(WORKER_TIMER_PERIOD + (uint16_t) ((call Random.rand16())%200));
	}

	event void ChatServerTimer.fired(){
		if(! call TCPSocket.isClosed(mServer.socket) ){
			TCPSocketAL connectedSock;

			//Attempt to Establish a Connection
			if(call TCPSocket.accept(mServer.socket, &(connectedSock)) == TCP_ERRMSG_SUCCESS){
				serverWorkerJL newWorker;
				
				dbg("Project4", "Chat Server - Connection Accepted.\n");
								
				//create a worker.
				call chatServerWorker.init(&newWorker, &connectedSock);
				newWorker.id = mServer.numofWorkers;
				mServer.numofWorkers++;
				serverWorkerListPushBack(&workers, newWorker);
			}
		}else{ //Shutdown
			//Socket is closed, shutdown
			dbg("Project4", "Chat Server - Server Shutdown\n" );
			
			call TCPSocket.release( mServer.socket );			
			call ChatWorkerTimer.stop();
			call ChatServerTimer.stop();
		}
	}
	
	command void chatServerWorker.init(serverWorkerJL *worker, TCPSocketAL *inputSocket){
		uint8_t tempPort;
		worker->inSocket = call TCPManager.socket();
		worker->outSocket = call TCPManager.socket();
		
		worker->outSocket->srcPort = call TCPManager.getFreePort();
		worker->outSocket->srcAddr = TOS_NODE_ID;
		
		chatBufferInit(&worker->cmdBuff);
		
		call TCPSocket.copy(inputSocket, worker->inSocket);
		//call TCPSocket.connect(outSock, inputSocket->destAddr, 4);
		//worker->socket->addr, worker->socket->destAddr);		
		dbg("Project4", "Chat Server - Worker Intilized\n");
	}

	command void chatServerWorker.execute(serverWorkerJL *worker){
		if(!call TCPSocket.isClosed(worker->inSocket)) {
			uint16_t count, i;
			uint8_t *ptr;
			count = call TCPSocket.read(worker->inSocket, worker->cmdBuff.buffer, worker->cmdBuff.length, CHAT_BUFFER_SIZE - worker->cmdBuff.length);
			worker->cmdBuff.length += count;
			
			if(count == -1){
				// Socket unable to read, release socket
				dbg("Project4", "Chat Server - Releasing socket\n");
				call TCPSocket.release( (worker->inSocket) );
				
				serverWorkerListRemoveValue(&workers, *worker);
				return;
			}
			if(count > 0) {
				memset(worker->nextCmd, 0, sizeof(worker->nextCmd));
				worker->cmdLen = chatBufferNextCmd(&worker->cmdBuff, worker->nextCmd, 128);
				if(worker->cmdLen > 0) {
					dbg("Project4", "received a full CMD\n");
					
					worker->nextCmd[worker->cmdLen-2] = 0;
					worker->cmdLen -= 2;
							
					switch(getChatCMD(worker->nextCmd, worker->cmdLen)) {
						uint8_t *userName, clientPort;
						char newMsg[128];
						serverWorkerJL *currentWorker;
						case CHAT_HELLO:
							dbg("Project4", "Received Hello Command %s\n", worker->nextCmd);
							strtok(worker->nextCmd, " ");
							userName = strtok(NULL, " ");
							strcpy(worker->username, userName);
							//dbg("Project4", "uusername:%s\n", worker->username);
							clientPort = atoi(strtok(NULL, " "));
							//dbg("Project4", "%d\n", worker->outSocket->srcPort);
							call TCPSocket.connect(worker->outSocket, worker->inSocket->destAddr, clientPort);
							//dbg("Project4", "clientport:%d\n", clientPort);
							break;
							
						case CHAT_MSG: //TODO even if i fix it go back and check why it crashes when theres no /r/n
							dbg("Project4", "Received Msg:\"%s\" command from:%s\n", &worker->nextCmd[4], worker->username);
							sprintf(newMsg, "msg %s %s\r\n", worker->username, &worker->nextCmd[4]);
							echoToAll(newMsg);
							break;
							
						case CHAT_LISTUSR:
							dbg("Project4", "Received listusr request from %s\n", worker->username);
							sprintf(newMsg, "listusr");
							for(i = 0; i<serverWorkerListSize(&workers); i++) {
								currentWorker = serverWorkerListGet(&workers, i);
								strcat(newMsg, ", ");
								strcat(newMsg, currentWorker->username);
							}
							strcat(newMsg, "\r\n");
							call TCPSocket.write(worker->outSocket, newMsg, 0, strlen(newMsg));
							break;
					}
				}
			}
		}else{
			uint32_t closeTime;
			closeTime = call ChatServerTimer.getNow();
				
			dbg("Project4", "Connection Closed:\n");
			dbg("Project4", "Close Time: %d\n", closeTime);
			call TCPManager.freeSocket(worker->inSocket);
			serverWorkerListRemoveValue(&workers, *worker);
			return;
		}
	}
	
	void echoToAll(char *msg) {
		uint16_t i;
		serverWorkerJL *currentWorker;
		dbg("Project4", "Size : %d\n", serverWorkerListSize(&workers));
		for(i=0; i<serverWorkerListSize(&workers); i++){
			currentWorker = serverWorkerListGet(&workers, i);
			dbg("Project4", "state : %d\n", currentWorker->outSocket->state);
			if(call TCPSocket.isConnected(currentWorker->outSocket)) {
				dbg("Project4", "Sending msg to %s\n", currentWorker->username);
				if(call TCPSocket.write(currentWorker->outSocket, msg, 0, strlen(msg)) != strlen(msg))
					dbg("Project4", "Couldnt write full msg\n");
			}
		}	
	}

	event void ChatWorkerTimer.fired(){
		uint16_t i;
		serverWorkerJL *currentWorker;
		
		for(i=0; i<serverWorkerListSize(&workers); i++){
			currentWorker = serverWorkerListGet(&workers, i);
			
			call chatServerWorker.execute(currentWorker);
		}	
	}
}