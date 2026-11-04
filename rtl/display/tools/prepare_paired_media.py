"""Copy same-name BMP/WAV pairs into portable 8.3 names; resample 44.1k PCM.

Original files are never overwritten. NumPy is needed only for 44.1k input.
"""
from pathlib import Path
import argparse,hashlib,json,shutil,struct,wave

def resample_44100(samples):
 import numpy as np
 n=(len(samples)*160+146)//147
 result=np.empty((n,2),dtype=np.int16)
 offsets=np.arange(-15,17)
 fraction=np.arange(160,dtype=np.float64)[:,None]/160
 distance=offsets[None,:]-fraction
 weights=np.sinc(distance)*np.where(abs(distance)<16,.5+.5*np.cos(np.pi*distance/16),0)
 weights=(weights/weights.sum(axis=1,keepdims=True)).astype(np.float32)
 for start in range(0,n,131072):
  end=min(start+131072,n);positions=np.arange(start,end,dtype=np.int64)*147
  base=positions//160;phase=positions%160;acc=np.zeros((end-start,2),dtype=np.float32)
  for k,delta in enumerate(offsets):
   source=samples[np.clip(base+delta,0,len(samples)-1)]
   acc+=source*weights[phase,k,None]
  result[start:end]=np.clip(np.rint(acc),-32768,32767).astype(np.int16)
 return result

def main():
 p=argparse.ArgumentParser();p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 a.output.mkdir(parents=True,exist_ok=True);report=[]
 images=sorted(a.input.glob('*.bmp'))
 friendly={'军事':'MILITARY','救灾':'RESCUE','睡眠':'SLEEP','音乐':'MUSIC'}
 for n,image in enumerate(images,1):
  wav=image.with_suffix('.wav');assert wav.is_file(),'Missing matching WAV: '+str(wav)
  name=friendly.get(image.stem,f'PAIR{n:04d}')
  outbmp=a.output/(name+'.BMP');outwav=a.output/(name+'.WAV')
  assert not outbmp.exists() and not outwav.exists(),'Do not overwrite output files'
  shutil.copy2(image,outbmp)
  with wave.open(str(wav),'rb')as f:
   assert f.getnchannels()==2 and f.getsampwidth()==2 and f.getcomptype()=='NONE'
   rate=f.getframerate();frames=f.getnframes()
   if rate==44100:
    import numpy as np
    source=np.frombuffer(f.readframes(frames),dtype='<i2').reshape(-1,2)
    converted=resample_44100(source)
    with wave.open(str(outwav),'wb')as g:
     g.setnchannels(2);g.setsampwidth(2);g.setframerate(48000);g.writeframes(converted.astype('<i2',copy=False).tobytes())
   else:assert rate==48000
  if rate==48000:shutil.copy2(wav,outwav)
  with wave.open(str(outwav),'rb')as f:
   assert f.getframerate()==48000 and f.getnchannels()==2 and f.getsampwidth()==2
   seconds=f.getnframes()/48000
   assert abs(seconds-frames/rate)<1/48000
  row={'original':image.stem,'bmp':outbmp.name,'wav':outwav.name,'source_rate':rate,'output_rate':48000,'seconds':seconds,
       'bmp_sha256':hashlib.sha256(outbmp.read_bytes()).hexdigest(),'wav_sha256':hashlib.sha256(outwav.read_bytes()).hexdigest()}
  report.append(row);print(json.dumps(row,ensure_ascii=False),flush=True)
 (a.output/'PAIRS.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
if __name__=='__main__':main()
