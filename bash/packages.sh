
function BotLog {
  echo $@ >&2
}

function BotPlatformSetup {
  export BOT_OS_NAME=$1
  if [[ $BOT_OS_NAME == 'linux' ]]; then
    export BOT_SHLIB="so"
    export LDFLAGS="$LDFLAGS -Wl,-rpath -Wl,'\$ORIGIN/../lib'"
    export CMAKE_FLAGS="$CMAKE_FLAGS -DPYTHON_INCLUDE_DIR=/usr/include/python2.7"
    export CMAKE_FLAGS="$CMAKE_FLAGS -DPYTHON_LIBRARY=/opt/python/2.7.13/lib/libpython2.7.so.1.0"
    export CMAKE_FLAGS="$CMAKE_FLAGS -DNumPy_DIR=/usr/lib/python2.7/dist-packages/numpy/core/include"
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$BOT_ROOT/lib"
    #export LDFLAGS="$LDFLAGS -Wl,-rpath -Wl,${BOT_ROOT}/lib"
  elif [[ $BOT_OS_NAME == 'osx' ]]; then
    export BOT_SHLIB="dylib"
    export PATH="$PATH:/usr/local/opt/coreutils/libexec/gnubin"
    export DYLD_FALLBACK_LIBRARY_PATH="${BOT_ROOT}/lib:$DYLD_LIBRARY_PATH"
  fi
}

function BotTimeRemaing {
  local REMAIN=$(expr 40 - $SECONDS / 60)
  if [[ $REMAIN -gt 0 && ( -z "$1" || $REMAIN -gt $1 ) ]]; then
    echo $REMAIN
  fi
}

function BotGetURL {
    local URL=$1; shift;
    local NAME=`basename $URL`
    wget $URL --no-check-certificate "$@" -qO "$TMPDIR/$NAME"
    echo "$TMPDIR/$NAME"
}

function BotTmpDir {
  # echo `mktemp -d 2>/dev/null || mktemp -d -t 'tmpdir'`
  mkdir -p "$TMPDIR/$1"
  echo "$TMPDIR/$1"
}

function BotExtractUrl {
  local DSTDIR=`BotTmpDir $1`; shift;
  local URL=$1; shift;
  local NAME=`basename $URL`
  local EXT=${NAME##*.}

  local FMT=z
  case "$EXT" in
    [tT][aA][rR]) FMT="" ;;
    [tT][gG][zZ]) FMT="z" ;;
    [tT][bB][zZ]) FMT="j" ;;
    [tT][xX][zZ]) FMT="J" ;;
  esac
  # 7Z p7zip
  # ZIP unzip
  wget $URL --no-check-certificate "$@" -qO- | tar -x${FMT} --strip-components=1 -C "$DSTDIR"
  echo $DSTDIR
}

function BotCmakeBuild {
  local TARGET=$1; shift;
  local PREFIX=$1; shift;
  mkdir tmpbuild && pushd tmpbuild
  echo  cmake $CMAKE_FLAGS -DCMAKE_PREFIX_PATH=$PREFIX -DCMAKE_INSTALL_PREFIX=$PREFIX "$@" ..
  cmake $CMAKE_FLAGS -DCMAKE_PREFIX_PATH=$PREFIX -DCMAKE_INSTALL_PREFIX=$PREFIX "$@" ..
  make -j $BOT_JOBS $TARGET
  popd
}

function BotCmakeBuildArk {
  local DSTDIR=$(BotExtractUrl $1 $2); shift; shift;
  pushd "$DSTDIR";
  BotCmakeBuild "$@"
  popd
  echo "$DSTDIR"
}

function BotCmakeInstall {
  BotCmakeBuild install "$@"
}

function BotCmakeInstallArk {
  pushd "$(BotExtractUrl $1 $2)"; shift; shift;
  BotCmakeInstall "$@"
  popd
}

function BotCmakeInstallGit {
  local DSTDIR=`BotTmpDir $1`; shift;
  git clone --depth 10 $1 "$DSTDIR"; shift;
  pushd $DSTDIR
    BotCmakeInstall "$@"
  popd
}

