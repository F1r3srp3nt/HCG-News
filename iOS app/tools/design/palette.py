#!/usr/bin/env python3
"""Edition palettes from the website OKLCH tokens, with WCAG contrast checks.
Usage: python3 palette.py out.json  (prints any contrast failures; expect none)."""
import math, json, sys
def oklch(L, C, h):
    L/=100; a=C*math.cos(math.radians(h)); b=C*math.sin(math.radians(h))
    l_=L+0.3963377774*a+0.2158037573*b; m_=L-0.1055613458*a-0.0638541728*b; s_=L-0.0894841775*a-1.2914855480*b
    l,m,s=l_**3,m_**3,s_**3
    r=4.0767416621*l-3.3077115913*m+0.2309699292*s; g=-1.2684380046*l+2.6097574011*m-0.3413193965*s; bb=-0.0041960863*l-0.7034186147*m+1.7076147010*s
    def enc(x): x=max(0,min(1,x)); return 12.92*x if x<=0.0031308 else 1.055*x**(1/2.4)-0.055
    return tuple(round(enc(v)*255) for v in (r,g,bb))
def mix(fg, bg, a): return tuple(round(f*a+b*(1-a)) for f,b in zip(fg,bg))
def lum(c):
    def lin(v): v/=255; return v/12.92 if v<=0.04045 else ((v+0.055)/1.055)**2.4
    r,g,b=(lin(x) for x in c); return 0.2126*r+0.7152*g+0.0722*b
def cr(a,b): la,lb=sorted([lum(a),lum(b)],reverse=True); return (la+0.05)/(lb+0.05)
hx=lambda c:'0x%02X%02X%02X'%c
W=(255,255,255); K=(0,0,0)

def theme(bg,surface,elevated,fg,muted,silver,sep_on,sep_a,signal,on_signal,breaking,on_breaking,warn,danger):
    return dict(background=bg,surface=surface,elevated=elevated,primaryText=fg,secondaryText=muted,silver=silver,
                separator=mix(sep_on,bg,sep_a),accent=signal,onAccent=on_signal,breaking=breaking,onBreaking=on_breaking,warning=warn,destructive=danger)
T={}
# Website (dark) tokens
fut_d=dict(bg=oklch(11.5,.003,260),surface=oklch(18,.004,260),elevated=oklch(24,.007,260),fg=oklch(95,.004,260),muted=oklch(68,.008,260),
           silver=oklch(84,.006,240),signal=oklch(81,.065,210),breaking=oklch(58,.2,27),on_breaking=oklch(98,.005,27))
T['future.dark']=theme(fut_d['bg'],fut_d['surface'],fut_d['elevated'],fut_d['fg'],fut_d['muted'],fut_d['silver'],W,.09,fut_d['signal'],oklch(16,.004,260),oklch(57,.2,27),fut_d['on_breaking'],oklch(80,.12,75),oklch(70,.15,25))
T['classic.dark']=theme(oklch(0,0,0),oklch(9,.003,260),oklch(15,.004,260),fut_d['fg'],fut_d['muted'],fut_d['silver'],W,.12,fut_d['signal'],oklch(16,.004,260),oklch(57,.2,27),fut_d['on_breaking'],oklch(80,.12,75),oklch(70,.15,25))
# Light counterparts (derived: same hues, inverted neutral scale; the website has no light mode)
T['future.light']=theme(oklch(97.5,.003,260),oklch(94,.004,260),oklch(100,0,0),oklch(17,.004,260),oklch(44,.008,260),oklch(50,.008,260),K,.10,oklch(47,.085,215),oklch(99,.002,260),oklch(52,.2,27),oklch(99,.003,27),oklch(48,.11,70),oklch(50,.19,27))
T['classic.light']=theme(oklch(100,0,0),oklch(96.5,.002,260),oklch(100,0,0),oklch(10,.002,260),oklch(40,.006,260),oklch(48,.006,260),K,.12,oklch(45,.08,215),oklch(99,.002,260),oklch(52,.2,27),oklch(99,.003,27),oklch(48,.11,70),oklch(50,.19,27))
# Increase Contrast variants
def hc(t,dark):
    t=dict(t)
    t['primaryText']=W if dark else K
    t['secondaryText']=mix(t['primaryText'],t['secondaryText'],0.45)
    t['silver']=mix(t['primaryText'],t['silver'],0.4)
    t['separator']=mix(W if dark else K,t['background'],0.30)
    t['accent']=mix(W if dark else K,t['accent'],0.30)
    return t
for k in list(T): T[k+'.hc']=hc(T[k], k.endswith('dark'))

fails=[]
for k,t in T.items():
    for txt,minr in [('primaryText',7),('secondaryText',4.5),('accent',4.5),('silver',3)]:
        for bgk in ['background','surface','elevated']:
            r=cr(t[txt],t[bgk])
            if r<minr: fails.append(f'{k}: {txt} on {bgk} = {r:.2f} < {minr}')
    for a,b,m in [('onAccent','accent',4.5),('onBreaking','breaking',4.5),('warning','background',4.5),('destructive','background',4.5)]:
        r=cr(t[a],t[b])
        if r<m: fails.append(f'{k}: {a} on {b} = {r:.2f} < {m}')
print('contrast failures:', fails or 'none')
for k,t in T.items(): print(k, {n:hx(c) for n,c in t.items()})
json.dump({k:{n:hx(c) for n,c in t.items()} for k,t in T.items()}, open(sys.argv[1],'w'), indent=1)
