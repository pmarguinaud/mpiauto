#!/bin/bash

\rm -f test.eo

export dir
export bin

dir=$PWD

\rm -rf tmp
mkdir -p tmp

for bin in bin/*
do
  bin=$(basename $bin)
  mkdir -p $dir/tmp/$bin
  cd $dir/tmp/$bin

  mkdir $dir/tmp/$bin/1
  cd $dir/tmp/$bin/1
  (
     set -x
     salloc -p normal64,huge256,haddock --time="00:01:00" -N1 $dir/../mpiauto      \
                                   --verbose                                       \
                                   -np 2 -- $dir/bin/$bin 
     echo "$dir/tmp/$bin/1:$?" >> $dir/tmp/test.eo
  ) > test.eo 2>&1

  mkdir $dir/tmp/$bin/2
  cd $dir/tmp/$bin/2
  (
     set -x
     salloc -p normal64,huge256,haddock --time="00:01:00" -N1 $dir/../mpiauto      \
                                   --verbose                                       \
                                   --nouse-slurm-mpi                               \
                                   -np 2 -- $dir/bin/$bin 
     echo "$dir/tmp/$bin/2:$?" >> $dir/tmp/test.eo
  ) > test.eo 2>&1

  mkdir $dir/tmp/$bin/3
  cd $dir/tmp/$bin/3
  (
     set -x
     salloc -p normal64,huge256,haddock --time="00:01:00" -N2 $dir/../mpiauto      \
                                   --verbose                                       \
                                   -np 4 -- $dir/bin/$bin                          \
                              --   -np 2 -- $dir/bin/$bin 
     echo "$dir/tmp/$bin/3:$?" >> $dir/tmp/test.eo
  ) > test.eo 2>&1

  mkdir $dir/tmp/$bin/4
  cd $dir/tmp/$bin/4
  (
     set -x
     salloc -p normal64,huge256,haddock --time="00:01:00" -N2 $dir/../mpiauto      \
                                   --verbose                                       \
                                   --nouse-slurm-mpi                               \
                                   -np 4 -- $dir/bin/$bin                          \
                              --   -np 2 -- $dir/bin/$bin 
     echo "$dir/tmp/$bin/4:$?" >> $dir/tmp/test.eo
  ) > test.eo 2>&1

  mkdir $dir/tmp/$bin/5
  cd $dir/tmp/$bin/5
  (
     set -x
     salloc -p normal64,huge256,haddock --time="00:01:00" -N2 $dir/../mpiauto      \
                                   --verbose                                       \
                                   --nouse-slurm-mpi                               \
                                   --use-mpi-machinefile                           \
                                   -np 4 -- $dir/bin/$bin                          \
                              --   -np 2 -- $dir/bin/$bin 
     echo "$dir/tmp/$bin/5:$?" >> $dir/tmp/test.eo
  ) > test.eo 2>&1

if [ 0 -eq 1 ]
then

  mkdir $dir/tmp/$bin/6
  cd $dir/tmp/$bin/6
  (
     set -x
     salloc -p normal64,huge256,haddock --time="00:01:00" -N2 $dir/../mpiauto      \
                                   --verbose                                       \
                                   --debugger-path /opt/softs/allinea/forge/6.0.2/bin/ddt \
                                   --x11-display   marguina@lxgmap33.cnrm.meteo.fr:1      \
                                   --debug                                                \
                                   --x11-b-proxy marguina@prolixlogin3                    \
                                   --x11-f-proxy marguina@prolix.meteo.fr                 \
                                   -np 4 -nn 2 -- $dir/bin/$bin                          
     echo "$dir/tmp/$bin/6:$?" >> $dir/tmp/test.eo
  ) > test.eo 2>&1

  mkdir $dir/tmp/$bin/7
  cd $dir/tmp/$bin/7
  (
     set -x
                                                              $dir/../mpiauto      \
                                   --verbose                                       \
                                   --debugger-path /opt/softs/allinea/forge/6.0.2/bin/ddt \
                                   --x11-display   $DISPLAY                               \
                                   --x11-direct                                           \
                                   --debug                                                \
                                   -np 4 -- $dir/bin/$bin                          
     echo "$dir/tmp/$bin/7:$?" >> $dir/tmp/test.eo
  ) > test.eo 2>&1

  mkdir $dir/tmp/$bin/8
  cd $dir/tmp/$bin/8
  (
     set -x
     salloc -p normal64,huge256,haddock --time="00:01:00" -N1 $dir/../mpiauto      \
                                   --verbose                                       \
                                   --debugger-path $dir/../xgdb                           \
                                   --x11-display   marguina@lxgmap33.cnrm.meteo.fr:1      \
                                   --debug                                                \
                                   --x11-b-proxy marguina@prolixlogin3                    \
                                   --x11-f-proxy marguina@prolix.meteo.fr                 \
                                   -np 1 -- $dir/bin/$bin                          
     echo "$dir/tmp/$bin/8:$?" >> $dir/tmp/test.eo
  ) > test.eo 2>&1

  mkdir $dir/tmp/$bin/9
  cd $dir/tmp/$bin/9
  (
     set -x
                                                              $dir/../mpiauto      \
                                   --verbose                                       \
                                   --debugger-path $dir/../xgdb                           \
                                   --x11-display   $DISPLAY                               \
                                   --x11-direct                                           \
                                   --debug                                                \
                                   -np 2 -- $dir/bin/$bin                          
     echo "$dir/tmp/$bin/9:$?" >> $dir/tmp/test.eo
  ) > test.eo 2>&1

fi

  mkdir $dir/tmp/$bin/10
  cd $dir/tmp/$bin/10
  (
     set -x
     salloc -p normal64,huge256,haddock --time="00:01:00" -N2 $dir/../mpiauto      \
                                   --verbose --mpi-allow-odd-dist                  \
                                   -np 3 -nn 2 -- $dir/bin/$bin                          
     echo "$dir/tmp/$bin/10:$?" >> $dir/tmp/test.eo
  ) > test.eo 2>&1


done


