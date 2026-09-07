// SPDX-License-Identifier: MIT
package device

import (
	"bytes"
	"crypto/rand"
	"fmt"
	"testing"
)

func TestTransportRandomConsumptionAndIsolation(t *testing.T) {
	var a, b transportRandom
	empty := []byte{}
	a.fill(empty)
	if a.remaining != 0 {
		t.Fatal("empty prefix fetched entropy")
	}
	first := make([]byte, 16)
	a.fill(first)
	if a.remaining != 2032 || b.remaining != 0 {
		t.Fatal("reservoir shared or wrong consumption")
	}
	expected := append([]byte{}, a.bytes[16:32]...)
	next := make([]byte, 16)
	a.fill(next)
	if !bytes.Equal(expected, next) || !bytes.Equal(a.bytes[:32], make([]byte, 32)) {
		t.Fatal("reused or retained consumed randomness")
	}
	seen := map[string]bool{string(first): true, string(next): true}
	for i := 0; i < 10000; i++ {
		a.fill(next)
		if seen[string(next)] {
			t.Fatal("repeated random prefix")
		}
		seen[string(next)] = true
	}
	b.fill(next)
	if seen[string(next)] {
		t.Fatal("workers share entropy")
	}
}

func TestTransportRandomSizesAndOversize(t *testing.T) {
	var r transportRandom
	for _, n := range []int{1, 12, 16, 31, 2047, 2048, 2049, 65500, 16} {
		data := make([]byte, n)
		r.fill(data)
		if bytes.Equal(data, make([]byte, n)) {
			t.Fatal("unfilled random prefix")
		}
		if r.remaining < 0 || r.remaining > len(r.bytes) {
			t.Fatal("invalid reservoir bounds")
		}
	}
}

func BenchmarkTransportRandom(b *testing.B) {
	for _, size := range []int{16, 64, 2048, 4096} {
		for _, buffered := range []bool{false, true} {
			b.Run(fmt.Sprintf("bytes%d/buffered%v", size, buffered), func(b *testing.B) {
				var r transportRandom
				dst := make([]byte, size)
				b.ReportAllocs()
				b.SetBytes(int64(size))
				b.ResetTimer()
				for i := 0; i < b.N; i++ {
					if buffered {
						r.fill(dst)
					} else {
						rand.Read(dst)
					}
				}
			})
		}
	}
}
