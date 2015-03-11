import struct, frenetic, binascii, array
from functools import partial
from ryu.lib.packet import packet, packet_base, ethernet, arp
from frenetic.syntax import *
from state import *
from tornado.ioloop import PeriodicCallback
from tornado.ioloop import IOLoop
from tornado.concurrent import return_future
from flood_switch import *

# Packet to be encoded for sending Probes over the probocol

def get(pkt,protocol):
    for p in pkt:
        if p.protocol_name == protocol:
            return p

class ProbeData(packet_base.PacketBase):

  PROBOCOL = 0x808
  NO_RESPONSE_THRESHOLD = 5
  _PACK_STR = '!LH'
  _MIN_LEN = struct.calcsize(_PACK_STR)
  _TYPE = {
      'ascii': [
          'src_switch', 'src_port'
      ]
  }

  def __init__(self, src_switch, src_port):
    self.src_switch = src_switch
    self.src_port = src_port

  @classmethod
  def parser(cls, buf):
      (src_switch, src_port) = struct.unpack_from(cls._PACK_STR, buf)
      return cls(src_switch, src_port), cls._TYPES.get(cls.PROBOCOL), buf[ProbeData._MIN_LEN:]

  def serialize(self, payload, prev):
      return struct.pack(ProbeData._PACK_STR, self.src_switch, self.src_port)

  def __eq__(self, other):
    return (isinstance(other, self.__class__) and
            self.src_switch == other.src_switch and
            self.src_port == other.src_port)

  def __hash__(self):
    return self.src_switch*29 + self.src_port*37

ProbeData.register_packet_type(ProbeData, ProbeData.PROBOCOL)

