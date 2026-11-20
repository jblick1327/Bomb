#include "geometry.hpp"
#include <iostream>
using namespace rb;
int main(){std::vector<Poly>ps={{{0,0},{2,0},{2,1},{1,1},{1,2},{0,2}},{{0,0},{3,0},{3,1},{0,1}}};for(size_t i=0;i<ps.size();++i)for(int k=0;k<3;++k)for(int seed:{1,7,42,255})try{Recipe r{4,6,.25f,uint32_t(k==0?3:k==1?5:6),k==1?.2f:1.f,k==2};auto c=generate(ps[i],r,uint8_t(seed));for(auto&p:c)if(!simple(p))throw std::runtime_error("non-simple");}catch(std::exception&e){std::cerr<<i<<' '<<k<<' '<<seed<<" : "<<e.what()<<'\n';return 1;}}
