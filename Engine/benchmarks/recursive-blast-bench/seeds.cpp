#include "geometry.hpp"
#include <chrono>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <random>
using namespace rb;
struct BatchSeed{uint64_t parent;float maximum_width;uint8_t seed;};
__attribute__((noinline)) void shared_check(const std::vector<BatchSeed>&in,std::vector<uint8_t>&out,size_t k,float cutoff){for(size_t b=0;b<in.size();++b){auto x=in[b];if(!x.seed||x.maximum_width<=cutoff){std::fill(out.begin()+b*k,out.begin()+(b+1)*k,0);}else for(size_t i=0;i<k;++i)out[b*k+i]=seed_for(x.seed,child_id(x.parent,i));}}
__attribute__((noinline)) void repeated_common_check(const std::vector<BatchSeed>&in,std::vector<uint8_t>&out,size_t k,float cutoff){for(size_t b=0;b<in.size();++b){auto x=in[b];for(size_t i=0;i<k;++i)out[b*k+i]=(x.seed&&x.maximum_width>cutoff)?seed_for(x.seed,child_id(x.parent,i)):0;}}
using Fn=void(*)(const std::vector<BatchSeed>&,std::vector<uint8_t>&,size_t,float);
using Clock=std::chrono::steady_clock;
inline void barrier(){asm volatile("":::"memory");}
double run(Fn fn,const std::vector<BatchSeed>&in,std::vector<uint8_t>&out,size_t k,size_t reps){barrier();auto a=Clock::now();for(size_t i=0;i<reps;++i){fn(in,out,k,.18f);asm volatile(""::"g"(out.data()):"memory");}return std::chrono::duration<double,std::nano>(Clock::now()-a).count()/reps;}
int main(){std::ofstream f("results/seeds.csv");f<<std::setprecision(12)<<"children_per_batch,batches,terminal_percent,variant,median_ns,p25_ns,p75_ns,repetitions";for(int i=0;i<9;++i)f<<",sample_"<<i<<"_ns";f<<",checksum\n";for(size_t k:{3U,5U,6U,12U,24U})for(int terminal:{0,50,100}){std::vector<BatchSeed>input;for(uint64_t b=0;b<4096;++b)input.push_back({b+1,b%100<uint64_t(terminal)?.1f:.4f,uint8_t(1+b%255)});std::vector<uint8_t>a(input.size()*k),b(a.size());shared_check(input,a,k,.18f);repeated_common_check(input,b,k,.18f);if(a!=b)throw std::runtime_error("seed results differ");uint64_t sig=0;for(auto x:a)sig=hash64(sig^x);std::array<Fn,2>fn{shared_check,repeated_common_check};std::array<size_t,2>reps{1,1};std::array<std::vector<double>,2>samples;for(int j=0;j<2;++j){for(int n=0;n<4;++n)run(fn[j],input,b,k,1);while(run(fn[j],input,b,k,reps[j])*reps[j]<3e6)reps[j]*=2;}std::mt19937 rng(733);for(int r=0;r<9;++r){int first=rng()%2;for(int n=0;n<2;++n){int j=(first+n)%2;samples[j].push_back(run(fn[j],input,b,k,reps[j]));}}for(int j=0;j<2;++j){auto s=samples[j];std::sort(s.begin(),s.end());f<<k<<','<<input.size()<<','<<terminal<<','<<(j==0?"shared":"per_child_common")<<','<<s[4]<<','<<s[2]<<','<<s[6]<<','<<reps[j];for(auto x:samples[j])f<<','<<x;f<<','<<sig<<'\n';}}std::cerr<<"seed checks and timings complete\n";}
