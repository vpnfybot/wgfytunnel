// SPDX-License-Identifier: MIT
package device

import (
	"bytes"
	"encoding/binary"
	"strings"
	"testing"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/tun/tuntest"
)

func TestMorphPaddingBoundsAndBudget(t *testing.T) {
	for _, profile := range []morphProfile{morphInteractive, morphWeb, morphStreaming, morphMixed} {
		var m TrafficMorpher
		payloadBytes, extraBytes := 0, 0
		for i := 0; i < 10000; i++ {
			payload := i % 1377
			packet := payload + 48
			ceiling := 1424
			if i%7 == 0 { ceiling = 500 } // conservative initial/roamed UDP window
			extra := m.padding(profile, payload, packet, ceiling, time.Now())
			if extra < 0 || (extra > 0 && packet+extra > ceiling) || extra > 384 {
				t.Fatalf("profile %v packet %d ceiling %d extra %d", profile, packet, ceiling, extra)
			}
			payloadBytes += payload
			extraBytes += extra
			if extraBytes > payloadBytes/5 { t.Fatal("padding exceeded 20% budget") }
		}
		if extraBytes == 0 { t.Fatalf("profile %v never padded", profile) }
		if m.padding(profile, 0, 48, 1424, time.Now().Add(3*time.Second)) != 0 {
			t.Fatal("idle peer produced padding without a payload budget")
		}
	}
	var m TrafficMorpher
	if m.padding(morphOff, 40, 88, 1424, time.Now()) != -1 { t.Fatal("off must use legacy policy") }
}

func TestMorphMixedActivityAndPeerIsolation(t *testing.T) {
	var busy, idle TrafficMorpher
	now := time.Now()
	for window := 0; window < 6; window++ {
		for packet := 0; packet < 100; packet++ {
			busy.padding(morphMixed, 1300, 1348, 1424, now.Add(time.Duration(window)*250*time.Millisecond))
		}
	}
	if morphProfile(busy.active.Load()) != morphStreaming { t.Fatal("sustained traffic did not select streaming") }
	idle.padding(morphMixed, 40, 88, 1424, now)
	if morphProfile(idle.active.Load()) != morphInteractive { t.Fatal("another peer changed idle profile") }
	busy.padding(morphMixed, 40, 88, 1424, now.Add(5*time.Second))
	if morphProfile(busy.active.Load()) != morphInteractive { t.Fatal("idle did not reset mixed profile") }
}

func TestMorphBurstBounds(t *testing.T) {
	for _, profile := range []morphProfile{morphOff, morphInteractive, morphWeb, morphStreaming} {
		var b morphBurst
		now := time.Now()
		if b.next(profile, 1400, now) != 0 { t.Fatal("first packet delayed") }
		pauses := 0
		for i := 0; i < 1000; i++ {
			d := b.next(profile, 1400, now)
			if d < 0 || d >= 2*time.Millisecond { t.Fatal("unbounded delay") }
			if d > 0 { pauses++ }
			now = now.Add(d+10*time.Microsecond)
		}
		if (profile == morphWeb || profile == morphStreaming) && pauses == 0 { t.Fatal("no burst gaps") }
		if (profile == morphOff || profile == morphInteractive) && pauses != 0 { t.Fatal("interactive delay") }
		if b.next(profile, 1400, now.Add(time.Second)) != 0 { t.Fatal("post-idle packet delayed") }
	}
}

func TestMorphLegacyInteropAndProfileSwitch(t *testing.T) {
	// Receiver uses the unchanged AWG decoding path, including content trimming.
	pair := genTestPair(t, true, "s1", "16", "s2", "16", "s3", "16", "s4", "16",
		"header_protection_key", strings.Repeat("ab", 32))
	for _, profile := range []string{"interactive", "web", "streaming", "mixed", "off"} {
		if err := pair[0].dev.IpcSet("traffic_morpher="+profile+"\n"); err != nil { t.Fatal(err) }
		pair.Send(t, Ping, nil)
		pair.Send(t, Pong, nil)
		for _, size := range []int{64, 256, 768, 1280, 1376} {
			msg := tuntest.Ping(pair[1].ip, pair[0].ip)
			msg = append(msg, bytes.Repeat([]byte{0xa5}, size-len(msg))...)
			binary.BigEndian.PutUint16(msg[2:4], uint16(len(msg)))
			pair[0].tun.Outbound <- msg
			select {
			case received := <-pair[1].tun.Inbound:
				if !bytes.Equal(msg, received) { t.Fatal("payload corrupted by padding") }
			case <-time.After(3*time.Second): t.Fatal("packet did not arrive")
			}
		}
		// Peer updates from awg syncconf must not reset the selected profile.
		if err := pair[0].dev.IpcSet("s4=16\n"); err != nil { t.Fatal(err) }
		if morphProfile(pair[0].dev.trafficMorpher.Load()).String() != profile { t.Fatal("lost profile") }
	}
	before := pair[0].dev.trafficMorpher.Load()
	if err := pair[0].dev.IpcSet("traffic_morpher=unknown\n"); err == nil { t.Fatal("accepted invalid profile") }
	if pair[0].dev.trafficMorpher.Load() != before { t.Fatal("invalid update changed profile") }
}
