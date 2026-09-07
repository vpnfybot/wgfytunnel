// SPDX-License-Identifier: MIT
// Runtime probe. Reads enrollment credentials from stdin, keeps them in memory,
// and runs two independent peers over the real UDP network without a system TUN.
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/netip"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun/netstack"
)

type request struct { Endpoint, AccessKey, TestURL string }
type bundle struct {
	Device struct { ID string `json:"id"` } `json:"device"`
	Tunnel struct {
		Address string `json:"address"`
		PrivateKey string `json:"private_key"`
		PublicKey string `json:"public_key"`
		ServerPublicKey string `json:"server_public_key"`
		PresharedKey string `json:"preshared_key"`
		Endpoint string `json:"endpoint"`
		Profile string `json:"traffic_morpher"`
		MTU int `json:"mtu"`
		AWG map[string]string `json:"awg"`
	} `json:"tunnel"`
}

type observedBind struct {
	conn.Bind
	sync.Mutex
	sizes map[int]int
	packets int
	bytes int
}
func (b *observedBind) Send(bufs [][]byte, ep conn.Endpoint) error {
	err := b.Bind.Send(bufs, ep)
	if err == nil {
		b.Lock()
		for _, buf := range bufs { b.sizes[len(buf)]++; b.packets++; b.bytes += len(buf) }
		b.Unlock()
	}
	return err
}

func key(value string) string {
	decoded, err := base64.StdEncoding.DecodeString(value)
	if err != nil || len(decoded) != 32 { panic("invalid key from enrollment") }
	return hex.EncodeToString(decoded)
}

func enroll(r request, id string) (bundle, error) {
	var b bundle
	data, _ := json.Marshal(map[string]string{"access_key":r.AccessKey,"device_id":id,"name":id})
	client := http.Client{Timeout:20*time.Second}
	resp, err := client.Post(r.Endpoint+"/api/enroll", "application/json", bytes.NewReader(data))
	if err != nil { return b, err }; defer resp.Body.Close()
	if resp.StatusCode != 201 && resp.StatusCode != 200 { return b, fmt.Errorf("enroll HTTP %d", resp.StatusCode) }
	err = json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&b)
	return b, err
}

