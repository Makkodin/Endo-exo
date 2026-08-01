#!/usr/bin/env python3
"""Lossless HERV/LTR/ERV locus quantification and class/family/repeat-name summaries."""
from __future__ import annotations
import argparse
from pathlib import Path
import pandas as pd

def parse_args():
    p=argparse.ArgumentParser()
    p.add_argument('--sample',required=True); p.add_argument('--counts',required=True)
    p.add_argument('--metadata',required=True); p.add_argument('--library-size',required=True)
    p.add_argument('--out-dir',required=True); p.add_argument('--min-count',type=float,default=1.0)
    return p.parse_args()

def read_counts(path):
    d=pd.read_csv(path,sep='\t',comment='#',low_memory=False); c=d.columns[-1]
    x=d[['Geneid','Chr','Start','End','Strand','Length',c]].copy().rename(columns={'Geneid':'locus_id',c:'count'})
    x['count']=pd.to_numeric(x['count'],errors='coerce').fillna(0.0)
    x['Length']=pd.to_numeric(x['Length'],errors='coerce').fillna(0.0)
    return x

def summarize(d,keys):
    return (d.groupby(keys,dropna=False).agg(
        n_loci=('locus_id','count'), n_expressed_loci=('is_expressed','sum'),
        total_count=('count','sum'), total_cpm=('cpm','sum'),
        total_tpm=('tpm_herv_space','sum'), total_rpm_library=('rpm_library','sum'),
        max_locus_count=('count','max'), max_locus_cpm=('cpm','max'),
        max_locus_tpm=('tpm_herv_space','max'), max_locus_rpm_library=('rpm_library','max'),
    ).reset_index().sort_values(['total_count','n_expressed_loci'],ascending=[False,False]))

def main():
    a=parse_args(); out=Path(a.out_dir); out.mkdir(parents=True,exist_ok=True)
    d=read_counts(a.counts)
    meta=pd.read_csv(a.metadata,sep='\t',low_memory=False)
    if meta['locus_id'].astype(str).duplicated().any():
        raise SystemExit('ERROR: duplicate locus_id in HERV metadata')
    d=d.merge(meta,on='locus_id',how='left',suffixes=('','_meta'),validate='one_to_one')
    for c in ['repeat_name','repeat_class','repeat_family']:
        if c not in d:d[c]='Unknown'
        d[c]=d[c].fillna('Unknown').astype(str)
    lib=pd.read_csv(a.library_size,sep='\t').iloc[0]
    pairs=float(lib.get('library_read_pairs_after_qc',0) or 0)
    total=float(d['count'].sum())
    d['cpm']=d['count']/total*1e6 if total else 0.0
    rate=d['count']/d['Length'].replace(0,pd.NA)
    denom=float(rate.sum(skipna=True)); d['tpm_herv_space']=(rate/denom*1e6).fillna(0.0) if denom else 0.0
    length_kb=d['Length'].replace(0,pd.NA)/1000
    million=total/1e6 if total else pd.NA
    d['rpkm_herv_space']=(d['count']/length_kb/million).fillna(0.0)
    d['rpm_library']=d['count']/pairs*1e6 if pairs else 0.0
    d['is_expressed']=d['count']>=a.min_count
    cols=['locus_id','Chr','Start','End','Strand','Length','count','cpm','tpm_herv_space','rpkm_herv_space','rpm_library','is_expressed',
          'repeat_name','repeat_class','repeat_family','chrom','start','end','length_bp','strand','swScore','milliDiv']
    for c in cols:
        if c not in d:d[c]=''
    norm=d[cols].sort_values(['count','cpm','locus_id'],ascending=[False,False,True])
    norm.to_csv(out/f'{a.sample}.herv_locus_counts.normalized.tsv',sep='\t',index=False)
    cls=summarize(d,['repeat_class']); fam=summarize(d,['repeat_class','repeat_family']); name=summarize(d,['repeat_class','repeat_family','repeat_name'])
    cls.to_csv(out/f'{a.sample}.herv_repeat_class_summary.tsv',sep='\t',index=False)
    fam.to_csv(out/f'{a.sample}.herv_repeat_family_summary.tsv',sep='\t',index=False)
    name.to_csv(out/f'{a.sample}.herv_repeat_name_summary.tsv',sep='\t',index=False)
    pd.DataFrame([{
      'sample_id':a.sample,'n_herv_loci_total':len(d),'n_herv_loci_count_gt0':int((d['count']>0).sum()),
      'n_herv_loci_count_ge_min':int(d['is_expressed'].sum()),'total_herv_fractional_count':total,
      'total_herv_rpm_library':float(d['rpm_library'].sum()),'top_repeat_class':cls.iloc[0]['repeat_class'] if len(cls) else '',
      'top_repeat_family':fam.iloc[0]['repeat_family'] if len(fam) else '',
      'top_repeat_name':name.iloc[0]['repeat_name'] if len(name) else '',
      'top_repeat_name_count':float(name.iloc[0]['total_count']) if len(name) else 0,
      'featurecounts_space_cpm_sum':float(d['cpm'].sum()),'featurecounts_space_tpm_sum':float(d['tpm_herv_space'].sum())
    }]).to_csv(out/f'{a.sample}.herv_expression_overview.tsv',sep='\t',index=False)

if __name__=='__main__':main()
