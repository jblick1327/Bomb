"""Bounded, seeded datagram impairment; payloads stay opaque to this supervisor."""
import gzip,heapq,json,random,select,socket,threading,time

class DatagramRelay:
    def __init__(self,server_port,trace_path,seed,rtt_ms=100,jitter_ms=20,loss=0,duplicate=.01,reorder=.02,burst_interval=120,burst_offset=45,burst_seconds=.5):
        self.server=('127.0.0.1',server_port)
        self.socket=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        self.socket.bind(('127.0.0.1',0));self.socket.setblocking(False)
        if hasattr(socket,'SIO_UDP_CONNRESET'):self.socket.ioctl(socket.SIO_UDP_CONNRESET,False)
        self.port=self.socket.getsockname()[1];self.stop=threading.Event();self.errors=[]
        self.config=dict(seed=seed,rtt_ms=rtt_ms,jitter_ms=jitter_ms,random_loss=loss,duplicate_probability=duplicate,reorder_probability=reorder,burst_interval=burst_interval,burst_offset=burst_offset,burst_seconds=burst_seconds,packet_bound=1200,queue_bound=10000,jitter='positive uniform per direction',version=1)
        self.counters=dict(received=0,forwarded=0,random_drops=0,burst_drops=0,duplicates=0,reordered=0,max_packet=0,peak_queued=0,shutdown_discarded=0)
        self.trace_path=trace_path;self.thread=threading.Thread(target=self.run,daemon=True);self.thread.start()
    def run(self):
        rng=random.Random(self.config['seed']);queue=[];client=None;sequence=0;started=time.monotonic();cfg=self.config;c=self.counters
        try:
            with gzip.open(self.trace_path,'wt',encoding='utf-8') as trace:
                trace.write(json.dumps({'configuration':cfg})+'\n')
                while not self.stop.is_set():
                    now=time.monotonic()
                    while queue and queue[0][0]<=now:
                        _,_,data,to=heapq.heappop(queue)
                        try:self.socket.sendto(data,to);c['forwarded']+=1
                        except ConnectionResetError:pass
                    timeout=min(.01,max(0,queue[0][0]-now)) if queue else .01
                    readable,_,_=select.select([self.socket],[],[],timeout)
                    if not readable:continue
                    while True:
                        try:data,source=self.socket.recvfrom(2048)
                        except BlockingIOError:break
                        except ConnectionResetError:continue
                        c['received']+=1;c['max_packet']=max(c['max_packet'],len(data))
                        if len(data)>cfg['packet_bound']:raise RuntimeError('Native packet exceeded the recorded bound')
                        if source==self.server:
                            if client is None:continue
                            target=client;direction='down'
                        else:client=source;target=self.server;direction='up'
                        elapsed=time.monotonic()-started
                        burst=elapsed>=cfg['burst_offset'] and (elapsed-cfg['burst_offset'])%cfg['burst_interval']<cfg['burst_seconds']
                        random_drop=rng.random()<cfg['random_loss'];duplicate=rng.random()<cfg['duplicate_probability'];reorder=rng.random()<cfg['reorder_probability']
                        delay=cfg['rtt_ms']/2000+rng.uniform(0,cfg['jitter_ms'])/1000
                        if reorder:delay+=rng.uniform(.03,.08)
                        sequence+=1
                        trace.write(json.dumps(dict(t=round(elapsed,6),sequence=sequence,direction=direction,bytes=len(data),burst_drop=burst,random_drop=random_drop,duplicate=duplicate,reorder=reorder,delay_ms=round(delay*1000,4)),separators=(',',':'))+'\n')
                        if burst:c['burst_drops']+=1;continue
                        if random_drop:c['random_drops']+=1;continue
                        if reorder:c['reordered']+=1
                        heapq.heappush(queue,(time.monotonic()+delay,sequence*2,data,target))
                        if duplicate:
                            heapq.heappush(queue,(time.monotonic()+delay+.002,sequence*2+1,data,target));c['duplicates']+=1
                        c['peak_queued']=max(c['peak_queued'],len(queue))
                        if len(queue)>cfg['queue_bound']:raise RuntimeError('Impairment queue exceeded its bound')
                c['shutdown_discarded']=len(queue)
        except Exception as exc:self.errors.append(str(exc))
    def close(self):
        self.stop.set();self.thread.join(timeout=3)
        if self.thread.is_alive():self.errors.append('Relay failed to stop')
        self.socket.close()
