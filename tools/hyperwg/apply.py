"""Apply the small HyperWG overlay to the pinned AWG 3.1 source tree."""
from pathlib import Path
import shutil
import sys

root = Path(sys.argv[1])
overlay = Path(__file__).resolve().parent

def replace(name, old, new):
    path = root / name
    text = path.read_text(encoding='utf-8')
    if text.count(old) != 1:
        raise RuntimeError(f'{name}: expected exactly one patch anchor')
    path.write_text(text.replace(old, new), encoding='utf-8', newline='\n')

replace('version.go', 'const Version = "0.0.20250522"', 'const Version = "3.1-hyperwg-morph1-perf3"')

for source in overlay.glob('*.go'):
    if not source.name.endswith('_test.go'):
        shutil.copyfile(source, root / 'device' / source.name)
for test in overlay.glob('*_test.go'):
    shutil.copyfile(test, root / ('conn' if test.name.startswith('conn_') else 'device') / test.name)
replace('device/device.go', '\tcontentPaddingAddition AtomicUintRange',
        '\ttrafficMorpher atomic.Uint32\n\tcontentPaddingAddition AtomicUintRange')
replace('device/peer.go', '\tisRunning         atomic.Bool',
        '\ttrafficMorpher TrafficMorpher\n\tmorphStop chan struct{}\n\tisRunning         atomic.Bool')
replace('device/peer.go', '\tpeer.stopping.Add(2)',
        '\tpeer.stopping.Add(2)\n\tpeer.morphStop = make(chan struct{})')
replace('device/peer.go', '\tpeer.timersStop()', '\tclose(peer.morphStop)\n\tpeer.timersStop()')
replace('device/send.go', '\tisKeepalive bool\n', '\tisKeepalive bool\n\tmorphPadding int\n')
replace('device/send.go', '\t\tcount, readErr = device.tun.device.Read(bufs, sizes, offset)', '''
        count, readErr = device.tun.device.Read(bufs, sizes, offset)
        // S4 can change while TUN.Read is blocked (including initial IpcSet).
        // Relocate the freshly read plaintext before assigning the wire padding.
        if currentPadding := device.paddings.transport.Load(); currentPadding != padding {
            newOffset := MessageTransportHeaderSize + int(currentPadding)
            for i := 0; i < count; i++ {
                if sizes[i] < 0 || newOffset + sizes[i] + MinMessageSize > len(bufs[i]) {
                    sizes[i] = 0
                    continue
                }
                copy(bufs[i][newOffset:newOffset+sizes[i]], bufs[i][offset:offset+sizes[i]])
            }
            padding, offset = currentPadding, newOffset
        }''')
replace('device/send.go', '\t\t\t\telem.keypair = keypair', '''
                packetSize := len(elem.packet) + MinMessageSize + int(elem.padding)
                ceiling := min(int(peer.udpWindow.Load()), int(peer.device.tun.mtu.Load()) + MinMessageSize + int(elem.padding), 1452, MaxMessageSize)
                elem.morphPadding = peer.trafficMorpher.padding(morphProfile(peer.device.trafficMorpher.Load()), len(elem.packet), packetSize, ceiling, time.Now())
                elem.keypair = keypair''')
replace('device/send.go', '\t\t\tpaddingSize := elem.peer.randomPaddingAddition(packetSize)', '''
            paddingSize := elem.morphPadding
            if paddingSize < 0 { paddingSize = elem.peer.randomPaddingAddition(packetSize) }''')
replace('device/send.go', '\tbufs := make([][]byte, 0, maxBatchSize)', '''
    bufs := make([][]byte, 0, maxBatchSize)
    burst := new(morphBurst)
    morphTimer := time.NewTimer(time.Hour)
    morphTimer.Stop()
    defer morphTimer.Stop()''')
replace('device/send.go', '\t\terr := peer.SendBuffers(bufs)', '''
        var err error
        if dataSent {
            err = peer.sendMorphedBuffers(bufs, burst, morphTimer)
        } else {
            err = peer.SendBuffers(bufs)
        }''')
replace('device/uapi.go', '\t\tif addition := device.contentPaddingAddition.Load(); !addition.IsZero() {', '''
        sendf("traffic_morpher=%s", morphProfile(device.trafficMorpher.Load()).String())
        if addition := device.contentPaddingAddition.Load(); !addition.IsZero() {''')
replace('device/uapi.go', '\tcase "content_padding_addition":', '''
    case "traffic_morpher":
        profile, err := parseMorphProfile(value)
        if err != nil { return ipcErrorf(ipc.IpcErrorInvalid, "%w", err) }
        ipcDev.trafficMorpher = uint32(profile)
    case "content_padding_addition":''')
replace('device/uapi.go', 'type ipcSetDevice struct {', 'type ipcSetDevice struct {\n\ttrafficMorpher uint32')
replace('device/uapi.go', 'func (d *ipcSetDevice) fromDevice(device *Device) {',
        'func (d *ipcSetDevice) fromDevice(device *Device) {\n\td.trafficMorpher = device.trafficMorpher.Load()')
replace('device/uapi.go', '\tdevice.paddings.transport.Store(d.paddings.transport)',
        '\tdevice.paddings.transport.Store(d.paddings.transport)\n\tdevice.trafficMorpher.Store(d.trafficMorpher)')
