"""HTML content templates for the safety portal and trusted-contact self-removal portal."""

_PORTAL_PAGE_HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Nexus Meetup Safety</title>
<style>
  :root {
    --safety-blue: #0284C7;
    --safety-teal: #0D9488;
  }
  * { box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: #0F172A;
    color: #F1F5F9;
    margin: 0;
    min-height: 100vh;
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding: 32px 16px;
  }
  .card {
    width: 100%;
    max-width: 440px;
    background: rgba(255,255,255,0.04);
    border: 1px solid rgba(255,255,255,0.08);
    border-radius: 16px;
    padding: 28px 24px;
  }
  h1 {
    font-size: 20px;
    margin: 0 0 4px;
    background: linear-gradient(90deg, var(--safety-blue), var(--safety-teal));
    -webkit-background-clip: text;
    background-clip: text;
    -webkit-text-fill-color: transparent;
  }
  .subtitle { color: #94A3B8; font-size: 14px; margin: 0 0 24px; }
  label { display: block; font-size: 13px; color: #CBD5E1; margin-bottom: 6px; }
  input {
    width: 100%;
    background: rgba(255,255,255,0.06);
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 10px;
    padding: 12px 14px;
    color: #F1F5F9;
    font-size: 16px;
    margin-bottom: 12px;
  }
  input:focus {
    outline: none;
    border-color: var(--safety-teal);
    box-shadow: 0 0 0 3px rgba(13,148,136,0.25);
  }
  button {
    width: 100%;
    border: none;
    border-radius: 10px;
    padding: 13px 14px;
    font-size: 15px;
    font-weight: 600;
    color: white;
    background: linear-gradient(90deg, var(--safety-blue), var(--safety-teal));
    cursor: pointer;
  }
  button:disabled { opacity: 0.5; cursor: not-allowed; }
  .link-btn {
    background: none;
    color: #94A3B8;
    font-weight: 400;
    font-size: 13px;
    width: auto;
    padding: 8px 0;
  }
  .error { color: #F87171; font-size: 13px; margin: -4px 0 12px; min-height: 16px; }
  .step { display: none; }
  .step.active { display: block; }
  .detail-row {
    border-bottom: 1px solid rgba(255,255,255,0.06);
    padding: 14px 0;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .detail-row:last-child { border: none; }
  .detail-row .label { color: #94A3B8; font-size: 13px; }
  .detail-row .value { font-weight: 500; font-size: 14px; }
  .detail-row .value a { color: #38BDF8; text-decoration: none; }
  .pill {
    display: inline-block;
    background: rgba(13,148,136,0.15);
    color: #2DD4BF;
    border: 1px solid rgba(13,148,136,0.3);
    padding: 4px 10px;
    border-radius: 9999px;
    font-size: 12px;
    font-weight: 500;
    margin-bottom: 20px;
  }
  .evidence-item {
    background: rgba(255,255,255,0.02);
    border: 1px solid rgba(255,255,255,0.06);
    border-radius: 12px;
    padding: 16px;
    margin-top: 12px;
  }
  .evidence-item .meta { font-size: 12px; color: #94A3B8; margin-bottom: 12px; }
  .evidence-item button { padding: 8px 12px; font-size: 13px; width: auto; }
  .evidence-item video, .evidence-item audio { width: 100%; display: block; margin-top: 8px; border-radius: 8px; }
</style>
</head>
<body>
  <div class="card">
    <h1>Meetup Safety Portal</h1>
    <p class="subtitle" id="subtitle">
      Verify your phone number to access safety status, live location, and evidence.
    </p>

    <div class="step active" id="step-phone">
      <label for="phone-input">Your phone number</label>
      <input id="phone-input" type="tel" placeholder="+91 98765 43210" autocomplete="tel">
      <div class="error" id="phone-error"></div>
      <button id="send-code-btn">Send code</button>
    </div>

    <div class="step" id="step-otp">
      <label for="otp-input">6-digit code</label>
      <input id="otp-input" type="tel" inputmode="numeric" maxlength="6" placeholder="000000">
      <div class="error" id="otp-error"></div>
      <button id="verify-code-btn">Verify</button>
      <button class="link-btn" id="resend-btn">Resend code</button>
    </div>

    <div class="step" id="step-details">
      <div id="details-content"></div>
    </div>
  </div>

<script>
(function () {
  var sessionId = window.location.pathname.split('/').filter(Boolean).pop();
  var apiBase = '/api/v1/safety/portal/' + sessionId;
  var phone = '';
  var portalToken = '';

  function show(stepId) {
    document.querySelectorAll('.step').forEach(function (el) {
      el.classList.toggle('active', el.id === stepId);
    });
  }

  function setError(elId, message) {
    document.getElementById(elId).textContent = message || '';
  }

  function base64ToBytes(base64) {
    var binString = atob(base64);
    var len = binString.length;
    var bytes = new Uint8Array(len);
    for (var i = 0; i < len; i++) {
      bytes[i] = binString.charCodeAt(i);
    }
    return bytes;
  }

  document.getElementById('send-code-btn').addEventListener('click', function () {
    phone = document.getElementById('phone-input').value.trim();
    setError('phone-error', '');
    if (phone.length < 6) {
      setError('phone-error', 'Enter a valid phone number.');
      return;
    }
    this.disabled = true;
    var btn = this;
    fetch(apiBase + '/otp/request', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: phone }),
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Failed to send code.'); });
        show('step-otp');
      })
      .catch(function (e) { setError('phone-error', e.message); })
      .finally(function () { btn.disabled = false; });
  });

  document.getElementById('resend-btn').addEventListener('click', function () {
    setError('otp-error', '');
    fetch(apiBase + '/otp/request', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: phone }),
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Could not resend code.'); });
        setError('otp-error', 'A new code was sent.');
      })
      .catch(function (e) { setError('otp-error', e.message); });
  });

  document.getElementById('verify-code-btn').addEventListener('click', function () {
    var code = document.getElementById('otp-input').value.trim();
    setError('otp-error', '');
    if (code.length < 4) {
      setError('otp-error', 'Enter the code you were texted.');
      return;
    }
    this.disabled = true;
    var btn = this;
    fetch(apiBase + '/otp/verify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: phone, code: code }),
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Verification failed.'); });
        return res.json();
      })
      .then(function (data) {
        portalToken = data.token;
        return loadDetails();
      })
      .catch(function (e) { setError('otp-error', e.message); })
      .finally(function () { btn.disabled = false; });
  });

  function loadDetails() {
    return fetch(apiBase + '/details', {
      headers: { 'Authorization': 'Bearer ' + portalToken },
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Could not load details.'); });
        return res.json();
      })
      .then(renderDetails);
  }

  function renderDetails(data) {
    var html = '';
    html += '<span class="pill">' + (data.status === 'active' ? 'Check-in active' : 'Check-in ended') + '</span>';
    html += '<div class="detail-row"><div class="label">Meetup</div><div class="value">' +
      escapeHtml(data.event_label || data.label || 'Not specified') + '</div></div>';
    if (data.last_location) {
      var mapsUrl = 'https://maps.google.com/?q=' + data.last_location.lat + ',' + data.last_location.lng;
      html += '<div class="detail-row"><div class="label">Last known location</div><div class="value">' +
        '<a href="' + mapsUrl + '" target="_blank" rel="noopener">Open in Maps</a></div></div>';
    } else {
      html += '<div class="detail-row"><div class="label">Last known location</div><div class="value">Not reported</div></div>';
    }

    if (data.evidence && data.evidence.length) {
      html += '<div class="detail-row"><div class="label">Evidence (' + data.evidence.length + ')</div></div>';
    }
    document.getElementById('details-content').innerHTML = html;

    (data.evidence || []).forEach(function (item, idx) {
      var wrap = document.createElement('div');
      wrap.className = 'evidence-item';
      var meta = document.createElement('div');
      meta.className = 'meta';
      meta.textContent = (item.content_type === 'video' ? 'Video' : 'Audio') +
        (item.duration_seconds ? ' · ' + Math.round(item.duration_seconds) + 's' : '');
      var btn = document.createElement('button');
      btn.textContent = 'Decrypt & play';
      btn.addEventListener('click', function () { decryptAndPlay(item, wrap, btn); });
      wrap.appendChild(meta);
      wrap.appendChild(btn);
      document.getElementById('details-content').appendChild(wrap);
    });

    show('step-details');
  }

  function escapeHtml(s) {
    var div = document.createElement('div');
    div.textContent = s;
    return div.innerHTML;
  }

  function decryptAndPlay(item, container, button) {
    button.disabled = true;
    button.textContent = 'Decrypting...';
    fetch(item.download_url)
      .then(function (res) { return res.arrayBuffer(); })
      .then(function (buf) {
        var bytes = new Uint8Array(buf);
        var nonce = bytes.slice(0, 12);
        var ciphertextAndTag = bytes.slice(12);
        return crypto.subtle.importKey('raw', base64ToBytes(item.media_key_base64), 'AES-GCM', false, ['decrypt'])
          .then(function (key) {
            return crypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce }, key, ciphertextAndTag);
          });
      })
      .then(function (plaintext) {
        var mime = item.content_type === 'video' ? 'video/mp4' : 'audio/mp4';
        var blob = new Blob([plaintext], { type: mime });
        var url = URL.createObjectURL(blob);
        var el = document.createElement(item.content_type === 'video' ? 'video' : 'audio');
        el.src = url;
        el.controls = true;
        button.remove();
        container.appendChild(el);
      })
      .catch(function () {
        button.disabled = false;
        button.textContent = 'Failed to decrypt - try again';
      });
  }
})();
</script>
</body>
</html>"""

_CONTACT_PORTAL_PAGE_HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Nexus Meetup Safety</title>
<style>
  :root {
    --safety-blue: #0284C7;
    --safety-teal: #0D9488;
    --safety-red: #DC2626;
  }
  * { box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: #0F172A;
    color: #F1F5F9;
    margin: 0;
    min-height: 100vh;
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding: 32px 16px;
  }
  .card {
    width: 100%;
    max-width: 440px;
    background: rgba(255,255,255,0.04);
    border: 1px solid rgba(255,255,255,0.08);
    border-radius: 16px;
    padding: 28px 24px;
  }
  h1 {
    font-size: 20px;
    margin: 0 0 4px;
    background: linear-gradient(90deg, var(--safety-blue), var(--safety-teal));
    -webkit-background-clip: text;
    background-clip: text;
    -webkit-text-fill-color: transparent;
  }
  .subtitle { color: #94A3B8; font-size: 14px; margin: 0 0 24px; }
  label { display: block; font-size: 13px; color: #CBD5E1; margin-bottom: 6px; }
  input {
    width: 100%;
    background: rgba(255,255,255,0.06);
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 10px;
    padding: 12px 14px;
    color: #F1F5F9;
    font-size: 16px;
    margin-bottom: 12px;
  }
  input:focus {
    outline: none;
    border-color: var(--safety-teal);
    box-shadow: 0 0 0 3px rgba(13,148,136,0.25);
  }
  button {
    width: 100%;
    border: none;
    border-radius: 10px;
    padding: 13px 14px;
    font-size: 15px;
    font-weight: 600;
    color: white;
    background: linear-gradient(90deg, var(--safety-blue), var(--safety-teal));
    cursor: pointer;
  }
  button.danger { background: var(--safety-red); }
  button:disabled { opacity: 0.5; cursor: not-allowed; }
  .link-btn {
    background: none;
    color: #94A3B8;
    font-weight: 400;
    font-size: 13px;
    width: auto;
    padding: 8px 0;
  }
  .error { color: #F87171; font-size: 13px; margin: -4px 0 12px; min-height: 16px; }
  .step { display: none; }
  .step.active { display: block; }
  .avatar {
    width: 72px; height: 72px; border-radius: 50%; object-fit: cover;
    display: block; margin: 0 auto 16px; border: 2px solid rgba(255,255,255,0.12);
  }
  .detail-row { margin-bottom: 16px; text-align: center; }
  .detail-row .label { font-size: 12px; color: #94A3B8; margin-bottom: 2px; }
  .detail-row .value { font-size: 16px; font-weight: 600; }
  .fine-print { font-size: 12px; color: #64748B; line-height: 1.5; margin: 16px 0; }
</style>
</head>
<body>
  <div class="card">
    <h1>Nexus Meetup Safety</h1>
    <p class="subtitle" id="subtitle">
      Someone listed you as a trusted contact. Verify your phone number to
      manage this.
    </p>

    <div class="step active" id="step-phone">
      <label for="phone-input">Your phone number</label>
      <input id="phone-input" type="tel" placeholder="+91 98765 43210" autocomplete="tel">
      <div class="error" id="phone-error"></div>
      <button id="send-code-btn">Send code</button>
    </div>

    <div class="step" id="step-otp">
      <label for="otp-input">6-digit code</label>
      <input id="otp-input" type="tel" inputmode="numeric" maxlength="6" placeholder="000000">
      <div class="error" id="otp-error"></div>
      <button id="verify-code-btn">Verify</button>
      <button class="link-btn" id="resend-btn">Resend code</button>
    </div>

    <div class="step" id="step-details">
      <div id="details-content"></div>
      <button class="danger" id="remove-btn">Remove me as a trusted contact</button>
      <p class="fine-print">
        This stops all future check-in and SOS texts from Nexus on this
        person's behalf, and can't be undone from here.
      </p>
    </div>

    <div class="step" id="step-removed">
      <p style="text-align:center; color: #5EEAD4;">
        You've been removed. You won't receive any more messages from
        Nexus about this person.
      </p>
    </div>
  </div>

<script>
(function () {
  var contactId = window.location.pathname.split('/').filter(Boolean).pop();
  var apiBase = '/api/v1/safety/contact/' + contactId;
  var phone = '';
  var portalToken = '';

  function show(stepId) {
    document.querySelectorAll('.step').forEach(function (el) {
      el.classList.toggle('active', el.id === stepId);
    });
  }

  function setError(elId, message) {
    document.getElementById(elId).textContent = message || '';
  }

  function escapeHtml(s) {
    var div = document.createElement('div');
    div.textContent = s;
    return div.innerHTML;
  }

  document.getElementById('send-code-btn').addEventListener('click', function () {
    phone = document.getElementById('phone-input').value.trim();
    setError('phone-error', '');
    if (phone.length < 6) {
      setError('phone-error', 'Enter a valid phone number.');
      return;
    }
    this.disabled = true;
    var btn = this;
    fetch(apiBase + '/otp/request', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: phone }),
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Failed to send code.'); });
        show('step-otp');
      })
      .catch(function (e) { setError('phone-error', e.message); })
      .finally(function () { btn.disabled = false; });
  });

  document.getElementById('resend-btn').addEventListener('click', function () {
    setError('otp-error', '');
    fetch(apiBase + '/otp/request', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: phone }),
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Could not resend code.'); });
        setError('otp-error', 'A new code was sent.');
      })
      .catch(function (e) { setError('otp-error', e.message); });
  });

  document.getElementById('verify-code-btn').addEventListener('click', function () {
    var code = document.getElementById('otp-input').value.trim();
    setError('otp-error', '');
    if (code.length < 4) {
      setError('otp-error', 'Enter the code you were texted.');
      return;
    }
    this.disabled = true;
    var btn = this;
    fetch(apiBase + '/otp/verify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: phone, code: code }),
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Verification failed.'); });
        return res.json();
      })
      .then(function (data) {
        portalToken = data.token;
        return loadDetails();
      })
      .catch(function (e) { setError('otp-error', e.message); })
      .finally(function () { btn.disabled = false; });
  });

  function loadDetails() {
    return fetch(apiBase + '/details', {
      headers: { 'Authorization': 'Bearer ' + portalToken },
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Could not load details.'); });
        return res.json();
      })
      .then(renderDetails);
  }

  function renderDetails(data) {
    var html = '';
    if (data.profile_pic) {
      html += '<img class="avatar" src="' + data.profile_pic + '" alt="">';
    }
    html += '<div class="detail-row"><div class="label">Listed you as their trusted contact</div><div class="value">' +
      escapeHtml(data.user_name) + '</div></div>';
    if (data.hometown || data.current_place) {
      html += '<div class="detail-row"><div class="label">From / based in</div><div class="value">' +
        escapeHtml([data.hometown, data.current_place].filter(Boolean).join(' · ')) + '</div></div>';
    }
    document.getElementById('details-content').innerHTML = html;
    show('step-details');
  }

  document.getElementById('remove-btn').addEventListener('click', function () {
    this.disabled = true;
    var btn = this;
    fetch(apiBase + '/remove', {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + portalToken },
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Could not remove you.'); });
        show('step-removed');
      })
      .catch(function () {
        btn.disabled = false;
      });
  });
})();
</script>
</body>
</html>"""
