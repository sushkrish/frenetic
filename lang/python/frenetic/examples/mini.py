#! /usr/bin/python

from mininet.topo import Topo
from mininet.net import Mininet
from mininet.util import dumpNodeConnections
from mininet.log import setLogLevel
from mininet.node import OVSController, RemoteController
from mininet.cli import CLI
import sys

class SingleSwitchTopo(Topo):
    "Single switch connected to n hosts."
    def __init__(self, n=2, **opts):
        # Initialize topology and default options
        Topo.__init__(self, **opts)
        switch = self.addSwitch('s1')
        # Python's range(N) generates 0..N-1
        for h in range(n):
            host = self.addHost('h%s' % (h + 1))
            self.addLink(host, switch)

def createNetwork():
    "Create and test a simple network"
    topo = SingleSwitchTopo(12)
    net = Mininet(topo = topo, controller = RemoteController)
    net.start()
    print "Dumping host connections"
    dumpNodeConnections(net.hosts)
    print "Start ping"
    net.pingAll()
    print net['h1']
    net.stop()

def pad(n):
    if (n < 10):
        return "0" + str(n)
    else: 
        return str(n)

def createNetwork2():
    "Create and test a simple network"
    fd = open("X01_final.txt", "r")
    with open ("X01_final.txt", "r") as file:
        data=file.readlines()
        data=data[0].split()
        print len(data)
    topo = SingleSwitchTopo(12)
    net = Mininet(topo = topo, controller = RemoteController)
    net.start()
    hosts = net.hosts  
    print "Setting up the servers..."   
    for h in range(12):
        print hosts[h].IP()
        print hosts[h].cmd( 'python -m SimpleHTTPServer &')
    print "Doing the requests..."
    m = 0
    for k in range(2016):
        for i in range(12):
            for j in range(12):
                if (i != j):
                    print str(hosts[j].IP()) + " curling from 10.0.0.%s:8000 %s times" % ((i + 1), data[m])
                    for l in range(int(data[m])):
                        hosts[j].cmd('curl 10.0.0.%s:8000' % (i + 1))
                m+=1
    
    print "Dumping host connections"
    dumpNodeConnections(net.hosts)
    net.stop()

if __name__ == '__main__':
    # Tell mininet to print useful information
    setLogLevel('info')
    createNetwork2()