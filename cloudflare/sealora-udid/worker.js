import * as asn1js from 'asn1js';
import * as pkijs from 'pkijs';

const BASE = 'https://udid.nextjailbreak.com';
const TTL = 900;
const SESSION = /^[A-Za-z0-9_-]{40,55}$/;
const UDID = /^[A-Za-z0-9-]{16,80}$/;
const HEADERS = {
  'Cache-Control': 'no-store, max-age=0',
  'Referrer-Policy': 'no-referrer',
  'X-Content-Type-Options': 'nosniff',
  'X-Robots-Tag': 'noindex, nofollow',
};

const escapeXML = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const response = (body, status = 200, extras = {}) =>
  new Response(body, { status, headers: { ...HEADERS, ...extras } });
const json = (obj, status = 200) => response(JSON.stringify(obj), status, { 'Content-Type': 'application/json; charset=utf-8' });
const escapeHTML = escapeXML;

function profileXML(session) {
  const uuid = crypto.randomUUID().toUpperCase();
  // Profile Service is Apple's specified top-level payload; request ONLY UDID.
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>PayloadType</key><string>Profile Service</string>
<key>PayloadVersion</key><integer>1</integer>
<key>PayloadIdentifier</key><string>com.nextsolution.sealora.udid.profile-service</string>
<key>PayloadUUID</key><string>${uuid}</string>
<key>PayloadDisplayName</key><string>Sealora — One-Time UDID Request</string>
<key>PayloadOrganization</key><string>Next Jailbreak</string>
<key>PayloadDescription</key><string>One-time voluntary request for this device's UDID only. Your signing credentials and IPA files are not requested or uploaded. The profile can be removed after use.</string>
<key>PayloadContent</key><dict>
<key>URL</key><string>${escapeXML(`${BASE}/callback?session=${session}`)}</string>
<key>Challenge</key><string>${escapeXML(session)}</string>
<key>DeviceAttributes</key><array><string>UDID</string></array>
</dict></dict></plist>`;
}

function completionProfile() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>PayloadType</key><string>Configuration</string>
<key>PayloadVersion</key><integer>1</integer>
<key>PayloadIdentifier</key><string>com.nextsolution.sealora.udid.response</string>
<key>PayloadUUID</key><string>${crypto.randomUUID().toUpperCase()}</string>
<key>PayloadDisplayName</key><string>Sealora UDID Request Completed</string>
<key>PayloadOrganization</key><string>Next Jailbreak</string>
<key>PayloadDescription</key><string>One-time UDID collection finished. No management or restrictions installed.</string>
<key>PayloadContent</key><array/>
</dict></plist>`;
}

function html(session) {
  const clean = escapeHTML(session);
  return `<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer"><title>Sealora · Device UDID</title>
<style>
:root{color-scheme:light dark}*{box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;background:#edf1ff;color:#132044;line-height:1.5;margin:0;padding:38px 16px}.panel{max-width:530px;margin:0 auto;padding:30px;border-radius:24px;background:#fff;box-shadow:0 18px 56px #23338920}.tag{font-weight:700;color:#4e45d6}.button{display:block;text-align:center;padding:15px 20px;border-radius:14px;background:linear-gradient(115deg,#306af6,#7843db);color:white;text-decoration:none;font-weight:700;margin-top:20px}.note{color:#4a5771;font-size:.92rem}h1{font-size:1.9rem;margin:12px 0}li{margin:9px 0}.ready{display:none}.pill{padding:12px;border-radius:12px;background:#edf5ff;margin:20px 0;color:#2559ad}
@media(prefers-color-scheme:dark){body{background:#0c0b21;color:#f3f4ff}.panel{background:#211f37;box-shadow:none}.note{color:#bac0dd}.pill{background:#293251;color:#b0cfff}}
</style></head><body><main class="panel"><div class="tag">NEXT JAILBREAK · SEALORA</div>
<h1>Get this device’s UDID</h1><p>Apple requires your consent. This profile requests <strong>only the UDID</strong>.</p>
<ol><li>Tap <strong>Download One-Time Profile</strong> and allow the download in Safari.</li>
<li>Open <strong>Settings → Profile Downloaded</strong> (or General → VPN &amp; Device Management).</li>
<li>Review the profile and tap <strong>Install</strong>.</li>
<li>Return to this Safari page; it will show <strong>Return to Sealora</strong> when the UDID arrives.</li></ol>
<a class="button" href="/mobileconfig?session=${clean}">Download One-Time Profile</a>
<div id="state" class="pill" aria-live="polite">Waiting for profile approval…</div>
<div id="ready" class="ready"><a class="button" href="sealora://udid?session=${clean}">Return to Sealora and Save UDID</a></div>
<p class="note">A short-lived random session associates this request with your app. The UDID is kept only temporarily to return it to Sealora; it is not used for analytics or device tracking. Delete the downloaded profile in Settings after completion. You can use manual UDID entry instead.</p>
<p class="note"><a href="https://nextjailbreak.com" rel="noopener noreferrer">Next Jailbreak</a> · Zeeshan0727</p></main>
<script>
const token=${JSON.stringify(session)};let complete=false;
async function check(){if(complete)return;try{const r=await fetch('/status?session='+encodeURIComponent(token),{cache:'no-store'});const j=await r.json();if(j.ready){complete=true;document.getElementById('ready').style.display='block';document.getElementById('state').textContent='UDID received. Tap Return to Sealora.';}else if(!r.ok){document.getElementById('state').textContent='This session has expired. Return to Sealora to begin again.';}}catch(_){document.getElementById('state').textContent='Waiting for the device response…';}}
}check();setInterval(check,2500);document.addEventListener('visibilitychange',()=>{if(!document.hidden)check();});
</script></body></html>`;
}

