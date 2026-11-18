import numpy as np, collections, sys
def load_gun(parts_wanted=('Frame',)):
    rows=[l.split() for l in open('/tmp/gun_tris.txt')]
    T=np.array([[float(x) for x in r[1:]] for r in rows if r[0] in parts_wanted]).reshape(-1,3,3)
    return T
def winding(T,P,chunk=400):
    w=np.zeros(len(P))
    for i in range(0,len(P),chunk):
        p=P[i:i+chunk][:,None,:]
        a=T[None,:,0]-p; b=T[None,:,1]-p; c=T[None,:,2]-p
        la=np.linalg.norm(a,axis=2); lb=np.linalg.norm(b,axis=2); lc=np.linalg.norm(c,axis=2)
        det=np.einsum('ijk,ijk->ij',a,np.cross(b,c))
        den=la*lb*lc+np.einsum('ijk,ijk->ij',a,b)*lc+np.einsum('ijk,ijk->ij',b,c)*la+np.einsum('ijk,ijk->ij',c,a)*lb
        w[i:i+chunk]=2*np.arctan2(det,den).sum(1)/(4*np.pi)
    return w
if __name__=='__main__':
    T=load_gun()
    h=[l.split() for l in open('/tmp/hand_verts.txt')]
    names=np.array([x[0] for x in h]); P=np.array([[float(y) for y in x[1:]] for x in h])
    near=(P[:,0]>-0.6)&(P[:,0]<0.1)&(P[:,1]>-0.05)&(P[:,1]<0.5)&(np.abs(P[:,2])<0.12)
    w=np.zeros(len(P)); w[near]=winding(T,P[near])
    ins=np.abs(w)>0.5
    print("frame winding sanity: centre of grip", winding(T,np.array([[-0.38,0.2,0.0],[-0.38,0.2,0.3]])).round(2))
    for b in sorted(set(names)):
        k=names==b
        if not k.any(): continue
        print(f"{b:12s} inside {int((ins&k).sum()):5d}/{int(k.sum()):5d}  centroid {P[k].mean(0).round(3)}")
    np.save('/tmp/inside.npy',ins)
