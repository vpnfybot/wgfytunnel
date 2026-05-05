# Android-Only NekoBox Split Tunnel Target

This workspace should be treated as Android-only.

## What must stay
- `android/`
- `lib/`
- `assets/`
- `pubspec.yaml` and `pubspec.lock`
- `NEKOBOX/`
- `tools/`
- Android sing-box artifacts that are actually used for Android builds

## What app + site split tunneling requires on Android

### 1. One VPN owner only
For Android app split tunneling plus site split tunneling, there must be a single `VpnService` owner.

Recommended target:
- `SingBoxVpnService` owns the Android VPN/TUN.
- WireGuard is used as a `sing-box` outbound.
- Do not try to stack Android `GoBackend` WireGuard VPN and a second sing-box VPN at the same time.

Why:
- Android allows only one active VPN interface.
- Domain/site routing needs TUN + DNS/domain classification, which raw WireGuard does not provide.

### 2. App split tunneling
There are two Android-valid mechanisms.

#### Official Android mechanism
Use `VpnService.Builder.addAllowedApplication()` or `addDisallowedApplication()`.

Confirmed by Android docs:
- If you call `addAllowedApplication()`, only those apps use the VPN.
- If you call `addDisallowedApplication()`, all apps except those bypass the VPN.
- You cannot mix allowed and disallowed in one builder.

NekoBox reference already uses this in:
- `NEKOBOX/app/src/main/java/io/nekohasekai/sagernet/bg/VpnService.kt`

#### sing-box Android tun mechanism
Use tun inbound fields:
- `include_package`
- `exclude_package`
- `include_android_user`

Confirmed by sing-box docs:
- These are Android-only tun filters.
- They require `auto_route = true`.

Recommendation for this repo:
- Pick one authority for app split.
- Prefer Android `VpnService.Builder` app filtering first, because it is official and already mirrored by NekoBox.
- Do not duplicate app filtering in both Builder and sing-box tun unless there is a very specific reason.

### 3. Site/domain split tunneling
Raw WireGuard cannot do domain-based routing by itself.

To route only selected sites or exclude selected sites, you need sing-box domain-aware routing:
- TUN inbound
- DNS interception
- FakeIP or reverse mapping
- Sniffing
- Route rules by `domain`, `domain_suffix`, `domain_regex`, or rule-set

Required sing-box pieces:
- `dns.fakeip.enabled = true`
- DNS servers for direct and remote resolution
- DNS rule for TUN inbound to `dns-fake`
- `sniff = true`
- `sniff_override_destination = true`
- Route rules with `domain_suffix` and outbound decision

Recommended routing model:
- Include mode: selected domains -> `proxy`, `route.final` -> `direct`
- Exclude mode: selected domains -> `direct`, `route.final` -> `proxy`

### 4. WireGuard through NekoBox/sing-box
For Android app + site split, WireGuard should be the outbound inside sing-box, not a separate Android VPN backend.

Required outbound type:
- `type = "wireguard"`
- endpoint host/port
- local addresses
- private key
- peer public key
- optional preshared key
- MTU

### 5. Tun inbound requirements
For Android NekoBox-style routing, the tun inbound should be the basis of the system.

Required baseline:
- `type = "tun"`
- `tag = "tun-in"`
- `auto_route = true`
- `stack = "system"` or `"mixed"`
- `sniff = true`
- `sniff_override_destination = true`
- valid `address` or `inet4_address`
- Android package filters only if chosen as the app-split authority

Important from sing-box docs:
- `include_package` / `exclude_package` require `auto_route = true`
- Android package rules are supported directly by tun inbound

### 6. DNS requirements
For selected-site routing to work reliably on Android:
- Use FakeIP DNS inside sing-box.
- Hijack DNS from the tun path.
- Resolve direct DNS via direct outbound.
- Resolve remote DNS via proxy outbound when needed.

Practical minimum:
- `dns-direct`
- `dns-remote`
- `dns-fake`
- DNS rule: traffic from `tun-in` -> `dns-fake`
- Route rule: DNS protocol or port 53 -> `hijack-dns`

### 7. Matching NekoBox core revisions
If you embed NekoBox libcore, the following must match:
- `libcore`
- `sing-box`
- `libneko`
- generated Java bindings
- packaged `libgojni.so`

This repo already contains the pinning clue here:
- `NEKOBOX/buildScript/lib/core/get_source.sh`

Meaning:
- Do not mix arbitrary current `NEKOBOX/sing-box` sources with a different prebuilt `libgojni.so`.
- Build the runtime from the pinned revisions NekoBox expects.

## Recommended repo direction from here

### Keep Android-only stack
- Keep Flutter only as Android UI shell if you still want Dart UI.
- Remove all non-Android platform targets.
- Keep only Android runtime path.

