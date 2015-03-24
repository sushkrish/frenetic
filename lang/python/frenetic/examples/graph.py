
import json
import networkx as nx
from networkx.readwrite import json_graph
#import http_server
import dill

def plot_conns():
	fd = open("conns.txt", "rb")
	conns = dill.load(fd)
	# write json formatted data
	d = json_graph.node_link_data(conns) # node-link format to serialize
	# write json
	json.dump(d, open("frenetic/examples/conns.json","wb"))
	print('Wrote node-link JSON data to conns.json')


def plot_sig():
	fd = open("sig.txt", "rb")
	sig = dill.load(fd)
	# write json formatted data
	d = json_graph.node_link_data(sig) # node-link format to serialize
	# write json
	json.dump(d, open("frenetic/examples/sig.json","wb"))
	print('Wrote node-link JSON data to sig.json')



if __name__ == '__main__':
	plot_conns()
	plot_sig()



