#!/usr/bin/env python3
"""Lossless RepeatMasker TE locus quantification and class/family/repeat-name summaries."""
import argparse
from pathlib import Path
import pandas as pd

TRACK_CLASSES=['LTR','LINE','SINE','DNA','Simple_repeat','Satellite','Low_complexity','RNA','RC','Unknown','Other']

def parse_args():
    p=argparse.ArgumentParser(); p.add_argument('--sample',required=True); p.add_argument('--counts',required=True)
    p.add_argument('--metadata',required=True); p.add_argument('--library-size',required=True); p.add_argument('--out-dir',required=True)
    p.add_argument('--gene-overlap',default=''); p.add_argument('--min-count',type=float,default=1.0); return p.parse_args()

def read_counts(path):
    d=pd.read_csv(path,sep='\t',comment='#',low_memory=False); c=d.columns[-1]
    x=d[['Geneid','Chr','Start','End','Strand','Length',c]].copy().rename(columns={'Geneid':'locus_id',c:'count'})
    x['count']=pd.to_numeric(x['count'],errors='coerce').fillna(0.0); x['Length']=pd.to_numeric(x['Length'],errors='coerce').fillna(0.0); return x

def summarize(d,keys):
    return (d.groupby(keys,dropna=False).agg(
      n_loci=('locus_id','count'), n_expressed_loci=('is_expressed','sum'), total_count=('count','sum'),
      total_cpm=('cpm_te_space','sum'), total_tpm=('tpm_te_space','sum'), total_rpm_library=('rpm_library','sum'),
      max_locus_count=('count','max'), max_locus_cpm=('cpm_te_space','max'), max_locus_tpm=('tpm_te_space','max'),
      max_locus_rpm_library=('rpm_library','max')
    ).reset_index().sort_values(['total_count','n_expressed_loci'],ascending=[False,False]))

def main():
    a=parse_args(); out=Path(a.out_dir); out.mkdir(parents=True,exist_ok=True)
    d=read_counts(a.counts); meta=pd.read_csv(a.metadata,sep='\t',low_memory=False)
    if meta['locus_id'].astype(str).duplicated().any():raise SystemExit('ERROR: duplicate locus_id in TE metadata')
    d=d.merge(meta,on='locus_id',how='left',suffixes=('','_meta'),validate='one_to_one')
    overlap=Path(a.gene_overlap) if a.gene_overlap else None
    if overlap and overlap.is_file() and overlap.stat().st_size:
        o=pd.read_csv(overlap,sep='\t',low_memory=False); keep=[c for c in ['locus_id','overlaps_gene','n_overlapping_genes','overlapping_genes'] if c in o]
        d=d.merge(o[keep].drop_duplicates('locus_id'),on='locus_id',how='left',validate='one_to_one')
    for c,default in [('overlaps_gene','unknown'),('n_overlapping_genes',''),('overlapping_genes','')]:
        if c not in d:d[c]=default
    for c in ['te_class_group','repeat_class','repeat_family','repeat_name']:
        if c not in d:d[c]='Unknown'
        d[c]=d[c].fillna('Unknown').astype(str)
    if 'is_herv_ltr_erv_like' not in d:d['is_herv_ltr_erv_like']=False
    lib=pd.read_csv(a.library_size,sep='\t').iloc[0]; pairs=float(lib.get('library_read_pairs_after_qc',0) or 0)
    total=float(d['count'].sum()); d['cpm_te_space']=d['count']/total*1e6 if total else 0.0
    rate=d['count']/d['Length'].replace(0,pd.NA); denom=float(rate.sum(skipna=True)); d['tpm_te_space']=(rate/denom*1e6).fillna(0.0) if denom else 0.0
    length_kb=d['Length'].replace(0,pd.NA)/1000; million=total/1e6 if total else pd.NA
    d['rpkm_te_space']=(d['count']/length_kb/million).fillna(0.0); d['rpm_library']=d['count']/pairs*1e6 if pairs else 0.0
    d['is_expressed']=d['count']>=a.min_count
    cols=['locus_id','Chr','Start','End','Strand','Length','count','cpm_te_space','tpm_te_space','rpkm_te_space','rpm_library','is_expressed',
          'repeat_name','repeat_class','te_class_group','repeat_family','is_herv_ltr_erv_like','chrom','start','end','length_bp','strand',
          'overlaps_gene','n_overlapping_genes','overlapping_genes','swScore','milliDiv']
    for c in cols:
        if c not in d:d[c]=''
    norm=d[cols].sort_values(['count','cpm_te_space','locus_id'],ascending=[False,False,True])
    norm.to_csv(out/f'{a.sample}.te_locus_counts.normalized.tsv',sep='\t',index=False)
    cls=summarize(d,['te_class_group']); fam=summarize(d,['te_class_group','repeat_class','repeat_family']); name=summarize(d,['te_class_group','repeat_class','repeat_family','repeat_name'])
    cls.to_csv(out/f'{a.sample}.te_repeat_class_summary.tsv',sep='\t',index=False)
    fam.to_csv(out/f'{a.sample}.te_repeat_family_summary.tsv',sep='\t',index=False)
    name.to_csv(out/f'{a.sample}.te_repeat_name_summary.tsv',sep='\t',index=False)
    norm[['locus_id','te_class_group','repeat_name','repeat_family','overlaps_gene','n_overlapping_genes','overlapping_genes']].to_csv(out/f'{a.sample}.te_locus_annotation_flags.tsv',sep='\t',index=False)
    row={'sample_id':a.sample,'n_te_loci_total':len(d),'n_te_loci_count_gt0':int((d['count']>0).sum()),'n_te_loci_count_ge_min':int(d['is_expressed'].sum()),
         'te_total_fractional_count':total,'total_te_rpm_library':float(d['rpm_library'].sum()),'te_top_class':cls.iloc[0]['te_class_group'] if len(cls) else '',
         'te_top_family':fam.iloc[0]['repeat_family'] if len(fam) else '','te_top_repeat_name':name.iloc[0]['repeat_name'] if len(name) else '',
         'featurecounts_space_cpm_sum':float(d['cpm_te_space'].sum()),'featurecounts_space_tpm_sum':float(d['tpm_te_space'].sum())}
    for group in TRACK_CLASSES:
        key=group.lower(); part=cls[cls['te_class_group']==group]; row[f'{key}_total_fractional_count']=float(part['total_count'].sum()) if len(part) else 0
    pd.DataFrame([row]).to_csv(out/f'{a.sample}.te_expression_overview.tsv',sep='\t',index=False)

if __name__=='__main__':main()
