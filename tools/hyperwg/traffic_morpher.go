// SPDX-License-Identifier: MIT
// HyperWG TrafficMorpher v1. Padding remains inside the AWG authenticated payload.
package device

import (
	"errors"
	"fmt"
	"sync"
	"sync/atomic"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
)

type morphProfile uint32

const HyperWGVersion = "3.1-hyperwg-morph1-perf3"

const (
	morphOff morphProfile = iota
	morphInteractive
	morphWeb
	morphStreaming
	morphMixed
)

func parseMorphProfile(value string) (morphProfile, error) {
	switch value {
	case "off":
		return morphOff, nil
	case "interactive":
		return morphInteractive, nil
	case "web":
		return morphWeb, nil
	case "streaming":
		return morphStreaming, nil
	case "mixed":
		return morphMixed, nil
	default:
		return morphOff, fmt.Errorf("unknown traffic_morpher profile %q", value)
	}
}

func (p morphProfile) String() string {
	return [...]string{"off", "interactive", "web", "streaming", "mixed"}[p]
}

// Each cryptographic peer owns its own activity, padding budget and scheduler.
// There is no shared endpoint/session identity and no new unauthenticated frame.
type TrafficMorpher struct {
	sync.Mutex
	active atomic.Uint32
	configured morphProfile
	windowStart time.Time
	windowBytes int
	busyWindows int
	credit int
	paddingBytes atomic.Uint64
	dataPackets atomic.Uint64
	bursts atomic.Uint64
}

func (m *TrafficMorpher) padding(profile morphProfile, payload, packet, ceiling int, now time.Time) int {
	if profile == morphOff {
		return -1 // preserve the original AWG padding policy exactly
	}
	m.Lock()
	defer m.Unlock()
	if m.configured != profile || m.windowStart.IsZero() || now.Sub(m.windowStart) > 2*time.Second {
		m.configured, m.windowStart = profile, now
		m.windowBytes, m.busyWindows, m.credit = 0, 0, 0
		m.active.Store(uint32(morphInteractive))
	}
	if now.Sub(m.windowStart) >= 250*time.Millisecond {
		if m.windowBytes >= 64*1024 {
			m.busyWindows++
		} else {
			m.busyWindows = 0
		}
		m.windowStart, m.windowBytes = now, 0
	}
	m.windowBytes += payload
	selected := profile
	if profile == morphMixed {
		selected = morphInteractive
		if m.windowBytes >= 8*1024 {
			selected = morphWeb
		}
		if m.busyWindows >= 4 && m.windowBytes >= 8*1024 {
			selected = morphStreaming
		}
	}
	m.active.Store(uint32(selected))
	// Earn at most 20% additional bytes from real payload, including keepalives
	// in the same budget. No idle cover traffic and no initial padding allowance.
	m.credit = min(4096, m.credit + payload/5)
	space := min(ceiling-packet, m.credit)
	if space <= 0 {
		return 0
	}
	// Conditional, non-uniform size clusters, with a small per-packet variation.
	// These are bounded engineering profiles, not measured QUIC/video models.
	choice := fastrandn(100)
	var target int
	switch selected {
	case morphInteractive:
		target = 96 + int(fastrandn(48))
		if choice >= 70 { target = 256 + int(fastrandn(64)) }
		space = min(space, 64)
	case morphWeb:
		target = 384 + int(fastrandn(128))
		if choice >= 25 { target = 768 + int(fastrandn(128)) }
		if choice >= 60 { target = ceiling - int(fastrandn(96)) }
		space = min(space, 256)
	case morphStreaming:
		target = ceiling - int(fastrandn(48))
		if choice < 15 { target = 256 + int(fastrandn(96)) }
		space = min(space, 384)
	}
	addition := min(space, max(0, target-packet))
	m.credit -= addition
	m.paddingBytes.Add(uint64(addition))
	m.dataPackets.Add(1)
	return addition
}

// morphBurst is used only by the existing sequential sender. It never delays
// handshake/cookie messages, never creates another queue, and resets after idle.
type morphBurst struct {
	remaining int
	last time.Time
	profile morphProfile
}

func (b *morphBurst) next(profile morphProfile, size int, now time.Time) time.Duration {
	if profile == morphOff || profile == morphInteractive || size == 0 {
		b.remaining, b.last, b.profile = 0, now, profile
		return 0
	}
	if b.profile != profile || now.Sub(b.last) > 20*time.Millisecond || b.last.IsZero() {
		b.remaining = 0
		b.profile = profile
	}
	var delay time.Duration
	if b.remaining <= 0 {
		if !b.last.IsZero() && now.Sub(b.last) <= 20*time.Millisecond && b.profile == profile {
			if profile == morphWeb {
				delay = time.Duration(250+fastrandn(1000))*time.Microsecond
			} else {
				delay = time.Duration(500+fastrandn(1500))*time.Microsecond
			}
		}
		if profile == morphWeb {
			b.remaining = 32*1024 + int(fastrandn(64*1024))
		} else {
			b.remaining = 128*1024 + int(fastrandn(128*1024))
		}
	}
	b.remaining -= size
	b.last = now.Add(delay)
	return delay
}

func (peer *Peer) sendMorphedBuffers(bufs [][]byte, burst *morphBurst, timer *time.Timer) error {
	profile := morphProfile(peer.device.trafficMorpher.Load())
	if profile == morphOff {
		return peer.SendBuffers(bufs)
	}
	profile = morphProfile(peer.trafficMorpher.active.Load())
	start := 0
	for i, buf := range bufs {
		delay := burst.next(profile, len(buf), time.Now())
		if delay == 0 { continue }
		if i > start {
			if err := peer.sendMorphBatch(bufs[start:i]); err != nil { return err }
		}
		// No device/network/endpoint locks are held while waiting. Stop wakes this
		// timer before it waits for the sender to return pooled packet buffers.
		timer.Reset(delay)
		select {
		case <-timer.C:
		case <-peer.morphStop:
			timer.Stop()
			return nil
		}
		peer.trafficMorpher.bursts.Add(1)
		start = i
	}
	return peer.sendMorphBatch(bufs[start:])
}

func (peer *Peer) sendMorphBatch(bufs [][]byte) error {
	err := peer.SendBuffers(bufs)
	var gso conn.ErrUDPGSODisabled
	if errors.As(err, &gso) { return gso.RetryErr }
	return err
}
