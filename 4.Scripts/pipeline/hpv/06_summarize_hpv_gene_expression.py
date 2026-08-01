#!/usr/bin/env python3
"""Normalize HPV featureCounts genes without using clinical metadata."""
import argparse,re
from pathlib import Path
import pandas as pd

def attrs(x):return dict(re.findall(r'(\S+)\s+"([^"]*)"',str(x)))
def main():
    p=argparse.ArgumentParser(); p.add_argument('--sample',required=True); p.add_argument('--counts',required=True); p.add_argument('--gtf',required=True); p.add_argument('--library-size',required=True); p.add_argument('--out-dir',required=True); a=p.parse_args()
    out=Path(a.out_dir); out.mkdir(parents=True,exist_ok=True)
    d=pd.read_csv(a.counts,sep='\t',comment='#',low_memory=False); c=d.columns[-1]
    x=d[['Geneid','Chr','Start','End','Strand','Length',c]].copy().rename(columns={'Geneid':'gene_id',c:'count'})
    x['count']=pd.to_numeric(x['count'],errors='coerce').fillna(0.0); x['Length']=pd.to_numeric(x['Length'],errors='coerce').fillna(0.0)
    meta=[]
    with open(a.gtf,encoding='utf-8',errors='replace') as fh:
        for line in fh:
            if not line or line.startswith('#'):continue
            z=line.rstrip('\n').split('\t')
            if len(z)!=9 or z[2] not in {'gene','CDS'}:continue
            at=attrs(z[8]); gid=at.get('gene_id','')
            if gid:meta.append({'gene_id':gid,'hpv_gene_name':at.get('gene_name',at.get('Name','')),'hpv_reference':z[0],'feature_type':z[2]})
    if meta:
        m=pd.DataFrame(meta).drop_duplicates('gene_id'); x=x.merge(m,on='gene_id',how='left')
    lib=pd.read_csv(a.library_size,sep='\t').iloc[0]; pairs=float(lib.get('library_read_pairs_after_qc',0) or 0)
    total=float(x['count'].sum()); x['cpm_hpv_space']=x['count']/total*1e6 if total else 0.0
    rate=x['count']/x['Length'].replace(0,pd.NA); denom=float(rate.sum(skipna=True)); x['tpm_hpv_space']=(rate/denom*1e6).fillna(0.0) if denom else 0.0
    length_kb=x['Length'].replace(0,pd.NA)/1000; million=total/1e6 if total else pd.NA
    x['rpkm_hpv_space']=(x['count']/length_kb/million).fillna(0.0); x['rpm_library']=x['count']/pairs*1e6 if pairs else 0.0
    cols=['gene_id','hpv_gene_name','hpv_reference','feature_type','Chr','Start','End','Strand','Length','count','cpm_hpv_space','tpm_hpv_space','rpkm_hpv_space','rpm_library']
    for col in cols:
        if col not in x:x[col]=''
    x[cols].sort_values(['count','gene_id'],ascending=[False,True]).to_csv(out/f'{a.sample}.hpv_gene_counts.normalized.tsv',sep='\t',index=False)
    pd.DataFrame([{'sample_id':a.sample,'n_hpv_gene_features':len(x),'n_hpv_gene_features_count_gt0':int((x['count']>0).sum()),'total_hpv_gene_fractional_count':total,
                   'total_hpv_gene_rpm_library':float(x['rpm_library'].sum()),'hpv_space_cpm_sum':float(x['cpm_hpv_space'].sum()),'hpv_space_tpm_sum':float(x['tpm_hpv_space'].sum())}]).to_csv(out/f'{a.sample}.hpv_gene_overview.tsv',sep='\t',index=False)
if __name__=='__main__':main()
