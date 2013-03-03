/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   Apr 28 2012
 * 
 */ 

#include <Timer.h>
#include "packet.h"


configuration NodeC{
}
implementation {
	components MainC;
	components Node;
	components RandomC as Random;
	
	components serverC as ALServer;
	components clientC as ALClient;
	components TCPManagerC as TCPManager;
	components TCPSocketC as ALSocket;
	
	components new TimerMilliC() as ServerTimer;
	components new TimerMilliC() as ClientTimer;
	components new TimerMilliC() as ServerWorkerTimer;
	components new TimerMilliC() as pingTimeoutTimer;
	components new TimerMilliC() as discoveryTimer;
	components new TimerMilliC() as lspTimer;
	components new TimerMilliC() as socketTimer;
	components new TimerMilliC() as shutdownTimer;
	
	components ActiveMessageC;
	components new AMSenderC(6);
	components new AMReceiverC(6);

	Node -> MainC.Boot;
	
	//Timers
	Node.pingTimeoutTimer->pingTimeoutTimer;
	Node.discoveryTimer->discoveryTimer;
	Node.lspTimer->lspTimer;
	
	TCPManager.socketTimer -> socketTimer;
	TCPManager.shutdownTimer -> shutdownTimer;
	
	Node.Random -> Random;
	ALSocket.Random -> Random;
	ALSocket.TCPManager -> TCPManager;
	
	ALSocket.NetLayer -> Node;
	TCPManager.NetLayer -> Node;
	
	Node.Packet -> AMSenderC;
	Node.AMPacket -> AMSenderC;
	Node.AMSend -> AMSenderC;
	Node.AMControl -> ActiveMessageC;
	Node.TCPManager -> TCPManager;
	TCPManager.TCPSocket -> ALSocket;
	Node.ALSocket -> ALSocket;

	Node.Receive -> AMReceiverC;
	
	Node.ALServer -> ALServer;
	ALServer.ServerTimer -> ServerTimer;
	ALServer.WorkerTimer -> ServerWorkerTimer;
	ALServer.TCPSocket -> ALSocket;
	ALServer.Random -> Random;
	ALServer.TCPManager -> TCPManager;
	
	Node.ALClient -> ALClient;
	ALClient.ClientTimer -> ClientTimer;
	ALClient.Random -> Random;
	ALClient.TCPManager -> TCPManager;
	ALClient.TCPSocket -> ALSocket;
}
