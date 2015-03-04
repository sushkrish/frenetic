package spn.netkat;

public class Filter implements Policy {
    private Predicate pred;

    public Filter(Predicate pred) {
        this.pred = pred;
    }

    public String toString() {
        return " { \"type\" : \"filter\", \"pred\" : " + pred + " }";
    }
}
