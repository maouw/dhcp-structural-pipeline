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
 echo $LD_LIBRARY_PATH  | tr ':' '\n' | grep -E '/opt/intel/oneapi/(tbb|mpi|ipp|ippcp)'
