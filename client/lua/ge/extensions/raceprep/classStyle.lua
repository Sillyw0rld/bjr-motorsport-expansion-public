-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Class colours and badges for the car rating (Forza Motorsport style:
-- a coloured class block next to the PI number).
--  * imgui windows (Race Prep, standings tower): coloured class letter + PI
--  * BeamNG's vehicle selector (Vue UI): a small script restyles tile names
--    ending in "[C 478]" into a coloured badge. It only adds its own elements
--    and attributes; if it is not running, the plain "[C 478]" text remains.
local Text, TooltipText = require("ge/extensions/raceprep/safeText").Text, require("ge/extensions/raceprep/safeText").TooltipText

local S = {}

-- class -> {background hex, text hex}
S.COLORS = {
    E = { "#8a96a3", "#ffffff" },
    D = { "#22b2e6", "#ffffff" },
    C = { "#f2c014", "#1a1a1a" },
    B = { "#f5841f", "#ffffff" },
    A = { "#e5333b", "#ffffff" },
    S = { "#9a4fe0", "#ffffff" },
    R = { "#2f63e6", "#ffffff" },
    P = { "#e33fa1", "#ffffff" },
    X = { "#36c24a", "#ffffff" },
}

local function hexToVec(hex)
    local r, g, b = hex:match("#(%x%x)(%x%x)(%x%x)")
    local vec = rawget(_G, "ImVec4")
    if not r or not vec then
        return nil
    end
    return vec(tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, 1)
end

local vecCache = {}
S.color = function(class)
    if vecCache[class] == nil then
        local c = S.COLORS[class]
        vecCache[class] = c and hexToVec(c[1]) or false
    end
    return vecCache[class] or nil
end

--- draw "C 478" with the class letter in its colour (imgui, current line)
S.drawBadge = function(entry, numberColor)
    if not entry or not entry.class then
        Text("--", { color = BJI.Utils.Style.TEXT_COLORS.DISABLED })
        return
    end
    Text(entry.class, { color = S.color(entry.class) })
    SameLine()
    Text(tostring(entry.pi or "?"), { color = numberColor or BJI.Utils.Style.TEXT_COLORS.DEFAULT })
end

-- selector badge script (Chromium embedded UI); idempotent
local cachedJS
local function js()
    if cachedJS then return cachedJS end
    local colors = {}
    for class, c in pairs(S.COLORS) do
        colors[#colors + 1] = string.format("%s:['%s','%s']", class, c[1], c[2])
    end
    cachedJS = [=[
(function(){try{
if(window.__raceprepBadges)return;window.__raceprepBadges=1;
var C={]=] .. table.concat(colors, ",") .. [=[};
var st=document.createElement('style');st.id='raceprep-badge-style';
st.textContent='.rp-badged{font-size:0!important}.rp-badged::before{content:attr(data-rp-name);font-size:var(--rp-fs,1em)}'+
'.rp-badge{display:inline-flex;align-items:stretch;flex:none;margin-left:.45em;border-radius:.3em;overflow:hidden;font-weight:800;'+
'line-height:1.35;font-size:.92em;vertical-align:middle;box-shadow:0 0 0 1.5px var(--rp-c),0 1px 3px rgba(0,0,0,.45)}'+
'.rp-badge .c{padding:0 .38em;letter-spacing:.02em}.rp-badge .p{background:#fff;color:#111;padding:0 .42em;font-variant-numeric:tabular-nums}';
document.head.appendChild(st);
var RE=/^\s*([\s\S]*?)\s*\[([EDCBASRPX]) (\d{1,3})\]\s*$/;
function apply(el,m){var nb=el.nextElementSibling;var has=nb&&nb.classList&&nb.classList.contains('rp-badge');
if(!el.classList.contains('rp-badged')){el.style.setProperty('--rp-fs',getComputedStyle(el).fontSize);el.classList.add('rp-badged');}
if(el.getAttribute('data-rp-name')!==m[1])el.setAttribute('data-rp-name',m[1]);
var key=m[2]+m[3];
if(!has){nb=document.createElement('span');nb.className='rp-badge';el.parentNode.insertBefore(nb,el.nextSibling);}
if(nb.getAttribute('data-k')!==key){var c=C[m[2]]||['#888','#fff'];nb.setAttribute('data-k',key);nb.style.setProperty('--rp-c',c[0]);
nb.innerHTML='<span class="c" style="background:'+c[0]+';color:'+c[1]+'">'+m[2]+'</span><span class="p">'+m[3]+'</span>';}}
function checkBadged(el){var m=RE.exec(el.textContent||'');if(!m){el.classList.remove('rp-badged');el.removeAttribute('data-rp-name');
var nb=el.nextElementSibling;if(nb&&nb.classList.contains('rp-badge'))nb.remove();}else apply(el,m);}
function scan(root){if(!root||!root.isConnected||root.closest&&root.closest('#raceprep-bjr-root,.rp-badge'))return;
if(root.classList&&root.classList.contains('rp-badged')){checkBadged(root);return;}
if((root.textContent||'').indexOf('[')<0)return;
var w=document.createTreeWalker(root,NodeFilter.SHOW_TEXT,{acceptNode:function(n){
return (n.nodeValue.indexOf('[')>=0&&RE.test(n.nodeValue))?NodeFilter.FILTER_ACCEPT:NodeFilter.FILTER_SKIP;}});
var hits=[];while(w.nextNode())hits.push(w.currentNode);
for(var j=0;j<hits.length;j++){var el2=hits[j].parentElement;if(!el2||el2.childNodes.length!==1||el2.closest('#raceprep-bjr-root,.rp-badge')||el2.classList.contains('rp-badged'))continue;
apply(el2,RE.exec(hits[j].nodeValue));}}
var queue=[],pending=false;
function enqueue(n){if(!n)return;var el=n.nodeType===3?n.parentElement:n.nodeType===1?n:null;
if(!el||el.closest&&el.closest('#raceprep-bjr-root,.rp-badge'))return;
if(el.classList&&el.classList.contains('rp-badged')||(el.textContent||'').indexOf('[')>=0){if(queue.indexOf(el)<0)queue.push(el);}}
new MutationObserver(function(ms){for(var i=0;i<ms.length;i++){var m=ms[i];
if(m.type==='characterData'){var p=m.target.parentElement;if(p&&(p.classList&&p.classList.contains('rp-badged')||(m.target.nodeValue||'').indexOf('[')>=0))enqueue(p);}
else{if(m.target&&m.target.classList&&m.target.classList.contains('rp-badged'))enqueue(m.target);
for(var k=0;k<m.addedNodes.length;k++)enqueue(m.addedNodes[k]);}}
if(!pending&&queue.length){pending=true;setTimeout(function(){pending=false;var batch=queue;queue=[];
try{var done=document.querySelectorAll('.rp-badged');for(var d=0;d<done.length;d++)checkBadged(done[d]);
for(var b=0;b<batch.length;b++)scan(batch[b]);}catch(e){}},250);}}).observe(document.body,{childList:true,subtree:true,characterData:true});
scan(document.body);}catch(e){}})();
]=]
    return cachedJS
end

--- inject (or re-inject after a UI reload) the selector badge script
S.injectSelectorBadges = function()
    if be and be.executeJS then
        pcall(be.executeJS, be, js())
    end
end

return S
