import numpy as np, trimesh, sys
sys.path.insert(0,'/tmp'); from wind import winding
rows=[l.split() for l in open('/tmp/gun_tris.txt')]
keep=('Frame','Hammer','Cylinder')
T=np.array([[float(x) for x in r[1:]] for r in rows if r[0] in keep]).reshape(-1,3,3)
c=T.mean(1); sel=(c[:,0]<0.1)&(c[:,1]<0.6); T=T[sel]; print("tris",len(T))
m=trimesh.Trimesh(vertices=T.reshape(-1,3),faces=np.arange(len(T)*3).reshape(-1,3),process=False)
xs=np.arange(-0.62,0.06,0.008); ys=np.arange(-0.10,0.56,0.008); zs=np.arange(-0.20,0.20,0.008)
G=np.stack(np.meshgrid(xs,ys,zs,indexing='ij'),-1).reshape(-1,3); print("grid",G.shape)
from scipy.spatial import cKDTree
S,fi=trimesh.sample.sample_surface_even(m,600000,radius=0.0012)
print("surface samples",len(S))
kd=cKDTree(S); dist,ix=kd.query(G,workers=-1); cp=S[ix]; nrm=m.face_normals[fi[ix]]
sgn=-np.sign(np.einsum('ij,ij->i',G-cp,nrm)); sgn[sgn==0]=1
# validate normal sign against winding on a sample near the surface
rs=np.random.default_rng(0); idx=rs.choice(np.where(dist<0.05)[0],1500,replace=False)
w=winding(T,G[idx]); ins_w=np.abs(w)>0.5; ins_n=sgn[idx]<0
print("normal-sign agrees with winding on %.1f%% of near-surface samples (inside: %d)"%(100*(ins_w==ins_n).mean(),ins_w.sum()))
sdf=(dist*sgn).reshape(len(xs),len(ys),len(zs))   # + outside, - inside
np.savez('/tmp/sdf.npz',xs=xs,ys=ys,zs=zs,sdf=sdf)
