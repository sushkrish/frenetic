package spn.netkat;

import java.util.List;
import java.util.ArrayList;

public class Or implements Predicate {
    private List<Policy> pols = new ArrayList<Policy>();

    public Or(Policy... pols) { 
        for (int i=0; i < pols.length; i++) { 
	    this.pols.add(pols[i]);
	}
    }

    public String toString() {
        String result = "{ \"type\" : \"or\", \"preds\" : [ ";
	for (int i = 0; i < pols.size(); i++) { 
	    if (i != 0) { 
		result += ", ";
	    }
	    result += pols.get(i).toString();
	}
	result += "] }";
	return result;
    }
}