function plistValue(xml, key) {
  const safeKey = key.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
  const pattern = new RegExp(`<key>\\s*${safeKey}\\s*</key>\\s*<(string|data)>\\s*([^<]+?)\\s*</\\1>`);
  const m = pattern.exec(xml);
  if (!m) return null;
  if(m[1] !== 'data')return m[2].trim();
  try {return atob(m[2].replace(/\s+/g,''))} catch {return null}
}

async function parseVerifiedDeviceResponse(body) {
  // The response must be a cryptographically valid CMS SignedData message.
  // Signature validation is not equivalent to Apple trust-chain validation.
  const asn = asn1js.fromBER(body);
  if(asn.offset === -1)throw new Error('Invalid CMS format');
  const wrapper = new pkijs.ContentInfo({ schema: asn.result });
  if(wrapper.contentType !== pkijs.ContentInfo.SIGNED_DATA)throw new Error('Unsigned device response');
  const signed = new pkijs.SignedData({ schema: wrapper.content });
  if(signed.signerInfos.length !== 1 || signed.certificates.length === 0)throw new Error('Invalid CMS signer');
  const valid = await signed.verify({signer:0, checkChain:false});
  if(!valid)throw new Error('Invalid CMS signature');
  const content = signed.encapContentInfo.eContent;
  if(!content)throw new Error('Missing signed device attributes');
  const buffer = content.getValue();
  const xml = new TextDecoder().decode(buffer);
  if(!xml.includes('<plist') || xml.length > 32768)throw new Error('Invalid signed payload');
  return {udid:plistValue(xml,'UDID'),challenge:plistValue(xml,'CHALLENGE')};
}

function allowedSession(url) {
  const session = url.searchParams.get('session') || '';
  return SESSION.test(session) ? session : null;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if(url.hostname !== 'udid.nextjailbreak.com')return response('Not found',404);
    const s = allowedSession(url);
    if (url.pathname === '/' || url.pathname === '/health')return json({service:'Sealora UDID',ready:true,version:'1.0.3'});
    if(!s)return json({error:'Invalid session token'},400);
    const key = `udid:${s}`;
    try {
      if(url.pathname === '/start' && request.method === 'GET'){
        if(!await env.SESSIONS.get(key))await env.SESSIONS.put(key,JSON.stringify({status:'pending'}),{expirationTtl:TTL});
        return response(html(s),200,{'Content-Type':'text/html; charset=utf-8'});
      }
      if(url.pathname === '/mobileconfig' && request.method === 'GET'){
        if(!await env.SESSIONS.get(key))return json({error:'Session expired'},410);
        return response(profileXML(s),200,{
          'Content-Type':'application/x-apple-aspen-config',
          'Content-Disposition':'attachment; filename="Sealora-UDID.mobileconfig"'
        });
      }
      if(url.pathname === '/callback' && request.method === 'POST'){
        const item = await env.SESSIONS.get(key);
        if(!item)return json({error:'Session expired'},410);
        const length = Number(request.headers.get('content-length') || 0);
        if(length > 262144)return json({error:'Request too large'},413);
        const raw = await request.arrayBuffer();
        if(raw.byteLength > 262144)return json({error:'Request too large'},413);
        const {udid,challenge} = await parseVerifiedDeviceResponse(raw);
        if(challenge !== s || !udid || !UDID.test(udid))return json({error:'Invalid device details'},422);
        await env.SESSIONS.put(key,JSON.stringify({status:'ready',udid}),{expirationTtl:TTL});
        return response(completionProfile(),200,{'Content-Type':'application/x-apple-aspen-config'});
      }
      if(url.pathname === '/status' && request.method === 'GET'){
        const record = await env.SESSIONS.get(key);
        if(!record)return json({error:'Expired'},410);
        return json({ready:JSON.parse(record).status === 'ready'});
      }
      if(url.pathname === '/result' && request.method === 'GET'){
        const record = await env.SESSIONS.get(key);
        if(!record)return json({error:'Expired'},410);
        const value = JSON.parse(record);
        if(value.status !== 'ready')return json({error:'Pending approval'},409);
        await env.SESSIONS.delete(key);
        return json({udid:value.udid});
      }
      return response('Not found',404);
    } catch(error) {
      // Never log or echo the bearer token or device identifier.
      return json({error:'Unable to complete request'},400);
    }
  }
};