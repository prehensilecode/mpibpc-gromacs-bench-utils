#!/bin/bash

function func.testquit
{
    if [ "$1" != "0" ] ; then
        echo "ERROR: exit code of the last command was $1. Exiting."
        exit
    fi
}

BASE=$( pwd )
OUTPUTFILE=results.txt
OUTPUT_ERR=errors.txt

printf "#GPU #MPI #OMP nPME  nstl  DD grid   r_Coul   ns/day  # GPUtype, processor, directory\n" > $BASE/$OUTPUTFILE
printf "The following errors occured:\n" > $BASE/$OUTPUT_ERR

for MDSYSTEM in "MEM" ; do  # can add more MD systems to test here

    cd $BASE

    for MAINDIR in $( ls -d run* ) ; do

       SUBDIR=$MAINDIR/$MDSYSTEM
       DIR=$BASE/$SUBDIR

       if [ -d "$DIR" ] ; then
           cd $DIR
           func.testquit $?

           FILENM=md.part0001.log
           if [ ! -f "$FILENM" ] ; then
               FILENM=md.log
           fi

           if [ -f "$FILENM" ] ; then
               F_ERROR=`grep      'Fatal error:'                 $FILENM`
               if [[ ! $F_ERROR ]]; then
                   VERSION=`grep      'GROMACS version:'             $FILENM | awk '{ print $3 }'`
                   CPUTYPE=`grep      'Brand:  '                     $FILENM | awk '{ print $2 " " $5 }'`
                   GPUTYPE=`grep      ' #0: NVIDIA '                 $FILENM | cut -f 1 -d , |  awk '{ print $3, $4 }'`
                   N_MPI__=`grep      ' MPI thread'                  $FILENM | awk '{ print $2 }'`
                   if [ -z $N_MPI__ ]; then
                       N_MPI__=`grep 'MPI processes'                 $FILENM | grep "Using" | awk '{ print $2 }'`
                   fi
                   N_OMP__=`grep      '^Using .* OpenMP threads '    $FILENM | awk '{ print $2 }'`
                   if [ -z $N_OMP__ ]; then
                       N_OMP__=1
                   fi
                   N_GPU__=`grep      'GPUs selected for this run'   $FILENM | awk '{ print $4 }'`
                   NANOSPD=`grep      'Performance'                  $FILENM | awk '{ print $2 }'`
                   NEIGHBS=`grep      'Neighbor search'              $FILENM | awk '{ print $8 }'`
                   NSTLIST=`grep      'nstlist              = '      $FILENM | awk '{ print $3 }'`
                   ACCELER=`grep      'Acceleration most likely'     $FILENM | awk '{ print $8 }'`
                   BRAND__=`grep      'Brand: '                      $FILENM | awk '{ print $3$5 }'`
                   PMENODE=`grep      ', separate PME nodes'         $FILENM | awk '{ print $NF }'`
#                   R_COUL_=`grep      '   optimal pme grid '         $FILENM | awk '{ print $9 }'`
                   R_COUL_=`grep      '   final   '                  $FILENM | awk '{ print $2 }'`
                   DOMDEC_=`grep      'Domain decomposition grid '   $FILENM | cut -d , -f 1 | awk '{ print $4 " " $6 " " $8 }'`
                   if [ "$N_MPI__" == "1" ] ; then
                       DOMDEC_="1 1 1"
                   fi

                   printf "%4d %4d %4d %4d %5d %8s %8.3f %8.3f  # %6s, %s, %s, %s\n" "${N_GPU__}" "${N_MPI__}" "${N_OMP__}" "${PMENODE}" "${NSTLIST}" "${DOMDEC_}" "$R_COUL_" "$NANOSPD" "${GPUTYPE}" "$CPUTYPE" "$VERSION" "$SUBDIR"  >> $BASE/$OUTPUTFILE
               else
                   echo "error"
                   echo "---> $F_ERROR in $SUBDIR/$FILENM !" >> $BASE/$OUTPUT_ERR
               fi
           else
               echo "problem"
               echo "--> No $FILENM in $DIR !" >> $BASE/$OUTPUT_ERR
           fi
       fi
   done
done

cat $BASE/results.txt | sort -g -k 10
