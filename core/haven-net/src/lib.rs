//! Haven networking — an iroh-backed P2P node that carries opaque payloads (in
//! practice, `p2pcore::social::SealedEnvelope` bytes) between peers over QUIC.
//!
//! Connections are **kept alive and reused bidirectionally**: each message is a uni
//! stream on a cached connection keyed by the remote's node id. Whoever can reach the
//! other dials once; both then send over that same connection. This is what lets
//! delivery flow both ways even when one peer is behind a NAT that can't be dialed
//! directly. The bytes on the wire are already end-to-end encrypted by `p2pcore`.

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::{anyhow, Result};
use data_encoding::BASE32_NOPAD;
use iroh::{
    endpoint::{presets::N0, Connection, Endpoint},
    EndpointAddr, EndpointId, SecretKey,
};

pub mod blobstore;
pub mod relay;
pub mod s3tunnel;

const ALPN: &[u8] = b"haven/social/0";
const MAX_PAYLOAD: usize = 256 * 1024 * 1024;

/// Called for each inbound payload (sealed envelope / protocol frame bytes).
pub type InboundHandler = Arc<dyn Fn(Vec<u8>) + Send + Sync>;

type Conns = Arc<Mutex<HashMap<EndpointId, Connection>>>;

/// Lock that tolerates poisoning (a panic in one task must not cascade-abort others).
fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

trait IntoAnyhow<T> {
    fn ah(self) -> Result<T>;
}
impl<T, E: std::fmt::Debug> IntoAnyhow<T> for std::result::Result<T, E> {
    fn ah(self) -> Result<T> {
        self.map_err(|e| anyhow!("{e:?}"))
    }
}

/// A peer-to-peer node.
pub struct Node {
    endpoint: Endpoint,
    conns: Conns,
    handler: InboundHandler,
}

impl Node {
    /// Bind a node using the owning identity's Ed25519 key (so `node_id_hex()` equals
    /// that identity's `node_id_bytes`), with the n0 preset: free public discovery +
    /// relays. Starts an accept loop that keeps each inbound connection alive.
    pub async fn spawn(secret: [u8; 32], handler: InboundHandler) -> Result<Self> {
        let endpoint = Endpoint::builder(N0)
            .secret_key(SecretKey::from_bytes(&secret))
            .alpns(vec![ALPN.to_vec()])
            .bind()
            .await
            .ah()?;
        let conns: Conns = Arc::new(Mutex::new(HashMap::new()));
        let ep = endpoint.clone();
        let c = conns.clone();
        let h = handler.clone();
        tokio::spawn(async move { accept_loop(ep, c, h).await });
        Ok(Self { endpoint, conns, handler })
    }

    /// This node's id (== the owning identity's `node_id_bytes`), as hex.
    pub fn node_id_hex(&self) -> String {
        hex(self.endpoint.id().as_bytes())
    }

    /// Send a payload to a contact by their hex node id. Discovery resolves the live
    /// address; an existing (dialed or accepted) connection is reused if present.
    pub async fn send_to_node(&self, node_id_hex: &str, payload: &[u8]) -> Result<()> {
        let bytes = decode_hex32(node_id_hex)?;
        let id = EndpointId::from_bytes(&bytes).map_err(|e| anyhow!("{e:?}"))?;
        self.send(EndpointAddr::new(id), payload).await
    }

    /// Send a payload to a peer address (reusing a live connection if one exists).
    pub async fn send(&self, to: EndpointAddr, payload: &[u8]) -> Result<()> {
        let conn = self.conn_for(to).await?;
        let mut s = conn.open_uni().await.ah()?;
        s.write_all(payload).await.ah()?;
        s.finish().ah()?;
        Ok(())
    }

    /// Reuse a live connection to this peer, or dial a fresh one (and start reading
    /// replies on it).
    async fn conn_for(&self, addr: EndpointAddr) -> Result<Connection> {
        let id = addr.id;
        if let Some(c) = lock(&self.conns).get(&id).cloned() {
            if c.close_reason().is_none() {
                return Ok(c);
            }
        }
        let conn = self.endpoint.connect(addr, ALPN).await.ah()?;
        lock(&self.conns).insert(id, conn.clone());
        let c = self.conns.clone();
        let h = self.handler.clone();
        let cc = conn.clone();
        tokio::spawn(async move { read_loop(cc, c, h).await });
        Ok(conn)
    }

