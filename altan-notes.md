    # fix: TBB and VTK
    git fetch origin master
    git checkout 973ce2f -- \
        CMake/Basis/BasisSettings.cmake \
        CMake/Basis/CommonTools.cmake \
        CMake/Basis/TargetTools.cmake \
        CMake/Modules/CMakeLists.txt \
        CMake/Modules/FindARPACK.cmake \
        CMake/Modules/FindTBB.cmake \
        CMake/Modules/mirtkTargetDependencies.cmake \
        Modules/Common/include/mirtk/Parallel.h \
        Modules/Common/include/mirtk/Vtk.h \
        Modules/Common/include/mirtk/VtkMath.h \
        Modules/Common/src/Parallel.cc \
        Modules/PointSet/src/Triangle.cc



Add libglm-dev libquazip5-dev

add /opt/dhcp/bin to PATH

[245/1786] Building CXX object Nifti/CMakeFiles/Nifti.dir/NiftiHeader.cxx.o
/opt/build/workbench/src/src/Nifti/NiftiHeader.cxx(616): warning #264: floating-point value does not fit in required floating-point type
              double mymin = mylimits::lowest();
                             ^
          detected during instantiation of "<unnamed>::Scaling<T>::Scaling(const double &, const double &) [with T=long double]" at line 704

/opt/build/workbench/src/src/Nifti/NiftiHeader.cxx(617): warning #264: floating-point value does not fit in required floating-point type
              mult = (maxval - minval) / ((double)mylimits::max() - mymin);//multiplying is the first step of decoding (after byteswap), so start with the range
                                          ^
          detected during instantiation of "<unnamed>::Scaling<T>::Scaling(const double &, const double &) [with T=long double]" at line 704

root@2c1935676324:/opt/dhcp/lib# ldd *.so | grep 'intel' | sed -E 's/\s+\(.*$//g' | grep -o '[/].*$' | sort | uniq
/opt/intel/oneapi/compiler/2023.2.0/linux/compiler/lib/intel64_lin/libimf.so
/opt/intel/oneapi/compiler/2023.2.0/linux/compiler/lib/intel64_lin/libintlc.so.5
/opt/intel/oneapi/compiler/2023.2.0/linux/compiler/lib/intel64_lin/libiomp5.so
/opt/intel/oneapi/compiler/2023.2.0/linux/compiler/lib/intel64_lin/libirng.so
/opt/intel/oneapi/compiler/2023.2.0/linux/compiler/lib/intel64_lin/libsvml.so
/opt/intel/oneapi/mkl/2023.2.0/lib/intel64/libmkl_core.so.2
/opt/intel/oneapi/mkl/2023.2.0/lib/intel64/libmkl_intel_lp64.so.2
/opt/intel/oneapi/mkl/2023.2.0/lib/intel64/libmkl_intel_thread.so.2

/opt/intel/oneapi/compiler/2023.2.0/linux/compiler/lib/intel64_lin
/opt/intel/oneapi/mkl/2023.2.0/lib/intel64
/opt/intel/oneapi/tbb/2021.12/env/../lib/intel64/gcc4.8

 echo $LD_LIBRARY_PATH  | tr ':' '\n' | grep -E '/opt/intel/oneapi/(tbb|mpi|ipp|ippcp)'
    libimf.so => not found
    libintlc.so.5 => not found
    libiomp5.so => not found
    libirng.so => not found
    libmkl_core.so.2 => not found
    libmkl_intel_lp64.so.2 => not found
    libmkl_intel_thread.so.2 => not found
    libmkl_tbb_thread.so.2 => not found
    libsvml.so => not found
    libtbb.so.12 => not found
    libtbbmalloc.so.2 => not found

    libimf.so => /opt/intel/oneapi/compiler/2023.2.0/linux/compiler/lib/intel64_lin/libimf.so 
    libintlc.so.5 => /opt/intel/oneapi/compiler/2023.2.0/linux/compiler/lib/intel64_lin/libintlc.so.5 
    libiomp5.so => /opt/intel/oneapi/compiler/2023.2.0/linux/compiler/lib/intel64_lin/libiomp5.so 
    libirng.so => /opt/intel/oneapi/compiler/2023.2.0/linux/compiler/lib/intel64_lin/libirng.so 
    libmkl_core.so.2 => /opt/intel/oneapi/mkl/2023.2.0/lib/intel64/libmkl_core.so.2 
    libmkl_intel_lp64.so.2 => /opt/intel/oneapi/mkl/2023.2.0/lib/intel64/libmkl_intel_lp64.so.2 
    libmkl_intel_thread.so.2 => /opt/intel/oneapi/mkl/2023.2.0/lib/intel64/libmkl_intel_thread.so.2 
    libmkl_tbb_thread.so.2 => /opt/intel/oneapi/mkl/2023.2.0/lib/intel64/libmkl_tbb_thread.so.2 
    libsvml.so => /opt/intel/oneapi/compiler/2023.2.0/linux/compiler/lib/intel64_lin/libsvml.so 
    libtbb.so.12 => /opt/intel/oneapi/tbb/2021.12/env/../lib/intel64/gcc4.8/libtbb.so.12 
    libtbbmalloc.so.2 => /opt/intel/oneapi/tbb/2021.12/env/../lib/intel64/gcc4.8/libtbbmalloc.so.2 

