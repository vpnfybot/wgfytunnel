// SPDX-License-Identifier: MIT
package device

// Only the sequential sender owns this state. pending preserves FIFO when the
// next encryption worker is unfinished; TryLock never holds up the ready batch.
type readyBatch struct {
	pending *QueueOutboundElementsContainer
	ended   bool
}

func (b *readyBatch) first(queue <-chan *QueueOutboundElementsContainer) *QueueOutboundElementsContainer {
	if b.pending != nil {
		c := b.pending
		b.pending = nil
		return c
	}
	if b.ended {
		return nil
	}
	return <-queue
}

// first is locked by the caller. Capacity counts packets, not containers. A
// standalone keepalive remains standalone and off retains the upstream path.
func (b *readyBatch) collect(queue <-chan *QueueOutboundElementsContainer, out []*QueueOutboundElementsContainer, limit int, enabled bool) []*QueueOutboundElementsContainer {
	count := len(out[0].elems)
	if !enabled || containsKeepalive(out[0]) {
		return out
	}
	for count < limit && len(out) < cap(out) {
		var c *QueueOutboundElementsContainer
		select {
		case c = <-queue:
		default:
			return out
		}
		if c == nil {
			b.ended = true
			return out
		}
		if !c.TryLock() {
			b.pending = c
			return out
		}
		if len(c.elems)+count > limit || containsKeepalive(c) {
			c.Unlock()
			b.pending = c
			return out
		}
		count += len(c.elems)
		out = append(out, c)
	}
	return out
}

func containsKeepalive(c *QueueOutboundElementsContainer) bool {
	for _, e := range c.elems {
		if e.isKeepalive {
			return true
		}
	}
	return false
}
