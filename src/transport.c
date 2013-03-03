#ifndef _TRANSPORT_H_
#define _TRANSPORT_H_

//Includes
#include "../packet.h"

void createTransport(transport *output, uint8_t srcPort, uint8_t destPort, uint8_t type, uint16_t window, int16_t seq, uint8_t *payload, uint8_t packetLength){
	uint16_t i=0;

	//Check to see if it is a valid transport Packet
	//	port does not need to be check is an 8 bit number is between 0 - 255
	if(type > TRANSPORT_TYPE_SIZE
			|| packetLength > TRANSPORT_MAX_PAYLOAD_SIZE){
		dbg("error", "Error: Transport - Invalid arguments It is type, %d and length %d.\n", type, packetLength);
		return;
	}
	output->srcPort=srcPort;
	output->destPort=destPort;
	output->type =type;
	output->window = window;
	output->seq = seq;
	output->length = packetLength;

	memcpy(output->payload, payload, packetLength);

	for(i=packetLength; i<TRANSPORT_MAX_PAYLOAD_SIZE; i++){
		output->payload[i]=0;
	}

}

void printTransport(transport *input){
	int i;
	dbg("transport", "Transport Packet - SrcPort: %hhu, DestPort: %hhu, Type: ", input->srcPort, input->destPort);
	switch(input->type){
		case TRANSPORT_SYN:
			dbg_clear("transport", "SYN ");
			break;
		case TRANSPORT_ACK:
			dbg_clear("transport", "ACK ");
			break;
		case TRANSPORT_FIN:
			dbg_clear("transport", "FIN ");
			break;
		case TRANSPORT_DATA:
			dbg_clear("transport", "DATA ");
			break;
		case TRANSPORT_RST:
			dbg_clear("transport", "RST ");
			break;
		default:
			dbg_clear("transport", "UNKNOWN");
	}
	dbg_clear("transport", "Window: %lu, Seq: %lu, Payload: ", input->window, input->seq, input->payload);

	for(i=0; i<input->length; i++){
		dbg_clear("transport", "%hhu, ", input->payload[i]);
	}

	dbg_clear("transport", "\n");
}

#endif
