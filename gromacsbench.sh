#!/bin/bash
#SBATCH --partition=gpu
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=4
#SBATCH --cpus-per-task=12
#SBATCH --gres=gpu:4
#SBATCH --gpu-bind=closest
#SBATCH --gres-flags=enforce-binding
#SBATCH --mem-per-gpu=44GB
#SBATCH --time=18:00:00

### Based on Kutzner et al.'s dobenchs.sh

module use /ifs/opt_cuda/modulefiles
module load gromacs/cuda11.2/2021.3

echo Host: $( uname -n )
echo GPU devices:
nvidia-smi

#==============================================================================
# Set number of cores for the node and nranks to test
# (nthreads will then be selected automatically)
#==============================================================================
# 48-core machine with 4 GPUs
CORES=48
NGPU_PER_HOST=4
RANKLIST=$( echo "$SLURM_JOB_NUM_NODES * $NGPU_PER_HOST" | bc )

NRANKS=$SLURM_NTASKS

#==============================================================================
# Where is the benchmark MD system
#==============================================================================
TPRDIR="../TPR"
TPRMEM="benchMEM.tpr"
STEPSMEM=100000   # Total steps to perform for each benchmark
RESETMEM=25000   # Reset mdrun time step counters after this time step number

#==============================================================================
# Do or do not restrict mdrun to use only certain GPUs:
#==============================================================================
USEGPUIDS="0123456789"  # only GPU id's from this list will be used

#==============================================================================
# Helper function to exit the whole script as soon as something goes wrong
#==============================================================================
function func.testquit
{
    if [ "$1" = "0" ] ; then
        echo "OK"
    else
            echo "ERROR: exit code of the last command was $1. Exiting."
        exit
    fi
}
#==============================================================================

#==============================================================================
# From the number of GPUs per node and the number of PP ranks
# determine an appropriate value for mdrun's "-gpu_id" string.
#
# GPUs will be assigned to PP ranks in order, from the lower to
# the higher IDs, so that each GPU gets approximately the same
# number of PP ranks. Here is an example of how 5 PP ranks would
# be mapped to 2 GPUs:
#            +-----+-----+-----+-----+-----+
# PP ranks:  |  0  |  1  |  2  |  3  |  4  |
#            +-----+-----+-----+-----+-----+
# GPUs:      |  0  |  0  |  0  |  1  |  1  |
#            +-----+-----+-----+-----+-----+
#
# Will consecutively use GPU IDs from the list passed to this
# function as the third argument.
#
func.getGpuString ( )
{
    if [ $# -ne 3 ]; then
        echo "ERROR: func.getGpuString needs #GPUs as 1st, #MPI as 2nd, and"
        echo "       a string with allowed GPU IDs as 3rd argument (all per node)!" >&2
        echo "       It got: '$@'" >&2
        exit 333
    fi

    # number of GPUs per node:
    local NGPU=$1
    # number of PP ranks per node:
    local N_PP=$2
    # string with the allowed GPU IDs to use:
    local ALLOWED=$3

    local currGPU=0
    local nextGPU=1
    local iPP
    # loop over all PP ranks on a node:
    for ((iPP=0; iPP < $N_PP; iPP++)); do
        local currGpuId=${ALLOWED:$currGPU:1} # single char starting at pos $currGPU
        local nextGpuId=${ALLOWED:$nextGPU:1} # single char starting at pos $nextGPU

        # append this GPU's ID to the GPU string:
        local GPUSTRING=${GPUSTRING}${currGpuId}
        
        # check which GPU ID the _next_ MPI rank should use:
        local NUM=$( echo "($iPP + 1) * $NGPU / $N_PP" | bc -l )
        local COND=$( echo "$NUM >= $nextGPU" | bc )
        if [ "$COND" -eq "1" ] ; then
            ((currGPU++))
            ((nextGPU++))
        fi
    done

    # return the constructed string:
    echo "$GPUSTRING"
}
#==============================================================================

#==============================================================================
# Do the benchmarks!
#==============================================================================

DIR=$( pwd )
for NTHREADS in 2 3 5 7 11 ; do
    export OMP_NUM_THREADS=$NTHREADS
    for DLB in "no" "yes" ; do
        for RUN in 01_nranks${NRANKS}_nthreads${NTHREADS}_dlb${DLB} 02_nranks${NRANKS}_nthreads${NTHREADS}_dlb${DLB} ; do
            echo "DLB = ${DLB}"
            echo "RUN = ${RUN}"

            mkdir "$DIR"/run$RUN
            func.testquit $?

            cd "$DIR"/run$RUN
            func.testquit $?
            mkdir MEM
            func.testquit $?
            cd MEM
            func.testquit $?
            export GMX_NSTLIST=40
            $MPI_RUN -n $NRANKS $GMXBIN/gmx_mpi mdrun -npme 0 -ntomp $NTHREADS -s "$DIR/$TPRDIR/$TPRMEM" -cpt 1440 -nsteps $STEPSMEM -resetstep $RESETMEM -v -noconfout -nb gpu -dlb $DLB -gpu_id 0123
            func.testquit $?

            echo "."
        done
    done
done