    /// Send a sealed payload to `final_dest` **via a relay**: wrap it in a mesh-relay
    /// frame addressed to the destination(s), then hand that frame to the relay node
    /// (by the relay's hex node id). The relay forwards the opaque payload onward; it
    /// can read only the destination ids, never the sealed bytes.
    pub async fn send_via_relay(
        &self,
        relay_node_hex: &str,
        final_dest: Vec<[u8; 32]>,
        payload: &[u8],
    ) -> Result<()> {
        let frame = relay::RoutingFrame::new(final_dest, payload.to_vec(), relay::DEFAULT_TTL);
        self.send_to_node(relay_node_hex, &frame.to_bytes()).await
    }

    /// Same-machine dial address (loopback + this node's port), for local tests.
    pub async fn local_dial_addr(&self) -> Result<EndpointAddr> {
        let addr = wait_for_direct_addr(&self.endpoint).await?;
        let port = addr
            .ip_addrs()
            .next()
            .map(|a| a.port())
            .ok_or_else(|| anyhow!("no direct port yet"))?;
        Ok(EndpointAddr::new(addr.id).with_ip_addr(SocketAddr::from(([127, 0, 0, 1], port))))
    }

    /// A shareable ticket (base32 of this node's address) for a peer to dial.
    pub async fn ticket(&self) -> Result<String> {
        let addr = wait_for_direct_addr(&self.endpoint).await?;
        Ok(BASE32_NOPAD.encode(&serde_json::to_vec(&addr).ah()?))
    }

    /// Send a payload to a peer identified by their [`Node::ticket`].
    pub async fn send_ticket(&self, ticket: &str, payload: &[u8]) -> Result<()> {
        let bytes = BASE32_NOPAD
            .decode(ticket.trim().as_bytes())
            .map_err(|_| anyhow!("bad ticket"))?;
        let addr: EndpointAddr = serde_json::from_slice(&bytes).map_err(|_| anyhow!("bad ticket"))?;
        self.send(addr, payload).await
    }

    pub async fn close(self) {
        self.endpoint.close().await;
    }
}

/// An always-on **connection relay**: a node that forwards mesh-relay frames toward
/// circle members it can reach, without ever reading the sealed payload.
///
/// It binds its own iroh identity (so members can dial it / it can dial them), keeps a
/// bounded RAM-only dedup set, and on each inbound [`relay::RoutingFrame`]:
///   1. drops it if the `msg_id` was already seen (loop/replay guard),
///   2. drops it if `ttl == 0`,
///   3. otherwise decrements the ttl and forwards the *same opaque payload* to every
///      destination node id in the header (except itself), re-wrapped in a fresh frame.
///
/// The relay never opens, stores, or logs the payload. It only moves ciphertext.
pub struct RelayNode {
    node: Arc<Node>,
    me_hex: String,
    seen: Arc<Mutex<relay::SeenSet>>,
}

impl RelayNode {
    /// Spawn a relay bound to `secret` (its own identity key). `on_frame`, if provided,
    /// is invoked with each *destination-matches-me* payload — i.e. when this relay is
    /// itself a listed recipient — so a relay that is also a normal member can still
    /// receive. Pure forwarders pass `None`.
    pub async fn spawn(
        secret: [u8; 32],
        on_frame: Option<InboundHandler>,
    ) -> Result<Arc<Self>> {
        // Late-bound self-reference so the inbound handler can forward via the node.
        let holder: Arc<Mutex<Option<Arc<RelayNode>>>> = Arc::new(Mutex::new(None));
        let seen: Arc<Mutex<relay::SeenSet>> = Arc::new(Mutex::new(relay::SeenSet::default()));

        let h = holder.clone();
        let handler: InboundHandler = Arc::new(move |bytes: Vec<u8>| {
            let this = lock(&h).clone();
            if let Some(this) = this {
                let deliver = on_frame.clone();
                tokio::spawn(async move {
                    this.handle_inbound(bytes, deliver).await;
                });
            }
        });

        let node = Arc::new(Node::spawn(secret, handler).await?);
        let me_hex = node.node_id_hex();
        let relay = Arc::new(RelayNode { node, me_hex, seen });
        *lock(&holder) = Some(relay.clone());
        Ok(relay)
    }

    /// This relay's node id (hex) — the value that goes in a circle's "relays" list.
    pub fn node_id_hex(&self) -> String {
        self.me_hex.clone()
    }

    /// Same-machine dial address (loopback), for local/integration tests.
    pub async fn local_dial_addr(&self) -> Result<EndpointAddr> {
        self.node.local_dial_addr().await
    }

