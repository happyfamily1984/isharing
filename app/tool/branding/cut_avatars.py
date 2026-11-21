import sys, os
from PIL import Image
from collections import deque
src, outdir = sys.argv[1], sys.argv[2]
im=Image.open(src).convert('RGB')
tiles=[(58,623,174,734)]
rows=[623,748,868,987,1105,1216,1322,1427,1529]
cols=[(58,174),(190,307),(322,439),(454,571),(586,702),(717,833)]
boxes='''190 623 307 734;321 623 439 734;453 623 571 734;586 623 702 734;716 623 833 735;58 748 174 855;191 748 308 855;322 748 439 855;454 748 571 855;586 748 702 855;717 748 833 855;58 868 174 974;192 868 309 974;324 868 441 974;455 868 572 974;586 868 703 974;717 868 833 974;58 987 174 1092;192 987 309 1092;324 987 441 1093;456 987 573 1092;587 987 703 1092;717 987 833 1092;58 1105 174 1207;192 1105 309 1207;324 1105 441 1207;456 1105 573 1207;586 1105 703 1207;717 1105 833 1207;58 1216 175 1312;192 1216 309 1312;325 1216 441 1312;457 1216 573 1312;587 1216 703 1312;717 1216 833 1312;58 1322 175 1419;192 1322 308 1419;324 1322 441 1419;456 1322 573 1419;587 1322 703 1419;717 1322 833 1419;58 1427 174 1521;190 1427 307 1521;324 1427 440 1521;456 1427 573 1521;587 1427 703 1521;717 1427 833 1521;58 1529 174 1622;189 1529 307 1622;324 1529 439 1622;456 1529 573 1622;587 1529 703 1622;717 1529 832 1622'''
tiles+= [tuple(map(int,b.split())) for b in boxes.split(';')]

def dist(a,b): return max(abs(a[0]-b[0]),abs(a[1]-b[1]),abs(a[2]-b[2]))

def cutout(crop, inset, T=26):
    w,h=crop.size
    px=crop.load()
    out=Image.new('RGBA',(w,h)); op=out.load()
    for y in range(h):
        for x in range(w): op[x,y]=px[x,y]+(255,)
    # 칸 테두리 안쪽에서 배경색 표본
    seeds=[(x,inset) for x in range(inset,w-inset)]+[(inset,y) for y in range(inset,h-inset)]+[(w-1-inset,y) for y in range(inset,h-inset)]
    bgref=sorted((px[s] for s in seeds), key=lambda c:sum(c))[len(seeds)//2]
    removed=[[False]*w for _ in range(h)]
    q=deque()
    for s in seeds:
        if dist(px[s],bgref)<=T: q.append(s); removed[s[1]][s[0]]=True
    # 테두리 바깥(inset 바깥)은 모두 지운다
    for y in range(h):
        for x in range(w):
            if x<inset or y<inset or x>=w-inset or (y>=h-inset and False):
                removed[y][x]=True
            # 칸의 둥근 모서리 바깥(화면 배경)도 지운다
            R=26
            for cx,cy in ((inset+R,inset+R),(w-1-inset-R,inset+R),(inset+R,h-1-inset-R),(w-1-inset-R,h-1-inset-R)):
                if ((x<cx)==(cx<w/2)) and ((y<cy)==(cy<h/2)) and (x-cx)**2+(y-cy)**2>R*R:
                    removed[y][x]=True
    while q:
        x,y=q.popleft()
        for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
            a,b=x+dx,y+dy
            if 0<=a<w and 0<=b<h and not removed[b][a] and dist(px[a,b],bgref)<=T:
                removed[b][a]=True; q.append((a,b))
    for y in range(h):
        for x in range(w):
            if removed[y][x]: op[x,y]=(0,0,0,0)
            else:
                # 경계의 섞인 픽셀은 반투명하게
                near=any(0<=x+dx<w and 0<=y+dy<h and removed[y+dy][x+dx] for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)))
                if near:
                    d=dist(px[x,y],bgref)
                    if d<70: op[x,y]=px[x,y]+(int(255*min(1,(d-T)/(70-T)+0.25)),)
    return out

os.makedirs(outdir,exist_ok=True)
for i,(x0,y0,x1,y1) in enumerate(tiles):
    crop=im.crop((x0,y0,x1+1,y1+1))
    a=cutout(crop, 5 if i==0 else 3, 10 if i+1 in (34,35,36,46,48) else 26)
    bb=a.getbbox()
    a=a.crop(bb)
    side=max(a.size)
    sq=Image.new('RGBA',(side,side),(0,0,0,0))
    sq.paste(a,((side-a.width)//2,(side-a.height)//2))
    sq.resize((160,160),Image.LANCZOS).save(f'{outdir}/c{i+1:02d}.png')
print(len(tiles))