replace('main.go', '\tdevice := device.NewDevice(tdev, conn.NewDefaultBind(), logger)', '''
    device := device.NewDevice(tdev, conn.NewDefaultBind(), logger)
    if profile := os.Getenv("HYPERWG_TRAFFIC_MORPHER"); profile != "" {
        if err := device.IpcSet("traffic_morpher=" + profile + "\\n"); err != nil {
            logger.Errorf("TrafficMorpher configuration failed: %v", err)
            device.Close()
            os.Exit(ExitSetupFailed)
        }
        logger.Verbosef("HyperWG TrafficMorpher v1: %s", profile)
    }''')

# Aggregate already encrypted containers without adding a timer or reordering.
replace('device/send.go', '\tfor elemsContainer := range peer.queue.outbound.c {', '\n    ready := readyBatch{}\n    containers := make([]*QueueOutboundElementsContainer, 0, maxBatchSize)\n    for {\n        elemsContainer := ready.first(peer.queue.outbound.c)')
replace('device/send.go', '\t\tdataSent := false\n\t\telemsContainer.Lock()\n\t\tfor _, elem := range elemsContainer.elems {', '\n        dataSent := false\n        elemsContainer.Lock()\n        containers = append(containers[:0], elemsContainer)\n        containers = ready.collect(peer.queue.outbound.c, containers, maxBatchSize, morphProfile(device.trafficMorpher.Load()) != morphOff)\n        for _, container := range containers {\n        for _, elem := range container.elems {')
replace('device/send.go', '\t\t\tbufs = append(bufs, elem.packet)\n\t\t}', '\t\t\tbufs = append(bufs, elem.packet)\n\t\t}\n        }')
replace('device/send.go', '\t\tfor _, elem := range elemsContainer.elems {\n\t\t\tdevice.PutMessageBuffer(elem.buffer)\n\t\t\tdevice.PutOutboundElement(elem)\n\t\t}\n\t\tdevice.PutOutboundElementsContainer(elemsContainer)', '\n        for i, container := range containers {\n            for _, elem := range container.elems {\n                device.PutMessageBuffer(elem.buffer)\n                device.PutOutboundElement(elem)\n            }\n            device.PutOutboundElementsContainer(container)\n            containers[i] = nil\n        }\n        clear(bufs)')

replace('conn/bind_std.go', 'func (s *StdNetBind) putMessages(msgs *[]ipv6.Message) {\n\tfor i := range *msgs {\n\t\t(*msgs)[i].OOB = (*msgs)[i].OOB[:0]\n\t\t(*msgs)[i] = ipv6.Message{Buffers: (*msgs)[i].Buffers, OOB: (*msgs)[i].OOB}\n\t}\n\ts.msgsPool.Put(msgs)\n}', 'func resetMessages(msgs []ipv6.Message) {\n    for i := range msgs {\n        m := &msgs[i]\n        clear(m.Buffers)\n        *m = ipv6.Message{Buffers: m.Buffers, OOB: m.OOB[:0]}\n    }\n}\n\nfunc (s *StdNetBind) putMessages(msgs *[]ipv6.Message, used int) {\n    resetMessages((*msgs)[:used])\n    s.msgsPool.Put(msgs)\n}')
# GRO can touch the tail AND split to the front, including on failure.
replace('conn/bind_std.go', '\tdefer s.putMessages(msgs)\n\tvar numMsgs int', '\tdefer s.putMessages(msgs, len(*msgs))\n\tvar numMsgs int')
replace('conn/bind_std.go', '\tdefer s.putMessages(msgs)\n\tua :=', '\tused := 0\n\tdefer func() { s.putMessages(msgs, used) }()\n\tua :=')
replace('conn/bind_std.go', '\t\tn := coalesceMessages(ua, endpoint.(*StdNetEndpoint), bufs, *msgs, setGSOSize)', '\t\tn := coalesceMessages(ua, endpoint.(*StdNetEndpoint), bufs, *msgs, setGSOSize)\n        used = n')
replace('conn/bind_std.go', '\t\t\tretried = true\n\t\t\tgoto retry', '\t\t\tretried = true\n            resetMessages((*msgs)[:used])\n            used = 0\n\t\t\tgoto retry')
replace('conn/bind_std.go', '\t\terr = s.send(conn, br, (*msgs)[:len(bufs)])', '\t\tused = len(bufs)\n\t\terr = s.send(conn, br, (*msgs)[:len(bufs)])')

# Only the public transport prefix uses this reservoir. Handshake randomness,
# private keys, nonce counters and the authenticated encryption path are unchanged.
replace('device/send.go', '\tvar nonce [chacha20poly1305.NonceSize]byte', '\tvar nonce [chacha20poly1305.NonceSize]byte\n    var prefixRandom transportRandom\n    defer clear(prefixRandom.bytes[:])')
replace('device/send.go', '\t\t\tcrypt := elem.buffer[:elem.padding]\n\t\t\trand.Read(crypt)', '\t\t\tcrypt := elem.buffer[:elem.padding]\n            prefixRandom.fill(crypt)')

# Upstream test diagnostic passed an atomic lock wrapper to printf; read its value.
replace('device/pools_test.go', 'maximum count (%d)", max, p.max)', 'maximum count (%d)", max.Load(), p.max)')
