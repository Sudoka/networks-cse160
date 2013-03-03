/*
 * Author: Alex Beltran
 * Created: April 10, 2012
 * Last Modified: April 10, 2012
 * Description: A basic packet used for TCP Protocol
 */
#ifndef TRANSPORT_H
#define TRANSPORT_H

//Includes
#include "../packet.h"

//General Transport Information
enum{
	TRANSPORT_MAX_SIZE = PACKET_MAX_PAYLOAD_SIZE,
	TRANSPORT_HEADER_SIZE = 8,
	TRANSPORT_MAX_PAYLOAD_SIZE = TRANSPORT_MAX_SIZE - TRANSPORT_HEADER_SIZE,
	TRANSPORT_MAX_PORT = 255 
};

//Types of Packets
enum{
	TRANSPORT_SYN = 0,
	TRANSPORT_ACK = 1,
	TRANSPORT_FIN = 2,
	TRANSPORT_DATA = 3,
	TRANSPORT_RST = 4,
	TRANSPORT_TYPE_SIZE = 5
};

enum{
	NULL_TRANSPORT_PAYLOAD = 0,
	NULL_TRANSPORT_VALUE = 0,
	NULL_TRANSPORT_HEX_VALUE = 0x0000
};

typedef nx_struct transport{
	nx_uint8_t srcPort;
	nx_uint8_t destPort;
	nx_uint8_t type;
	nx_uint16_t window;
	nx_uint16_t seq; //this cant be allowed to go above 2^15
	nx_uint8_t length;
	nx_uint8_t payload[TRANSPORT_MAX_PAYLOAD_SIZE];
}transport;

void createTransport(transport *output, uint8_t srcPort, uint8_t destPort, uint8_t type, uint16_t window, int16_t seq, uint8_t *payload, uint8_t packetLength);
void printTransport(transport *input);

#include "transport.c"
#endif /* TRANSPORT_H */
