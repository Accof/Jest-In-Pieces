import sys; sys.path.insert(0,'/tmp'); from handfk import *
SH=np.eye(4); SH[2,3]=0.01
root=SH@B['hand.R']['G']
TOL=0.0035
def seg_min(f,pose):
    Gs=chain_G(f,pose,root); return [SDF((Gs[n]@LOCAL[n])[:3].T).min() for n in Gs if n in LOCAL]
out={}
for f in ('middle','ring','little'):
    cands=[]
    for c1 in range(0,101,4):
        for c2 in range(0,111,5):
            for k in (0.45,0.6,0.75,0.9):
                c3=round(c2*k); pose={f'{f}_01':(c1,0,0),f'{f}_02':(c2,0,0),f'{f}_03':(c3,0,0)}
                m=seg_min(f,pose); pen=max(0,-min(m))
                if pen>TOL: continue
                gap=sum(max(0,x-0.004)**2 for x in m)
                cands.append((gap,(c1,c2,c3),m))
    cands.sort(key=lambda c:c[0])
    print(f)
    for g,c,m in cands[:4]: print(f"   {c}  segment gaps (cm) {[round(x*29,2) for x in m]}")
    out[f]=cands[0][1]
import json; json.dump(out,open('/tmp/fingers.json','w'))
