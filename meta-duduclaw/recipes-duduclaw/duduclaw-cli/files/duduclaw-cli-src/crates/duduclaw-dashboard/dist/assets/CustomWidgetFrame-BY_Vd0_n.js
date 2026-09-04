import{n as e}from"./chunk-CaILmz35.js";import{Cn as t,Fn as n,Zn as r,ga as i,ma as a,pa as o,vn as s,wn as c,yn as l}from"./index-3-LYRpGv.js";var u=e(i(),1),d=10,f={"agents.summary":async()=>({agents:(await r.agents.list()).agents.map(e=>({name:e.name,display_name:e.display_name,role:e.role,department:e.department??``,archived:!!e.archived}))}),"tasks.summary":async()=>{let e=await r.tasks.list(),t={},n=new Date,i=e=>{if(!e)return!1;let t=new Date(e);return t.getFullYear()===n.getFullYear()&&t.getMonth()===n.getMonth()&&t.getDate()===n.getDate()};for(let n of e.tasks)t[n.status]=(t[n.status]??0)+1;return{total:e.tasks.length,by_status:t,completed_today:e.tasks.filter(e=>i(e.completed_at)).length,recent:e.tasks.slice(0,10).map(e=>({id:e.id,title:e.title,status:e.status,assignee:e.assigned_to||``,completed_at:e.completed_at??null}))}},"cost.summary":()=>r.cost.summary(24),"channels.status":async()=>({channels:(await r.channels.status()).channels.map(e=>({channel:e.name,connected:e.connected}))}),"system.status":()=>r.system.status()},p=15e3,m=new Map;function h(e,t){let n=Date.now(),r=m.get(e);if(r&&n-r.at<p)return r.promise;let i=t().catch(t=>{throw m.delete(e),t});return m.set(e,{at:n,promise:i}),i}async function g(e,t){if(e.type!==`duduclaw:rpc`)return null;let n=Date.now();for(;t.length>0&&n-t[0]>1e3;)t.shift();if(t.length>=d)return{seq:e.seq,ok:!1,error:`rate limit exceeded (10 req/s)`};t.push(n);let r=f[e.method];if(!r)return{seq:e.seq,ok:!1,error:`method '${e.method}' is not allowed`};try{let t=await h(e.method,r);return{seq:e.seq,ok:!0,result:t}}catch(t){return{seq:e.seq,ok:!1,error:t instanceof Error?t.message:String(t)}}}var _=`default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src data:`,v=`
(function () {
  var seq = 0, pending = {}, themeCbs = [], theme = null;
  window.duduclaw = {
    call: function (method, params) {
      return new Promise(function (resolve, reject) {
        var id = ++seq;
        pending[id] = { resolve: resolve, reject: reject };
        parent.postMessage({ type: 'duduclaw:rpc', seq: id, method: method, params: params || {} }, '*');
        setTimeout(function () {
          if (pending[id]) { delete pending[id]; reject(new Error('duduclaw.call timeout')); }
        }, 15000);
      });
    },
    onTheme: function (cb) { themeCbs.push(cb); if (theme) cb(theme); },
  };
  window.addEventListener('message', function (e) {
    var d = e.data || {};
    if (d.type === 'duduclaw:rpc:result' && pending[d.seq]) {
      var p = pending[d.seq]; delete pending[d.seq];
      d.ok ? p.resolve(d.result) : p.reject(new Error(d.error || 'bridge error'));
    } else if (d.type === 'duduclaw:theme') {
      theme = d.mode;
      document.documentElement.setAttribute('data-theme', d.mode);
      themeCbs.forEach(function (cb) { cb(d.mode); });
    }
  });
  var report = function () {
    parent.postMessage({ type: 'duduclaw:resize', height: document.documentElement.scrollHeight }, '*');
  };
  new ResizeObserver(report).observe(document.documentElement);
  window.addEventListener('load', report);
})();
`,y=`
:root { color-scheme: light; --bg: transparent; --fg: #1c1917; --muted: #78716c; --accent: #f59e0b; --card: #fafaf9; --border: #e7e5e4; }
:root[data-theme="dark"] { color-scheme: dark; --fg: #fafaf9; --muted: #a8a29e; --card: #292524; --border: #44403c; }
html, body { margin: 0; padding: 0; background: var(--bg); color: var(--fg);
  font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif; font-size: 14px; line-height: 1.6; }
`;function b(e,t){return[`<!doctype html><html data-theme="`+t+`"><head><meta charset="utf-8">`,`<meta http-equiv="Content-Security-Policy" content="${_}">`,`<style>${y}</style>`,`<script>${v}<\/script>`,`</head><body>`,e,`</body></html>`].join(`
`)}var x=a();function S(e){return e===`dark`?`dark`:e===`light`?`light`:typeof window<`u`&&window.matchMedia(`(prefers-color-scheme: dark)`).matches?`dark`:`light`}var C=80,w=800;function T({widgetId:e,html:i,title:a,headerAction:d}){let f=o(),p=S(n(e=>e.theme)),m=(0,u.useRef)(null),h=(0,u.useRef)([]),[_,v]=(0,u.useState)(null),[y,T]=(0,u.useState)(null),[E,D]=(0,u.useState)(160);(0,u.useEffect)(()=>{if(!e)return;let t=!0;return r.widgetsCustom.get(e).then(e=>t&&v({html:e.html,title:e.title})).catch(e=>t&&T(e instanceof Error?e.message:String(e))),()=>{t=!1}},[e]);let O=i??_?.html??null,k=(0,u.useMemo)(()=>O===null?null:b(O,p),[O]);(0,u.useEffect)(()=>{let e=e=>{let t=m.current;if(!t||e.source!==t.contentWindow)return;let n=e.data;if(n?.type===`duduclaw:resize`&&typeof n.height==`number`){D(Math.max(C,Math.min(w,Math.ceil(n.height))));return}g(n,h.current).then(e=>{e&&t.contentWindow&&t.contentWindow.postMessage({type:`duduclaw:rpc:result`,...e},`*`)})};return window.addEventListener(`message`,e),()=>window.removeEventListener(`message`,e)},[]),(0,u.useEffect)(()=>{m.current?.contentWindow?.postMessage({type:`duduclaw:theme`,mode:p},`*`)},[p]);let A=a??_?.title;return(0,x.jsxs)(s,{className:`gap-0 py-0`,children:[(A||d)&&(0,x.jsxs)(t,{className:`pt-3 pb-2`,children:[(0,x.jsx)(c,{className:`truncate text-sm`,children:A}),d&&(0,x.jsx)(l,{children:d})]}),y?(0,x.jsx)(`p`,{className:`px-4 py-3 text-sm text-muted-foreground`,children:f.formatMessage({id:`widgets.frame.loadError`})}):k===null?(0,x.jsx)(`div`,{className:`h-24 animate-pulse`}):(0,x.jsx)(`iframe`,{ref:m,sandbox:`allow-scripts`,srcDoc:k,title:A??`custom widget`,className:`block w-full border-0`,style:{height:E}})]})}export{T as t};