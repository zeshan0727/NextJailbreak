#pragma once
#include <vector>
#include <stdexcept>
#include <cmath>
// SD-Turbo's EulerDiscreteScheduler uses trailing spacing over 1000 timesteps.
inline std::vector<float> nextAITurboTimesteps(unsigned steps) {
 if(steps!=1 && steps!=2 && steps!=4)throw std::invalid_argument("Turbo supports 1, 2 or 4 steps.");
 std::vector<float> times;for(unsigned i=0;i<steps;i++)times.push_back(std::round(1000.0f-i*(1000.0f/steps))-1.0f);
 return times;
}
