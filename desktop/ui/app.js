// Haven desktop frontend. Talks to the Rust backend (which links the shared core) via
// Tauri `invoke`. No framework — small DOM helpers + per-view render functions, re-rendered
// when the backend emits `haven:changed`.

const TAURI = window.__TAURI__ || {};
const invoke = TAURI.core ? TAURI.core.invoke : async () => { throw new Error("Tauri not ready"); };
const listen = TAURI.event ? TAURI.event.listen : async () => {};

// ---- tiny helpers ----------------------------------------------------------------------
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
const el = (tag, props = {}, ...kids) => {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === "class") e.className = v;
    else if (k === "html") e.innerHTML = v;
    else if (k.startsWith("on") && typeof v === "function") e.addEventListener(k.slice(2), v);
    else if (v !== null && v !== undefined) e.setAttribute(k, v);
  }
  for (const kid of kids.flat()) {
    if (kid == null) continue;
    e.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
  }
  return e;
};
const esc = (s) => (s || "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

function toast(msg) {
  const t = $("#toast");
  t.textContent = msg;
  t.classList.add("show");
  clearTimeout(toast._t);
  toast._t = setTimeout(() => t.classList.remove("show"), 2200);
}

function relTime(ms) {
  const n = Number(ms);
  if (!n) return "";
  const diff = Date.now() - n;
  const s = Math.floor(diff / 1000);
  if (s < 60) return "just now";
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h`;
  const d = Math.floor(h / 24);
  if (d < 7) return `${d}d`;
  return new Date(n).toLocaleDateString();
}

function initials(name) {
  const p = (name || "").trim().split(/\s+/);
  if (!p[0]) return "·";
  return (p[0][0] + (p[1] ? p[1][0] : "")).toUpperCase();
}

function modal(node) {
  const root = $("#modal-root");
  const backdrop = el("div", { class: "modal-backdrop", onclick: (e) => { if (e.target === backdrop) root.replaceChildren(); } }, node);
  node.classList.add("modal");
  root.replaceChildren(backdrop);
  return () => root.replaceChildren();
}

// Decrypt + lazy-load a media ref into an <img>/<video>.
async function loadMedia(node, circleId, ref) {
  try {
    const url = await invoke("media_data_url", { circleId, reference: ref });
    if (url) node.src = url;
    else node.replaceWith(el("div", { class: "tag" }, "media syncing…"));
  } catch (_) {}
}

// ---- app state -------------------------------------------------------------------------
const state = {
  view: "feed",
  node: "",
  inviteUri: "",
  inviteLink: "",
  profile: {},
  activeCircle: "default",
  activeDm: null,
  attachments: [], // {ref, url, isVideo}
};

// ---- navigation ------------------------------------------------------------------------
function switchView(view) {
  state.view = view;
  $$(".nav-btn").forEach((b) => b.classList.toggle("active", b.dataset.view === view));
  $$(".view").forEach((v) => v.classList.toggle("active", v.id === `view-${view}`));
  render();
}

async function render() {
  switch (state.view) {
    case "feed": return renderFeed();
    case "stories": return renderStories();
    case "messages": return renderMessages();
    case "connect": return renderConnect();
    case "relay": return renderRelay();
    case "you": return renderYou();
  }
}

async function refreshBadges() {
  try {
    const pend = await invoke("pending");
    const b = $("#badge-pending");
    b.textContent = pend.length;
    b.classList.toggle("show", pend.length > 0);
  } catch (_) {}
  try {
    const dms = await invoke("dm_threads");
    const b = $("#badge-messages");
    b.textContent = dms.length;
    b.classList.toggle("show", dms.length > 0);
  } catch (_) {}
}

async function refreshStatus() {
  try {
    const s = await invoke("relay_status");
    const dot = $("#status-dot");
    const txt = $("#status-text");
    dot.classList.toggle("on", s.started);
    dot.classList.toggle("relay", s.hosting);
    txt.textContent = s.hosting ? "relaying" : s.started ? (s.internet_active ? "connected" : "online") : "starting…";
  } catch (_) {}
}

// ---- Feed ------------------------------------------------------------------------------
async function renderFeed() {
  const root = $("#view-feed");
  const circles = await invoke("circles");
  if (!circles.find((c) => c.id === state.activeCircle)) state.activeCircle = "default";

  const head = el("div", { class: "view-head" },
    el("h1", {}, "Feed"),
    el("div", { class: "spacer" }),
    (() => {
      const sel = el("select", { style: "width:auto", onchange: (e) => { state.activeCircle = e.target.value; renderFeed(); } });
      for (const c of circles) sel.append(el("option", { value: c.id, selected: c.id === state.activeCircle || null }, `${c.name} (${c.member_count})`));
      return sel;
    })(),
    el("button", { class: "btn small", onclick: newCircleDialog }, "+ Circle"),
  );

  const composer = buildComposer((body) => invoke("post", { circleId: state.activeCircle, body, media: state.attachments.map((a) => a.ref), music: null }));

  const items = (await invoke("feed", { circleId: state.activeCircle })).filter((i) => !i.story);
  const list = el("div", {});
  if (!items.length) list.append(el("div", { class: "empty" }, "No posts yet. Say hello to your circle, or connect a friend."));
  for (const it of items) list.append(postCard(it, state.activeCircle));

  root.replaceChildren(head, composer, list);
  hydrateMedia(root, state.activeCircle);
}

function buildComposer(onPost, placeholder = "Share something with your circle…") {
  const ta = el("textarea", { placeholder });
  const previews = el("div", { class: "attach-preview" });
  const drawPreviews = () => {
    previews.replaceChildren(...state.attachments.map((a, i) =>
      el("div", { class: "chip" },
        a.isVideo ? el("video", { src: a.url, muted: "" }) : el("img", { src: a.url }),
        el("span", { class: "x", onclick: () => { state.attachments.splice(i, 1); drawPreviews(); } }, "×"),
      )));
  };
  const fileInput = el("input", { type: "file", accept: "image/*,video/*", style: "display:none", onchange: (e) => handleFiles(e.target.files, drawPreviews) });
  const card = el("div", { class: "card col" },
    ta,
    previews,
    el("div", { class: "row" },
      el("button", { class: "btn small ghost", onclick: () => fileInput.click() }, "📎 Photo / Video"),
      el("div", { class: "spacer", style: "flex:1" }),
      el("button", {
        class: "btn primary", onclick: async () => {
          const body = ta.value.trim();
          if (!body && !state.attachments.length) return;
          await onPost(body);
          ta.value = "";
          state.attachments = [];
          drawPreviews();
          toast("Posted");
        }
      }, "Post"),
    ),
    fileInput,
  );
  return card;
}

async function handleFiles(files, after) {
  for (const f of files) {
    const isVideo = f.type.startsWith("video");
    try {
      const b64 = isVideo ? await fileToBase64(f) : await imageToJpegBase64(f);
      const ref = await invoke("add_media", { circleId: state.activeCircle, dataBase64: b64, isVideo });
      const url = await invoke("media_data_url", { circleId: state.activeCircle, reference: ref });
      state.attachments.push({ ref, url, isVideo });
      after();
    } catch (e) { toast("Couldn't attach: " + e); }
  }
}

function fileToBase64(file) {
  return new Promise((res, rej) => {
    const r = new FileReader();
    r.onload = () => res(r.result.split(",")[1]);
    r.onerror = rej;
    r.readAsDataURL(file);
  });
}

function imageToJpegBase64(file, maxDim = 2048, quality = 0.82) {
  return new Promise((res, rej) => {
    const img = new Image();
    img.onload = () => {
      const scale = Math.min(1, maxDim / Math.max(img.width, img.height));
      const c = el("canvas");
      c.width = Math.round(img.width * scale);
      c.height = Math.round(img.height * scale);
      c.getContext("2d").drawImage(img, 0, 0, c.width, c.height);
      res(c.toDataURL("image/jpeg", quality).split(",")[1]);
      URL.revokeObjectURL(img.src);
    };
    img.onerror = rej;
    img.src = URL.createObjectURL(file);
  });
}

function postCard(it, circleId) {
  const head = el("div", { class: "post-head" },
    el("div", { class: "avatar" }, initials(it.author_name)),
    el("div", {},
      el("div", { class: "name" }, it.author_name),
      el("div", { class: "muted small" }, relTime(it.created_at) + (it.edited ? " · edited" : "")),
    ),
    it.is_me ? el("button", { class: "kebab menu-btn", onclick: (e) => postMenu(e, it, circleId) }, "⋯") : null,
  );

  const body = it.unsent
    ? el("div", { class: "post-body muted" }, "🚫 This post was unsent")
    : el("div", { class: "post-body" }, it.body);

  const media = el("div", { class: "post-media" });
  for (const ref of it.media || []) {
    const m = ref.startsWith("v:") ? el("video", { controls: "", "data-ref": ref }) : el("img", { "data-ref": ref, loading: "lazy" });
    media.append(m);
  }

  const song = it.music ? el("div", { class: "song-chip" }, "🎵 ", el("strong", {}, it.music.title), " — ", it.music.artist) : null;

  const actions = el("div", { class: "post-actions" });
  const heart = el("button", { class: "react-pill" + (hasMine(it.reactions, "❤️") ? " mine" : ""), onclick: () => toggleReact(circleId, it.id, "❤️", it.reactions) }, "❤️", reactCount(it.reactions, "❤️"));
  actions.append(heart);
  for (const r of it.reactions || []) {
    if (r.emoji === "❤️") continue;
    actions.append(el("span", { class: "react-pill" + (r.mine ? " mine" : ""), onclick: () => toggleReact(circleId, it.id, r.emoji, it.reactions) }, r.emoji, " ", String(r.count)));
  }
  actions.append(el("button", { class: "react-pill", onclick: (e) => emojiPicker(e, circleId, it.id) }, "＋"));
  const cmtBtn = el("button", { class: "btn small ghost" }, `💬 ${(it.comments || []).length}`);
  actions.append(cmtBtn);

  const comments = el("div", { class: "comments" });
  for (const c of it.comments || []) {
    comments.append(el("div", { class: "comment" },
      el("div", { class: "avatar", style: "width:26px;height:26px;font-size:11px" }, initials(c.author_name)),
      el("div", { class: "bubble" }, el("div", { class: "small muted" }, c.author_name + " · " + relTime(c.created_at)), el("div", {}, c.body)),
    ));
  }
  const cin = el("input", { placeholder: "Add a comment…", onkeydown: async (e) => { if (e.key === "Enter" && e.target.value.trim()) { await invoke("comment", { circleId, target: it.id, body: e.target.value.trim() }); e.target.value = ""; } } });
  comments.append(el("div", { class: "row" }, cin));
  cmtBtn.addEventListener("click", () => comments.classList.toggle("show"));

  return el("div", { class: "card post" }, head, body, media.children.length ? media : null, song, actions, comments);
}

const hasMine = (rs, e) => (rs || []).some((r) => r.emoji === e && r.mine);
const reactCount = (rs, e) => { const r = (rs || []).find((x) => x.emoji === e); return r ? " " + r.count : ""; };

async function toggleReact(circleId, target, emoji, reactions) {
  const mine = hasMine(reactions, emoji);
  await invoke(mine ? "unreact" : "react", { circleId, target, emoji });
}

function emojiPicker(e, circleId, target) {
  const choices = ["👍", "😂", "🔥", "😮", "😢", "🎉", "💜", "👏"];
  const m = el("div", {}, el("h2", {}, "React"),
    el("div", { class: "row wrap" }, ...choices.map((c) =>
      el("button", { class: "btn", style: "font-size:22px", onclick: async () => { await invoke("react", { circleId, target, emoji: c }); $("#modal-root").replaceChildren(); } }, c))));
  modal(m);
}

function postMenu(e, it, circleId) {
  const m = el("div", {}, el("h2", {}, "Post"),
    el("div", { class: "col" },
      el("button", { class: "btn", onclick: () => { $("#modal-root").replaceChildren(); editPostDialog(it, circleId); } }, "✏️ Edit"),
      el("button", { class: "btn danger", onclick: async () => { await invoke("unsend_post", { circleId, target: it.id }); $("#modal-root").replaceChildren(); toast("Unsent"); } }, "🚫 Unsend"),
    ));
  modal(m);
}

function editPostDialog(it, circleId) {
  const ta = el("textarea", {}, );
  ta.value = it.body;
  modal(el("div", {}, el("h2", {}, "Edit post"), ta,
    el("div", { class: "row", style: "margin-top:12px;justify-content:flex-end" },
      el("button", { class: "btn primary", onclick: async () => { await invoke("edit_post", { circleId, target: it.id, body: ta.value.trim() }); $("#modal-root").replaceChildren(); } }, "Save"))));
}

function newCircleDialog() {
  const inp = el("input", { placeholder: "Circle name (e.g. Family)" });
  modal(el("div", {}, el("h2", {}, "New circle"), inp,
    el("div", { class: "row", style: "margin-top:12px;justify-content:flex-end" },
      el("button", { class: "btn primary", onclick: async () => { if (inp.value.trim()) { state.activeCircle = await invoke("create_circle", { name: inp.value.trim() }); } $("#modal-root").replaceChildren(); renderFeed(); } }, "Create"))));
}

function hydrateMedia(root, circleId) {
  $$("[data-ref]", root).forEach((node) => loadMedia(node, circleId, node.dataset.ref));
}

// ---- Stories ---------------------------------------------------------------------------
async function renderStories() {
  const root = $("#view-stories");
  const items = (await invoke("feed", { circleId: "default" })).filter((i) => i.story && !i.unsent);
  const tray = el("div", { class: "story-tray" });
  tray.append(el("div", { class: "story-ring", onclick: addStoryDialog },
    el("div", { class: "ring" }, el("div", {}, "＋")), el("div", { class: "small" }, "Add")));
  for (const it of items) {
    const inner = el("div", {});
    if ((it.media || []).length) { const img = el("img", { "data-ref": it.media[0] }); inner.append(img); }
    else inner.append(document.createTextNode("✨"));
    tray.append(el("div", { class: "story-ring", onclick: () => viewStory(it) },
      el("div", { class: "ring" }, inner), el("div", { class: "small" }, it.author_name.split(" ")[0])));
  }
  root.replaceChildren(el("div", { class: "view-head" }, el("h1", {}, "Stories")), tray,
    items.length ? el("div", { class: "muted small" }, "Stories disappear after 24 hours.") : el("div", { class: "empty" }, "No active stories."));
  hydrateMedia(root, "default");
}

function addStoryDialog() {
  state.attachments = [];
  const composer = buildComposer(async (body) => {
    await invoke("post_story", { body, media: state.attachments[0] ? state.attachments[0].ref : null, music: null });
  }, "Caption your story…");
  modal(el("div", {}, el("h2", {}, "New story"), composer));
}

function viewStory(it) {
  const inner = el("div", { class: "col", style: "align-items:center" });
  if ((it.media || []).length) { const m = it.media[0].startsWith("v:") ? el("video", { "data-ref": it.media[0], controls: "", autoplay: "" }) : el("img", { "data-ref": it.media[0], style: "max-width:100%;border-radius:12px" }); inner.append(m); }
  if (it.body) inner.append(el("p", {}, it.body));
  const m = el("div", {}, el("h2", {}, it.author_name + "'s story"), inner);
  modal(m);
  hydrateMedia(m, "default");
}

// ---- Messages --------------------------------------------------------------------------
async function renderMessages() {
  const root = $("#view-messages");
  if (state.activeDm) return renderThread(root, state.activeDm);
  const threads = await invoke("dm_threads");
  const contacts = await invoke("contacts");
  const list = el("div", { class: "thread-list" });
  for (const t of threads) {
    list.append(el("div", { class: "thread-item", onclick: () => { state.activeDm = { id: t.circle_id, name: t.name }; renderMessages(); } },
      el("div", { class: "avatar" }, initials(t.name)),
      el("div", { style: "flex:1;min-width:0" }, el("div", { class: "name" }, t.name), el("div", { class: "muted small", style: "white-space:nowrap;overflow:hidden;text-overflow:ellipsis" }, t.last_body || "No messages yet")),
      el("div", { class: "muted small" }, relTime(t.last_at)),
    ));
  }
  if (!threads.length) list.append(el("div", { class: "empty" }, "No conversations yet. Start one from a contact below."));
  const cl = el("div", { class: "col" });
  for (const c of contacts) {
    cl.append(el("div", { class: "list-item" }, el("div", { class: "avatar" }, initials(c.name)), el("div", { style: "flex:1" }, c.name),
      el("button", { class: "btn small", onclick: async () => { const id = await invoke("start_dm", { contactIdHex: c.id_hex, contactName: c.name }); state.activeDm = { id, name: c.name }; renderMessages(); } }, "Message")));
  }
  root.replaceChildren(el("div", { class: "view-head" }, el("h1", {}, "Messages")), list,
    contacts.length ? el("h3", { class: "muted" }, "Start a chat") : null, cl);
}

async function renderThread(root, dm) {
  const msgs = await invoke("messages", { circleId: dm.id });
  const chat = el("div", { class: "chat" });
  for (const m of msgs) {
    if (m.unsent) continue;
    chat.append(el("div", { class: "bubble-row" + (m.is_me ? " me" : "") },
      el("div", { class: "chat-bubble" }, m.body || "", ...(m.media || []).map((r) => r.startsWith("v:") ? el("video", { "data-ref": r, controls: "" }) : el("img", { "data-ref": r, style: "max-width:220px;border-radius:8px;display:block;margin-top:6px" })))));
  }
  const input = el("input", { placeholder: "Message…", onkeydown: async (e) => { if (e.key === "Enter" && e.target.value.trim()) { await invoke("send_dm", { circleId: dm.id, body: e.target.value.trim(), media: [] }); e.target.value = ""; } } });
  root.replaceChildren(
    el("div", { class: "view-head" }, el("button", { class: "btn small ghost", onclick: () => { state.activeDm = null; renderMessages(); } }, "← Back"), el("h1", {}, dm.name)),
    el("div", { class: "card" }, chat, el("div", { class: "chat-input" }, input, el("button", { class: "btn primary", onclick: async () => { if (input.value.trim()) { await invoke("send_dm", { circleId: dm.id, body: input.value.trim(), media: [] }); input.value = ""; } } }, "Send"))),
  );
  hydrateMedia(root, dm.id);
  chat.scrollTop = chat.scrollHeight;
}

// ---- Connect ---------------------------------------------------------------------------
async function renderConnect() {
  const root = $("#view-connect");
  const pending = await invoke("pending");
  const contacts = await invoke("contacts");

  const qrBox = el("div", { class: "qr-box" });
  try { qrBox.innerHTML = makeQrSvg(state.inviteUri); } catch (_) { qrBox.textContent = "QR unavailable"; }

  const mine = el("div", { class: "card col" },
    el("h3", {}, "Your invite"),
    el("div", { class: "muted small" }, "Have a friend scan this, or send them the link. Verify the safety code matches on both devices."),
    el("div", { class: "row", style: "align-items:flex-start" }, qrBox,
      el("div", { class: "col", style: "flex:1" },
        el("div", { class: "mono" }, state.inviteUri),
        el("div", { class: "row" },
          el("button", { class: "btn small", onclick: () => { navigator.clipboard.writeText(state.inviteUri); toast("Invite copied"); } }, "Copy haven:// link"),
          el("button", { class: "btn small", onclick: () => { navigator.clipboard.writeText(state.inviteLink); toast("Web link copied"); } }, "Copy web link"),
        ),
      ),
    ),
  );

  const linkInput = el("input", { placeholder: "Paste a haven:// or https:// invite…" });
  const add = el("div", { class: "card col" },
    el("h3", {}, "Connect a friend"),
    el("div", { class: "row" }, linkInput, el("button", { class: "btn primary", onclick: async () => { if (await invoke("connect_by_link", { uri: linkInput.value.trim() })) { toast("Invite sent — they'll appear once they accept"); linkInput.value = ""; } else toast("That doesn't look like a Haven link"); } }, "Connect")),
    el("button", { class: "btn ghost small", onclick: startScan }, "📷 Scan a QR with your camera"),
  );

  const pend = el("div", { class: "card col" }, el("h3", {}, `Requests (${pending.length})`));
  if (!pending.length) pend.append(el("div", { class: "muted small" }, "No pending requests."));
  for (const p of pending) {
    pend.append(el("div", { class: "pending-item" },
      el("div", { class: "row" }, el("div", { class: "avatar" }, initials(p.name)),
        el("div", { style: "flex:1" }, el("div", { class: "name" }, p.name), el("div", { class: "muted small mono" }, "safety: " + p.verify_hex.slice(0, 16))),
        el("button", { class: "btn small primary", onclick: async () => { await invoke("approve", { idHex: p.id_hex }); toast("Connected"); } }, "Accept"),
        el("button", { class: "btn small ghost", onclick: async () => { await invoke("dismiss", { idHex: p.id_hex }); } }, "Ignore"),
      )));
  }

  const cl = el("div", { class: "card col" }, el("h3", {}, `Contacts (${contacts.length})`));
  if (!contacts.length) cl.append(el("div", { class: "muted small" }, "No contacts yet."));
  for (const c of contacts) {
    cl.append(el("div", { class: "list-item" },
      el("div", { class: "avatar" }, initials(c.name)),
      el("div", { style: "flex:1" }, el("div", { class: "name" }, c.name), el("div", { class: "muted small mono" }, c.id_hex.slice(0, 16) + "…")),
      el("button", { class: "btn small", onclick: async () => { const id = await invoke("start_dm", { contactIdHex: c.id_hex, contactName: c.name }); state.activeDm = { id, name: c.name }; switchView("messages"); } }, "Message"),
      el("button", { class: "kebab", onclick: () => contactMenu(c) }, "⋯"),
    ));
  }

  root.replaceChildren(el("div", { class: "view-head" }, el("h1", {}, "Connect")),
    el("div", { class: "grid2" }, el("div", {}, mine, add), el("div", {}, pend, cl)));
}

function contactMenu(c) {
  modal(el("div", {}, el("h2", {}, c.name),
    el("div", { class: "col" },
      el("button", { class: "btn danger", onclick: async () => { await invoke("block", { idHex: c.id_hex }); $("#modal-root").replaceChildren(); toast("Blocked"); renderConnect(); } }, "Block " + c.name),
    )));
}

function makeQrSvg(text) {
  const qr = qrcode(0, "M");
  qr.addData(text);
  qr.make();
  return qr.createSvgTag({ cellSize: 5, margin: 2 });
}

async function startScan() {
  const video = el("video", { id: "scan-video", autoplay: "", muted: "", playsinline: "" });
  const canvas = el("canvas", { style: "display:none" });
  const status = el("div", { class: "muted small" }, "Point your camera at a Haven QR code.");
  let stream, raf;
  const close = modal(el("div", {}, el("h2", {}, "Scan QR"), video, status, canvas,
    el("div", { class: "row", style: "margin-top:10px;justify-content:flex-end" }, el("button", { class: "btn", onclick: () => stop() }, "Close"))));
  const stop = () => { if (raf) cancelAnimationFrame(raf); if (stream) stream.getTracks().forEach((t) => t.stop()); close(); };
  try {
    stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } });
    video.srcObject = stream;
    const tick = () => {
      if (video.readyState === video.HAVE_ENOUGH_DATA) {
        canvas.width = video.videoWidth; canvas.height = video.videoHeight;
        const ctx = canvas.getContext("2d");
        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
        const img = ctx.getImageData(0, 0, canvas.width, canvas.height);
        const code = window.jsQR ? window.jsQR(img.data, img.width, img.height) : null;
        if (code && code.data) {
          stop();
          invoke("connect_by_link", { uri: code.data.trim() }).then((ok) => toast(ok ? "Invite sent!" : "Not a Haven QR"));
          return;
        }
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
  } catch (e) { status.textContent = "Camera unavailable: " + e; }
}

// ---- Relay -----------------------------------------------------------------------------
async function renderRelay() {
  const root = $("#view-relay");
  const s = await invoke("relay_status");
  const adoptInput = el("input", { placeholder: "Paste a relay node id (64 hex)…" });
  const hostCard = el("div", { class: "card col" },
    el("h3", {}, "Host the relay on this PC"),
    el("div", { class: "muted small" }, "Your circle's mailbox runs here so posts and media reach friends even when you're both offline. The relay never sees your content — everything is end-to-end sealed."),
    s.hosting
      ? el("div", { class: "col" },
          el("div", { class: "ok-text" }, "● Relaying"),
          s.relay_link ? el("div", { class: "row" }, el("div", { class: "mono", style: "flex:1" }, s.relay_link), el("button", { class: "btn small", onclick: () => { navigator.clipboard.writeText(s.relay_link); toast("Relay id copied"); } }, "Copy")) : null,
          el("div", { class: "muted small" }, "Share this id with your circle so they adopt the same mailbox."),
          el("button", { class: "btn danger small", onclick: async () => { await invoke("stop_hosting"); renderRelay(); } }, "Stop hosting"),
        )
      : el("button", { class: "btn primary", onclick: async () => { try { await invoke("start_hosting"); toast("Relay started"); } catch (e) { toast("" + e); } renderRelay(); } }, "Start hosting"),
  );
  const adoptCard = el("div", { class: "card col" },
    el("h3", {}, "Use a friend's relay"),
    el("div", { class: "muted small" }, "Paste the relay node id a friend (or a standalone " + esc("haven-relay") + ") shared. " + (s.has_relay ? "A relay is currently configured." : "No relay configured yet.")),
    el("div", { class: "row" }, adoptInput, el("button", { class: "btn primary", onclick: async () => { if (adoptInput.value.trim().length === 64) { await invoke("adopt_relay", { nodeHex: adoptInput.value.trim() }); toast("Relay adopted"); adoptInput.value = ""; renderRelay(); } else toast("That's not a 64-hex node id"); } }, "Adopt")),
  );
  const headless = el("div", { class: "card col" },
    el("h3", {}, "Run headless"),
    el("div", { class: "muted small html", html: "Launch <span class='mono'>haven-desktop --headless</span> to run only the relay with no window — like a small always-on server for your circle. It prints a relay id to share." }),
  );
  root.replaceChildren(el("div", { class: "view-head" }, el("h1", {}, "Relay")), hostCard, adoptCard, headless);
}

// ---- You / Settings --------------------------------------------------------------------
async function renderYou() {
  const root = $("#view-you");
  const p = await invoke("get_profile");
  const blocked = await invoke("blocked");
  const name = el("input", { value: p.name || "", placeholder: "Display name" });
  const emoji = el("input", { value: p.emoji || "", placeholder: "Emoji (optional)", maxlength: 4, style: "width:90px" });
  const bio = el("textarea", { placeholder: "One-line bio (optional)" }); bio.value = p.bio || "";
  const link = el("input", { value: p.link || "", placeholder: "A link to show (optional)" });

  const profileCard = el("div", { class: "card col" },
    el("h3", {}, "Your profile"),
    el("div", { class: "row" }, el("div", { class: "avatar lg" }, p.emoji || initials(p.name)), el("div", { class: "col", style: "flex:1" }, el("div", { class: "row" }, name, emoji))),
    bio, link,
    el("div", { class: "muted small mono" }, "id: " + state.node),
    el("button", { class: "btn primary", onclick: async () => { await invoke("set_profile", { name: name.value.trim(), bio: bio.value.trim(), link: link.value.trim(), emoji: emoji.value.trim(), avatar: p.avatar || "" }); toast("Profile saved & shared"); } }, "Save profile"),
  );

  const security = el("div", { class: "card col" },
    el("h3", {}, "Security"),
    el("div", { class: "muted small" }, "Run the on-device hybrid post-quantum self-test (Ed25519 + ML-DSA, X25519 + ML-KEM-768)."),
    el("button", { class: "btn", onclick: async () => { const r = await invoke("self_test"); modal(el("div", {}, el("h2", {}, r.all_ok ? "✅ All checks passed" : "⚠️ Some checks failed"), el("div", { class: "col small" }, line("Identity", r.identity_ok), line("Hybrid KEM", r.hybrid_kem_ok), line("Signatures", r.signature_ok), line("Reach-me link", r.link_ok)), el("p", { class: "muted small" }, r.summary))); } }, "Run self-test"),
  );

  const blockedCard = el("div", { class: "card col" }, el("h3", {}, `Blocked (${blocked.length})`));
  if (!blocked.length) blockedCard.append(el("div", { class: "muted small" }, "No one is blocked."));
  for (const b of blocked) blockedCard.append(el("div", { class: "list-item" }, el("div", { class: "mono", style: "flex:1" }, b.slice(0, 24) + "…"), el("button", { class: "btn small", onclick: async () => { await invoke("unblock", { idHex: b }); renderYou(); } }, "Unblock")));

  const danger = el("div", { class: "card col" },
    el("h3", {}, "Start over"),
    el("div", { class: "muted small" }, "Wipe this device's identity, contacts, circles and media. This cannot be undone."),
    el("button", { class: "btn danger", onclick: () => { modal(el("div", {}, el("h2", {}, "Start over?"), el("p", {}, "This permanently deletes your identity and all local data on this PC."), el("div", { class: "row", style: "justify-content:flex-end" }, el("button", { class: "btn ghost", onclick: () => $("#modal-root").replaceChildren() }, "Cancel"), el("button", { class: "btn danger", onclick: async () => { await invoke("reset"); location.reload(); } }, "Delete everything")))); } }, "Start over"),
  );

  root.replaceChildren(el("div", { class: "view-head" }, el("h1", {}, "You")), profileCard, security, blockedCard, danger);
}

const line = (label, ok) => el("div", { class: "row" }, el("span", { style: "flex:1" }, label), el("span", { class: ok ? "ok-text" : "warn-text" }, ok ? "✓ pass" : "✗ fail"));

// ---- boot ------------------------------------------------------------------------------
async function boot() {
  $$(".nav-btn").forEach((b) => b.addEventListener("click", () => switchView(b.dataset.view)));
  try {
    const b = await invoke("bootstrap");
    state.node = b.node_id_hex;
    state.inviteUri = b.invite_uri;
    state.inviteLink = b.invite_link;
    state.profile = b.profile;
    $("#nav-node").textContent = b.node_id_hex.slice(0, 10) + "…";
  } catch (e) {
    $("#nav-node").textContent = "core error";
    toast("Backend not ready: " + e);
  }
  await refreshStatus();
  await refreshBadges();
  await render();

  // First-run nudge to set a name.
  if (!state.profile.name) switchView("you");

  listen("haven:changed", async () => { await refreshStatus(); await refreshBadges(); await render(); });
  listen("haven:notify", (e) => { const p = e.payload || {}; toast(`${p.title}: ${p.body}`); });
  setInterval(refreshStatus, 5000);

  // Tell the backend whether the window is foregrounded (suppress notifications when it is).
  invoke("set_foreground", { fg: document.hasFocus() }).catch(() => {});
  window.addEventListener("focus", () => invoke("set_foreground", { fg: true }).catch(() => {}));
  window.addEventListener("blur", () => invoke("set_foreground", { fg: false }).catch(() => {}));
}

window.addEventListener("DOMContentLoaded", boot);
