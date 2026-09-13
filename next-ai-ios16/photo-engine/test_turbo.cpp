#include "NextTurboSchedule.h"
#include <cassert>
int main(){
 assert(nextAITurboTimesteps(1)==std::vector<float>({999}));
 assert(nextAITurboTimesteps(2)==std::vector<float>({999,499}));
 assert(nextAITurboTimesteps(4)==std::vector<float>({999,749,499,249}));
 bool rejected=false;try{nextAITurboTimesteps(20);}catch(const std::invalid_argument&){rejected=true;}assert(rejected);
}