class Topology(frenetic.App):

  client_id = "topology"

  def __init__(self, state, version):
    frenetic.App.__init__(self)
    self.version = version
    self.state = state
    self.state.register(self)

  def connected(self):
    # Every 10 seconds send out probes on ports we don't know about
    PeriodicCallback(self.run_probe, 10000).start()
    # In version 2, read port counters every 10 seconds too.
    if self.version == 2:
      PeriodicCallback(self.update_weights, 10000).start()

  def update_next_callback(self, ftr):
    # Pull the edges out of the future and propogate the edges along
    # Yay for monads in python!
    edges = ftr.result()
    self.update_weights_helper(edges)

  def update_callback(self, ftr, edge, edges, callback):
    # Pull out the current edge weight if it exists
    curr_weight = 0
    if 'weight' in self.state.network[edge[0]][edge[1]]:
      curr_weight = self.state.network[edge[0]][edge[1]]['weight']
    data = ftr.result()
    weight = data['rx_bytes'] + data['tx_bytes']
    # If the weight has changed, update the edge weight and mark the state as dirty
    if weight != curr_weight:
      label = self.state.network[edge[0]][edge[1]]['label']
      self.state.network.add_edge(edge[0], edge[1], label=label, weight=weight)
      self.state._clean = False
    callback(edges)

  @return_future
  def update_next(self, edges, callback):
    # This should never be called with an empty edge list
    assert edges
    # Take the next edge, pull out the label and ask for the port_stats
    edge = edges.pop()
    switch_id = edge[0]
    dst_id = edge[1]
    port_id = self.state.network[switch_id][dst_id]['label']
    ftr = self.port_stats(str(switch_id), str(port_id))
    f = partial(self.update_callback,
                edge = edge,
                edges = edges,
                callback = callback)
    IOLoop.instance().add_future(ftr, f)

  def update_weights_helper(self, edges):
    # If there are no edges left, call notify.
    if edges:
      ftr = self.update_next(edges)
      IOLoop.instance().add_future(ftr, self.update_next_callback)
    else:
      self.state.notify()

  def update_weights(self):
    edges = networkx.get_edge_attributes(self.state.network, 'label').keys()
    self.update_weights_helper(edges)


  def run_update(self):
    # This function is invoked by State when the network changes
    self.update(self.policy())

  def check_host_edge(self, probe_data):
    # If we have not met the probe threshold don't accept any edges
    if self.state.probes_sent[probe_data] < ProbeData.NO_RESPONSE_THRESHOLD:
      return False
    # If we are past the threshold but no tentative edge exists keep probing
    if not (probe_data in self.state.tentative_edge):
      return False
    # Else we should solidify the edge and stop probing
    host_id = self.state.tentative_edge[probe_data]
    del self.state.tentative_edge[probe_data]
    print "Permanent edge: (%s, %s) to %s" % (probe_data.src_switch, probe_data.src_port, host_id)
    return True

  def run_probe(self):
    to_remove = set()
    for probe_data in self.state.probes:
      # Check if this probe is a host edge
      if self.check_host_edge(probe_data):
        to_remove.add(probe_data)
        continue

      # Build a PROBOCOL packet and send it out
      print "Sending probe: (%s, %s)" % (probe_data.src_switch, probe_data.src_port)
      pkt = packet.Packet()
      pkt.add_protocol(ethernet.ethernet(ethertype=ProbeData.PROBOCOL))
      pkt.add_protocol(probe_data)
      pkt.serialize()
      payload = NotBuffered(binascii.a2b_base64(binascii.b2a_base64(pkt.data)))
      actions = [Output(Physical(probe_data.src_port))]
      self.pkt_out(probe_data.src_switch, payload, actions)
      self.state.probes_sent[probe_data] = self.state.probes_sent[probe_data] + 1

    # Cleanup any host edges we discovered
    for probe_data in to_remove:
      self.state.probes.discard(probe_data)

  def policy(self):
    # All PROBOCOL traffic is sent to the controller, otherwise flood
    probe_traffic = Filter(Test(EthType(ProbeData.PROBOCOL))) >> Mod(Location(Pipe("http")))
    sniff_arp = Filter(Test(EthType(0x806))) >> Mod(Location(Pipe("http")))
    return probe_traffic | sniff_arp

  def create_probes(self, switch_ref):
    for port in switch_ref.ports:
      probe_data = ProbeData(switch_ref.id, port)
      self.state.probes.add(probe_data)
      self.state.probes_sent[probe_data] = 0

  def discard_probes(self, switch_ref):
    for port in switch_ref.ports:
      probe_data = ProbeData(switch_ref.id, port)
      self.state.probes.discard(probe_data)
      del self.state.probes_sent[probe_data]

  def switch_up(self, switch_id, ports):
    # When a switch comes up, add it to the network and create
    # probes for each of its ports
    print "switch_up(%s, %s)" % (switch_id, ports)
    switch_ref = SwitchRef(switch_id, ports)
    self.state.add_switch(switch_ref)
    self.create_probes(switch_ref)
    self.state.notify()

  def switch_down(self, switch_id):
    # When a switch goes down, remove any unresolved probes and remove
    # it from the network graph
    print "switch_down(%s)" % switch_id
    self.discard_probes(self.state.switches()[switch_id])
    self.state.remove_switch(switch_id)
    self.state.notify()

  def remove_tentative_edge(self, probe_data):
    if(probe_data in self.state.tentative_edge):
      host_id = self.state.tentative_edge[probe_data]
      del self.state.tentative_edge[probe_data]
      self.state.remove_edge(probe_data.src_switch, host_id)
      self.state.remove_edge(host_id, probe_data.src_switch)
      self.state.notify()
      print "Removed tentative edge: (%s, %s) to %s" % (probe_data.src_switch, probe_data.src_port, host_id)

  def handle_probe(self, dst_switch, dst_port, src_switch, src_port):
    # When a probe is received, add edges based on where it traveled
    print "Probe received from (%s, %s) to (%s, %s)" % (src_switch, src_port, dst_switch, dst_port)
    self.state.add_edge(dst_switch, src_switch, label=dst_port)
    self.state.add_edge(src_switch, dst_switch, label=src_port)
    self.state.probes.discard(ProbeData(dst_switch, dst_port))
    self.state.probes.discard(ProbeData(src_switch, src_port))
    self.remove_tentative_edge(ProbeData(src_switch, src_port))
    self.remove_tentative_edge(ProbeData(dst_switch, dst_port))
    self.state.notify()

  def handle_arp(self, switch_id, port_id, arp):
    self.state.add_host(arp.src_mac)
    if(ProbeData(switch_id, port_id) in self.state.probes and
       ProbeData(switch_id, port_id) not in self.state.tentative_edge):
      print "Tentative edge found from (%s, %s) to %s" % (switch_id, port_id, arp.src_mac)
      # This switch / ports probe has not been seen
      # We will tentatively assume it is connected to the src host
      self.state.tentative_edge[ProbeData(switch_id, port_id)] = arp.src_mac
      self.state.add_edge(switch_id, arp.src_mac, label=port_id)
      self.state.add_edge(arp.src_mac, switch_id)
      self.state.notify()

  def packet_in(self, switch_id, port_id, payload):
    pkt = packet.Packet(array.array('b', payload.data))
    p = get(pkt, 'ethernet')

    if (p.ethertype == ProbeData.PROBOCOL):
      probe_data = get(pkt, 'ProbeData')
      self.handle_probe(switch_id, port_id, probe_data.src_switch, probe_data.src_port)

    if (p.ethertype == 0x806):
      arp = get(pkt, 'arp')
      self.handle_arp(switch_id, port_id, arp)