    /// Forward a frame on behalf of a member who can't reach the destinations directly.
    /// (Members call this by sending the relay a [`relay::RoutingFrame`]; this is also
    /// the programmatic entry used in tests / when wrapping locally.)
    pub async fn forward(&self, frame: relay::RoutingFrame) {
        self.handle_inbound(frame.to_bytes(), None).await;
    }

    async fn handle_inbound(&self, bytes: Vec<u8>, deliver: Option<InboundHandler>) {
        let Some(frame) = relay::RoutingFrame::parse(&bytes) else {
            // Not a relay frame: a bare payload addressed straight to us. Deliver if we
            // have a member handler; otherwise (pure forwarder) ignore.
            if let Some(d) = deliver {
                d(bytes);
            }
            return;
        };

        // Loop / replay guard (RAM-only, bounded).
        if !lock(&self.seen).insert(frame.msg_id) {
            return;
        }

        // If we're one of the destinations and we're acting as a member too, deliver
        // the inner payload locally.
        let me_is_dest = frame
            .dest
            .iter()
            .any(|d| relay::RoutingFrame::dest_hex(d) == self.me_hex);
        if me_is_dest {
            if let Some(d) = &deliver {
                d(frame.payload.clone());
            }
        }

        if frame.ttl == 0 {
            return;
        }
        let next_ttl = frame.ttl - 1;

        // Forward the SAME opaque payload to every other destination. We re-wrap with a
        // fresh single-dest frame per hop, preserving the original msg_id so downstream
        // relays dedup the whole multicast as one message.
        for d in &frame.dest {
            let dh = relay::RoutingFrame::dest_hex(d);
            if dh == self.me_hex {
                continue;
            }
            let fwd = relay::RoutingFrame {
                ttl: next_ttl,
                msg_id: frame.msg_id,
                dest: vec![*d],
                payload: frame.payload.clone(),
            };
            // Best-effort: a destination we can't reach right now is simply skipped; the
            // member will get it from the storage mailbox or a later online overlap.
            let _ = self.node.send_to_node(&dh, &fwd.to_bytes()).await;
        }
    }

    pub async fn close(self: Arc<Self>) {
        // Drop our reference; the underlying endpoint closes when the last Arc to the
        // inner Node is gone. We expose an explicit no-panic close for symmetry.
        if let Ok(node) = Arc::try_unwrap(self) {
            if let Ok(inner) = Arc::try_unwrap(node.node) {
                inner.close().await;
            }
        }
    }
}

async fn accept_loop(endpoint: Endpoint, conns: Conns, handler: InboundHandler) {
    while let Some(incoming) = endpoint.accept().await {
        let conns = conns.clone();
        let handler = handler.clone();
        tokio::spawn(async move {
            let Ok(connecting) = incoming.accept() else { return };
            let Ok(conn) = connecting.await else { return };
            // Keep the inbound connection so we can send back to a peer who dialed us
            // (they may be unreachable for us to dial directly).
            lock(&conns).insert(conn.remote_id(), conn.clone());
            read_loop(conn, conns, handler).await;
        });
    }
}

/// Read every uni stream on a connection as one message, for the connection's life.
async fn read_loop(conn: Connection, conns: Conns, handler: InboundHandler) {
    loop {
        match conn.accept_uni().await {
            Ok(mut recv) => {
                let handler = handler.clone();
                tokio::spawn(async move {
                    if let Ok(payload) = recv.read_to_end(MAX_PAYLOAD).await {
                        // The handler crosses into a foreign (Swift) callback — a panic
                        // there would abort the whole app, so contain it.
                        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                            handler(payload);
                        }));
                    }
                });
            }
            Err(_) => break,
        }
    }
    let id = conn.remote_id();
    let mut map = lock(&conns);
    if map.get(&id).map(|c| c.close_reason().is_some()).unwrap_or(false) {
        map.remove(&id);
    }
}

async fn wait_for_direct_addr(endpoint: &Endpoint) -> Result<EndpointAddr> {
    for _ in 0..50 {
        let addr = endpoint.addr();
        if addr.ip_addrs().next().is_some() {
            return Ok(addr);
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    Err(anyhow!("no direct addresses discovered within 5s"))
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

fn decode_hex32(s: &str) -> Result<[u8; 32]> {
    let s = s.trim();
    if s.len() != 64 {
        return Err(anyhow!("node id must be 64 hex chars"));
    }
    let mut out = [0u8; 32];
    for i in 0..32 {
        out[i] = u8::from_str_radix(&s[i * 2..i * 2 + 2], 16).map_err(|_| anyhow!("bad hex"))?;
    }
    Ok(out)
}
