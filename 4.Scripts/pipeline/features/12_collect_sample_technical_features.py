#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, os, platform, re, subprocess
from datetime import datetime, timezone
from pathlib import Path
import pandas as pd

def parse_args():
    p=argparse.ArgumentParser()
    p.add_argument('--sample',required=True); p.add_argument('--sample-dir',required=True)
    p.add_argument('--log-dir',required=True); p.add_argument('--r1',required=True); p.add_argument('--r2',required=True)
    p.add_argument('--input-type',required=True); p.add_argument('--sra',default='')
    p.add_argument('--checksum-mode',choices=['metadata','sha256'],default='metadata')
    p.add_argument('--out',required=True); p.add_argument('--inventory-out',required=True); p.add_argument('--versions-out',required=True)
    return p.parse_args()

def one(path):
    p=Path(path)
    if not p.is_file() or p.stat().st_size==0: return {}
    try: return pd.read_csv(p,sep='\t',low_memory=False).iloc[0].to_dict()
    except Exception: return {}

def safe(s): return re.sub(r'[^A-Za-z0-9]+','_',str(s).strip()).strip('_').lower()
def add_prefixed(row,prefix,data):
    for k,v in data.items():
        if k in {'sample','sample_id'}: continue
        row[f'{prefix}__{safe(k)}']=v

def parse_seqkit(path,prefix,row):
    p=Path(path)
    if not p.is_file(): return
    df=pd.read_csv(p,sep='\t')
    for i,r in df.iterrows():
        mate='r1' if i==0 else 'r2' if i==1 else f'file{i+1}'
        add_prefixed(row,f'{prefix}_{mate}',r.to_dict())

def parse_star(path,row):
    p=Path(path)
    if not p.is_file(): return
    for line in p.read_text(errors='replace').splitlines():
        if '|' not in line: continue
        k,v=[x.strip() for x in line.split('|',1)]
        v=v.rstrip('%').strip()
        try: val=float(v.replace(',',''))
        except ValueError: val=v
        row[f'star__{safe(k)}']=val

def parse_flagstat(path,row):
    p=Path(path)
    if not p.is_file(): return
    patterns={
      'total_reads':r'^(\d+) \+ \d+ in total', 'primary_reads':r'^(\d+) \+ \d+ primary$',
      'mapped_reads':r'^(\d+) \+ \d+ mapped', 'properly_paired_reads':r'^(\d+) \+ \d+ properly paired',
      'duplicates':r'^(\d+) \+ \d+ duplicates', 'secondary':r'^(\d+) \+ \d+ secondary',
      'supplementary':r'^(\d+) \+ \d+ supplementary'
    }
    for line in p.read_text(errors='replace').splitlines():
        for key,pat in patterns.items():
            m=re.search(pat,line)
            if m: row[f'samtools_flagstat__{key}']=int(m.group(1))

def parse_samtools_stats(path,row):
    p=Path(path)
    if not p.is_file(): return
    for line in p.read_text(errors='replace').splitlines():
        if not line.startswith('SN\t'): continue
        parts=line.split('\t')
        if len(parts)>=3:
            k=parts[1].rstrip(':'); v=parts[2]
            try: v=float(v)
            except ValueError: pass
            row[f'samtools_stats__{safe(k)}']=v

def parse_fc_summary(path,prefix,row):
    p=Path(path)
    if not p.is_file(): return
    df=pd.read_csv(p,sep='\t')
    if df.shape[1]<2:return
    valcol=df.columns[-1]
    for _,r in df.iterrows(): row[f'{prefix}__{safe(r.iloc[0])}']=float(r[valcol])

def file_info(path, checksum):
    p=Path(path); d={'path':str(p)}
    if p.exists():
        st=p.stat(); d.update(size_bytes=st.st_size,mtime=datetime.fromtimestamp(st.st_mtime,timezone.utc).isoformat())
        if checksum=='sha256' and p.is_file():
            h=hashlib.sha256()
            with p.open('rb') as fh:
                for chunk in iter(lambda:fh.read(8*1024*1024),b''): h.update(chunk)
            d['sha256']=h.hexdigest()
    return d

