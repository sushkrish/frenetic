from ryu.lib.packet import packet
import base64
import networkx as nx
import frenetic
import array
from frenetic.syntax import *
import repeater
import time
from operator import itemgetter
import matplotlib.pyplot as plt
import pickle

"""Ethernet Learning switch"""

conns = nx.DiGraph()

##
# Helper functions
##

def get_tcp(pkt):
    for p in pkt:
        if p.protocol_name == 'tcp':
            return p
def get_ip(pkt):
    for p in pkt:
        if p.protocol_name == 'ipv4':
           return p

def get_time():
    """ returns the number of seconds since Epoch"""
    return int (time.time())

def controller():
    return Mod(Location(Pipe("monitor")))

def unexpected_talkers_w(node):
    """returns a list of tuples (j, w value) where w value is the edge weight from 
       (node, j) divided by j's in-degree"""
    values = []
    out_edges = conns.out_edges([node],data=True )
    for e in out_edges:
        num_incoming = conns.in_degree([e[2]])
        values.append((e[2],conns[node][e[2]]["weight"]/num_incoming))
    return values

def top_talkers_w(node):    
    """returns a list of tuples (j, w value) where w value is the edge weight from (node, j)"""
    values = [] 
    out_edges = conns.out_edges([node],data=True )
    for e in out_edges:
        values.append((e[2],conns[node][e[2]]["weight"]))
    return values
    
        
def signature(node):
    """creates a signature for a given host using the top talkers w function"""
    sig = nx.Graph()
    k = 10
    w_values = top_talkers_w(node)
    if len(w_values) < 10:
        for n,w in w_values:
            sig.add_node(n, device = "host")
    else:
        while k > 0:
           node = max(w_values, key=itemgetter(1))[0]
           sig.add_node(node, device = "host")
           k -= 1

##
# Learning switch functions
##


known_pred = false

def time_window():
    """ keeps edges from the past 30 days"""
    edges = list(conns.edges_iter(data = True))
    for e in edges:
        if get_time() - e[2]['weight'] >= 2592000: 
            conns.remove_edge(e[0], e[1])
    
def monitor(packet):
    global known_pred
    p1 = get_tcp(packet)
    p2 = get_ip(packet)
    if p1 == None or p2 == None:
        return
    tcpSrc = p1.src_port
    tcpDst = p1.dst_port
    ipSrc = p2.src
    ipDst = p2.dst
    print "[monitor] %s:%d => %s:%d" % (ipSrc,tcpSrc,ipDst,tcpDst)
    conns.add_node(ipSrc, device = 'host')
    conns.add_node(ipDst, device = 'host')
    if conns.has_edge(ipSrc, ipDst):
        conns.edge[ipSrc][ipDst]['weight']+=1
        conns.edge[ipSrc][ipDst][time] = get_time()        
    else: 
        conns.add_edge(ipSrc, ipDst, src = tcpSrc, dst = tcpDst, weight = 1, time = get_time())
    host_pred = Test(Location(Pipe("ipSrc"))) & Test(Location(Pipe("ipDst"))) & Test(Location(Pipe("tcpSrc"))) & Test(Location(Pipe("tcpDst")))
    known_pred = known_pred | host_pred
    print "CONNS: {%s}" % conns.edges()
    fd = open("conns.txt", "w")
    pickle.dump(conns, fd)
    fd.close()
    
def policy():
    return Filter(~known_pred) >> controller()

class MonitorApp(frenetic.App):
    client_id = "monitor"

    def packet_in(self,switch_id, port_id, payload):
        ryu_pkt = packet.Packet(array.array('b', payload.data))
        monitor(ryu_pkt)
        self.update(policy())
        time_window()

if __name__ == '__main__':
    print "---WELCOME TO MONITOR---"
    repeater = repeater.RepeaterApp()
    app = MonitorApp()
    app.update(policy())
    app.start_event_loop()