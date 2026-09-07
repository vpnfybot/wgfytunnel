import java.util.List;
import org.amnezia.awg.config.Interface;
import org.amnezia.awg.config.BadConfigException;

public final class InterfaceMorphTest {
    public static void main(String[] args) throws Exception {
        String key = "PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAE=";
        Interface legacy = Interface.parse(List.of(key));
        if (legacy.toAwgUserspaceString().contains("traffic_morpher=")) throw new AssertionError("legacy changed");
        for (String profile : List.of("off", "interactive", "web", "streaming", "mixed")) {
            Interface config = Interface.parse(List.of(key, "TrafficMorpher = " + profile));
            if (!config.toAwgUserspaceString().contains("traffic_morpher=" + profile + "\n")) throw new AssertionError("UAPI");
            if (!config.toAwgQuickString().contains("TrafficMorpher = " + profile + "\n")) throw new AssertionError("quick export");
            if (config.equals(legacy)) throw new AssertionError("equals ignored profile");
            if (!config.toAwgUserspaceString().equals(Interface.parse(List.of(key, "TrafficMorpher = " + profile)).toAwgUserspaceString())) throw new AssertionError("config roundtrip");
        }
        try {
            Interface.parse(List.of(key, "TrafficMorpher = unsupported"));
            throw new AssertionError("invalid profile accepted");
        } catch (BadConfigException expected) {}
        Interface.Builder builder = new Interface.Builder().parsePrivateKey(key.substring("PrivateKey = ".length()));
        Interface web = builder.setTrafficMorpher("web").build();
        if (!web.equals(builder.build())) throw new AssertionError("builder equality");
        if (web.equals(builder.setTrafficMorpher("mixed").build())) throw new AssertionError("profile equality");
        System.out.println("Interface TrafficMorpher: 5 profiles, legacy, validation and equality passed");
    }
}
