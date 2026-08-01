#!/usr/bin/env python3
import argparse, re
from pathlib import Path
import pandas as pd

def args():
    p=argparse.ArgumentParser()
    p.add_argument('--sample',required=True); p.add_argument('--counts',required=True)
    p.add_argument('--star-gene-counts',required=True); p.add_argument('--gtf',required=True)
    p.add_argument('--library-size',required=True); p.add_argument('--out-dir',required=True)
    return p.parse_args()

def attrs(text):
    return dict(re.findall(r'(\S+)\s+"([^"]*)"', str(text)))

def gtf_metadata(path):
    rows={}
    with open(path,encoding='utf-8',errors='replace') as fh:
        for line in fh:
            if not line or line.startswith('#'): continue
            p=line.rstrip('\n').split('\t')
            if len(p)!=9 or p[2]!='gene': continue
            a=attrs(p[8]); gid=a.get('gene_id','').split('.')[0]
            if gid and gid not in rows:
                rows[gid]={'gene_name':a.get('gene_name',''),'gene_type':a.get('gene_type',a.get('gene_biotype','')),'chrom':p[0],'strand':p[6]}
    return pd.DataFrame.from_dict(rows,orient='index').rename_axis('gene_id_base').reset_index()

def library_pairs(path):
    d=pd.read_csv(path,sep='\t').iloc[0]
    return float(d.get('library_read_pairs_after_qc',0) or 0)

def main():
    a=args(); out=Path(a.out_dir); out.mkdir(parents=True,exist_ok=True)
    fc=pd.read_csv(a.counts,sep='\t',comment='#',low_memory=False)
    c=fc.columns[-1]
    df=fc[['Geneid','Chr','Start','End','Strand','Length',c]].copy().rename(columns={'Geneid':'gene_id',c:'count'})
    df['gene_id_base']=df['gene_id'].astype(str).str.split('.').str[0]
    df['count']=pd.to_numeric(df['count'],errors='coerce').fillna(0.0)
    df['Length']=pd.to_numeric(df['Length'],errors='coerce').fillna(0.0)
    df=df.merge(gtf_metadata(a.gtf),on='gene_id_base',how='left')
    total=float(df['count'].sum()); pairs=library_pairs(a.library_size)
    df['cpm']=df['count']/total*1e6 if total>0 else 0.0
    rate=df['count']/df['Length'].replace(0,pd.NA)
    denom=float(rate.sum(skipna=True)); df['tpm']=(rate/denom*1e6).fillna(0.0) if denom>0 else 0.0
    df['rpkm']=(df['count']/(df['Length'].replace(0,pd.NA)/1000)/(pairs/1e6)).fillna(0.0) if pairs>0 else 0.0
    star=pd.read_csv(a.star_gene_counts,sep='\t',header=None,names=['gene_id','star_unstranded_count','star_forward_count','star_reverse_count'])
    star=star[~star['gene_id'].astype(str).str.startswith('N_')].copy()
    star['gene_id_base']=star['gene_id'].astype(str).str.split('.').str[0]
    star=star.drop(columns=['gene_id']).drop_duplicates('gene_id_base')
    df=df.merge(star,on='gene_id_base',how='left')
    for col in ['star_unstranded_count','star_forward_count','star_reverse_count']:
        df[col]=pd.to_numeric(df[col],errors='coerce').fillna(0.0)
    order=['gene_id','gene_id_base','gene_name','gene_type','chrom','strand','Length','count','cpm','tpm','rpkm','star_unstranded_count','star_forward_count','star_reverse_count']
    for col in order:
        if col not in df: df[col]=''
    df[order].sort_values(['count','gene_id'],ascending=[False,True]).to_csv(out/f'{a.sample}.human_gene_counts.normalized.tsv',sep='\t',index=False)
    pd.DataFrame([{
        'sample_id':a.sample,'n_genes_total':len(df),'n_genes_count_gt0':int((df['count']>0).sum()),
        'total_gene_assigned_read_pairs':total,'gene_assignment_fraction_of_library_pairs':total/pairs if pairs else 0,
        'star_unstranded_gene_total':float(df['star_unstranded_count'].sum()),
        'star_forward_gene_total':float(df['star_forward_count'].sum()),
        'star_reverse_gene_total':float(df['star_reverse_count'].sum())
    }]).to_csv(out/f'{a.sample}.human_gene_overview.tsv',sep='\t',index=False)

if __name__=='__main__': main()
