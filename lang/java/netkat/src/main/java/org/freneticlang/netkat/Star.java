package spn.netkat;

public class Star implements Policy {
    private Policy pol;

    public Star(Policy pol) {
        this.pol = pol;
    }

    public String toString() {
        return "{ \"type\" : \"star\", \"pol\" : " + pol + " }";
    }
}
