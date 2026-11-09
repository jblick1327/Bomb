using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace Bom.Unity {
public struct BomGeometryTicket {public ulong Session,Cell;public uint Epoch;public BomGeometryTicket(ulong session,uint epoch,ulong cell){Session=session;Epoch=epoch;Cell=cell;}}
// Main-thread coordinator; worker delegates receive copied immutable value data.
// No task creates Unity objects. Cached cap geometry is independent of membership.
public sealed class BomGeometryJobs:IDisposable {
 public readonly int ActiveLimit,PendingLimit,CompletionLimit;public readonly long CacheLimit,BufferLimit;
 int outstandingAtDispose;long bufferBytes;public Task Drained{get;private set;}=Task.CompletedTask;
 public int ActiveCount=>Disposed?Volatile.Read(ref outstandingAtDispose):active.Count;public int PendingCount=>pending.Count;public int CacheCount=>cache.Count;public long CacheBytes{get;private set;}public long BufferBytes{get=>Interlocked.Read(ref bufferBytes);private set=>Interlocked.Exchange(ref bufferBytes,value);}
 public long StaleResults{get;private set;}public long CacheHits{get;private set;}public long Evictions{get;private set;}public long QueueRefusals{get;private set;}public long CompletedBuilds{get;private set;}
 public ulong Session{get;private set;}public uint Epoch{get;private set;}public bool Disposed{get;private set;}
 sealed class Request {public BomGeometryTicket Ticket;public string Key;public long Bytes,Order;public int Priority;public Func<CancellationToken,BomClipResult> Build;public CancellationTokenSource Cancellation;public Task<BomClipResult> Task;}
 sealed class Record {public string Key;public BomClipResult Result;public int References;public LinkedListNode<Record> Node;}
 public struct Completion {public BomGeometryTicket Ticket;public string Key;public BomClipResult Result;}
 readonly List<Request> pending=new List<Request>(),active=new List<Request>();readonly Queue<Completion> completed=new Queue<Completion>();readonly Dictionary<string,Record> cache=new Dictionary<string,Record>();readonly LinkedList<Record> lru=new LinkedList<Record>();readonly List<CancellationTokenSource> retired=new List<CancellationTokenSource>();CancellationTokenSource cancellation=new CancellationTokenSource();long order;
 public BomGeometryJobs(int activeLimit=2,int pendingLimit=128,long cacheBytes=256L*1024*1024,long bufferBytes=64L*1024*1024){if(activeLimit<1||pendingLimit<1||cacheBytes<1||bufferBytes<1)throw new ArgumentException("invalid geometry budget");ActiveLimit=activeLimit;PendingLimit=pendingLimit;CompletionLimit=pendingLimit;CacheLimit=cacheBytes;BufferLimit=bufferBytes;}
 public bool Current(BomGeometryTicket ticket)=>!Disposed&&ticket.Session==Session&&ticket.Epoch==Epoch;
 public void Reset(ulong session,uint epoch){if(Disposed)throw new ObjectDisposedException(nameof(BomGeometryJobs));cancellation.Cancel();retired.Add(cancellation);cancellation=new CancellationTokenSource();foreach(var request in pending)BufferBytes-=request.Bytes;pending.Clear();completed.Clear();Session=session;Epoch=epoch;ReclaimTokens();}
 void ReclaimTokens(){for(int i=retired.Count-1;i>=0;i--){bool busy=false;foreach(var job in active)if(job.Cancellation==retired[i]){busy=true;break;}if(!busy){retired[i].Dispose();retired.RemoveAt(i);}}}
 void Touch(Record record){lru.Remove(record.Node);lru.AddFirst(record.Node);}
 public bool TryGet(string key,out BomClipResult result){if(cache.TryGetValue(key,out var record)){Touch(record);CacheHits++;result=record.Result;return true;}result=null;return false;}
 public bool Acquire(string key,out BomClipResult result){if(cache.TryGetValue(key,out var record)){record.References++;Touch(record);result=record.Result;return true;}result=null;return false;}
 public void Release(string key){if(!cache.TryGetValue(key,out var record)||record.References<=0)throw new InvalidOperationException("unbalanced geometry cache release");record.References--;}
 public bool RequestBuild(BomGeometryTicket ticket,string key,long estimatedBytes,int priority,Func<CancellationToken,BomClipResult> build){
  if(!Current(ticket)||string.IsNullOrEmpty(key)||build==null)return false;
  if(cache.ContainsKey(key))return true;
  foreach(var job in active)if(Current(job.Ticket)&&job.Key==key)return true;foreach(var job in pending)if(job.Key==key){job.Priority=Math.Max(job.Priority,priority);return true;}
  if(estimatedBytes<1||estimatedBytes>BufferLimit||BufferBytes>BufferLimit-estimatedBytes||pending.Count>=PendingLimit){QueueRefusals++;return false;}
  pending.Add(new Request{Ticket=ticket,Key=key,Bytes=estimatedBytes,Priority=priority,Order=order++,Build=build,Cancellation=cancellation});BufferBytes+=estimatedBytes;return true;
 }
 static BomClipResult Negative(string reason)=>new BomClipResult{Reason=reason};
 bool MakeSpace(long bytes){
  while(CacheBytes+bytes>CacheLimit||cache.Count>=8192){var node=lru.Last;while(node!=null&&node.Value.References>0)node=node.Previous;if(node==null)return false;var record=node.Value;CacheBytes-=record.Result.Bytes;cache.Remove(record.Key);lru.Remove(node);Evictions++;}return true;
 }
 void Store(string key,BomClipResult result){if(cache.TryGetValue(key,out var old)){Touch(old);return;}if(!MakeSpace(result.Bytes)){result=Negative("geometry cache budget occupied by referenced cells");if(!MakeSpace(0))return;}var record=new Record{Key=key,Result=result};record.Node=lru.AddFirst(record);cache.Add(key,record);CacheBytes+=result.Bytes;}
 public void Pump(){
  if(Disposed)return;
  for(int i=active.Count-1;i>=0;i--){var request=active[i];if(!request.Task.IsCompleted)continue;active.RemoveAt(i);BufferBytes-=request.Bytes;BomClipResult result;
   try{result=request.Task.GetAwaiter().GetResult()??Negative("worker returned no geometry");}catch(OperationCanceledException){result=Negative("obsolete generation cancelled");}catch(Exception error){result=Negative("geometry worker failed: "+error.GetType().Name);}
   if(!Current(request.Ticket)){StaleResults++;continue;}CompletedBuilds++;
   if(!result.Supported)result=Negative(result.Reason);else if(result.Bytes<0||result.Bytes>request.Bytes||result.Bytes>BufferLimit)result=Negative("geometry exceeded its reserved buffer budget");
   Store(request.Key,result);if(cache.TryGetValue(request.Key,out var stored)&&completed.Count<CompletionLimit)completed.Enqueue(new Completion{Ticket=request.Ticket,Key=request.Key,Result=stored.Result});
  }
  ReclaimTokens();
  pending.Sort((a,b)=>a.Priority!=b.Priority?b.Priority.CompareTo(a.Priority):a.Order.CompareTo(b.Order));
  while(active.Count<ActiveLimit&&pending.Count>0&&completed.Count<CompletionLimit){var request=pending[0];pending.RemoveAt(0);if(!Current(request.Ticket)){BufferBytes-=request.Bytes;continue;}var token=request.Cancellation.Token;request.Task=Task.Run(()=>request.Build(token));active.Add(request);}
 }
 public bool TryDequeue(out Completion completion){while(completed.Count>0){completion=completed.Dequeue();if(Current(completion.Ticket))return true;StaleResults++;}completion=default;return false;}
 public void Dispose(){if(Disposed)return;Disposed=true;cancellation.Cancel();foreach(var request in pending)BufferBytes-=request.Bytes;pending.Clear();completed.Clear();cache.Clear();lru.Clear();CacheBytes=0;foreach(var source in retired)source.Cancel();
  // Running work owns only managed immutable arrays. Cancellation completes
  // asynchronously; no Unity resource or result is applied after disposal.
  var sources=new List<CancellationTokenSource>(retired){cancellation};var tasks=new Task[active.Count];for(int i=0;i<active.Count;i++)tasks[i]=active[i].Task;outstandingAtDispose=active.Count;active.Clear();Drained=Task.WhenAll(tasks).ContinueWith(finished=>{var observed=finished.Exception;foreach(var source in sources)source.Dispose();Interlocked.Exchange(ref outstandingAtDispose,0);BufferBytes=0;},TaskScheduler.Default);
 }
}
}
