from pathlib import Path
root=Path(__file__).resolve().parent/'stable-diffusion.cpp'
def replace(path,old,new):
    p=root/path;s=p.read_text()
    if s.count(old)!=1: raise RuntimeError(f'Expected one pinned source marker in {path}: {old!r}')
    p.write_text(s.replace(old,new))
replace('stable-diffusion.h','    GITS,\n    N_SCHEDULES','    GITS,\n    NEXTAI_TURBO,\n    N_SCHEDULES')
replace('denoiser.hpp','struct DiscreteSchedule : SigmaSchedule {','''#include "../NextTurboSchedule.h"
struct NextAITurboSchedule : SigmaSchedule {
    std::vector<float> get_sigmas(uint32_t n, float, float, t_to_sigma_t t_to_sigma) override {
        std::vector<float> sigmas;
        for(float t : nextAITurboTimesteps(n)) sigmas.push_back(t_to_sigma(t));
        sigmas.push_back(0.0f);
        return sigmas;
    }
};
struct DiscreteSchedule : SigmaSchedule {''')
replace('stable-diffusion.cpp','            switch (schedule) {','''            switch (schedule) {
                case NEXTAI_TURBO:
                    denoiser->schedule = std::make_shared<NextAITurboSchedule>();
                    break;''')
# Turbo explicitly uses epsilon prediction; do not run the SD2 guess/calibration pass.
replace('stable-diffusion.cpp','        if (sd_version_is_sd2(version)) {','        if (sd_version_is_sd2(version) && schedule != NEXTAI_TURBO) {')
print('Applied pinned SD-Turbo trailing schedule and epsilon-prediction path.')
