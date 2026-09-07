"""Add a validated, immutable TrafficMorpher field to AWG's Java config."""
from pathlib import Path
import sys

root = Path(sys.argv[1])
path = root / 'tunnel/src/main/java/org/amnezia/awg/config/Interface.java'
source = path.read_text(encoding='utf-8')

def replace(old, new):
    global source
    if source.count(old) != 1:
        raise RuntimeError(f'Interface.java: patch anchor mismatch: {old}')
    source = source.replace(old, new)

replace('    private final Optional<String> contentPaddingAddition;',
        '    private final Optional<String> trafficMorpher;\n    private final Optional<String> contentPaddingAddition;')
replace('        contentPaddingAddition = builder.contentPaddingAddition;',
        '        trafficMorpher = builder.trafficMorpher;\n        contentPaddingAddition = builder.contentPaddingAddition;')
replace('                case "contentpaddingaddition":', '''                case "trafficmorpher":
                    builder.setTrafficMorpher(attribute.getValue());
                    break;
                case "contentpaddingaddition":''')
replace('                && contentPaddingAddition.equals(other.contentPaddingAddition)',
        '                && trafficMorpher.equals(other.trafficMorpher)\n                && contentPaddingAddition.equals(other.contentPaddingAddition)')
replace('        hash = 31 * hash + contentPaddingAddition.hashCode();',
        '        hash = 31 * hash + trafficMorpher.hashCode();\n        hash = 31 * hash + contentPaddingAddition.hashCode();')
replace('        contentPaddingAddition.ifPresent(cpa -> sb.append("ContentPaddingAddition = ").append(cpa).append(\'\\n\'));',
        '        trafficMorpher.ifPresent(p -> sb.append("TrafficMorpher = ").append(p).append(\'\\n\'));\n        contentPaddingAddition.ifPresent(cpa -> sb.append("ContentPaddingAddition = ").append(cpa).append(\'\\n\'));')
replace('        contentPaddingAddition.ifPresent(cpa -> sb.append("content_padding_addition=").append(cpa).append(\'\\n\'));',
        '        trafficMorpher.ifPresent(p -> sb.append("traffic_morpher=").append(p).append(\'\\n\'));\n        contentPaddingAddition.ifPresent(cpa -> sb.append("content_padding_addition=").append(cpa).append(\'\\n\'));')
replace('        private Optional<String> contentPaddingAddition = Optional.empty();',
        '        private Optional<String> trafficMorpher = Optional.empty();\n        private Optional<String> contentPaddingAddition = Optional.empty();')
replace('        public Builder parseContentPaddingAddition(final String contentPaddingAddition) throws BadConfigException {', '''        public Builder setTrafficMorpher(final String profile) throws BadConfigException {
            if (!java.util.Arrays.asList("off", "interactive", "web", "streaming", "mixed").contains(profile)) {
                throw new BadConfigException(Section.INTERFACE, Location.TOP_LEVEL, Reason.INVALID_VALUE, profile);
            }
            trafficMorpher = Optional.of(profile);
            return this;
        }

        public Builder parseContentPaddingAddition(final String contentPaddingAddition) throws BadConfigException {''')
path.write_text(source, encoding='utf-8', newline='\n')

# Report the fork version and preserve single-owner cleanup when configuration
# validation fails. Device.Close owns the TUN fd and all worker goroutines.
path = root / 'tunnel/tools/libwg-go/api-android.go'
source = path.read_text(encoding='utf-8')
replace('\t"runtime/debug"\n', '')
replace('\t"strings"\n', '')
start = source.index('func awgVersion() *C.char {')
end = source.index('\nfunc main() {}', start)
source = source[:start] + 'func awgVersion() *C.char {\n\treturn C.CString(device.HyperWGVersion)\n}\n' + source[end:]
replace('\t\tunix.Close(int(tunFd))\n\t\tlogger.Errorf("IpcSet: %v", err)',
        '\t\tdevice.Close()\n\t\tlogger.Errorf("IpcSet: %v", err)')
source = source.replace('\t\tuapiFile.Close()\n\t\tdevice.Close()',
                        '\t\tif uapi != nil { uapi.Close() }\n\t\tif uapiFile != nil { uapiFile.Close() }\n\t\tdevice.Close()')
path.write_text(source, encoding='utf-8', newline='\n')
