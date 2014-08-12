#!/bin/bash
# This script assumes you've already installed packages mentioned here: http://www.openfoam.org/download/git.php
#Notes: On Ubuntu, don't forget to also run:
#   sudo apt-get install libglib2.0-dev subversion binutils-dev 
# On x86_64, also include: libc6-dev-i386

set -e

echo "Detected system specifications:"
#Detect architecture and make an abstract designation
arch=`uname -m`
case $arch in
  i*86)
    arch=32
    ;;
  x86_64)
    arch=64
    ;;
  *)
    echo "Sorry, architecture not recognized, aborting."
    exit 1
    ;;
esac

echo "Architecture to be used: $arch bit"

echo "Starting downloads..."
cd $HOME
if [ ! -d OpenFOAM ]; then mkdir OpenFOAM; fi
cd OpenFOAM
wget -c http://downloads.sourceforge.net/project/foam/foam/1.5/OpenFOAM-1.5.General.gtgz
wget -c http://downloads.sourceforge.net/project/foam/foam/1.7.1/ThirdParty-1.7.1.gtgz

echo "Extracting packages..."
tar -xzf OpenFOAM-1.5.General.gtgz
tar -xzf ThirdParty-1.7.1.gtgz --transform 's=ThirdParty-1.7.1=ThirdParty-1.5='


echo "Fix errors..."
#lets plug-in the latest bashrc and settings.sh
cd OpenFOAM-1.5/etc
mv bashrc bashrc.orig
wget -c --no-check-certificate https://github.com/OpenCFD/OpenFOAM-1.7.x/raw/master/etc/bashrc
mv settings.sh settings.sh.orig
wget -c --no-check-certificate https://github.com/OpenCFD/OpenFOAM-1.7.x/raw/master/etc/settings.sh
mv aliases.sh aliases.sh.orig
wget -c --no-check-certificate https://github.com/OpenCFD/OpenFOAM-1.7.x/raw/master/etc/aliases.sh

sed -i -e 's_1\.7\.x_1.5_' -e 's_Gcc};_Gcc43};_' bashrc
sed -i -e 's_: ${compilerInstall:=system}_: ${compilerInstall:=OpenFOAM}_' settings.sh

#unleash multicore building
echo '' >> bashrc
echo '#' >> bashrc
echo '# Set the number of cores to build on' >> bashrc
echo '#' >> bashrc
echo 'WM_NCOMPPROCS=1' >> bashrc
echo '' >> bashrc
echo 'if [ -r /proc/cpuinfo ]' >> bashrc
echo 'then' >> bashrc
echo '    WM_NCOMPPROCS=$(egrep "^processor" /proc/cpuinfo | wc -l)' >> bashrc
echo '    [ $WM_NCOMPPROCS -le 8 ] || WM_NCOMPPROCS=8' >> bashrc
echo 'fi' >> bashrc
echo '' >> bashrc
echo 'echo "Building on " $WM_NCOMPPROCS " cores"' >> bashrc
echo 'export WM_NCOMPPROCS' >> bashrc
echo 'export WM_OS=Unix' >> bashrc

#This is a hack for modern 64bit Ubuntu
# http://www.lukedodd.com/?p=225
if [ -n "$arch" -a $arch -eq 64 ]; then
  echo 'export LIBRARY_PATH=/usr/lib/x86_64-linux-gnu' >> bashrc
else #they missplaced stubs-32.h ...
  echo 'export LIBRARY_PATH=/usr/lib/i386-linux-gnu' >> bashrc
  echo 'export C_INCLUDE_PATH=/usr/include/i386-linux-gnu' >> bashrc
  echo 'export CPLUS_INCLUDE_PATH=/usr/include/i386-linux-gnu' >> bashrc
fi


#Patch to work on 32-bit versions
if [ -n "arch" -a $arch -eq 32 ]; then

echo '--- ../../bashrc  2009-11-21 00:00:47.502453988 +0000
+++ bashrc  2009-11-21 00:01:20.814519578 +0000
@@ -93,7 +93,7 @@
 # Compilation options (architecture, precision, optimised, debug or profiling)
 # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 # WM_ARCH_OPTION = 32 | 64
-: ${WM_ARCH_OPTION:=64}; export WM_ARCH_OPTION
+: ${WM_ARCH_OPTION:=32}; export WM_ARCH_OPTION

 # WM_PRECISION_OPTION = DP | SP
 : ${WM_PRECISION_OPTION:=DP}; export WM_PRECISION_OPTION' | patch -p0

fi


#now lets get some important things
cd ../bin
wget -c --no-check-certificate https://github.com/OpenCFD/OpenFOAM-1.7.x/raw/master/bin/foamEtcFile
chmod +x foamEtcFile

#gotta fix some rules...
cd ../wmake/rules
cp -r linux64Gcc linux64Gcc43
cp -r linuxGcc linuxGcc43
sed -i -e '/include $(GENERAL_RULES)\/java/d' General/standard
sed -i -e 's=/lib/cpp $(GFLAGS)=cpp -traditional-cpp $(GFLAGS)=' linuxGcc43/general
sed -i -e 's=/lib/cpp $(GFLAGS)=cpp -traditional-cpp $(GFLAGS)=' linux64Gcc43/general

#still gotta get an important function
cd ..
wget -c --no-check-certificate https://github.com/OpenCFD/OpenFOAM-1.7.x/raw/master/wmake/wmakeCheckPwd
chmod +x wmakeCheckPwd
cd ..

#Remove all stupid comments from "Make/options" files
find . -name 'options' | grep 'Make/options' | xargs sed -i -e '/^\/\//d'

(
#activate the OpenFOAM environment we want, but before clean up some variables
unset WM_PROJECT_VERSION FOAM_INST_DIR WM_COMPILER
. etc/bashrc

echo "Get and build gcc..."
#lets fly to the Thirdparty-1.5 dir and fix a few things
cd $WM_THIRD_PARTY_DIR
wget -c http://modular.nucleation.googlecode.com/hg/of17x/files/ThirdParty_Allwmake.diff
patch -p0 < ThirdParty_Allwmake.diff
wget -c http://original.nucleation.googlecode.com/hg/build-gcc_v4.tar.gz
tar -xzf build-gcc_v4.tar.gz
echo "Things are going to get hot, 'cause gcc 4.3.3 is going to build at full speed."
echo "You can track the current progress in another terminal, by running:"
echo "  tail -F $PWD/gccmake.log"
./build-gcc43 > gccmake.log 2>&1
)

(
#activate the OpenFOAM environment we want, but before clean up some variables
unset WM_PROJECT_VERSION FOAM_INST_DIR WM_COMPILER
. etc/bashrc

#build 3rd party first, due to a strange bug regarding OpenMPI...
echo "Building ThirdParty, 1st stage, no monitoring needed..."
#lets fly to the Thirdparty-1.5 dir and fix a few things
cd $WM_THIRD_PARTY_DIR
./Allwmake > 3rdmake_1ststage.log 2>&1
)

#now lets get this party started!
. etc/bashrc
echo "Things are going to get hot, 'cause OpenFOAM 1.5 is going to build at full speed."
echo "You can track the current progress in another terminal, by running:"
echo "  tail -F $PWD/make.log"
./Allwmake > make.log 2>&1

if [ `grep "Error " make.log | wc -l` -eq 0 ] ; then
  echo "All done and ready to get work! Well, only if you run:"
  echo "     source $WM_PROJECT_DIR/etc/bashrc"
else
  echo "Crud, something went very wrong :("
  tar -czf make.log.tar.gz make.log
  echo "Please attach the following file to your next forum post: $PWD/make.log.tar.gz"
fi
