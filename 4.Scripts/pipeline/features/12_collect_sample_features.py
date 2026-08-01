#!/usr/bin/env python3
from __future__ import annotations
import argparse
from pathlib import Path
import pandas as pd

def args():
    p=argparse.ArgumentParser(); p.add_argument('--sample',required=True); p.add_argument('--sample-dir',required=True); p.add_argument('--technical',required=True); p.add_argument('--out',required=True); return p.parse_args()
def one(path):
    p=Path(path)
    if not p.is_file() or p.stat().st_size==0:return {}
    try:return pd.read_csv(p,sep='\t',low_memory=False).iloc[0].to_dict()
    except Exception:return {}
def add(row,prefix,d):
    for k,v in d.items():
        if k in {'sample','sample_id'}:continue
        row[f'{prefix}__{k}']=v

def main():
    a=args(); sd=Path(a.sample_dir); row={'sample_id':a.sample}
    add(row,'technical',one(a.technical))
    add(row,'human_gene',one(sd/'08_human_gene_expression'/f'{a.sample}.human_gene_overview.tsv'))
    hpv=sd/'05_hpv_calling'/f'{a.sample}.hpv_final_status.tsv'
    if hpv.is_file() and hpv.stat().st_size:
        d=pd.read_csv(hpv,sep='\t',low_memory=False)
        if not d.empty:
            add(row,'hpv_top',d.iloc[0].to_dict())
            for col in ['mapped_reads','covered_bases','covered_blocks','max_depth','E6_count','E7_count','E1_count']:
                if col in d: row[f'hpv_all__sum_{col}']=pd.to_numeric(d[col],errors='coerce').fillna(0).sum()
            row['hpv_all__n_viruses_with_mapped_reads']=int((pd.to_numeric(d.get('mapped_reads',0),errors='coerce').fillna(0)>0).sum())
    integ=sd/'07_hpv_integration'/f'{a.sample}.hpv_integration_loci.annotated.tsv'
    if integ.is_file() and integ.stat().st_size:
        d=pd.read_csv(integ,sep='\t',low_memory=False)
        row['integration__n_loci']=len(d)
        for col in ['total_supporting_reads','supporting_reads','n_breakpoints']:
            if col in d:
                x=pd.to_numeric(d[col],errors='coerce').fillna(0)
                row[f'integration__sum_{col}']=x.sum(); row[f'integration__max_{col}']=x.max() if len(x) else 0
        if not d.empty:
            sort='total_supporting_reads' if 'total_supporting_reads' in d else 'supporting_reads' if 'supporting_reads' in d else None
            top=d.sort_values(sort,ascending=False).iloc[0] if sort else d.iloc[0]
            for col in ['hpv_type','human_chr','human_cluster_start','human_cluster_end','overlapping_genes','nearest_gene','nearest_gene_distance','integration_locus_confidence']:
                if col in top: row[f'integration_top__{col}']=top[col]
    add(row,'herv',one(sd/'09_herv_expression'/f'{a.sample}.herv_expression_overview.tsv'))
    add(row,'te',one(sd/'10_te_expression'/f'{a.sample}.te_expression_overview.tsv'))
    add(row,'telescope',one(sd/'11_telescope'/f'{a.sample}.telescope_overview.tsv'))
    Path(a.out).parent.mkdir(parents=True,exist_ok=True)
    pd.DataFrame([row]).to_csv(a.out,sep='\t',index=False)
if __name__=='__main__':main()
