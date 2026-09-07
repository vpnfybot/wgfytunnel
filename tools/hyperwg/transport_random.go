// SPDX-License-Identifier: MIT
package device

import "crypto/rand"

// A private reservoir per encryption worker amortizes OS CSPRNG calls for the
// public random transport prefix. Never used for session keys or AEAD counters.
// There is no seeded/predictable PRNG, sharing, rewind or reuse of consumed bytes.
type transportRandom struct {
	bytes     [2048]byte
	remaining int
}

func (r *transportRandom) fill(dst []byte) {
	if len(dst) == 0 {
		return
	}
	// Large prefixes do not benefit from buffering; avoid an extra copy.
	if len(dst) >= 256 {
		rand.Read(dst) // Go 1.25 crypto/rand terminates on entropy-source failure.
		return
	}
	if len(dst) > r.remaining {
		rand.Read(r.bytes[:])
		r.remaining = len(r.bytes)
	}
	start := len(r.bytes) - r.remaining
	copy(dst, r.bytes[start:start+len(dst)])
	clear(r.bytes[start : start+len(dst)])
	// Clear consumed public randomness instead of retaining copies in the worker.
	r.remaining -= len(dst)
}