function BotMakeBuildArk {
  pushd "$(BotExtractUrl $1 $2)"; shift; shift;
  local PREFIX=$1; shift;
  ./configure --prefix=$PREFIX --enable-shared --disable-static "$@"
  make -j $BOT_JOBS install
  popd
}

function BotEmptyUsrLocal {
  sudo mv /usr/local.bak/opt /usr/local/
  sudo mv /usr/local.bak/Cellar /usr/local/
  sudo mv /usr/local.bak/bin/cmake /usr/local/bin/
  sudo mv /usr/local.bak/bin/wget /usr/local/bin/
  sudo mv /usr/local.bak/bin/git /usr/local/bin/
  sudo mv /usr/local.bak/bin/ccache /usr/local/bin/
}

function BotRestoreUsrLocal {
  sudo mv /usr/local/opt /usr/local.bak/
  sudo mv /usr/local/Cellar /usr/local.bak/
  sudo mv /usr/local/bin/cmake /usr/local.bak/bin/
  sudo mv /usr/local/bin/wget /usr/local.bak/bin/
  sudo mv /usr/local/bin/git /usr/local.bak/bin/
  sudo mv /usr/local/bin/timeout /usr/local.bak/bin/
  tar -c /usr/local | gzip -9 > $HOME/built/built.tgz
  sudo mv /usr/local /usr/local.built
  sudo mv /usr/local.bak /usr/local
}

function BotMvLibAndInclude {
  rsync -a "$1/lib" "$2/"
  rsync -a "$1/include" "$2/"
}

function BotMountDMG {
  echo `hdiutil attach "$1" | grep /Volumes | awk '{print substr($0, index($0,$3))}'`
}

function BotMountURL {
  echo `BotMountDMG $(BotGetURL $1)`
}

