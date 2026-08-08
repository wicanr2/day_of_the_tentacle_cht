import struct, subprocess, os
B='/w'; OUT='/p/voice'
os.makedirs(OUT, exist_ok=True)
ORG = 241851264   # 「這全都是你的錯，伯納。」三個版本長度 2.66/3.12/2.11 秒，塞得進分鏡
for tag, p in [('en', f'{B}/game-orig/dott/monster.sof'),
               ('tw', f'{B}/game-cht/dott/monster-tw.sof'),
               ('cl', f'{B}/game-cht/dott/monster-cl.sof')]:
    f = open(p,'rb'); isz = struct.unpack('>I', f.read(4))[0]; raw = f.read(isz)
    tbl = {}
    for i in range(isz//16):
        o,n,t,s = struct.unpack('>IIII', raw[i*16:(i+1)*16]); tbl[o]=(n,t,s)
    n,t,s = tbl[ORG]; f.seek(4+isz+n+t); d = f.read(s); f.close()
    open(f'{OUT}/{tag}.flac','wb').write(d)
    subprocess.run(['ffmpeg','-y','-v','error','-i',f'{OUT}/{tag}.flac','-ar','44100','-ac','2',
                    f'{OUT}/{tag}.wav'], check=True)
    dur = subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',
                          f'{OUT}/{tag}.wav'],capture_output=True,text=True).stdout.strip()
    print(f'{tag}  {float(dur):.2f}s')
