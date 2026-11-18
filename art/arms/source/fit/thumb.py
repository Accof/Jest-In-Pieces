import sys, json; sys.path.insert(0,'/tmp'); from handfk import *
SH=np.eye(4); SH[2,3]=0.01
root=SH@B['hand.R']['G']
cands=[]
for x1 in range(-20,61,5):
  for z1 in range(-40,41,8):
    for c2 in range(-10,61,10):
      for c3 in range(0,61,10):
        pose={'thumb_01':(x1,0,z1),'thumb_02':(c2,0,0),'thumb_03':(c3,0,0)}
        Gs=chain_G('thumb',pose,root)
        m=[SDF((Gs[n]@LOCAL[n])[:3].T).min() for n in Gs if n in LOCAL]
        if max(0,-min(m))>0.0035: continue
        tipz=Gs['thumb_03.R'][2,3]
        gap=sum(max(0,x-0.004)**2 for x in m[1:])
        cands.append((gap,(x1,z1,c2,c3),m,tipz))
cands.sort(key=lambda c:c[0])
for g,c,m,tz in cands[:5]: print(c,[round(x*29,2) for x in m],'tip z %.3f'%tz)
json.dump(dict(thumb=cands[0][1]),open('/tmp/thumb.json','w'))
