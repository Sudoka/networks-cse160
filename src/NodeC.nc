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
	
	components ChatServerC as JLServer;
	components ChatClientC as JLClient;
	components TCPManagerC as TCPManager;
	components TCPSocketC as ALSocket;
	
	components new TimerMilliC() as ChatServerTimer;
	components new TimerMilliC() as ChatClientTimer;
	components new TimerMilliC() as ChatServerWorkerTimer;
	components new TimerMilliC() as pingTimeoutTimer;
	components new TimerMilliC() as discoveryTimer;
	components new TimerMilliC() as lspTimer;
	components new TimerMilliC() as socketTimer;
	components new TimerMilliC() as shutdownTimer;
	components new TimerMilliC() as tcpTimer;
	
	components ActiveMessageC;
	components new AMSenderC(6);
	components new AMReceiverC(6);

	Node -> MainC.Boot;
	
	//Timers
	Node.pingTimeoutTimer->pingTimeoutTimer;
	Node.discoveryTimer->discoveryTimer;
	Node.lspTimer->lspTimer;
	
	Node.Random -> Random;
	ALSocket.TCPManager -> TCPManager;
	ALSocket.tcpTimer -> tcpTimer;
	
	ALSocket.NetLayer -> Node;
	TCPManager.NetLayer -> Node;
	TCPManager.socketTimer -> socketTimer;
	TCPManager.shutdownTimer -> shutdownTimer;
	
	Node.Packet -> AMSenderC;
	Node.AMPacket -> AMSenderC;
	Node.AMSend -> AMSenderC;
	Node.AMControl -> ActiveMessageC;
	Node.TCPManager -> TCPManager;
	TCPManager.TCPSocket -> ALSocket;
	Node.TCPSocket -> ALSocket;

	Node.Receive -> AMReceiverC;
	
	Node.JLServer -> JLServer;
	JLServer.ChatServerTimer -> ChatServerTimer;
	JLServer.ChatWorkerTimer -> ChatServerWorkerTimer;
	JLServer.TCPSocket -> ALSocket;
	JLServer.Random -> Random;
	JLServer.TCPManager -> TCPManager;
	
	Node.JLClient -> JLClient;
	JLClient.ChatClientTimer -> ChatClientTimer;
	JLClient.Random -> Random;
	JLClient.TCPManager -> TCPManager;
	JLClient.TCPSocket -> ALSocket;
}