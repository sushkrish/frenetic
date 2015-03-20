import matplotlib.pyplot as plt
import pickle
import networkx as nx

def plot():
    conns = pickle.load(open('conns.txt'))
    pos = nx.circular_layout(conns)
    nx.draw_networkx_edge_labels(conns, pos)
    nx.draw_networkx_labels(conns, pos)
    nx.draw(conns,pos)
    plt.show()

if __name__ == '__main__':
	plot()