function BotInstallPackages {
  echo "BotInstallPackages $@"
  local LDIR="$1"; shift
  pushd "$LDIR"
  for f in "$@"; do
    gzip -cd "$f" | pax -r
  done
  rsync -a ./Library/* $BOT_ROOT/Library/
  rsync -a ./usr/* $BOT_ROOT
  popd
  # rm -rf "$LDIR"/*
}

function BotHasInclude {
  if [[ -f "$BOT_ROOT/include/$1" || -d "$BOT_ROOT/include/$1" ]]; then
    echo 1
  fi
}

function BotMachOFiles {
  if [ -f "$1" ]; then
    if [[ `file $1 | awk 'NR==1{print $2}'` == "Mach-O" ]]; then
        echo $1
    fi
    return
  fi

  for f in "$1/"*; do
    if [[ ! -h $f ]] && [[ `file $f | awk 'NR==1{print $2}'` == "Mach-O" ]]; then
      echo $f
    fi
  done
}

function BotInstallPathID {
  local recurse="";
  if [[ $1 == "recurse" ]]; then
    recurse=1
    shift;
  fi
  for lib in $@; do
    if [ -f "$BOT_ROOT/lib/$lib" ]; then
      install_name_tool -id @loader_path/../lib/$lib $BOT_ROOT/lib/$lib
      if [[ ! -z $recurse ]]; then
        for libl in $@; do
          install_name_tool -change $libl @loader_path/../lib/$libl $BOT_ROOT/lib/$lib
        done
      fi
    fi
  done
}

function BotInstallNameChangePrefix {
  local prfx=$1; shift;
  local rpath=$1; shift;
  for arg in $@; do
    for file in `BotMachOFiles $arg`; do
      local dynlib=`file $file | grep dynamically`
      otool -L $file | sed 1d | while read line; do
        local abs=`echo $line | grep "$prfx"`
        if [[ ! -z $abs ]]; then
          abs=${abs%% *}
          lib=${abs#$prfx}
          if [[ -z $dynlib ]]; then
            install_name_tool -change "$abs" ${rpath}$lib $file
          else
            install_name_tool -id ${rpath}$lib $file
          fi
        fi
        dynlib=""
      done
    done
  done
}

function BotInstallNameChange {
  BotInstallNameChangePrefix $BOT_ROOT/lib/ $@
}

function BotPlatformInstall {
  if [ $BOT_OS_NAME == 'osx' ]; then
    # CUDA
    if [ ! -d /usr/local/cuda ]; then
      local vol=`BotMountURL http://developer.download.nvidia.com/compute/cuda/7.5/Prod/local_installers/cuda_7.5.27_mac.dmg`
      sudo $vol/CUDAMacOSXInstaller.app/Contents/MacOS/CUDAMacOSXInstaller --accept-eula --silent --no-window --install-package=cuda-toolkit
    fi

    # QT
    local vol=`BotMountURL http://qt.mirror.constant.com/archive/qt/4.8/4.8.6/qt-opensource-mac-4.8.6-1.dmg`
    QT_PKGS="${vol}/packages/Qt_"
    QT_ARK=".pkg/Contents/Archive.pax.gz"
    BotInstallPackages `BotTmpDir QT` "${QT_PKGS}libraries${QT_ARK}" "${QT_PKGS}headers${QT_ARK}" "${QT_PKGS}tools${QT_ARK}"

    # PySide
    local pkg=`BotGetURL http://pyside.markus-ullmann.de/pyside-1.2.1-qt4.8.5-py27apple-developer-signed.pkg`
    pkgutil --expand $pkg "$TMPDIR/PySide"
    BotInstallPackages "$TMPDIR/PySide" Payload

    # Intel TBB
    local USD_TBB=tbb2017_20161128oss
    #USD_TBB=tbb2017_20161004oss
    local TBB_URL=https://www.threadingbuildingblocks.org/sites/default/files/software_releases/mac/${USD_TBB}_osx.tgz
    BotMvLibAndInclude `BotExtractUrl tbb $TBB_URL` "$BOT_ROOT"
  fi
}

function BotInstall_pkgconfig {
  local pconfig=`which pkg-config`
  if [[ ! -z $pconfig ]] && [[ $pconfig != "pkg-config not found" ]]; then
    BotLog "Using pkg-config: $pconfig"
    return 0;
  fi

  BotMakeBuildArk pkgcfg https://pkg-config.freedesktop.org/releases/pkg-config-0.29.1.tar.gz "$BOT_ROOT" $@
}

function BotInstall_boost {
  if [ ! $(BotTimeRemaing 15) ] || [ $(BotHasInclude boost) ]; then
    BotLog "Using cached boost"
    return 0;
  fi

  pushd `BotExtractUrl boost https://pilotfiber.dl.sourceforge.net/project/boost/boost/1.63.0/boost_1_63_0.tar.gz`
    # echo "REMAINING: " `BotTimeRemaing`
    ./bootstrap.sh
    # echo "REMAINING: " `BotTimeRemaing`
    ./bjam -j 4 --prefix="$BOT_ROOT" --build-type=minimal link=shared cxxflags="-Wno-c99-extensions -Wno-variadic-macros" $@ install # > /dev/null
    #./bjam -j 4 --prefix="$BOT_ROOT" --build-type=minimal link=shared install > /tmp/boost.log & tail -f /tmp/boost.log
    # travis_wait `BotTimeRemaing` ./bjam -j 4 --prefix="$BOT_ROOT" --build-type=minimal link=shared install > /tmp/boost.log
    # timeout "$(BotTimeRemaing)m" ./bjam -j 4 --prefix="$BOT_ROOT" --build-type=minimal link=shared install > /tmp/boost.log & tail -f /tmp/boost.log
  popd

  if [ $BOT_OS_NAME == 'osx' ] ; then
    BotInstallPathID recurse libboost_chrono.dylib libboost_container.dylib libboost_context.dylib \
      libboost_coroutine.dylib libboost_date_time.dylib libboost_filesystem.dylib \
      libboost_graph.dylib libboost_iostreams.dylib libboost_locale.dylib \
      libboost_log_setup.dylib libboost_log.dylib libboost_math_c99.dylib \
      libboost_math_c99f.dylib libboost_math_c99l.dylib libboost_math_tr1.dylib \
      libboost_math_tr1f.dylib libboost_math_tr1l.dylib libboost_numpy.dylib \
      libboost_prg_exec_monitor.dylib libboost_program_options.dylib \
      libboost_python.dylib libboost_random.dylib libboost_regex.dylib \
      libboost_serialization.dylib libboost_signals.dylib libboost_system.dylib \
      libboost_thread.dylib libboost_timer.dylib libboost_type_erasure.dylib \
      libboost_unit_test_framework.dylib libboost_wave.dylib libboost_wserialization.dylib
  fi
}

function BotInstall_glew {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude GL) ]; then
    BotLog "Using cached glew"
    return 0;
  fi

  pushd "$(BotExtractUrl glew https://cytranet.dl.sourceforge.net/project/glew/glew/2.0.0/glew-2.0.0.tgz)"
    make -j $BOT_JOBS GLEW_PREFIX="$BOT_ROOT" GLEW_DEST="$BOT_ROOT" $@ install
    if [ $BOT_OS_NAME == 'linux' ]; then
      mv $BOT_ROOT/lib64/* $BOT_ROOT/lib
    elif [ $BOT_OS_NAME == 'osx' ] ; then
      BotInstallPathID libGLEW.2.0.0.dylib
    fi
  popd
}

function BotInstall_freetype {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude freetype2) ]; then
    BotLog "Using cached freetype"
    return 0;
  fi

  BotMakeBuildArk harfbuzz https://www.freedesktop.org/software/harfbuzz/release/harfbuzz-1.4.1.tar.bz2 "$BOT_ROOT" $@
  BotMakeBuildArk freetype http://download.savannah.gnu.org/releases/freetype/freetype-2.7.1.tar.gz "$BOT_ROOT" $@
}

function BotInstall_clew {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude clew.h) ]; then
    BotLog "Using cached clew"
    return 0;
  fi

  BotCmakeInstallGit clew https://github.com/martijnberger/clew.git "$BOT_ROOT" $@
}
  
function BotInstall_glfw {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude GLFW) ]; then
    BotLog "Using cached GLFW"
    return 0;
  fi

  BotCmakeInstallArk glfw https://github.com/glfw/glfw/archive/3.2.1.tar.gz "$BOT_ROOT" $@
}

function BotInstall_ptex {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude Ptexture.h) ]; then
    BotLog "Using cached Ptex"
    return 0;
  fi

  BotCmakeInstallArk ptex https://github.com/wdas/ptex/archive/v2.1.28.tar.gz "$BOT_ROOT" $@
}

function BotInstall_osd {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude opensubdiv) ]; then
    BotLog "Using cached OpenSubdiv"
    return 0;
  fi

  BotCmakeInstallArk osd https://github.com/PixarAnimationStudios/OpenSubdiv/archive/v3_1_1.tar.gz "$BOT_ROOT" \
    -DNO_EXAMPLES=1 -DNO_TUTORIALS=1 -DNO_REGRESSION=1 -DNO_DOC=1 \
    -DCUDA_NVCC_FLAGS="-ccbin $CCOMPILER" -DGLEW_LOCATION="$BOT_ROOT" \
    -DGLEW_ROOT="$BOT_ROOT" -DTBB_LOCATION="$BOT_ROOT" $@
  # -DGLEW_INCLUDE_DIR="$BOT_ROOT/include/GL" -DGLEW_LIBRARY="$BOT_ROOT/lib"
  #-DOPENGL_4_2_FOUND=1 -DOPENGL_4_3_FOUND=1
  #-DOPENSUBDIV_HAS_GLSL_TRANSFORM_FEEDBACK
}

function BotInstall_numpy {
  # https://github.com/numpy/numpy/archive/v1.12.0.tar.gz
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude numpy) ]; then
    BotLog "Using cached numpy"
    return 0;
  fi

  mkdir -p "$BOT_ROOT/lib/python2.7/site-packages"
  if [ $BOT_OS_NAME != 'linux' ]; then
    pushd `BotTmpDir numpy`
      if [ $BOT_OS_NAME == 'linux' ]; then
        numpy="https://pypi.python.org/packages/5b/a4/761dd4596da94d3ce438d93673fcd8053eb368400526223ab7e981547592/numpy-1.12.0-cp27-cp27m-manylinux1_x86_64.whl"
      else
        numpy="https://pypi.python.org/packages/4b/fb/99346d8d7d2460337f9e1772072d35e1274ca81ce9ef64f821d4686233b4/numpy-1.12.0-cp27-cp27m-macosx_10_6_intel.macosx_10_9_intel.macosx_10_9_x86_64.macosx_10_10_intel.macosx_10_10_x86_64.whl"
      fi
      numpy=`BotGetURL "$numpy"`
      echo "numpy: $numpy"
      ls -l $numpy
      unzip $numpy
      if [ $BOT_OS_NAME == 'linux' ]; then
        sudo mv numpy/.libs/* "$BOT_ROOT/lib/"
        rm -rf numpy/.libs/
        ldd numpy/core/multiarray.so
        ldd $BOT_ROOT/lib/libopenblasp-r0-39a31c03.2.18.so
        ldd $BOT_ROOT/lib/libgfortran-ed201abd.so.3.0.0
      fi
      sudo mv numpy/core/include/numpy "$BOT_ROOT/include"
      sudo mv numpy $BOT_ROOT/lib/python2.7/site-packages/
    popd
    export PYTHONPATH="$PYTHONPATH:$BOT_ROOT/lib/python2.7/site-packages"
  else
    export PYTHONPATH="$PYTHONPATH:/usr/lib/python2.7/dist-packages"
  fi
  #python "$BOT_ROOT/lib/python2.7/site-packages/numpy/core/machar.py"
  python --version
  which python
  ldd /opt/python/2.7.13/bin/python
  find /usr/include -name Python.h
  python -c "import numpy.core.multiarray"
  python -c "import numpy;print numpy.get_include()"
}
  
function BotInstall_openexr {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude OpenEXR) ]; then
    BotLog "Using cached OpenEXR"
    return 0;
  fi

  #BotMakeBuildArk ilmbase http://download.savannah.nongnu.org/releases/openexr/ilmbase-2.2.0.tar.gz "$BOT_ROOT"
  #BotMakeBuildArk openexr http://download.savannah.nongnu.org/releases/openexr/openexr-2.2.0.tar.gz "$BOT_ROOT" --with-pkg-config=no LDFLAGS="-Wl,-rpath -Wl,$USD_DEPS/lib"

  pushd `BotExtractUrl openexr https://github.com/openexr/openexr/archive/v2.2.0.tar.gz`
    ls -l
    for dir in IlmBase OpenEXR PyIlmBase OpenEXR_Viewers; do
      pushd $dir
      BotCmakeInstall "$BOT_ROOT" -DBOOSTROOT="$BOT_ROOT" -DILMBASE_PACKAGE_PREFIX="$BOT_ROOT" \
        -DCMAKE_CXX_FLAGS="-I${BOT_ROOT}/include" $@
      popd
    done
    pushd "$BOT_ROOT/lib"
      ln -s libIlmImfUtil-2_2.${BOT_SHLIB} libIlmImfUtil.${BOT_SHLIB}
      ln -s libIlmThread-2_2.${BOT_SHLIB} libIlmThread.${BOT_SHLIB}
      ln -s libIex-2_2.${BOT_SHLIB} libIex.${BOT_SHLIB}
      ln -s libImath-2_2.${BOT_SHLIB} libImath.${BOT_SHLIB}
    popd
    mkdir "${BOT_ROOT}/include/PyImath"
    cp PyIlmBase/PyImath/*.h "${BOT_ROOT}/include/PyImath/"
    ls -l PyIlmBase/PyImath/*.h
    ls -l ${BOT_ROOT}/include/PyImath/
  popd
}

function BotInstall_hdf5 {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude hdf5.h) ]; then
    BotLog "Using cached HDF5"
    return 0;
  fi

  BotMakeBuildArk szip https://support.hdfgroup.org/ftp/lib-external/szip/2.1.1/src/szip-2.1.1.tar.gz "$BOT_ROOT" $@
  if [ $BOT_OS_NAME == 'osx' ] ; then
    BotInstallPathID libsz.2.dylib
  fi

  # -Wno-strict-overflow -Wno-double-promotion -Wno-sign-conversion -Wno-c++-compat -Wno-cast-qual -Wno-format-nonliteral -Wno-unused-result -Wno-conversion -Wno-suggest-attribute=pure -Wno-suggest-attribute=const -Wno-frame-larger-than= -Wno-larger-than=
  BotMakeBuildArk hdf5 https://support.hdfgroup.org/ftp/HDF5/current18/src/hdf5-1.8.19.tar.gz \
    "$BOT_ROOT" --with-szip="$BOT_ROOT" $@
}

function BotInstall_alembic {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude Alembic) ]; then
    BotLog "Using cached Alembic"
    return 0;
  fi

  BotCmakeInstallArk alembic https://github.com/alembic/alembic/archive/1.7.3.tar.gz "$BOT_ROOT" \
    -DUSE_HDF5=ON -DUSE_PYALEMBIC=ON \
    -DALEMBIC_PYIMATH_MODULE_DIRECTORY="$BOT_ROOT/lib/python2.7/site-packages" \
    -DALEMBIC_PYILMBASE_INCLUDE_DIRECTORY="$BOT_ROOT/include/PyImath" \
    -DHDF5_C_INCLUDE_DIR="$$BOT_ROOT" -DCMAKE_CXX_FLAGS="-Wno-deprecated-register" \
    $@
}

function BotInstall_field3D {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude Field3D) ]; then
    BotLog "Using cached Field3D"
    return 0;
  fi

  BotCmakeInstallArk field3d https://github.com/imageworks/Field3D/archive/v1.7.2.tar.gz "$BOT_ROOT" \
  -DHDF5_INCLUDE_DIRS=$BOT_ROOT/include -DHDF5_LIBRARIES=$BOT_ROOT/lib $@
}

function BotInstall_blosc {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude blosc.h) ]; then
    BotLog "Using cached blosc"
    return 0;
  fi

  BotCmakeInstallArk blosc https://github.com/Blosc/c-blosc/archive/v1.12.1.tar.gz "$BOT_ROOT" $@
}

function BotInstall_openvdb {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude openvdb) ]; then
    BotLog "Using cached OpenVDB"
    return 0;
  fi

  BotInstall_blosc;
  BotCmakeInstallArk openvdb https://github.com/dreamworksanimation/openvdb/archive/v4.0.2.tar.gz "$BOT_ROOT" \
    -DHDF5_INCLUDE_DIRS="$BOT_ROOT/include" -DHDF5_LIBRARIES="$BOT_ROOT/lib" \
    -DBLOSC_LOCATION="$BOT_ROOT" -DTBB_LOCATION="$BOT_ROOT" -DILMBASE_LOCATION="$BOT_ROOT" $@
}

function BotInstall_png {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude libpng16) ]; then
    BotLog "Using cached PNG"
    return 0;
  fi

  BotMakeBuildArk png https://download.sourceforge.net/libpng/libpng-1.6.30.tar.gz "$BOT_ROOT" $@
}

function BotInstall_yasm {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude libyasm) ]; then
    BotLog "Using cached yasm"
    return 0;
  fi

  BotMakeBuildArk yasm http://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz "$BOT_ROOT"
}

function BotInstall_jpeg {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude jpeglib.h) ]; then
    BotLog "Using cached JPEG"
    return 0;
  fi

  BotInstall_yasm
  BotCmakeInstallGit jpeg https://github.com/marsupial/libjpeg-turbo.git "$BOT_ROOT" \
    -DNASM="$BOT_ROOT/bin/yasm" -DENABLE_SHARED=ON -DENABLE_STATIC=OFF $@
  #BotCmakeInstallArk jpeg https://github.com/libjpeg-turbo/libjpeg-turbo/archive/1.5.2.tar.gz "$BOT_ROOT" $@
}

function BotInstall_gif {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude gif_lib.h) ]; then
    BotLog "Using cached GIF"
    return 0;
  fi

  BotMakeBuildArk gif "https://iweb.dl.sourceforge.net/project/giflib/giflib-5.1.4.tar.bz2" "$BOT_ROOT" $@
}

function BotInstall_tiff {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude tiff.h) ]; then
    BotLog "Using cached Tiff"
    return 0;
  fi

  BotMakeBuildArk tiff http://dl.maptools.org/dl/libtiff/tiff-3.8.2.tar.gz "$BOT_ROOT" $@
}

function BotInstall_jpeg2000 {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude openjpeg-2.1) ]; then
    BotLog "Using cached OpenJPEG"
    return 0;
  fi

  BotCmakeInstallArk jasper https://github.com/mdadams/jasper/archive/version-2.0.10.tar.gz "$BOT_ROOT" $@
  BotCmakeInstallArk openjpeg https://github.com/uclouvain/openjpeg/archive/v2.1.2.tar.gz "$BOT_ROOT" $@
  mv "$BOT_ROOT/lib/openjpeg-2.1" "$BOT_ROOT/lib/cmake"
}

function BotInstall_webp {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude webp) ]; then
    BotLog "Using cached WebP"
    return 0;
  fi

  pushd $(BotExtractUrl webp "https://github.com/webmproject/libwebp/archive/v0.6.0.tar.gz")
  BotCmakeBuild "" "$BOT_ROOT" $@
  mv src/webp "$BOT_ROOT/include"
  rsync -a "tmpbuild/include" "$BOT_ROOT"
  mv tmpbuild/libwebp.${BOT_SHLIB} "$BOT_ROOT/lib/"
  popd
}

function BotInstall_libraw {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude libraw) ]; then
    BotLog "Using cached LibRAW"
    return 0;
  fi

  BotMakeBuildArk libraw http://www.libraw.org/data/LibRaw-0.18.0.tar.gz "$BOT_ROOT" \
    --enable-demosaic-pack-gpl2=$(BotExtractUrl librawdm2 http://www.libraw.org/data/LibRaw-demosaic-pack-GPL2-0.18.0.tar.gz) \
    --enable-demosaic-pack-gpl3=$(BotExtractUrl librawdm3 http://www.libraw.org/data/LibRaw-demosaic-pack-GPL3-0.18.0.tar.gz) \
    $@
}

function BotInstall_ffmpeg {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude libavcodec) ]; then
    BotLog "Using cached FFMpeg"
    return 0;
  fi

  BotInstall_yasm
  BotMakeBuildArk ffmpeg https://github.com/FFmpeg/FFmpeg/archive/n2.8.10.tar.gz "$BOT_ROOT" \
    --yasmexe="$BOT_ROOT/bin/yasm" $@
}

function BotInstall_dcmtk {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude dcmtk) ]; then
    BotLog "Using cached DCMTK"
    return 0;
  fi

  BotCmakeInstallArk dcmtk http://dicom.offis.de/download/dcmtk/dcmtk362/dcmtk-3.6.2.tar.gz "$BOT_ROOT" \
    -DCMTK_USE_CXX11_STL=ON -DJPEG_INCLUDE_DIR="$BOT_ROOT/include" $@
}

function BotInstall_codecs {
  BotInstall_png $@
  BotInstall_jpeg $@
  BotInstall_gif $@
  BotInstall_tiff $@
  BotInstall_jpeg2000 $@
  BotInstall_webp $@
  BotInstall_libraw $@
  BotInstall_ffmpeg $@
}

function BotInstall_openssl {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude openssl) ]; then
    BotLog "Using pkg-config: $pconfig"
    return 0;
  fi

  local target=linux-x86_64
  if [ $BOT_OS_NAME == 'osx' ] ; then
    target=darwin64-x86_64-cc
  fi

  pushd "$(BotExtractUrl openssl https://www.openssl.org/source/openssl-1.0.2l.tar.gz)";
    ../Configure darwin64-x86_64-cc zlib-dynamic enable-ec_nistp_64_gcc_128
    KERNEL_BITS=64 ../Configure $target \
      shared enable-ec_nistp_64_gcc_128 no-ssl2 no-ssl3 no-comp \
      --prefix="$BOT_ROOT" --openssldir="$BOT_ROOT" $@

    make -j $BOT_JOBS install
  popd
}

function BotInstall_oiio {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude OpenImageIO) ]; then
    BotLog "Using cached OpenIamgeIO"
    return 0;
  fi

  BotInstall_codecs
  BotInstall_dcmtk
  BotInstall_freetype
  #BotInstall_openssl

  BotCmakeInstallGit oiio https://github.com/marsupial/oiio.git "$BOT_ROOT" -DBOOST_ROOT="$BOT_ROOT" \
    -DEMBEDPLUGINS=OFF -DSTOP_ON_WARNING=OFF \
    -DWEBP_INCLUDE_DIR="$BOT_ROOT/include" -DWEBP_LIBRARY="$BOT_ROOT/lib/libwebp.$BOT_SHLIB" \
    -DUSE_OPENJPEG=ON -DOPENJPEG_HOME="$BOT_ROOT" \
    -DILMBASE_PACKAGE_PREFIX="$BOT_ROOT" -DOPENEXR_INCLUDE_PATH="$BOT_ROOT/include" \
    -DFREETYPE_PATH="$BOT_ROOT" -DUSE_OPENSSL=1 $@
  # -DCMAKE_CXX_FLAGS="-Wno-misleading-indentation -Wno-placement-new"
}

function BotInstall_lcms2 {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude lcms2.h) ]; then
    BotLog "Using cached LCMS2"
    return 0;
  fi

 BotMakeBuildArk lcms2 https://cytranet.dl.sourceforge.net/project/lcms/lcms/2.8/lcms2-2.8.tar.gz "$BOT_ROOT" $@
}

function BotInstall_tinyxml {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude tinyxml2.h) ]; then
    BotLog "Using cached TinyXML"
    return 0;
  fi

  BotCmakeInstallArk tinyxml https://github.com/leethomason/tinyxml2/archive/5.0.1.tar.gz "$BOT_ROOT" $@
}

function BotInstall_yamlxx {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude yaml-cpp) ]; then
    BotLog "Using cached Yaml++"
    return 0;
  fi

  BotCmakeInstallArk yamlxx https://github.com/jbeder/yaml-cpp/archive/yaml-cpp-0.5.3.tar.gz "$BOT_ROOT" $@
}

function BotInstall_ocio {
  if [ ! $(BotTimeRemaing 5) ] || [ $(BotHasInclude OpenColorIO) ]; then
    BotLog "Using cached OpenColorIO"
    return 0;
  fi

  BotInstall_lcms2;
  BotInstall_tinyxml;
  BotInstall_yamlxx;
  BotCmakeInstallGit ocio https://github.com/marsupial/OpenColorIO.git "$BOT_ROOT" \
    -DUSE_EXTERNAL_YAML=ON -DUSE_EXTERNAL_TINYXML=ON -DOCIO_BUILD_SHARED=ON -DOCIO_BUILD_STATIC=OFF \
    -DTinyXML2_DIR="$BOT_ROOT/lib/cmake/tinyxml2" -DCMAKE_CXX_FLAGS=-std=c++11 $@
  # BotCmakeInstallArk ocio https://github.com/imageworks/OpenColorIO/archive/v1.0.9.tar.gz "$BOT_ROOT" -DBUILD_STATIC_LIBS=OFF -DUSE_EXTERNAL_LCMS=ON
  # -DUSE_EXTERNAL_YAML=ON -DUSE_EXTERNAL_TINYXML=ON
}