### Recommended implementation path
1. Make `SingBoxVpnService` the only VPN engine for all domain-routing modes.
2. Keep a single Android VPN/TUN lifecycle.
3. Use WireGuard as sing-box outbound.
4. Use Android Builder app split or sing-box `include_package/exclude_package`, but not both at once by default.
5. Use sing-box DNS + FakeIP + route rules for site split.
6. Rebuild embedded libcore from the exact pinned NekoBox source revisions before further feature work.

## Concrete target state for this repo
- `MainActivity` should prepare config and start one Android VPN service.
- `SingBoxVpnService` should establish the TUN and run the box instance.
- App split should be applied in exactly one place.
- Domain split should be expressed in sing-box route rules.
- No separate Android WireGuard VPN should coexist with the sing-box VPN.

## Current repo mismatches
- `android/app/src/main/kotlin/com/example/wgfytunnel/MainActivity.kt` still contains two VPN engines: `GoBackend` for plain WireGuard and `SingBoxManager` for domain-aware mode.
- `android/app/src/main/kotlin/com/example/wgfytunnel/SingBoxVpnService.kt` already applies app split with Android `VpnService.Builder`, which is the cleaner authority to keep first.
- `android/app/src/main/kotlin/com/example/wgfytunnel/SingBoxConfig.kt` still sets `auto_route = false`, so it is not yet aligned with the Android tun package-routing model described in sing-box docs.
- The current blocker is not routing design anymore; it is runtime stability around embedded `Libcore.newSingBoxInstance(...)`.

## Execution order

### Slice 1: stabilize the sing-box runtime
Do this before any architectural cleanup.

Files:
- `android/app/src/main/kotlin/com/example/wgfytunnel/SingBoxVpnService.kt`
- `android/app/src/main/kotlin/com/example/wgfytunnel/LibcoreBridge.kt`
- embedded `NEKOBOX/libcore` build inputs

Goal:
- Make `Libcore.newSingBoxInstance(...)` start reliably with the smallest valid config.

Do not do yet:
- Do not remove `GoBackend` fallback before this slice is stable.
- Do not mix new package-routing experiments into the same debugging step.

### Slice 2: keep app split in Android Builder only
Once sing-box starts reliably, keep app selection in one place first.

Files:
- `android/app/src/main/kotlin/com/example/wgfytunnel/SingBoxVpnService.kt`
- `android/app/src/main/kotlin/com/example/wgfytunnel/MainActivity.kt`

Goal:
- Keep `addAllowedApplication()` / `addDisallowedApplication()` as the only app-split authority.
- Do not also inject `include_package` / `exclude_package` into sing-box during this slice.

Reason:
- This matches the current service implementation and removes one variable while the runtime is still being stabilized.

### Slice 3: make sing-box the only VPN engine
After slices 1 and 2 are stable, remove the dual-engine branch.

Files:
- `android/app/src/main/kotlin/com/example/wgfytunnel/MainActivity.kt`
- `android/app/src/main/kotlin/com/example/wgfytunnel/SingBoxManager.kt`

Goal:
- Route all Android VPN connections through `SingBoxVpnService`.
- Keep raw `GoBackend` only if you intentionally want a temporary fallback build variant.

### Slice 4: finish config alignment
Only after the service is stable and singular.

Files:
- `android/app/src/main/kotlin/com/example/wgfytunnel/SingBoxConfig.kt`

Goal:
- Align tun settings with the chosen authority model.
- If app split stays in Android Builder, keep tun package lists empty.
- If app split moves into sing-box later, switch `auto_route` on and emit `include_package` / `exclude_package` explicitly.

### Slice 5: remove debug-only probes
After the Android-only path is proven.

Files:
- `android/app/src/main/jni/**`
- `NEKOBOX/libcore/**` temporary diagnostics
- extra trace-only logging in `SingBoxVpnService.kt`

Goal:
- Keep only the minimum diagnostics needed for production support.

## First code change worth making next
If you want the next implementation slice instead of more documentation, the best next change is:
- reduce the sing-box startup path to the smallest known-good config and validate `Libcore.newSingBoxInstance(...)` before changing routing behavior.

That is the highest-value next move because:
- app split design is already clear,
- site split design is already clear,
- the unresolved blocker is the embedded runtime start path, not the routing model.

## Short answer
To implement split tunneling of apps plus sites on Android for WireGuard using NekoBox, you need:
- one Android `VpnService`
- sing-box tun inbound
- WireGuard outbound inside sing-box
- Android app filtering (`addAllowedApplication` / `addDisallowedApplication`) or tun `include_package` / `exclude_package`
- FakeIP DNS + DNS hijack
- route rules by `domain_suffix` / rule-set
- a libcore build from matching pinned NekoBox revisions
