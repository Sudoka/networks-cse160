#ANDES Lab - University of California, Merced
#Author: UCM ANDES Lab
#Last Update: 4/28/2011
#! /usr/bin/python
from TOSSIM import *
from packet import *
import sys

numNodes = 2

t = Tossim([])
r = t.radio()
f = open("topo.txt", "r")


for line in f:
  s = line.split()
  if s:
    print " ", s[0], " ", s[1], " ", s[2];
    r.add(int(s[0]), int(s[1]), float(s[2]))

# Channels used for debuging
t.addChannel("genDebug", sys.stdout)
t.addChannel("cmdDebug", sys.stdout);
t.addChannel("Project1N", sys.stdout)
t.addChannel("Project1F", sys.stdout)



noise = open("no_noise.txt", "r")
for line in noise:
  str1 = line.strip()
  if str1:
    val = int(str1)
    for i in range(1, 3):
       t.getNode(i).addNoiseTraceReading(val)

for i in range(1, 3):
  print "Creating noise model for ",i;
  t.getNode(i).createNoiseModel()

t.getNode(1).bootAtTime(1000);
t.getNode(2).bootAtTime(2333);


def package(string):
 	ints = []
	for c in string:
		ints.append(ord(c))
	return ints

def run(ticks):
	for i in range(ticks):
		t.runNextEvent()

def runTime(amount):
	time = t.time()
	while time + amount*10000000000 > t.time():
		t.runNextEvent() 

#Create a Command Packet
msg = pack()
msg.set_seq(0)
msg.set_TTL(15)
msg.set_protocol(0)

pkt = t.newPacket()
print(type(pkt))
pkt.setData(msg.data)
pkt.setType(msg.get_amType())

def sendCMD(string):
	args = string.split(' ');
	msg.set_src(int(args[0]));
	msg.set_dest(int(args[1]));
	payload=args[2];
	for i in range(3, len(args)):
		payload= payload + ' '+ args[i]
	
	msg.setString_payload(payload)
	
	pkt.setData(msg.data)
	pkt.setDestination(int(args[1]))
	
	#print "Delivering!"
	pkt.deliver(int(args[1]), t.time()+5)
	runTime(2);


runTime(200)
#where is this send happening in code, i tried to make a debug print that would say "sending packet %s", msg
#but i could not find the proper place in the Node.nc file 
#id like to have 3 print segments per packet sent, a sending, a receiving, and a replying
sendCMD("1 2 Hello World!")
sendCMD("2 1 Hi im marbin!")
#sendCMD("1 3 Greatest Destiny")
    
