package spn.netkat;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.apache.http.client.fluent.Request;
import org.apache.http.entity.ContentType;

import com.google.gson.JsonArray;
import com.google.gson.JsonParser;

public class WebKAT
{
    private static String serverUrl = new String("http://localhost:9000");
    
    public static void setServer(String url) {
        serverUrl = url;
    }
    
    public static void update_vno(Policy policy, int id) {
        try {
            String json = policy.toString();
            Request.Post(serverUrl + "/update_vno/" + id)
                .bodyString(json, ContentType.DEFAULT_TEXT)
                .execute().returnContent();
        } catch (Exception e) {
            System.out.println("Request failed: " + e.toString());
        }
    }

    public static void update(Policy policy) {
        try {
            String json = policy.toString();
            Request.Post(serverUrl + "/update/")
                .bodyString(json, ContentType.DEFAULT_TEXT)
                .execute().returnContent();
        } catch (Exception e) {
            System.out.println("Request failed: " + e.toString());
        }
    }

    public static JsonArray flowTable(long switchId) {
        try {
            String response = Request.Get(serverUrl + "/" + Long.toString(switchId) + "/flow_table")
                .execute().returnContent().asString();
            JsonParser parser = new JsonParser();
            return parser.parse(response).getAsJsonArray();
        } catch (Exception e) {
            System.out.println("Request failed: " + e.toString());
            return null;
        }
    }

    public static JsonArray flowTable_vno(long switchId) {
        try {
            String response = Request.Get(serverUrl + "/" + Long.toString(switchId) + "/vno_flow_table")
                .execute().returnContent().asString();
            JsonParser parser = new JsonParser();
            return parser.parse(response).getAsJsonArray();
        } catch (Exception e) {
            System.out.println("Request failed: " + e.toString());
            return null;
        }
    }
}
