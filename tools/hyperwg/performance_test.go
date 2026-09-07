// SPDX-License-Identifier: MIT
package device

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun/tuntest"
	"net/netip"
	"sort"
	"testing"
	"time"
)

// One server with independent cryptographic peers, including interleaved data,
// real UDP sockets, header protection, MTU-size packets and repeated handshake.
func TestPerformanceMultiplePeers(t *testing.T) {
	for _, n := range []int{1, 4, 10} {
		t.Run(fmt.Sprint(n), func(t *testing.T) {
			serverTun := tuntest.NewChannelTUN()
			server := NewDevice(serverTun.TUN(), conn.NewDefaultBind(), NewLogger(LogLevelError, "server: "))
			t.Cleanup(server.Close)
			var sk NoisePrivateKey
			rand.Read(sk[:])
			sp := sk.publicKey()
			common := []string{"traffic_morpher", "mixed", "s1", "16", "s2", "16", "s3", "16", "s4", "16", "header_protection_key", hex.EncodeToString(make([]byte, 31)) + "ab"}
			if err := server.IpcSet(uapiCfg(append(append([]string{}, common...), "private_key", hex.EncodeToString(sk[:]), "listen_port", "0")...)); err != nil {
				t.Fatal(err)
			}
			if err := server.Up(); err != nil {
				t.Fatal(err)
			}
			clients := make([]*tuntest.ChannelTUN, n)
			for i := 0; i < n; i++ {
				var k NoisePrivateKey
				rand.Read(k[:])
				pub := k.publicKey()
				clients[i] = tuntest.NewChannelTUN()
				d := NewDevice(clients[i].TUN(), conn.NewDefaultBind(), NewLogger(LogLevelError, "client: "))
				t.Cleanup(d.Close)
				cfg := append(append([]string{}, common...), "private_key", hex.EncodeToString(k[:]), "public_key", hex.EncodeToString(sp[:]), "allowed_ip", "10.90.0.1/32", "endpoint", fmt.Sprintf("127.0.0.1:%d", server.net.port))
				if err := d.IpcSet(uapiCfg(cfg...)); err != nil {
					t.Fatal(err)
				}
				if err := server.IpcSet(uapiCfg("public_key", hex.EncodeToString(pub[:]), "allowed_ip", fmt.Sprintf("10.90.0.%d/32", i+2))); err != nil {
					t.Fatal(err)
				}
				if err := d.Up(); err != nil {
					t.Fatal(err)
				}
			}
			receive := func(ch <-chan []byte, want []byte) {
				t.Helper()
				select {
				case got := <-ch:
					if !bytes.Equal(got, want) {
						t.Fatal("payload or order mismatch")
					}
				case <-time.After(5 * time.Second):
					t.Fatal("packet lost")
				}
			}
			var times []int64
			for round := 0; round < 12; round++ {
				for i, c := range clients {
					src := netip.AddrFrom4([4]byte{10, 90, 0, byte(i + 2)})
					dst := netip.MustParseAddr("10.90.0.1")
					payload := make([]byte, []int{0, 64, 1252}[round%3])
					rand.Read(payload)
					up := tuntest.Ping(dst, src)
					down := tuntest.Ping(src, dst)
					// Append opaque data and update the IPv4 total length (IP checksum is not
					// evaluated by these userspace channel TUNs).
					up = append(up, payload...)
					down = append(down, payload...)
					up[2], up[3] = byte(len(up)>>8), byte(len(up))
					down[2], down[3] = byte(len(down)>>8), byte(len(down))
					start := time.Now()
					c.Outbound <- up
					receive(serverTun.Inbound, up)
					serverTun.Outbound <- down
					receive(c.Inbound, down)
					if round > 0 {
						times = append(times, time.Since(start).Microseconds())
					}
				}
			}
			sort.Slice(times, func(i, j int) bool { return times[i] < times[j] })
			t.Logf("peers=%d exchanges=%d p95=%dus p99=%dus payload_loss=0", n, n*12, times[(len(times)-1)*95/100], times[(len(times)-1)*99/100])
		})
	}
}

func BenchmarkPerformanceTunnel(b *testing.B) {
	pair := genTestPair(b, true, "traffic_morpher", "streaming", "s1", "16", "s2", "16", "s3", "16", "s4", "16")
	pair.Send(b, Ping, nil)
	packet := tuntest.Ping(pair[0].ip, pair[1].ip)
	packet = append(packet, make([]byte, 1252)...)
	packet[2], packet[3] = byte(len(packet)>>8), byte(len(packet))
	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := 0; i < b.N; i++ {
			pair[1].tun.Outbound <- packet
		}
	}()
	b.SetBytes(int64(len(packet)))
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		select {
		case got := <-pair[0].tun.Inbound:
			if !bytes.Equal(got, packet) {
				b.Fatal("corrupt payload")
			}
		case <-time.After(10 * time.Second):
			b.Fatal("loss")
		}
	}
	<-done
}
