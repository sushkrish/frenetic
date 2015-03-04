package org.freneticlang.netkat;

import org.apache.http.client.fluent.*;
import org.freneticlang.netkat.*;
import org.apache.http.entity.*;
import org.json.*;

public class WebKAT
{
    public static void update_vno(Policy policy, int id) {
        try {
            /* TODO(jnf): Convert policies to JSON properly. */
            String json = "{ data : \"" + policy.toString() + "\", type : \"policy\"}";
            Request.Post("http://localhost:9000/update_vno/" + id)
                .bodyString(json, ContentType.DEFAULT_TEXT)
                .execute().returnContent();
        } catch (Exception e) {
            System.out.println("Request failed: " + e.toString());
        }
    }

    public static void update(Policy policy, int id) {
        try {
            /* TODO(jnf): Convert policies to JSON properly. */
            String json = "{ data : \"" + policy.toString() + "\", type : \"policy\"}";
            Request.Post("http://localhost:9000/update/")
                .bodyString(json, ContentType.DEFAULT_TEXT)
                .execute().returnContent();
        } catch (Exception e) {
            System.out.println("Request failed: " + e.toString());
        }
    }

    public static JSONArray flowTable(long switchId) {
        try {
            String s = Request.Get("http://localhost:9000/" + Long.toString(switchId) + "/flow_table")
                .execute().returnContent().asString();
            return new JSONArray(s);
        } catch (Exception e) {
            System.out.println("Request failed: " + e.toString());
            return null;
        }
    }

    public static JSONArray flowTable_vno(long switchId) {
        try {
            String s = Request.Get("http://localhost:9000/" + Long.toString(switchId) + "/vno_flow_table")
                .execute().returnContent().asString();
            return new JSONArray(s);
        } catch (Exception e) {
            System.out.println("Request failed: " + e.toString());
            return null;
        }
    }

    public static void main( String[] args )
    {
        /*
          filter(switch = 1 & port = 3 & ipSrc = 10.0.0.1); 1@2 => 2@1; port:=3 + 
          filter(switch = 2 & port = 3 & ipSrc = 10.0.0.2); 2@2 => 3@2; port:=1 ; 3@1 => 1@1; port :=3  + 
          ...

          filter (switch = 1);
          (filter (ipSrc = 10.0.0.1 & ipDst = 10.0.0.2); port:=2 + 
          filter (ipSrc = 10.0.0.1 & ipDst = 10.0.0.3); port:=1 +  
          filter (ipDst = 10.0.0.1); port := 3)
        */     
        Policy s1 = 
            new Sequence(new Filter(new Test("switch", "1")),
                         new Union(new Sequence(new Filter(new And(new Test("ipSrc", "10.0.0.1"),
                                                                   new Test("ipDst", "10.0.0.2"))),
                                                new Modification("port", "2"))
                                   new Union(new Sequence(new Filter(new And(new Test("ipSrc", "10.0.0.1"),
                                                                             new Test("ipDst", "10.0.0.3"))),
                                                          new Modification("port", "1")),
                                             new Sequence(new Filter(new Test("ipDst", "10.0.0.1")),
                                                          new Modification("port", "3")))));
        Policy s2 = ...;
        Policy s3 = ...;
        Policy pol = new Union(s1, new Union(s2, s3));

        System.out.println(flowTable(1));
        System.out.println(flowTable(2));
        System.out.println(flowTable(3));
    }
}
