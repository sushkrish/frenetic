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
import json
from networkx.readwrite import json_graph
import tornado.web
import tornado.ioloop


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
    return int(time.time())

def controller():
    return Mod(Location(Pipe("monitor")))

def unexpected_talkers_w(node):
    """returns a list of tuples (j, w value) where w value is the edge weight from 
       (node, j) divided by j's in-degree"""
    global conns
    values = []
    out_edges = conns.out_edges([node],data=True )
    for e in out_edges:
        num_incoming = conns.in_degree([e[1]])
        values.append((e[1],conns[node][e[1]]['weight']/num_incoming))
    return values

def top_talkers_w(node):    
    """returns a list of tuples (j, w value) where w value is the edge weight from (node, j)"""
    global conns
    values = [] 
    out_edges = conns.out_edges([node],data=True )
    for e in out_edges:
        values.append((e[1],conns[node][e[1]]['weight']))
    print "W VALUES: %s" %values
    return values
  
sig = nx.Graph()

def signature(node):
    """creates a signature for a given host using the top talkers w function"""
    global conns
    sig = nx.Graph()
    k = 5
    w_values = top_talkers_w(node)
    if len(w_values) < 5:
        for n,w in w_values:
            print "ADDING NODE TO SIG %s" % n
            sig.add_node(n, device = "host")
    else:
        while k > 0:
           node = max(w_values, key=itemgetter(1))[0]
           print "ADDING NODE TO SIG %s" % node
           sig.add_node(node, device = "host")
           w_values.remove(max(w_values, key=itemgetter(1)))
           k -= 1

    print "SIG NODES: %s" % sig.nodes()


##
# Learning switch functions
##


known_pred = false

def time_window():
    """ keeps edges from the past 30 days"""
    global conns
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
    #conns.add_node(ipSrc, device = 'host')
    #conns.add_node(ipDst, device = 'host')
    if conns.has_edge(ipSrc, ipDst):
        print "SAME EDGE %s to %s" % (ipSrc, ipDst)
        conns.edge[ipSrc][ipDst]['weight']+=1
        conns.edge[ipSrc][ipDst]["time"] = get_time()        
    else: 
        print "Adding new edge from %s to %s" % (ipSrc, ipDst)
        conns.add_edge(ipSrc, ipDst, src = tcpSrc, dst = tcpDst, weight = 1, time = get_time())
    host_pred = Test(Location(Pipe("ipSrc"))) & Test(Location(Pipe("ipDst"))) & Test(Location(Pipe("tcpSrc"))) & Test(Location(Pipe("tcpDst")))
    known_pred = known_pred | host_pred
    print "CONNS NODES: %s" % conns.nodes()
    print "CONNS EDGES: %s" % conns.edges()
    signature("10.0.0.4")
    
def policy():
    return Filter(~known_pred) >> controller()

class MonitorApp(frenetic.App):
    client_id = "monitor"

    def packet_in(self,switch_id, port_id, payload):
        ryu_pkt = packet.Packet(array.array('b', payload.data))
        monitor(ryu_pkt)
        self.update(policy())

##
# Tornado Server
##

class MainHandler(tornado.web.RequestHandler):
    def get(self):
        self.render("graph.html")

    def post():
        pass

class ConnsHandler(tornado.web.RequestHandler):
    def get(self):
        global conns
        j = json.dumps(json_graph.node_link_data(conns))
        self.write(j)

    def post(self):
        pass

class SigHandler(tornado.web.RequestHandler):
    def get(self):
        global sig
        j = json.dumps(json_graph.node_link_data(sig))
        self.write(j)

    def post(self):
        pass

app = tornado.web.Application([
(r"/", MainHandler),
(r"/conns.json", ConnsHandler),
(r"/sig.json", SigHandler),
])

if __name__ == '__main__':
    print "---WELCOME TO MONITOR---"
    repeater = repeater.RepeaterApp()
    app.listen(8888)
    app = MonitorApp()
    app.update(policy())
    app.start_event_loop()




