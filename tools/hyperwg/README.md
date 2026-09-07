# HyperWG TrafficMorpher v1

The server and wgfytunnel use the same overlay on **AmneziaWG Go 3.1**, commit
`b5928efb6ca19f0153958460c3d141f04abc5c2e` (tag `v3.1.20260828`). Android JNI/config
sources are pinned to `5c16489e2cd9ed3a0a7a27c7445bba5238132f86` (tag `v3.1.20260814`).
Upstream: https://github.com/amnezia-vpn/amneziawg-go

## Behavior and compatibility

- Profiles: `off`, `interactive`, `web`, `streaming`, `mixed`.
- Mixed uses each peer's **outgoing** traffic: small requests stay interactive,
  an active window switches to web, sustained transfers switch to streaming.
  Idle periods reset its state. Both directions adapt independently.
- Size shaping uses conditional size clusters and zero padding **inside AEAD**.
  Extra padding earns a 20% budget from actual payload, capped at 4096 bytes of
  accumulated credit per peer. Per-packet additions are capped at 64/256/384
  bytes for interactive/web/streaming. No traffic is generated while idle.
- Padding never expands a packet beyond the peer's observed UDP window, the
  configured tunnel MTU plus AWG overhead, 1452 bytes, or the message buffer.
  An already oversized packet is not padded. Configure MTU for the actual path;
  this layer does not implement PMTU discovery or fragmentation/reassembly.
- The existing ordered sender introduces gaps of 0.25–1.25 ms between web bursts
  of 32–96 KiB, or 0.5–2 ms between streaming bursts of 128–256 KiB. Handshakes,
  cookies and standalone keepalives bypass pacing. Actual timing depends on OS
  scheduling. Peer shutdown cancels waits, with no new worker/queue per packet.
- Cryptography, replay protection, receiver framing, endpoint roaming, allowed
  IPs and per-device keys remain AWG. Existing AWG clients decode padded packets.
  `off` uses upstream padding and send behavior.
- One logical HyperWG config still enrolls a distinct cryptographic peer per
  device. Device limits, eviction, quotas and traffic accounting stay in the
  existing control plane. Padding contributes to native wire byte counters.

These are bounded traffic shaping profiles, **not a measured video/QUIC model**.
No fake QUIC headers are added. Resistance to a specific DPI classifier must be
measured against that classifier and representative traffic; indistinguishability
has not been established. This version does not hide every handshake/timing clue.

## Configuration

The server executable reads `HYPERWG_TRAFFIC_MORPHER` at startup. Docker/Compose
default to `mixed`; unset standalone binaries retain `off`. Invalid profiles fail
startup. A container restart applies an environment change.

Core UAPI supports `traffic_morpher=off|interactive|web|streaming|mixed` and reports
the configured profile on `get`. Normal `awg syncconf` retains it. AWG tools do
not need a new config field, and generated legacy `.conf` files stay importable.

Enrollment advertises `tunnel.traffic_morpher`. Updated wgfytunnel validates this
field and inserts `TrafficMorpher = <profile>` into its temporary native config.
Its patched immutable Java Interface serializes it to UAPI. Older servers omit
the field; older clients ignore the extra JSON property. Standard WG/AWG imports
keep morphing off unless explicitly configured in the new native library.

## Build

The repository Dockerfile pins and checks the core commit, applies `apply.py`,
formats the edited files and runs the morphing tests before building the daemon.

For an Android library, clone the two pinned upstream trees, then run:

```text
python apply.py <amneziawg-go>
python android.py <amneziawg-android>
python build_android.py --go <go-executable> --ndk <ndk-root> --java <jdk-root> --sdk <android-sdk-root> --annotations <annotation-jvm.jar> --android <amneziawg-android> --core <amneziawg-go> --base-aar <amneziawg31.aar> --out <build-directory>
```

The build produces `hyperwg31.aar` and `build.json` with hashes, source commits,
toolchain and ABI list. It rebuilds **all four Go/JNI libraries** plus
Interface/Builder classes, preserving the base AAR's other Java classes,
wg/wg-quick native tools, resources and manifest. Base AAR provenance is recorded
by hash; those unchanged components are not rebuilt by this script.

The Android build retains WireGuard's CLOCK_BOOTTIME timer behavior through a Go
source overlay. It does not edit the shared installed Go toolchain. Invalid UAPI
configuration closes the Device that owns the TUN and workers.

Both repositories keep the identical overlay: server `protocol/hyperwg`, client
`tools/hyperwg`. Keep these files synchronized when updating the core. The app
depends on `android/app/libs/hyperwg31.aar`; its previous `amneziawg31.aar` remains
as the explicit base and rollback artifact. No APK is produced by these scripts.

## Verification

`traffic_morpher_test.go` exercises padding/MTU/credit bounds, per-peer isolation,
mixed transitions, burst timing limits, legacy receive compatibility, profile
changes and UAPI validation over actual UDP sockets. The integration also fixes
the upstream first-packet loss when S4 changes during a blocked TUN read.

`InterfaceMorphTest.java` checks all profiles, serialization, validation and
immutable builder equality. Dart tests cover negotiated and legacy enrollment;
server request tests retain enrollment identity/device-limit behavior.

`probe/main.go` can be copied into the overlaid core as `cmd/hyperwg-probe/main.go`
and built with `go build ./cmd/hyperwg-probe`. It reads a JSON object containing
`Endpoint`, `AccessKey`, `TestURL` from stdin, never writes credentials, and opens
two independent userspace tunnels from one logical configuration. It verifies
simultaneous bidirectional echo transfers, payload hashes, re-enrollment identity,
fresh handshakes and Internet egress. Run against a temporary dedicated config;
the operator must remove that config and echo service after the test.

## CPU optimizations (September 2026)

The sequential sender drains only already encrypted, immediately available FIFO
containers, up to the bind packet limit. An unfinished container remains first
for the next iteration; no accumulation delay is introduced. Keepalives remain
standalone. The same morpher still splits the combined packets at burst boundaries.
The send message pool clears only touched slots, including all GSO retry slots;
receive/GRO clears the full array because splitting can touch both ends.
The public random transport prefix uses a private 2048-byte CSPRNG reservoir per
worker for requests below 256 bytes; larger prefixes use crypto/rand directly.
Consumed bytes and remaining bytes at worker shutdown are cleared. Key generation,
handshakes, AEAD nonce assignment and header-protection encryption are unchanged.
