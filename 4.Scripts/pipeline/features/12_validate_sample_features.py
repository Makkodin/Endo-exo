#!/usr/bin/env python3
import argparse, hashlib, json, os
from datetime import datetime, timezone
from pathlib import Path
import pandas as pd

def parse():
    p=argparse.ArgumentParser(); p.add_argument('--sample',required=True); p.add_argument('--sample-dir',required=True)
    p.add_argument('--enable-human',type=int,default=1); p.add_argument('--enable-hpv',type=int,default=1)
    p.add_argument('--enable-herv',type=int,default=1); p.add_argument('--enable-te',type=int,default=1); p.add_argument('--enable-telescope',type=int,default=1)
    p.add_argument('--out',required=True); p.add_argument('--marker',required=True); return p.parse_args()
def sha(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for b in iter(lambda:f.read(4*1024*1024),b''):h.update(b)
    return h.hexdigest()
def check_table(path,key=None,nonnegative=()):
    p=Path(path)
    if not p.is_file() or p.stat().st_size==0:return False,'missing_or_empty',0
    try:d=pd.read_csv(p,sep='\t',low_memory=False)
    except Exception as e:return False,f'parse_error:{e}',0
    if d.empty:return False,'no_data_rows',0
    if key and key in d and d[key].astype(str).duplicated().any():return False,f'duplicate_{key}',len(d)
    for col in nonnegative:
        if col in d and (pd.to_numeric(d[col],errors='coerce').dropna()<0).any():return False,f'negative_values:{col}',len(d)
    return True,'ok',len(d)
def main():
    version=os.getenv('ENDO_EXO_VERSION','unknown')
    git_commit=os.getenv('ENDO_EXO_GIT_COMMIT','unknown')
    git_describe=os.getenv('ENDO_EXO_GIT_DESCRIBE','unknown')
    a=parse(); sd=Path(a.sample_dir); checks=[]
    def add(name,path,required=True,key=None,nonnegative=()):
        ok,msg,n=check_table(path,key,nonnegative)
        passed=ok or not required
        checks.append({'check':name,'required':required,'passed':passed,'status':msg,'rows':n,'path':str(path)})
    add('library_size',sd/'qc'/f'{a.sample}.library_size.tsv',True)
    add('technical_features',sd/f'{a.sample}.technical_features.tsv',True)
    add('sample_features',sd/f'{a.sample}.sample_features.tsv',True)
    add('human_gene_locus',sd/'08_human_gene_expression'/f'{a.sample}.human_gene_counts.normalized.tsv',bool(a.enable_human),'gene_id',('count','cpm','tpm','rpkm'))
    add('hpv_final',sd/'05_hpv_calling'/f'{a.sample}.hpv_final_status.tsv',bool(a.enable_hpv),None,('mapped_reads','E6_count','E7_count','E1_count'))
    add('integration_loci',sd/'07_hpv_integration'/f'{a.sample}.hpv_integration_loci.annotated.tsv',False)
    add('herv_locus',sd/'09_herv_expression'/f'{a.sample}.herv_locus_counts.normalized.tsv',bool(a.enable_herv),'locus_id',('count','cpm','rpkm_herv_space','rpm_library'))
    add('herv_repeat_name',sd/'09_herv_expression'/f'{a.sample}.herv_repeat_name_summary.tsv',bool(a.enable_herv),None,('total_count','total_cpm','total_rpm_library'))
    add('te_locus',sd/'10_te_expression'/f'{a.sample}.te_locus_counts.normalized.tsv',bool(a.enable_te),'locus_id',('count','cpm_te_space','rpkm_te_space','rpm_library'))
    add('te_repeat_name',sd/'10_te_expression'/f'{a.sample}.te_repeat_name_summary.tsv',bool(a.enable_te),None,('total_count','total_cpm','total_rpm_library'))
    add('telescope_locus',sd/'11_telescope'/f'{a.sample}.telescope_counts.normalized.tsv',bool(a.enable_telescope),'locus_id',('telescope_count','telescope_rpm'))
    add('telescope_repeat_name',sd/'11_telescope'/f'{a.sample}.telescope_repeat_name_summary.tsv',bool(a.enable_telescope),None,('total_telescope_count','telescope_rpm'))
    out=pd.DataFrame(checks); Path(a.out).parent.mkdir(parents=True,exist_ok=True); out.to_csv(a.out,sep='\t',index=False)
    passed=bool(out['passed'].all())
    files={}
    for p in sd.rglob('*.tsv'):
        if p.is_file() and p.stat().st_size>0 and ('normalized' in p.name or 'summary' in p.name or p.name.endswith('features.tsv')):
            files[str(p.relative_to(sd))]={'size_bytes':p.stat().st_size,'sha256':sha(p)}
    marker={
      'sample':a.sample,
      'status':'complete' if passed else 'failed_validation',
      'strict_validation_passed':passed,
      'validated_at_utc':datetime.now(timezone.utc).isoformat(),
      'pipeline_version':version,
      'pipeline_git_commit':git_commit,
      'pipeline_git_describe':git_describe,
      'validated_feature_files':files,
    }
    Path(a.marker).write_text(json.dumps(marker,indent=2,ensure_ascii=False)+'\n')
    if not passed:
        print(out[~out['passed']].to_string(index=False)); raise SystemExit(2)
if __name__=='__main__':main()
