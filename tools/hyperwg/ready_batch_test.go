// SPDX-License-Identifier: MIT
package device

import (
	"testing"
	"time"
)

func batchContainer(n int) *QueueOutboundElementsContainer {
	c := &QueueOutboundElementsContainer{}
	for i := 0; i < n; i++ {
		c.elems = append(c.elems, &QueueOutboundElement{})
	}
	return c
}

func TestReadyBatchFIFOAndReadiness(t *testing.T) {
	q := make(chan *QueueOutboundElementsContainer, 4)
	a, b, c := batchContainer(1), batchContainer(1), batchContainer(1)
	a.Lock()
	b.Lock()
	q <- b
	q <- c
	state := readyBatch{}
	out := state.collect(q, append(make([]*QueueOutboundElementsContainer, 0, 128), a), 128, true)
	if len(out) != 1 || state.pending != b || len(q) != 1 {
		t.Fatal("waited for encryption or overtook pending packet")
	}
	b.Unlock()
	if state.first(q) != b {
		t.Fatal("lost FIFO")
	}
	b.Lock()
	out = state.collect(q, append(out[:0], b), 128, true)
	if len(out) != 2 || out[1] != c {
		t.Fatal("did not batch ready container")
	}
}

func TestReadyBatchLimitsAndClose(t *testing.T) {
	for _, mode := range []string{"capacity", "keepalive", "off", "closed"} {
		t.Run(mode, func(t *testing.T) {
			q := make(chan *QueueOutboundElementsContainer, 2)
			a, b := batchContainer(8), batchContainer(2)
			a.Lock()
			limit := 128
			if mode == "capacity" {
				limit = 9
			}
			if mode == "keepalive" {
				b.elems[0].isKeepalive = true
			}
			q <- b
			close(q)
			state := readyBatch{}
			out := state.collect(q, append(make([]*QueueOutboundElementsContainer, 0, 128), a), limit, mode != "off")
			if mode == "closed" {
				if len(out) != 2 || !state.ended || state.first(q) != nil {
					t.Fatal("close dropped batch")
				}
				return
			}
			if len(out) != 1 || state.first(q) != b {
				t.Fatal("boundary or FIFO violated")
			}
		})
	}
}

func TestReadyBatchNoAccumulationDelay(t *testing.T) {
	q := make(chan *QueueOutboundElementsContainer)
	a := batchContainer(1)
	a.Lock()
	done := make(chan struct{})
	go func() {
		state := readyBatch{}
		state.collect(q, []*QueueOutboundElementsContainer{a}, 128, true)
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("empty queue blocks send")
	}
}
