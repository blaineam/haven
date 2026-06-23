//! The **local-disk media store-and-forward** proof:
//!
//! One node (Alice) seals a media blob to the circle and PUTs it to a relay that stores
//! it on **local disk** over Haven Net (iroh, ALPN `haven/blob/1`). A *different* node
//! (Bob) — who never talked to Alice — GETs the same content-addressed blob from the
//! relay over iroh and opens it with **his own** circle keys. We then assert the relay,
//! which is not a circle member, **cannot decrypt** what it stored: it only ever held
//! opaque ciphertext on disk.
//!
//! This is the headline guarantee: decentralized local-disk mailbox, host is a
//! non-key-holder.

use haven_net::blobstore::{BlobClient, BlobServer};
use p2pcore::identity::Identity;
use p2pcore::social::{open_bytes, seal_bytes, Group, SealedEnvelope};
use tokio::time::{timeout, Duration};

/// Content-address a sealed blob exactly the way the mailbox does: a stable key derived
/// from the sealed bytes, namespaced under the circle's mailbox path.
fn mailbox_key(circle: &str, sealed: &[u8]) -> String {
    let hash = blake3::hash(sealed);
    format!("mailbox/{circle}/{}", hash.to_hex())
}

#[tokio::test]
async fn sealed_blob_put_to_local_disk_relay_is_fetched_by_another_node_and_relay_cannot_decrypt() {
    // The circle: Alice + Bob hold the keys. The relay does NOT (it is not a member).
    let alice = Identity::generate();
    let bob = Identity::generate();
    let relay_id = Identity::generate();
    let group = Group::new("fam", vec![alice.public(), bob.public()]);

    // Alice seals a media blob to the whole circle.
    let plaintext = b"\x89PNG\r\n\x1a\n ...pretend this is a family photo... \xff\xd8\xff";
    let sealed = seal_bytes(&alice, &group, plaintext).unwrap().to_bytes();
    let key = mailbox_key("fam", &sealed);

    // The relay serves a LOCAL DIRECTORY over iroh. Nothing is public; no rclone, no S3.
    let store_dir =
        std::env::temp_dir().join(format!("haven-relay-blobtest-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&store_dir);
    let server = BlobServer::spawn(relay_id.node_secret_bytes(), store_dir.clone())
        .await
        .unwrap();
    // Same-machine: dial the relay's loopback address directly (no discovery needed).
    let relay_addr = server.local_dial_addr().await.unwrap();

    // Alice connects to the relay and PUTs the sealed blob.
    let alice_client = BlobClient::connect_addr(alice.node_secret_bytes(), relay_addr.clone())
        .await
        .unwrap();
    timeout(Duration::from_secs(10), alice_client.put(&key, &sealed))
        .await
        .expect("put timed out")
        .expect("put failed");

    // Prove the blob really landed on the relay's DISK as opaque ciphertext.
    let on_disk = std::fs::read(store_dir.join(&key)).expect("blob written to local disk");
    assert_eq!(on_disk, sealed, "the relay stored the exact sealed bytes, verbatim");
    assert_ne!(
        on_disk, plaintext,
        "what's on the relay's disk is ciphertext, not the plaintext media"
    );

    // Bob — a DIFFERENT node that never spoke to Alice — fetches the same key over iroh.
    let bob_client = BlobClient::connect_addr(bob.node_secret_bytes(), relay_addr.clone())
        .await
        .unwrap();
    assert!(
        timeout(Duration::from_secs(10), bob_client.has(&key))
            .await
            .expect("has timed out")
            .unwrap(),
        "relay reports it has the blob"
    );
    let fetched = timeout(Duration::from_secs(10), bob_client.get(&key))
        .await
        .expect("get timed out")
        .expect("get failed")
        .expect("relay returned the blob");
    assert_eq!(fetched, sealed, "Bob fetched the exact sealed bytes over Haven Net");

    // Bob opens it with HIS OWN circle keys → recovers Alice's original media.
    let env = SealedEnvelope::from_bytes(&fetched).unwrap();
    let opened = open_bytes(&bob, &alice.public(), &env).unwrap();
    assert_eq!(opened, plaintext, "Bob recovers Alice's exact media via the local-disk relay");

    // The relay is NOT a circle member, so even with the bytes it stored, it cannot
    // decrypt them. This is the non-key-holder guarantee, asserted directly.
    assert!(
        open_bytes(&relay_id, &alice.public(), &env).is_err(),
        "the relay must NOT be able to decrypt the blob it stored"
    );

    // LIST surfaces the key under the circle prefix (mailbox poll).
    let listed = timeout(Duration::from_secs(10), bob_client.list("mailbox/fam"))
        .await
        .expect("list timed out")
        .unwrap();
    assert!(listed.contains(&key), "the stored key shows up in a mailbox LIST");

    // A missing key is a clean MISS, not an error.
    let miss = bob_client.get("mailbox/fam/deadbeef").await.unwrap();
    assert!(miss.is_none(), "absent key returns None");

    alice_client.close().await;
    bob_client.close().await;
    let _ = std::fs::remove_dir_all(&store_dir);
    let _ = &server;
}
