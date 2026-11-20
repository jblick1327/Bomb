"""Compare actual server-side send expectations and client hash reports.
Missing reports are listed; an intentional reset/disconnect tail is never counted
as a matching hash. All older missing reports fail the real-run gate.
"""
import collections,re

def analyze(text,grace_ticks=120):
 expected={};reports=collections.defaultdict(list);closed={};epoch_start={}
 for line in text.splitlines():
  m=re.search(r'HASH EXPECT client=(\d+) connection=(\d+) epoch=(\d+) revision=(\d+) tick=(\d+) queued=(\w+)',line)
  if m:
   client,generation,epoch,revision,tick=map(int,m.groups()[:5]);key=(client,generation,epoch,revision)
   expected.setdefault(key,{'tick':tick,'queued':m[6]=='yes'})
   epoch_start.setdefault((client,generation,epoch),tick)
  m=re.search(r'HASH REPORT client=(\d+) connection=(\d+) epoch=(\d+) revision=(\d+) hash=(\d+) tick=(\d+) result=(\w+)',line)
  if m:reports[tuple(map(int,m.groups()[:4]))].append({'hash':int(m[5]),'tick':int(m[6]),'result':m[7]})
  m=re.search(r'HASH CLOSED client=(\d+) connection=(\d+) tick=(\d+)',line)
  if m:closed[tuple(map(int,m.groups()[:2]))]=int(m[3])
 missing=[];matched=0;bad=[];per_client=collections.defaultdict(lambda:{'matched':0,'missing_steady':0,'missing_tail':0})
 for key,item in expected.items():
  client,generation,epoch,revision=key;label=f'{client}:{generation}'
  if not item['queued']:bad.append({'key':key,'reason':'reliable send did not queue every part'})
  if key in reports:
   if all(r['result']=='match' for r in reports[key]):matched+=1;per_client[label]['matched']+=1
   else:bad.append({'key':key,'reason':'mismatch or unrecorded hash','reports':reports[key]})
   continue
  boundaries=[(tick,'epoch-reset') for (c,g,e),tick in epoch_start.items() if c==client and g==generation and e!=epoch and tick>=item['tick']]
  if (client,generation) in closed:boundaries.append((closed[(client,generation)],'disconnect'))
  tail=next((reason for tick,reason in sorted(boundaries) if 0<=tick-item['tick']<=grace_ticks),None)
  missing.append({'client':client,'connection':generation,'epoch':epoch,'revision':revision,'sent_tick':item['tick'],'classification':tail+'-tail' if tail else 'steady-state'})
  per_client[label]['missing_tail' if tail else 'missing_steady']+=1
 unexpected=[{'key':key,'reports':value} for key,value in reports.items() if key not in expected]
 steady=sum(x['classification']=='steady-state' for x in missing)
 return {'status':'passed' if expected and matched and not bad and not unexpected and steady==0 else 'failed','expected_unique':len(expected),'matching_unique':matched,'missing_steady':steady,'missing_tail':len(missing)-steady,'missing_reports':missing,'bad_reports':bad,'unexpected_reports':unexpected,'per_client_connection':dict(per_client),'tail_policy':f'Reports missing within {grace_ticks} network ticks before intentional epoch reset/disconnect are explicitly listed and excluded from matches.'}
