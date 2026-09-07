// SPDX-License-Identifier: MIT
package conn

import (
	"errors"
	"fmt"
	"golang.org/x/net/ipv6"
	"net"
	"os"
	"testing"
)

// Run in an isolated namespace: dummy route MTU 1500, TX checksum off.
// Disabling checksum offload forces Linux UDP_SEGMENT to return EIO.
func TestMessagePoolRealGSORetry(t *testing.T) {
	endpoint := os.Getenv("HYPERWG_GSO_TEST_ENDPOINT")
	if endpoint == "" {
		t.Skip("requires isolated low-MTU route")
	}
	s := NewStdNetBind().(*StdNetBind)
	_, _, err := s.Open(0)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	ep, err := s.ParseEndpoint(endpoint)
	if err != nil {
		t.Fatal(err)
	}
	packets := [][]byte{make([]byte, 1400, 65535), make([]byte, 1400, 65535)}
	err = s.Send(packets, ep)
	var disabled ErrUDPGSODisabled
	if !errors.As(err, &disabled) || disabled.RetryErr != nil || s.ipv4TxOffload {
		t.Fatalf("fallback failed: %v", err)
	}
	if err = s.Send([][]byte{make([]byte, 100)}, ep); err != nil {
		t.Fatalf("pool reuse after retry failed: %v", err)
	}
}

func TestMessagePoolReset(t *testing.T) {
	s := NewStdNetBind().(*StdNetBind)
	for _, n := range []int{128, 1, 8, 128, 1} {
		msgs := s.getMessages()
		for i := 0; i < n; i++ {
			m := &(*msgs)[i]
			m.Addr = &net.UDPAddr{Port: i}
			m.Buffers[0] = make([]byte, 40)
			m.N = 40
			m.NN = 8
			m.Flags = 7
			m.OOB = append(m.OOB, 1, 2, 3, 4)
		}
		resetMessages((*msgs)[:n])
		for i, m := range *msgs {
			if m.Addr != nil || m.N != 0 || m.NN != 0 || m.Flags != 0 || len(m.OOB) != 0 || m.Buffers[0] != nil {
				t.Fatalf("retained address/buffer/control at %d", i)
			}
		}
		s.putMessages(msgs, n)
	}
}

func TestMessagePoolGSOFallbackReset(t *testing.T) {
	s := NewStdNetBind().(*StdNetBind)
	msgs := s.getMessages()
	addr := &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 1}
	ep := &StdNetEndpoint{AddrPort: addr.AddrPort()}
	bufs := [][]byte{make([]byte, 100, 200), make([]byte, 100)}
	n := coalesceMessages(addr, ep, bufs, *msgs, func(oob *[]byte, _ uint16) { *oob = append(*oob, 9) })
	if n != 1 || len((*msgs)[0].OOB) == 0 {
		t.Fatal("GSO not coalesced")
	}
	resetMessages((*msgs)[:n])
	for i, b := range bufs {
		(*msgs)[i].Buffers[0] = b
		(*msgs)[i].Addr = addr
		if len((*msgs)[i].OOB) != 0 {
			t.Fatal("stale GSO control in retry")
		}
	}
	s.putMessages(msgs, len(bufs))
}

func BenchmarkMessagePoolClear(b *testing.B) {
	for _, n := range []int{1, 8, 128} {
		for _, old := range []bool{true, false} {
			b.Run(fmt.Sprintf("slots%d/old%v", n, old), func(b *testing.B) {
				s := NewStdNetBind().(*StdNetBind)
				msgs := s.getMessages()
				packet := make([]byte, 1400)
				b.ReportAllocs()
				b.ResetTimer()
				for k := 0; k < b.N; k++ {
					for i := 0; i < n; i++ {
						(*msgs)[i].Buffers[0] = packet
					}
					if old {
						for i := range *msgs {
							m := &(*msgs)[i]
							*m = ipv6.Message{Buffers: m.Buffers, OOB: m.OOB[:0]}
						}
					} else {
						resetMessages((*msgs)[:n])
					}
				}
			})
		}
	}
}