def command_version(cmd):
    try:
        x=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=30,check=False)
        return (x.stdout or '').splitlines()[0].strip()
    except Exception as e: return f'unavailable: {e}'

def main():
    version=os.getenv('ENDO_EXO_VERSION','unknown')
    a=parse_args(); sd=Path(a.sample_dir); q=sd/'qc'; star=sd/'03_star_grch38'
    row={'sample_id':a.sample,'input_type':a.input_type,'sra_accession':a.sra,
         'collection_time_utc':datetime.now(timezone.utc).isoformat(),'pipeline_version':version}
    add_prefixed(row,'library',one(q/f'{a.sample}.library_size.tsv'))
    parse_seqkit(q/f'{a.sample}.raw_seqkit_stats.tsv','raw_fastq',row)
    parse_seqkit(q/f'{a.sample}.processed_seqkit_stats.tsv','processed_fastq',row)
    fastp=q/f'{a.sample}.fastp.json'
    if fastp.is_file():
        d=json.loads(fastp.read_text())
        for scope in ('before_filtering','after_filtering'):
            add_prefixed(row,f'fastp_{scope}',d.get('summary',{}).get(scope,{}))
        add_prefixed(row,'fastp_filtering',d.get('filtering_result',{}))
    parse_star(star/f'{a.sample}.Log.final.out',row)
    parse_flagstat(star/f'{a.sample}.samtools.flagstat.txt',row)
    parse_samtools_stats(star/f'{a.sample}.samtools.stats.txt',row)
    parse_fc_summary(sd/'08_human_gene_expression'/f'{a.sample}.human_gene_featurecounts.tsv.summary','gene_featurecounts',row)
    parse_fc_summary(sd/'09_herv_expression'/f'{a.sample}.herv_locus_counts.tsv.summary','herv_featurecounts',row)
    parse_fc_summary(sd/'10_te_expression'/f'{a.sample}.te_locus_counts.tsv.summary','te_featurecounts',row)
    for prefix,path in [
      ('human',sd/'08_human_gene_expression'/f'{a.sample}.human_gene_overview.tsv'),
      ('herv',sd/'09_herv_expression'/f'{a.sample}.herv_expression_overview.tsv'),
      ('te',sd/'10_te_expression'/f'{a.sample}.te_expression_overview.tsv'),
      ('telescope',sd/'11_telescope'/f'{a.sample}.telescope_overview.tsv')]: add_prefixed(row,prefix,one(path))
    for label,path in [('input_r1',a.r1),('input_r2',a.r2)]: add_prefixed(row,label,file_info(path,a.checksum_mode))
    pd.DataFrame([row]).to_csv(a.out,sep='\t',index=False)

    records=[]
    for p in sorted(sd.rglob('*')):
        if p.is_file() or p.is_symlink():
            try: st=p.stat(); size=st.st_size
            except FileNotFoundError: size=0
            records.append({'sample_id':a.sample,'relative_path':str(p.relative_to(sd)),'size_bytes':size,'is_symlink':p.is_symlink(),'symlink_target':os.readlink(p) if p.is_symlink() else ''})
    pd.DataFrame(records).to_csv(a.inventory_out,sep='\t',index=False)

    versions={
      'pipeline':f'Endo-exo {version}','python':platform.python_version(),
      'STAR':command_version(['STAR','--version']),'samtools':command_version(['samtools','--version']),
      'featureCounts':command_version(['featureCounts','-v']),'fastp':command_version(['fastp','--version']),
      'seqkit':command_version(['seqkit','version']),'bowtie2':command_version(['bowtie2','--version']),
      'pandas':pd.__version__
    }
    pd.DataFrame([{'tool':k,'version':v} for k,v in versions.items()]).to_csv(a.versions_out,sep='\t',index=False)

if __name__=='__main__': main()
