#!/usr/bin/env python3
"""Build metadata-free run-level dense summaries and lossless sparse locus matrices."""
from __future__ import annotations
import argparse,gzip,hashlib,json,os,re
from datetime import datetime,timezone
from pathlib import Path
import numpy as np
import pandas as pd
from scipy.io import mmwrite
from scipy.sparse import coo_matrix,save_npz

def parse():
    p=argparse.ArgumentParser(); p.add_argument('--samples-normalized',required=True); p.add_argument('--results-dir',required=True)
    p.add_argument('--run-name',required=True); p.add_argument('--out-dir',required=True)
    p.add_argument('--build-locus-sparse',type=int,choices=[0,1],default=int(os.getenv('BUILD_LOCUS_SPARSE_MATRICES','1')))
    return p.parse_args()
def sha(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
    return h.hexdigest()
def token(x):return re.sub(r'[^A-Za-z0-9._-]+','_',str(x)).strip('_') or 'NA'
def read(path,**kw):return pd.read_csv(path,sep='\t',low_memory=False,**kw)
def feature_id(df,cols):
    vals=[df[c].fillna('NA').astype(str) if c in df else pd.Series(['NA']*len(df),index=df.index) for c in cols]
    out=vals[0]
    for v in vals[1:]:out=out+'|'+v
    return out

SUMMARY_BLOCKS={
 'human_gene':{'rel':'08_human_gene_expression/{s}.human_gene_counts.normalized.tsv','ids':['gene_id'],'ann':['gene_id_base','gene_name','gene_type','chrom','strand','Length'],'metrics':['count','cpm','tpm','rpkm','star_unstranded_count','star_forward_count','star_reverse_count'],'primary':'tpm'},
 'hpv_gene':{'rel':'06_hpv_expression/{s}.hpv_gene_counts.normalized.tsv','ids':['hpv_reference','gene_id'],'ann':['gene_id','hpv_gene_name','hpv_reference','feature_type','Length'],'metrics':['count','cpm_hpv_space','tpm_hpv_space','rpkm_hpv_space','rpm_library'],'primary':'rpm_library'},
 'herv_class':{'rel':'09_herv_expression/{s}.herv_repeat_class_summary.tsv','ids':['repeat_class'],'ann':['repeat_class'],'metrics':['total_count','total_cpm','total_tpm','total_rpm_library','n_loci','n_expressed_loci','max_locus_count','max_locus_cpm','max_locus_tpm','max_locus_rpm_library'],'primary':'total_cpm'},
 'herv_family':{'rel':'09_herv_expression/{s}.herv_repeat_family_summary.tsv','ids':['repeat_class','repeat_family'],'ann':['repeat_class','repeat_family'],'metrics':['total_count','total_cpm','total_tpm','total_rpm_library','n_loci','n_expressed_loci','max_locus_count','max_locus_cpm','max_locus_tpm','max_locus_rpm_library'],'primary':'total_cpm'},
 'herv_repeat_name':{'rel':'09_herv_expression/{s}.herv_repeat_name_summary.tsv','ids':['repeat_class','repeat_family','repeat_name'],'ann':['repeat_class','repeat_family','repeat_name'],'metrics':['total_count','total_cpm','total_tpm','total_rpm_library','n_loci','n_expressed_loci','max_locus_count','max_locus_cpm','max_locus_tpm','max_locus_rpm_library'],'primary':'total_cpm'},
 'te_class':{'rel':'10_te_expression/{s}.te_repeat_class_summary.tsv','ids':['te_class_group'],'ann':['te_class_group'],'metrics':['total_count','total_cpm','total_tpm','total_rpm_library','n_loci','n_expressed_loci','max_locus_count','max_locus_cpm','max_locus_tpm','max_locus_rpm_library'],'primary':'total_cpm'},
 'te_family':{'rel':'10_te_expression/{s}.te_repeat_family_summary.tsv','ids':['te_class_group','repeat_class','repeat_family'],'ann':['te_class_group','repeat_class','repeat_family'],'metrics':['total_count','total_cpm','total_tpm','total_rpm_library','n_loci','n_expressed_loci','max_locus_count','max_locus_cpm','max_locus_tpm','max_locus_rpm_library'],'primary':'total_cpm'},
 'te_repeat_name':{'rel':'10_te_expression/{s}.te_repeat_name_summary.tsv','ids':['te_class_group','repeat_class','repeat_family','repeat_name'],'ann':['te_class_group','repeat_class','repeat_family','repeat_name'],'metrics':['total_count','total_cpm','total_tpm','total_rpm_library','n_loci','n_expressed_loci','max_locus_count','max_locus_cpm','max_locus_tpm','max_locus_rpm_library'],'primary':'total_cpm'},
 'telescope_class':{'rel':'11_telescope/{s}.telescope_class_summary.tsv','ids':['te_class_group'],'ann':['te_class_group'],'metrics':['total_telescope_count','telescope_rpm','n_loci','n_loci_count_gt0','top_locus_count','top_locus_rpm'],'primary':'telescope_rpm'},
 'telescope_family':{'rel':'11_telescope/{s}.telescope_family_summary.tsv','ids':['te_class_group','repeat_family'],'ann':['te_class_group','repeat_family'],'metrics':['total_telescope_count','telescope_rpm','n_loci','n_loci_count_gt0','max_locus_count'],'primary':'telescope_rpm'},
 'telescope_repeat_name':{'rel':'11_telescope/{s}.telescope_repeat_name_summary.tsv','ids':['te_class_group','repeat_class','repeat_family','repeat_name'],'ann':['te_class_group','repeat_class','repeat_family','repeat_name'],'metrics':['total_telescope_count','telescope_rpm','n_loci','n_loci_count_gt0','max_locus_count'],'primary':'telescope_rpm'},
}
LOCUS_BLOCKS={
 'herv_locus':{'rel':'09_herv_expression/{s}.herv_locus_counts.normalized.tsv','id':'locus_id','ann':['Chr','Start','End','Strand','Length','repeat_name','repeat_class','repeat_family','swScore','milliDiv'],'metrics':['count','cpm','tpm_herv_space','rpkm_herv_space','rpm_library']},
 'te_locus':{'rel':'10_te_expression/{s}.te_locus_counts.normalized.tsv','id':'locus_id','ann':['Chr','Start','End','Strand','Length','repeat_name','repeat_class','te_class_group','repeat_family','is_herv_ltr_erv_like','overlaps_gene','n_overlapping_genes','overlapping_genes','swScore','milliDiv'],'metrics':['count','cpm_te_space','tpm_te_space','rpkm_te_space','rpm_library']},
 'telescope_locus':{'rel':'11_telescope/{s}.telescope_counts.normalized.tsv','id':'locus_id','ann':['repeat_name','repeat_class','te_class_group','repeat_family','is_herv_ltr_erv_like'],'metrics':['telescope_count','telescope_rpm']},
}

def write_summary_block(name,spec,samples,results,out_root,registry,analysis_parts):
    bd=out_root/'blocks'/name; bd.mkdir(parents=True,exist_ok=True)
    metric_series={m:{} for m in spec['metrics']}; anns=[]; longs=[]
    for sample in samples:
        p=results/sample/spec['rel'].format(s=sample)
        if not p.is_file() or p.stat().st_size==0:continue
        d=read(p); d['feature_id']=feature_id(d,spec['ids'])
        if d['feature_id'].duplicated().any():
            num=[m for m in spec['metrics'] if m in d]
            ann=[c for c in spec['ann'] if c in d]
            agg={c:'first' for c in ann}; agg.update({m:'sum' for m in num})
            d=d.groupby('feature_id',as_index=False,dropna=False).agg(agg)
        anns.append(d[['feature_id']+[c for c in spec['ann'] if c in d]].drop_duplicates('feature_id'))
        keep=['feature_id']+[m for m in spec['metrics'] if m in d]
        long=d[keep].copy(); long.insert(0,'sample_id',sample); longs.append(long)
        for metric in spec['metrics']:
            if metric in d:
                metric_series[metric][sample]=pd.Series(pd.to_numeric(d[metric],errors='coerce').fillna(0).to_numpy(),index=d['feature_id'].astype(str),name=sample)
    if not longs:return
    ann=pd.concat(anns,ignore_index=True).drop_duplicates('feature_id'); ann.to_csv(bd/f'{name}.feature_annotation.tsv.gz',sep='\t',index=False,compression='gzip')
    long=pd.concat(longs,ignore_index=True); long.to_csv(bd/f'{name}.long.tsv.gz',sep='\t',index=False,compression='gzip'); long.to_parquet(bd/f'{name}.long.parquet',index=False)
    for metric,series in metric_series.items():
        if not series:continue
        mat=pd.concat(series,axis=1).fillna(0.0); mat.index.name='feature_id'
        f=bd/f'{name}__{metric}__feature_by_sample.tsv.gz'; g=bd/f'{name}__{metric}__sample_by_feature.tsv.gz'
        mat.reset_index().to_csv(f,sep='\t',index=False,compression='gzip'); mat.T.rename_axis('sample_id').reset_index().to_csv(g,sep='\t',index=False,compression='gzip')
        registry.append({'block':name,'level':'gene' if name.endswith('gene') else name.split('_',1)[-1],'metric':metric,'storage':'dense_tsv_gz+parquet_long','n_features':len(mat),'n_samples':mat.shape[1],'feature_by_sample':str(f.relative_to(out_root)),'sample_by_feature':str(g.relative_to(out_root)),'primary_normalized_metric':metric==spec['primary']})
        if metric==spec['primary']:
            x=mat.T.copy(); x.columns=[f'{name}__{metric}__{token(c)}' for c in x.columns]; analysis_parts.append(x)

def write_locus_sparse(name,spec,samples,results,out_root,registry):
    bd=out_root/'locus_sparse'/name; bd.mkdir(parents=True,exist_ok=True)
    feature_to_row={}; feature_rows=[]; metric_rows={m:[] for m in spec['metrics']}; metric_cols={m:[] for m in spec['metrics']}; metric_vals={m:[] for m in spec['metrics']}
    source=[]
    for col_idx,sample in enumerate(samples):
        p=results/sample/spec['rel'].format(s=sample)
        if not p.is_file() or p.stat().st_size==0:continue
        d=read(p)
        if spec['id'] not in d:raise RuntimeError(f'{name}: missing {spec["id"]} in {p}')
        ids=d[spec['id']].astype(str)
        if ids.duplicated().any():raise RuntimeError(f'{name}: duplicate locus IDs in {p}')
        for pos,fid in enumerate(ids):
            row_idx=feature_to_row.get(fid)
            if row_idx is None:
                row_idx=len(feature_rows); feature_to_row[fid]=row_idx
                rec={'matrix_row_1based':row_idx+1,'feature_id':fid}
                for c in spec['ann']:rec[c]=d.iloc[pos][c] if c in d else ''
                feature_rows.append(rec)
        idx=np.fromiter((feature_to_row[x] for x in ids),dtype=np.int64,count=len(ids))
        for metric in spec['metrics']:
            if metric not in d:continue
            vals=pd.to_numeric(d[metric],errors='coerce').fillna(0).to_numpy(dtype=float)
            nz=np.flatnonzero(vals!=0)
            metric_rows[metric].extend(idx[nz].tolist()); metric_cols[metric].extend([col_idx]*len(nz)); metric_vals[metric].extend(vals[nz].tolist())
        source.append({'sample_id':sample,'source_file':str(p.resolve()),'rows':len(d),'size_bytes':p.stat().st_size,'sha256':sha(p)})
    if not feature_rows:return
    pd.DataFrame(feature_rows).to_csv(bd/f'{name}.feature_index.tsv.gz',sep='\t',index=False,compression='gzip')
    pd.DataFrame({'matrix_col_1based':range(1,len(samples)+1),'sample_id':samples}).to_csv(bd/f'{name}.sample_index.tsv',sep='\t',index=False)
    pd.DataFrame(source).to_csv(bd/f'{name}.source_files.tsv',sep='\t',index=False)
    shape=(len(feature_rows),len(samples))
    for metric in spec['metrics']:
        mat=coo_matrix((metric_vals[metric],(metric_rows[metric],metric_cols[metric])),shape=shape).tocsr()
        npz=bd/f'{name}__{metric}.feature_by_sample.csr.npz'; mtx=bd/f'{name}__{metric}.feature_by_sample.mtx.gz'
        save_npz(npz,mat,compressed=True)
        with gzip.open(mtx,'wb') as fh:mmwrite(fh,mat)
        registry.append({'block':name,'level':'locus','metric':metric,'storage':'sparse_csr_npz+matrix_market_gz','n_features':shape[0],'n_samples':shape[1],'nnz':int(mat.nnz),'sparse_npz':str(npz.relative_to(out_root)),'matrix_market':str(mtx.relative_to(out_root)),'feature_index':str((bd/f'{name}.feature_index.tsv.gz').relative_to(out_root)),'sample_index':str((bd/f'{name}.sample_index.tsv').relative_to(out_root)),'primary_normalized_metric':False})

def main():
    version=os.getenv('ENDO_EXO_VERSION','unknown')
    a=parse(); results=Path(a.results_dir); out=Path(a.out_dir); out.mkdir(parents=True,exist_ok=True)
    manifest=read(a.samples_normalized); requested=manifest['sample'].astype(str).tolist(); samples=[]; status=[]
    for s in requested:
        marker=results/s/f'{s}.features_complete.json'; ok=False
        if marker.is_file():
            try:ok=json.loads(marker.read_text()).get('strict_validation_passed') is True
            except Exception:pass
        status.append({'sample_id':s,'strict_validation_passed':ok,'marker':str(marker)})
        if ok:samples.append(s)
    pd.DataFrame(status).to_csv(out/'sample_completion_status.tsv',sep='\t',index=False)
    if not samples:raise SystemExit('ERROR: no strictly validated samples')
    rows=[]
    for s in samples:
        p=results/s/f'{s}.sample_features.tsv'
        if p.is_file():rows.append(read(p))
    run=pd.concat(rows,ignore_index=True) if rows else pd.DataFrame({'sample_id':samples})
    run.to_csv(out/'run_sample_features.tsv',sep='\t',index=False); run.to_parquet(out/'run_sample_features.parquet',index=False)
    registry=[]; analysis=[]
    for name,spec in SUMMARY_BLOCKS.items():write_summary_block(name,spec,samples,results,out,registry,analysis)
    if a.build_locus_sparse:
        for name,spec in LOCUS_BLOCKS.items():write_locus_sparse(name,spec,samples,results,out,registry)
    for label,rel in [('hpv_status','05_hpv_calling/{s}.hpv_final_status.tsv'),('hpv_integration_candidates','07_hpv_integration/{s}.hpv_integration_candidates.tsv'),('hpv_integration_loci','07_hpv_integration/{s}.hpv_integration_loci.annotated.tsv')]:
        parts=[]
        for s in samples:
            p=results/s/rel.format(s=s)
            if p.is_file() and p.stat().st_size:
                d=read(p); d.insert(0,'sample_id_run',s); parts.append(d)
        if parts:
            x=pd.concat(parts,ignore_index=True); x.to_csv(out/f'{label}.long.tsv.gz',sep='\t',index=False,compression='gzip'); x.to_parquet(out/f'{label}.long.parquet',index=False)
    reg=pd.DataFrame(registry); reg.to_csv(out/'feature_registry.tsv',sep='\t',index=False)
    if analysis:
        base=pd.DataFrame(index=samples)
        for x in analysis:base=base.join(x,how='left')
        base=base.fillna(0.0); base.index.name='sample_id'; dense=base.reset_index()
        dense.to_csv(out/'analysis_ready_normalized_sample_by_feature.tsv.gz',sep='\t',index=False,compression='gzip'); dense.to_parquet(out/'analysis_ready_normalized_sample_by_feature.parquet',index=False)
    checks=[
      {'check':'all_requested_samples_complete','passed':len(samples)==len(requested),'observed':len(samples),'expected':len(requested)},
      {'check':'run_sample_features_rows','passed':len(run)==len(samples),'observed':len(run),'expected':len(samples)},
      {'check':'feature_registry_nonempty','passed':not reg.empty,'observed':len(reg),'expected':'>0'},
      {'check':'no_clinical_sample_metadata','passed':set(manifest.columns)=={'sample','input_type','sra','Fq1','Fq2'},'observed':','.join(manifest.columns),'expected':'sample,input_type,sra,Fq1,Fq2'},
    ]
    pd.DataFrame(checks).to_csv(out/'run_feature_validation.tsv',sep='\t',index=False); passed=all(x['passed'] for x in checks)
    summary={'run_name':a.run_name,'pipeline_version':version,'status':'complete' if passed else 'incomplete','strict_validation_passed':passed,'n_requested_samples':len(requested),'n_complete_samples':len(samples),'completed_at_utc':datetime.now(timezone.utc).isoformat(),'clinical_sample_metadata_included':False,'reports_generated':False,'locus_sparse_matrices_built':bool(a.build_locus_sparse)}
    (out/'run_features_complete.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False)+'\n')
    if not passed:raise SystemExit(2)
if __name__=='__main__':main()