---

6.3. Activate Bash's Debug Mode

If you still don't see the error of your ways, Bash's debugging mode might help you see the problem through the code.

When Bash runs with the x option turned on, it prints out every command it executes before executing it (to standard error). That is, after any expansions have been applied. As a result, you can see exactly what's happening as each line in your code is executed. Pay very close attention to the quoting used. Bash uses quotes to show you exactly which strings are passed as a single argument.

There are three ways of turning on this mode.

    Run the script with bash -x:

    $ bash -x ./mybrokenscript

    Modify your script's header:

    #!/bin/bash -x
    [.. script ..]

    Or:

    #!/usr/bin/env bash
    set -x

    Or add set -x somewhere in your code to turn on this mode for only a specific block of your code:

    #!/usr/bin/env bash
    [..irrelevant code..]
    set -x
    [..relevant code..]
    set +x
    [..irrelevant code..]

Because the debugging output goes to stderr, you will generally see it on the screen, if you are running the script in a terminal. If you would like to log it to a file, you can tell Bash to send all stderr to a file:

exec 2>> /path/to/my.logfile
set -x

A nice feature of bash version >= 4.1 is the variable BASH_XTRACEFD. This allows you to specify the file descriptor to write the set -x debugging output to. In older versions of bash, this output always goes to stderr, and it is difficult if not impossible to keep it separate from normal output (especially if you are logging stderr to a file, but you need to see it on the screen to operate the program). Here's a nice way to use it:

Toggle line numbers

   1 # dump set -x data to a file
   2 # turns on with a filename as $1
   3 # turns off with no params
   4 setx_output()
   5 {
   6     if [[ $1 ]]; then
   7         exec {BASH_XTRACEFD}>>"$1"
   8         set -x
   9     else
  10         set +x
  11         unset -v BASH_XTRACEFD
  12     fi
  13 }

If you have a complicated mess of scripts, you might find it helpful to change PS4 before setting -x. If the value assigned to PS4 is surrounded by double quotes it will be expanded during variable assignment, which is probably not what you want; with single quotes, the value will be expanded when the PS4 prompt is displayed.

PS4='+$BASH_SOURCE:$LINENO:$FUNCNAME: '

6.4. Step Your Code

If the script goes too fast for you, you can enable code-stepping. The following code uses the DEBUG trap to inform the user about what command is about to be executed and wait for his confirmation do to so. Put this code in your script, at the location you wish to begin stepping:

debug_prompt () { read -p "[$BASH_SOURCE:$LINENO] $BASH_COMMAND?" _ ;}
trap 'debug_prompt "$_"' DEBUG

6.5. The Bash Debugger

The Bash Debugger Project is a gdb-style debugger for bash, available from http://bashdb.sourceforge.net/

The Bash Debugger will allow you to walk through your code and help you track down bugs. 










# 

Invoked non-interactively

When Bash is started non-interactively, to run a shell script, for example, it looks for the variable BASH_ENV in the environment, expands its value if it appears there, and uses the expanded value as the name of a file to read and execute. Bash behaves as if the following command were executed:

if [ -n "$BASH_ENV" ]; then . "$BASH_ENV"; fi

but the value of the PATH variable is not used to search for the filename.

As noted above, if a non-interactive shell is invoked with the --login option, Bash attempts to read and execute commands from the login shell startup files. 