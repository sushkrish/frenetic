package spn.netkat;

public class Not implements Predicate {
    private Predicate pred;

    public Not(Predicate pred) {
        this.pred = pred;
    }

    public String toString() {
        return " { \"type\" : \"neg\", \"pred\" : " + pred + " }";
    }
}
