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

