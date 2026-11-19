#!/usr/bin/env python3
"""Generate original, short MedTrack notification WAVs using Python stdlib only."""
from pathlib import Path
import math, struct, wave

ROOT=Path(__file__).parent/'MedTrack'/'Sounds'
ROOT.mkdir(parents=True, exist_ok=True)
RATE=22050

def render(filename, notes, duration):
    samples=[0.0]*int(RATE*duration)
    for onset, frequency, length, strength, decay in notes:
        start=round(onset*RATE)
        for idx in range(min(round(length*RATE), len(samples)-start)):
            t=idx/RATE
            env=(1-math.exp(-t*80))*math.exp(-decay*t)
            val=math.sin(2*math.pi*frequency*t)
            val+=.21*math.sin(2*math.pi*frequency*2.002*t)
            val+=.055*math.sin(2*math.pi*frequency*3.01*t)
            samples[start+idx]+=strength*val*env
    peak=max(max(abs(x) for x in samples),.001)
    scale=min(.78/peak,1.0)
    fade=max(1,int(RATE*.08))
    data=bytearray()
    for index,v in enumerate(samples):
        v*=scale*min(1.0,(len(samples)-index)/fade)
        data.extend(struct.pack('<h',int(max(-1,min(1,v))*32767)))
    dest=ROOT/filename
    with wave.open(str(dest),'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(bytes(data))
    print(f'{dest.name}: {len(data)//1024} KB')

render('airport_announcement.wav',[(.07,740,1.14,.49,2.8),(.5,560,1.3,.53,2.6)],2.2)
render('inflight_ding.wav',[(.04,1060,.85,.46,4.3),(.37,1415,.98,.49,3.9)],1.6)
render('soft_bell.wav',[(.06,615,1.55,.39,2.2)],1.75)
render('bright_alert.wav',[(.03,784,.68,.3,4.2),(.3,988,.74,.32,4.0),(.57,1175,.9,.31,3.7)],1.65)
render('calm_pulse.wav',[(.07,430,.62,.3,4.0),(.46,520,.82,.25,3.6)],1.45)