func run(r request, id string, b bundle, ready *sync.WaitGroup, start <-chan struct{}) error {
	t := b.Tunnel
	addr := netip.MustParsePrefix(t.Address).Addr()
	tun, net, err := netstack.CreateNetTUN([]netip.Addr{addr}, []netip.Addr{netip.MustParseAddr("1.1.1.1")}, t.MTU)
	if err != nil { ready.Done(); return err }
	bind := &observedBind{Bind:conn.NewDefaultBind(),sizes:make(map[int]int)}
	dev := device.NewDevice(tun, bind, device.NewLogger(device.LogLevelError, id+": "))
	defer dev.Close()
    defer func() {
        state, _ := dev.IpcGet()
        stats := map[string]string{}
        for _, line := range strings.Split(state,"\n") {
            k,v,ok := strings.Cut(line,"=")
            if ok && (k == "traffic_morpher" || k == "rx_bytes" || k == "tx_bytes" || k == "last_handshake_time_sec") { stats[k]=v }
        }
        encoded,_ := json.Marshal(map[string]any{"device":id,"final_state":stats})
        fmt.Fprintln(os.Stderr,string(encoded))
    }()
	var config strings.Builder
	fmt.Fprintf(&config,"private_key=%s\ntraffic_morpher=%s\n", key(t.PrivateKey), t.Profile)
	mapping := map[string]string{"HeaderProtectionKey":"header_protection_key", "ContentPaddingAddition":"content_padding_addition", "RekeyAfterTime":"rekey_after_time", "RekeyTimeout":"rekey_timeout", "RejectAfterTime":"reject_after_time", "KeepaliveTimeout":"keepalive_timeout", "MaxHandshakeAttempts":"max_handshake_attempts", "RandomTrailers":"random_trailers", "DisableCookies":"disable_cookies"}
	for name, value := range t.AWG {
		k, ok := mapping[name]; if !ok { k = strings.ToLower(name) }
		if name == "HeaderProtectionKey" { value = key(value) }
		if name == "RandomTrailers" || name == "DisableCookies" {
			if value == "on" || value == "true" { value = "1" } else { value = "0" }
		}
		fmt.Fprintf(&config,"%s=%s\n", k,value)
	}
	fmt.Fprintf(&config,"public_key=%s\npreshared_key=%s\nallowed_ip=0.0.0.0/0\nendpoint=%s\npersistent_keepalive_interval=25\n", key(t.ServerPublicKey),key(t.PresharedKey),t.Endpoint)
	if err := dev.IpcSet(config.String()); err != nil { ready.Done(); return err }
	if err := dev.Up(); err != nil { ready.Done(); return err }
	transport := &http.Transport{DialContext:net.DialContext, DisableKeepAlives:true}
	defer transport.CloseIdleConnections()
	client := http.Client{Transport:transport,Timeout:30*time.Second}
	ready.Done(); <-start
	started := time.Now()
	payload := bytes.Repeat([]byte("HyperWG-TrafficMorpher-runtime-check\n"),32768)
	wanted := fmt.Sprintf("%x", sha256.Sum256(payload))
	for round:=0; round<3; round++ {
		resp, err := client.Post(r.TestURL+"/echo", "application/octet-stream", bytes.NewReader(payload))
		if err != nil { return err }
		received, err := io.ReadAll(io.LimitReader(resp.Body,int64(len(payload)+1))); resp.Body.Close()
		if err != nil || resp.StatusCode != 200 || !bytes.Equal(received,payload) { return fmt.Errorf("echo payload mismatch (round %d)",round) }
	}
	// Re-enrollment must preserve this device's key/address and the other peer.
	again, err := enroll(r,id)
	if err != nil || again.Device.ID != b.Device.ID || again.Tunnel.PublicKey != t.PublicKey || again.Tunnel.Address != t.Address { return fmt.Errorf("reenrollment changed peer identity: %v",err) }
	resp, err := client.Get("https://api.ipify.org")
	if err != nil { return err }
	ip, err := io.ReadAll(io.LimitReader(resp.Body,128)); resp.Body.Close()
	if err != nil || resp.StatusCode != 200 { return fmt.Errorf("internet HTTP failed") }
	state, err := dev.IpcGet(); if err != nil { return err }
	stats := map[string]string{}
	for _, line := range strings.Split(state,"\n") {
		k,v,ok := strings.Cut(line,"="); if ok && (k == "traffic_morpher" || k == "rx_bytes" || k == "tx_bytes" || k == "last_handshake_time_sec") { stats[k]=v }
	}
	if hs,_ := strconv.ParseInt(stats["last_handshake_time_sec"],10,64); hs == 0 { return fmt.Errorf("missing handshake") }
	bind.Lock(); defer bind.Unlock()
	sizes := make([]int,0,len(bind.sizes)); for size := range bind.sizes { sizes=append(sizes,size) }; sort.Ints(sizes)
	result := map[string]any{"device":id,"address":t.Address,"internet_ip":string(ip),"elapsed_seconds":time.Since(started).Seconds(),"echo_bytes_each_way":3*len(payload),"payload_sha256":wanted,"udp_packets":bind.packets,"udp_bytes":bind.bytes,"unique_udp_sizes":len(sizes),"udp_min":sizes[0],"udp_max":sizes[len(sizes)-1],"state":stats}
	encoded,_:=json.Marshal(result); fmt.Println(string(encoded))
	return nil
}

func main() {
	var r request
	if err:=json.NewDecoder(os.Stdin).Decode(&r); err != nil { panic(err) }
	bundles:=make([]bundle,2)
	ids:=[]string{"hyperwg-morph-probe-a","hyperwg-morph-probe-b"}
	for i,id := range ids { b,err:=enroll(r,id); if err!=nil { panic(err) }; bundles[i]=b }
	if bundles[0].Tunnel.PublicKey==bundles[1].Tunnel.PublicKey || bundles[0].Tunnel.Address==bundles[1].Tunnel.Address { panic("devices share a cryptographic peer") }
	var ready,done sync.WaitGroup
	ready.Add(2); done.Add(2)
	start:=make(chan struct{}); errs:=make(chan error,2)
	for i,id:=range ids { go func(i int,id string){ defer done.Done(); errs<-run(r,id,bundles[i],&ready,start) }(i,id) }
	ready.Wait(); close(start); done.Wait(); close(errs)
	failed:=false; for err:=range errs { if err!=nil { fmt.Fprintln(os.Stderr,err); failed=true } }
	if failed { os.Exit(1) }
}
