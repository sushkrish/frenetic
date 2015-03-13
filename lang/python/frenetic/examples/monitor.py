from ryu.lib.packet import packet
import base64
from netkat import webkat
import networkx as nx
from netkat.syntax import *
import learning
import time 
from operator import itemgetter

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
    return modify("port", "http")


def unexpected_talkers_w(node):
    """returns a list of tuples (j, w value) where w value is the edge weight from 
       (node, j) divided by j's in-degree"""
    values = []
    out_edges = conns.out_edges([node],data=True )
    for e in out_edges:
        num_incoming = conns.in_degree([e[2]])
        values.append((e[2],conns.[node][e[2]]["weight"]/num_incoming))
    return values

def top_talkers_w(node):    
    """returns a list of tuples (j, w value) where w value is the edge weight from (node, j)"""
    values = [] 
    out_edges = conns.out_edges([node],data=True )
    for e in out_edges:
        values.append((e[2],conns.[node][e[2]]["weight"]))
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


known_pred = false()
def time_window():
    """ keeps edges from the past 30 days"""
    edges = list(conns.edges.iter(data = True))
    for e in edges:
        if get_time() - e[2].['weight'] >= 2592000: 
            conns.delete_edge(e[0], e[1])
    

def monitor(packet):
    global known_pred
    p1 = get_tcp(packet)
    tcpSrc = p1.src_port
    tcpDst = p1.dst_port
    p2 = get_ip(packet)
    ipSrc = p2.src
    ipDst = p2.dst
    conns.add_node(ipSrc, device = 'host')
    conns.add_node(ipDst, device = 'host')
    if conns.has_edge(ipSrc, ipDst):
        conns.edge[ipSrc][ipDst]['weight']+=1
        conns.edge[ipSrc][ipDst][time] = get_time()        
    else: 
        conns.add_edge(ipSrc, ipDst, src = tcpSrc, dst = tcpDst, weight = 1, time = get_time())
    print conns
    host_pred = test('ipSrc', ipSrc) & test('ipDst', ipDst) & test('tcpSrcPort', tcpSrc) & test('tcpDstPort', tcpDst)
    known_pred = known_pred | host_pred
    
def policy():
    return filter(~known_pred) >> controller()

class MonitorApp(webkat.App):

    def packet_in(self,switch_id, port_id, packet):
        monitor(packet)
        self.update(policy())
        time_window()

if __name__ == '__main__':
    print "---WELCOME TO MONITOR---"
    webkat.UnionApp(learning.LearningApp(), MonitorApp()).start()
    webkat.start()
