# A repeater that learns the switches and ports in a network then creates a
# policy that explicitly sends packets out of all ports, for each port.
import frenetic
from frenetic.syntax import *

class RepeaterApp(frenetic.App):
    client_id = "repeater"

    def __init__(self):
        print "----Welcome to Repeater----"
        frenetic.App.__init__(self)
        self.topo = {}

    def policy(self):
        return Union(self.sw_policy(sw) for sw in self.topo.keys())

    def sw_policy(self, sw):
        ports = self.topo[sw]
        p = Union(self.port_policy(in_port, ports) for in_port in ports)
        return Filter(Test(Switch(sw))) >> p

    def port_policy(self, in_port, ports):
        out_ports = [port for port in ports if port != in_port]
        p = Union(Mod(Location(Physical(p))) for p in out_ports)
        return Filter(Test(Location(Physical(in_port)))) >> p

    def switch_up(self,switch_id,ports):
        print "Repeater Switch Up: %s" % ports
        self.topo[switch_id] = ports
        self.update(self.policy())

    def switch_down(self,switch_id):
        del self.topo[switch_id]
        self.update(self.policy())

    def port_up(self,switch_id, port_id):
        self.topo[switch_id].append(port_id)
        app.update(self.policy())

    def port_down(self,switch_id, port_id):
        self.topo[switch_id].remove(port_id)
        app.update(self.policy())

    def packet_in(self,switch_id, port_id, payload):
        pass

if __name__ == '__main__':
    app = RepeaterApp()
    RepeaterApp.start_event_loop()