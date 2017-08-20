
function BotLog {
  echo "$@" >&2
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
    export DYLD_FALLBACK_LIBRARY_PATH="${BOT_ROOT}/lib:$DYLD_FALLBACK_LIBRARY_PATH"
  fi
}

function BotTimeRemaining {
  local remains=$(expr 39 - $SECONDS / 60)
  if [[ $remains -gt 0 && ( -z "$1" || $remains -gt $1 ) ]]; then
    echo $remains
  fi
}

function BotTmpDir {
  # echo `mktemp -d 2>/dev/null || mktemp -d -t 'tmpdir'`
  mkdir -p "$TMPDIR/$1"
  echo "$TMPDIR/$1"
}

function BotTestBin {
  local result=`which "$1"`
  if [[ -z $result || $result == "$1 not found" ]]; then
    return 0
  fi
  echo "1"
}

function BotURLCommand {
  local url=$1; shift;
  if [[ ! -z $(BotTestBin wget) ]]; then
    echo wget $url --no-check-certificate -O- $@
  else
    echo curl $url -L $@
  fi
}

function BotGetURL {
  local url="$1"; shift;
  local loc="$TMPDIR/$(basename $url)"
  local getURL=$(BotURLCommand $url $@)
  eval $getURL > "$loc"
  echo "$loc"
}

function BotExtractArchive {
  local output="$1"; shift;
  local url="$1"; shift;
  local name=`basename $url`
  local ext=${name##*.}

  local fmt=z
  case "$ext" in
    [tT][aA][rR]) fmt="" ;;
    [tT][gG][zZ]|[gG][zZ]) fmt="z" ;;
    [tT][bB][zZ]|[bB][zZ]2|[bB][zZ]) fmt="j" ;;
    [tT][xX][zZ]|[xX][zZ]) fmt="J" ;;
    # 7Z p7zip
    # ZIP unzip
  esac

  local getURL=$(BotURLCommand $url)
  eval $getURL $@ | tar -x${fmt} --strip-components=1 -C "$output"
}

function BotExtractUrl {
  local output=`BotTmpDir $1`; shift;
  BotExtractArchive "$output" $@
  echo "$output"
}

function BotRunCommand {
  if [[ ! -z $(BotTestBin timeout) ]]; then
    timeout $(BotTimeRemaining)m $@
  else
    $@
  fi
}

function BotBuildTarget {
  BotRunCommand make -j $BOT_JOBS $@
}

function BotCmakeBuildDir {
  local TARGET=$1; shift;
  local PREFIX=$1; shift;
  mkdir tmpbuild && pushd tmpbuild
    BotLog "$CMAKE_FLAGS -DCMAKE_PREFIX_PATH=$PREFIX -DCMAKE_INSTALL_PREFIX=$PREFIX $@"
    cmake $CMAKE_FLAGS -DCMAKE_PREFIX_PATH=$PREFIX -DCMAKE_INSTALL_PREFIX=$PREFIX $@
    BotBuildTarget $TARGET
  popd
}

function BotCmakeBuild {
  BotCmakeBuildDir $@ ..
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

function BotGitCloneRepo {
  local dstdir=`BotTmpDir $1`; shift;
  git clone --depth 10 $@ "$dstdir";
  echo "$dstdir"
}

function BotCmakeInstallGit {
  pushd "$(BotGitCloneRepo $1 $2)"; shift; shift;
    BotCmakeInstall "$@"
  popd
}

function BotMakeBuildArk {
  pushd "$(BotExtractUrl $1 $2)"; shift; shift;
  local PREFIX=$1; shift;
    BotLog "./configure --prefix=$PREFIX --enable-shared --disable-static $@"
    ./configure --prefix=$PREFIX --enable-shared --disable-static "$@"
  BotBuildTarget install
  popd
}

function BotEmptyUsrLocal {
  sudo mv /usr/local /usr/local.bak
  sudo mkdir -p /usr/local/bin
  # sudo chmod -R 777 /usr/local/
  if [ -f $HOME/built/built.tgz ]; then
    #tar xzf $HOME/built/built.tgz -C /
    echo "NoTAR"
  fi
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
  #tar -c /usr/local | gzip -9 > $HOME/built/built.tgz
  sudo mv /usr/local /usr/local.built
  sudo mv /usr/local.bak /usr/local
}

function BotRsyncToDir {
  local dst="$1"; shift;
  for f in $@; do
    rsync -a "$f" "$dst"
  done
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

function BotBinaryObjFiles {
  local fmt="$1";
  local path="$2";
  if [[ -f $path ]]; then
    if [[ `file "$path" | awk 'NR==1{print $2}'` == $fmt ]]; then
        echo "$path"
    fi
    return
  fi

  for f in "$path/"*; do
    if [[ ! -h $f ]] && [[ `file $f | awk 'NR==1{print $2}'` == $fmt ]]; then
      echo $f
    fi
  done
}

function BotMachOFiles {
  BotBinaryObjFiles "Mach-O" $@
}

function BotELFFiles {
  BotBinaryObjFiles "ELF" $@
}

function BotInstallPathID {
  local recurse="";
  if [[ $1 == "recurse" ]]; then
    recurse=1
    shift;
  fi
  for lib in $@; do
    if [ -f "$BOT_ROOT/lib/$lib" ]; then
      install_name_tool -id "@loader_path/../lib/$lib" "$BOT_ROOT/lib/$lib"
      if [[ ! -z $recurse ]]; then
        for libl in $@; do
          install_name_tool -change "$libl" "@loader_path/../lib/$libl" "$BOT_ROOT/lib/$lib"
        done
      fi
    fi
  done
}

function BotInstallRemoveRPath {
  local rpath=$1; shift;
  for arg in $@; do
    for file in `BotMachOFiles $arg`; do
      install_name_tool -delete_rpath "$rpath" "$file"
    done
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

function BotRPathEdit {
  local rpath="$1"; shift;
  for arg in $@; do
    for file in `BotELFFiles $arg`; do
      patchelf --force-rpath --remove-rpath "$file"
      patchelf --set-rpath "$rpath" "$file"
    done
  done
}

function BotInstallPatchElf {
  if [[ ! -z $(BotTestBin $BOT_ROOT/bin/patchelf) ]]; then
    alias patchelf=$BOT_ROOT/bin/patchelf
    echo "Found installed patchelf: $BOT_ROOT/bin/patchelf"
    return 0;
  fi

  if [[ ! -z $(BotTestBin patchelf) ]]; then return 0; fi

  sudo apt-get install patchelf
  if [ $? -eq 0 ]; then return 0; fi

  case `BotInstallCheckFlags "$1" ../bin/patchelf` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotMakeBuildArk patchelf https://nixos.org/releases/patchelf/patchelf-0.9/patchelf-0.9.tar.bz2 "$BOT_ROOT" $@
  alias patchelf=$BOT_ROOT/bin/patchelf
}

function BotInstallNameChange {
  BotInstallNameChangePrefix $BOT_ROOT/lib/ $@
}

function BotPlatformInstall {
  local cuda=""
  if [[ $BOT_OS_NAME == 'osx' ]]; then
    # CUDA
    if [ ! -d /usr/local/cuda ]; then
      local vol=`BotMountURL http://developer.download.nvidia.com/compute/cuda/7.5/Prod/local_installers/cuda_7.5.27_mac.dmg`
      sudo $vol/CUDAMacOSXInstaller.app/Contents/MacOS/CUDAMacOSXInstaller --accept-eula --silent --no-window --install-package=cuda-toolkit
    fi
    cuda="/usr/local/cuda"
    ls -l /usr/local/cuda
    ls -l /usr/local/cuda/*

    if [[ 0 -eq 1 ]]; then
      # Intel TBB
      local USD_TBB=tbb2017_20161128oss
      #USD_TBB=tbb2017_20161004oss
      local TBB_URL=https://www.threadingbuildingblocks.org/sites/default/files/software_releases/mac/${USD_TBB}_osx.tgz
      BotMvLibAndInclude `BotExtractUrl tbb $TBB_URL` "$BOT_ROOT"
    fi

    if [[ 0 -eq 1 ]]; then
      # QT 4.8
      local vol=`BotMountURL http://qt.mirror.constant.com/archive/qt/4.8/4.8.6/qt-opensource-mac-4.8.6-1.dmg`
      QT_PKGS="${vol}/packages/Qt_"
      QT_ARK=".pkg/Contents/Archive.pax.gz"
      BotInstallPackages `BotTmpDir QT` "${QT_PKGS}libraries${QT_ARK}" "${QT_PKGS}headers${QT_ARK}" "${QT_PKGS}tools${QT_ARK}"

      # PySide
      local pkg=`BotGetURL http://pyside.markus-ullmann.de/pyside-1.2.1-qt4.8.5-py27apple-developer-signed.pkg`
      pkgutil --expand $pkg "$TMPDIR/PySide"
      BotInstallPackages "$TMPDIR/PySide" Payload
    fi
  else
    cuda=$(BotGetURL http://developer.download.nvidia.com/compute/cuda/7.5/Prod/local_installers/cuda_7.5.18_linux.run)
    sudo $cuda --silent --toolkit # --toolkitpath=/tmp/CUDALINX
    cuda="/usr/local/cuda-7.5"
  fi
  if [[ $cuda ]]; then
    mkdir -p "$BOT_ROOT/include/cuda"
    BotRsyncToDir "$BOT_ROOT/include/cuda" "$cuda/include/"
    BotRsyncToDir "$BOT_ROOT/lib/" $cuda/lib/libcuda*
  fi
}

function BotInstallCheckFlags {
  local timeout=5
  if [ $# -gt 2 ]; then timeout=$3; fi
  if [ ! $(BotTimeRemaining $timeout) ]; then
    BotLog "Not enough time to build '$2'"
    echo "0"
    return 0
  fi

  if [[ $1 == "--force" ]]; then
    BotLog "Forcing build of '$2'"
    rm -rf "$BOT_ROOT/include/$2"
    echo "1"
  elif [[ $(BotHasInclude $2) ]]; then
    BotLog "Using cached '$2'"
    echo "0"
  else
    echo "2"
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
  case `BotInstallCheckFlags "$1" boost 15` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  pushd `BotExtractUrl boost https://pilotfiber.dl.sourceforge.net/project/boost/boost/1.63.0/boost_1_63_0.tar.gz`
    # echo "REMAINING: " `BotTimeRemaining`
    ./bootstrap.sh
    # echo "REMAINING: " `BotTimeRemaining`
    ./bjam -j 4 --prefix="$BOT_ROOT" --build-type=minimal link=shared cxxflags="-Wno-c99-extensions -Wno-variadic-macros" $@ install # > /dev/null
    #./bjam -j 4 --prefix="$BOT_ROOT" --build-type=minimal link=shared install > /tmp/boost.log & tail -f /tmp/boost.log
    # travis_wait `BotTimeRemaining` ./bjam -j 4 --prefix="$BOT_ROOT" --build-type=minimal link=shared install > /tmp/boost.log
    # timeout "$(BotTimeRemaining)m" ./bjam -j 4 --prefix="$BOT_ROOT" --build-type=minimal link=shared install > /tmp/boost.log & tail -f /tmp/boost.log
  popd

  if [[ $BOT_OS_NAME == 'osx' ]] ; then
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

function BotInstall_freetype {
  case `BotInstallCheckFlags "$1" freetype2` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotMakeBuildArk bsftype http://download.savannah.gnu.org/releases/freetype/freetype-2.7.1.tar.gz "$BOT_ROOT" --with-harfbuzz=no $@
  BotMakeBuildArk harfbuzz https://www.freedesktop.org/software/harfbuzz/release/harfbuzz-1.4.1.tar.bz2 "$BOT_ROOT" $@

  rm -rf "$BOT_ROOT/include/freetype2"
  rm -rf "$BOT_ROOT/lib/"libfreetype*
  BotMakeBuildArk freetype http://download.savannah.gnu.org/releases/freetype/freetype-2.7.1.tar.gz "$BOT_ROOT" $@
}

function BotInstall_pyside {
  case `BotInstallCheckFlags "$1" "../lib/python2.7/PySide2"` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  pushd "$(BotGitCloneRepo pyside --branch 5.6 https://code.qt.io/pyside/pyside-setup)"
    BotRunCommand python setup.py install --prefix="$BOT_ROOT" --qmake="$BOT_ROOT/bin/qmake"
    # --cmake=/path/to/bin/cmake --openssl=/path/to/openssl/bin
    if [[ $BOT_OS_NAME == 'osx' ]] ; then
      for lib in `BotMachOFiles $BOT_ROOT/lib/python2.7/site-packages/PySide2`; do
        install_name_tool -add_rpath "@loader_path/../../../" $lib
        install_name_tool -add_rpath "@loader_path" $lib
        install_name_tool -delete_rpath $buildDir $lib
      done
      BotInstallNameChangePrefix "@loader_path/../lib/" "@loader_path/../../../" "$BOT_ROOT/lib/python2.7/site-packages/PySide2"
    fi
  popd
}

function BotInstall_fixupqt {
  if [[ $BOT_OS_NAME == 'osx' ]] ; then
    echo "
contains(QT_CONFIG, system-freetype) {
  # pull in the proper freetype2 include directory
  include(\$\$QT_SOURCE_TREE/config.tests/unix/freetype/freetype.pri)
  HEADERS += \$\$QT_SOURCE_TREE/src/gui/text/qfontengine_ft_p.h
  SOURCES += \$\$QT_SOURCE_TREE/src/gui/text/qfontengine_ft.cpp
  CONFIG += opentype
}
" >> qtbase/src/platformsupport/fontdatabases/mac/coretext.pri
    echo "LIBS += -lfreetype" >> qtbase/src/plugins/platforms/cocoa/cocoa.pro
  else
    sed -i '1i#include <qapplication.h>' qtbase/src/widgets/styles/qstylehelper.cpp
    sed -i '1i#include <QtCore/qdebug.h>' qtx11extras/src/x11extras/qx11info_x11.cpp
  fi
  echo -n "
#WEBENGINE_CONFIG+=use_system_ffmpeg
WEBENGINE_CONFIG+=use_proprietary_codecs
" >> qtwebengine/qtwebengine.pro
}

function BotInstall_qt {
  case `BotInstallCheckFlags "$1" QtCore 15` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotInstall_freetype

  local branch="adsk-contrib/vfx/5.6.1"
  local noframework=""
  local cxxflags="$CXXFLAGS"
  local ldflags="$LDFLAGS"
  local nopch="-no-pch"
  local silent="-silent"

  if [[ $BOT_OS_NAME == 'osx' ]] ; then
    export LDFLAGS="-stdlib=libc++ $LDFLAGS"
    export CXXFLAGS="-std=c++11 -stdlib=libc++ $CXXFLAGS -I$BOT_ROOT/include/freetype2"
    noframework=-no-framework
  fi

  export QMAKE_CXX="$CXX"
  export QMAKE_CC="$CC"
  if [[ -z $nopch ]]; then
    export CXXFLAGS="$CXXFLAGS -fpch-preprocess"
    export CCACHE_SLOPPINESS="pch_defines,time_macros" # ,$CCACHE_SLOPPINESS"
  fi

  pushd "$(BotExtractUrl qt5 http://download.qt.io/archive/qt/5.6/5.6.1-1/single/qt-everywhere-opensource-src-5.6.1-1.tar.xz)"
    rm -rf qtbase
    git clone --depth 10 --branch $branch https://github.com/autodesk-forks/qtbase.git
    rm -rf qtx11extras
    git clone --depth 10 --branch $branch https://github.com/autodesk-forks/qtx11extras.git

    BotInstall_fixupqt

    mkdir tmpbuild && pushd tmpbuild
      ../configure  -release -shared -prefix "$BOT_ROOT" -I$BOT_ROOT/include -L$BOT_ROOT/lib \
        -system-harfbuzz  -nomake examples -nomake tests \
        $noframework $nopch -c++std c++11 -opensource -confirm-license $silent
       BotBuildTarget
       if [[ $? -eq 0 ]]; then
         BotBuildTarget install
       fi
    popd
  popd

  if [[ $BOT_OS_NAME == 'osx' ]] ; then
    export CXXFLAGS="$cxxflags"
    export LDFLAGS="$ldflags"
    BotInstallNameChangePrefix "@rpath/" "@loader_path/../lib/" "$BOT_ROOT/bin"
    BotInstallNameChangePrefix "@rpath/" "@loader_path/../lib/" "$BOT_ROOT/lib"
    BotInstallNameChangePrefix "@rpath/" "@loader_path/../../lib/" $BOT_ROOT/plugins/*/
    BotInstallNameChangePrefix "@rpath/" "@loader_path/../../../../lib/" $BOT_ROOT/bin/*.app/Contents/MacOS
  #else
  #  ln -s "libQt5PrintSupport.so.5.6.1" "$BOT_ROOT/lib/libQt5PrintSupport.so.5"
  fi

  if [[ -z $nopch ]]; then
    unset CCACHE_SLOPPINESS;
  fi
}

function BotInstall_glew {
  case `BotInstallCheckFlags "$1" GL` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  pushd "$(BotExtractUrl glew https://cytranet.dl.sourceforge.net/project/glew/glew/2.0.0/glew-2.0.0.tgz)"
    BotBuildTarget GLEW_PREFIX="$BOT_ROOT" GLEW_DEST="$BOT_ROOT" $@ install
    if [ $BOT_OS_NAME == 'linux' ]; then
      mv $BOT_ROOT/lib64/* $BOT_ROOT/lib
    elif [ $BOT_OS_NAME == 'osx' ] ; then
      BotInstallPathID libGLEW.2.0.0.dylib
    fi
  popd
}

function BotInstall_clew {
  case `BotInstallCheckFlags "$1" clew.h` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotCmakeInstallGit clew https://github.com/martijnberger/clew.git "$BOT_ROOT" $@
}
  
function BotInstall_glfw {
  case `BotInstallCheckFlags "$1" GLFW` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotCmakeInstallArk glfw https://github.com/glfw/glfw/archive/3.2.1.tar.gz "$BOT_ROOT" $@
}

function BotInstall_ptex {
  case `BotInstallCheckFlags "$1" Ptexture.h` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotCmakeInstallArk ptex https://github.com/wdas/ptex/archive/v2.1.28.tar.gz "$BOT_ROOT" $@
}

function BotInstall_osd {
  case `BotInstallCheckFlags "$1" opensubdiv` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  local platformFlags=""
  if [[ $BOT_OS_NAME == 'osx' ]] ; then
    platformFlags="$platformFlags -DNO_CLEW=ON"
  fi

  # https://github.com/PixarAnimationStudios/OpenSubdiv/archive/v3_1_1.tar.gz
  BotCmakeInstallArk osd https://github.com/PixarAnimationStudios/OpenSubdiv/archive/v3_3_0.tar.gz "$BOT_ROOT" \
    -DNO_REGRESSION=1 -DCUDA_NVCC_FLAGS="-ccbin $CCOMPILER" \
    -DGLEW_LOCATION="$BOT_ROOT" -DCLEW_LOCATION="$BOT_ROOT" -DTBB_LOCATION="$BOT_ROOT" \
    -DNO_DOC=1 $platformFlags $@ -DNO_EXAMPLES=1 -DNO_TUTORIALS=1 VERBOSE=1
  #  -DNO_EXAMPLES=1 -DNO_TUTORIALS=1 -DNO_DOC=1 $@

  #-DOPENSUBDIV_HAS_GLSL_TRANSFORM_FEEDBACK
}

function BotInstall_numpy {
  # https://github.com/numpy/numpy/archive/v1.12.0.tar.gz
  case `BotInstallCheckFlags "$1" numpy` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

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
  case `BotInstallCheckFlags "$1" OpenEXR` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

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
  case `BotInstallCheckFlags "$1" hdf5.h` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotMakeBuildArk szip https://support.hdfgroup.org/ftp/lib-external/szip/2.1.1/src/szip-2.1.1.tar.gz "$BOT_ROOT" $@
  if [[ $BOT_OS_NAME == 'osx' ]] ; then
    BotInstallPathID libsz.2.dylib
  fi

  # -Wno-strict-overflow -Wno-double-promotion -Wno-sign-conversion -Wno-c++-compat -Wno-cast-qual -Wno-format-nonliteral -Wno-unused-result -Wno-conversion -Wno-suggest-attribute=pure -Wno-suggest-attribute=const -Wno-frame-larger-than= -Wno-larger-than=
  BotMakeBuildArk hdf5 https://support.hdfgroup.org/ftp/HDF5/current18/src/hdf5-1.8.19.tar.gz \
    "$BOT_ROOT" --with-szip="$BOT_ROOT" $@
}

function BotInstall_alembic {
  case `BotInstallCheckFlags "$1" Alembic 10` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotCmakeInstallArk alembic https://github.com/alembic/alembic/archive/1.7.3.tar.gz "$BOT_ROOT" \
    -DUSE_HDF5=ON -DUSE_PYALEMBIC=ON \
    -DALEMBIC_PYIMATH_MODULE_DIRECTORY="$BOT_ROOT/lib/python2.7/site-packages" \
    -DALEMBIC_PYILMBASE_INCLUDE_DIRECTORY="$BOT_ROOT/include/PyImath" \
    -DHDF5_C_INCLUDE_DIR="$$BOT_ROOT" -DCMAKE_CXX_FLAGS="-Wno-deprecated-register" \
    $@
}

function BotInstall_field3D {
  case `BotInstallCheckFlags "$1" Field3D 10` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotCmakeInstallArk field3d https://github.com/imageworks/Field3D/archive/v1.7.2.tar.gz "$BOT_ROOT" \
  -DHDF5_INCLUDE_DIRS=$BOT_ROOT/include -DHDF5_LIBRARIES=$BOT_ROOT/lib $@
}

function BotInstall_lz4 {
  case `BotInstallCheckFlags "$1" lz4` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  pushd "$(BotExtractUrl lz4 https://github.com/lz4/lz4/archive/v1.7.5.tar.gz)";
    BotCmakeBuildDir install "$BOT_ROOT" ../contrib/cmake_unofficial
  popd
}

function BotInstall_snappy {
  case `BotInstallCheckFlags "$1" snappy.h` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac
  BotCmakeInstallArk snappy https://github.com/google/snappy/archive/1.1.6.tar.gz "$BOT_ROOT" $@
}

function BotInstall_zstd {
  case `BotInstallCheckFlags "$1" zstd` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  pushd "$(BotExtractUrl zstd https://github.com/facebook/zstd/archive/v1.3.0.tar.gz)";
    BotCmakeBuildDir install "$BOT_ROOT" ../build/cmake
  popd
}

function BotInstall_compressors {
  BotInstall_lz4
  BotInstall_snappy
  BotInstall_zstd
}

function BotInstall_blosc {
  case `BotInstallCheckFlags "$1" blosc.h` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotInstall_compressors
  BotCmakeInstallArk blosc https://github.com/Blosc/c-blosc/archive/v1.12.1.tar.gz "$BOT_ROOT" \
    -DPREFER_EXTERNAL_LZ4=ON -DPREFER_EXTERNAL_SNAPPY=ON -DPREFER_EXTERNAL_ZSTD=ON \
    -DPREFER_EXTERNAL_ZLIB=ON $@
}

function BotInstall_openvdb {
  case `BotInstallCheckFlags "$1" openvdb` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotInstall_blosc
  BotCmakeInstallArk openvdb https://github.com/dreamworksanimation/openvdb/archive/v4.0.2.tar.gz "$BOT_ROOT" \
    -DHDF5_INCLUDE_DIRS="$BOT_ROOT/include" -DHDF5_LIBRARIES="$BOT_ROOT/lib" \
    -DBLOSC_LOCATION="$BOT_ROOT" -DTBB_LOCATION="$BOT_ROOT" \
    -DOPENEXR_LOCATION="$BOT_ROOT" -DILMBASE_LOCATION="$BOT_ROOT" \
    $@
}

function BotInstall_png {
  case `BotInstallCheckFlags "$1" libpng16` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotMakeBuildArk png https://download.sourceforge.net/libpng/libpng-1.6.30.tar.gz "$BOT_ROOT" $@
}

function BotInstallStaticToDynlib {
  local lib="$BOT_ROOT/lib/lib${1}"
  if [[ ! -e "$lib.$BOT_SHLIB" ]]; then
    $CC -shared -o "$lib.$BOT_SHLIB" "$lib.a"
    rm "$lib.a"
  fi
}

function BotInstall_yasm {
  case `BotInstallCheckFlags "$1" libyasm` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotMakeBuildArk yasm http://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz "$BOT_ROOT"
  BotInstallStaticToDynlib yasm
}

function BotInstall_jpeg {
  case `BotInstallCheckFlags "$1" jpeglib.h` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotInstall_yasm
  BotCmakeInstallGit jpeg https://github.com/marsupial/libjpeg-turbo.git "$BOT_ROOT" \
    -DNASM="$BOT_ROOT/bin/yasm" -DENABLE_SHARED=ON -DENABLE_STATIC=OFF $@
  #BotCmakeInstallArk jpeg https://github.com/libjpeg-turbo/libjpeg-turbo/archive/1.5.2.tar.gz "$BOT_ROOT" $@
}

function BotInstall_gif {
  case `BotInstallCheckFlags "$1" gif_lib.h` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotMakeBuildArk gif "https://iweb.dl.sourceforge.net/project/giflib/giflib-5.1.4.tar.bz2" "$BOT_ROOT" $@
}

function BotInstall_tiff {
  case `BotInstallCheckFlags "$1" tiff.h` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotMakeBuildArk tiff http://dl.maptools.org/dl/libtiff/tiff-3.8.2.tar.gz "$BOT_ROOT" $@
}

function BotInstall_jpeg2000 {
  case `BotInstallCheckFlags "$1" openjpeg-2.1` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotInstall_yasm;
  BotInstall_lcms2;
  BotCmakeInstallArk jasper https://github.com/mdadams/jasper/archive/version-2.0.10.tar.gz "$BOT_ROOT" $@
  BotCmakeInstallArk openjpeg https://github.com/uclouvain/openjpeg/archive/v2.1.2.tar.gz "$BOT_ROOT" $@
  mv "$BOT_ROOT/lib/openjpeg-2.1" "$BOT_ROOT/lib/cmake"
}

function BotInstall_webp {
  case `BotInstallCheckFlags "$1" webp` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  pushd $(BotExtractUrl webp "https://github.com/webmproject/libwebp/archive/v0.6.0.tar.gz")
    BotCmakeBuild "" "$BOT_ROOT" $@
    mv src/webp "$BOT_ROOT/include"
    rsync -a "tmpbuild/include" "$BOT_ROOT"
    mv tmpbuild/libwebp.${BOT_SHLIB} "$BOT_ROOT/lib/"

    local webp_pc=`cat src/libwebp.pc.in`
    webp_pc=`sed s#@prefix@#$BOT_ROOT#g <<< "$webp_pc"`
    webp_pc=`sed s#@exec_prefix@#$BOT_ROOT#g <<< "$webp_pc"`
    webp_pc=`sed s#@libdir@#$BOT_ROOT/lib#g <<< "$webp_pc"`
    webp_pc=`sed s#@includedir@#$BOT_ROOT/include#g <<< "$webp_pc"`
    webp_pc=`sed s#@PACKAGE_VERSION@#0.6.0#g <<< "$webp_pc"`
    webp_pc=`sed s#@PTHREAD_CFLAGS@##g <<< "$webp_pc"`
    webp_pc=`sed s#@PTHREAD_LIBS@##g <<< "$webp_pc"`
    echo -n "$webp_pc" > "$BOT_ROOT/lib/pkgconfig/libwebp.pc"
  popd
}

function BotInstall_libraw {
  case `BotInstallCheckFlags "$1" libraw` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotMakeBuildArk libraw http://www.libraw.org/data/LibRaw-0.18.0.tar.gz "$BOT_ROOT" \
    --enable-demosaic-pack-gpl2=$(BotExtractUrl librawdm2 http://www.libraw.org/data/LibRaw-demosaic-pack-GPL2-0.18.0.tar.gz) \
    --enable-demosaic-pack-gpl3=$(BotExtractUrl librawdm3 http://www.libraw.org/data/LibRaw-demosaic-pack-GPL3-0.18.0.tar.gz) \
    $@
}

function BotInstall_ffmpeg {
  case `BotInstallCheckFlags "$1" libavcodec` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotInstall_yasm
  BotMakeBuildArk ffmpeg https://github.com/FFmpeg/FFmpeg/archive/n2.8.10.tar.gz "$BOT_ROOT" \
    --yasmexe="$BOT_ROOT/bin/yasm" $@
}

function BotInstall_dcmtk {
  case `BotInstallCheckFlags "$1" dcmtk` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

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
  case `BotInstallCheckFlags "$1" openssl` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  local target=linux-x86_64
  if [[ $BOT_OS_NAME == 'osx' ]] ; then
    target=darwin64-x86_64-cc
  fi

  pushd "$(BotExtractUrl openssl https://www.openssl.org/source/openssl-1.0.2l.tar.gz)";
    ../Configure darwin64-x86_64-cc zlib-dynamic enable-ec_nistp_64_gcc_128
    KERNEL_BITS=64 ../Configure $target \
      shared enable-ec_nistp_64_gcc_128 no-ssl2 no-ssl3 no-comp \
      --prefix="$BOT_ROOT" --openssldir="$BOT_ROOT" $@

    BotBuildTarget install
  popd
}

function BotInstall_oiio {
  case `BotInstallCheckFlags "$1" OpenImageIO` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

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
  case `BotInstallCheckFlags "$1" lcms2.h` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

 BotMakeBuildArk lcms2 https://cytranet.dl.sourceforge.net/project/lcms/lcms/2.8/lcms2-2.8.tar.gz "$BOT_ROOT" $@
}

function BotInstall_tinyxml {
  case `BotInstallCheckFlags "$1" tinyxml2.h` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotCmakeInstallArk tinyxml https://github.com/leethomason/tinyxml2/archive/5.0.1.tar.gz "$BOT_ROOT" $@
}

function BotInstall_yamlxx {
  case `BotInstallCheckFlags "$1" yaml-cpp` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotCmakeInstallArk yamlxx https://github.com/jbeder/yaml-cpp/archive/yaml-cpp-0.5.3.tar.gz "$BOT_ROOT" $@
}

function BotInstall_jsoncpp {
  case `BotInstallCheckFlags "$1" json` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotCmakeInstallArk jsoncpp https://github.com/open-source-parsers/jsoncpp/archive/1.8.1.tar.gz "$BOT_ROOT" $@
  BotInstallStaticToDynlib jsoncpp
}

function BotInstall_ocio {
  case `BotInstallCheckFlags "$1" OpenColorIO` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotInstall_lcms2
  BotInstall_tinyxml
  BotInstall_yamlxx
  BotCmakeInstallGit ocio https://github.com/marsupial/OpenColorIO.git "$BOT_ROOT" \
    -DUSE_EXTERNAL_YAML=ON -DUSE_EXTERNAL_TINYXML=ON -DOCIO_BUILD_SHARED=ON -DOCIO_BUILD_STATIC=OFF \
    -DTinyXML2_DIR="$BOT_ROOT/lib/cmake/tinyxml2" -DCMAKE_CXX_FLAGS=-std=c++11 $@
  # BotCmakeInstallArk ocio https://github.com/imageworks/OpenColorIO/archive/v1.0.9.tar.gz "$BOT_ROOT" -DBUILD_STATIC_LIBS=OFF -DUSE_EXTERNAL_LCMS=ON
  # -DUSE_EXTERNAL_YAML=ON -DUSE_EXTERNAL_TINYXML=ON
}


function BotInstall_seexpr {
  case `BotInstallCheckFlags "$1" seexpr` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotCmakeInstallGit seexpr https://github.com/wdas/SeExpr.git "$BOT_ROOT" $@
}

function BotInstall_partio {
  case `BotInstallCheckFlags "$1" partio` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotCmakeInstallGit partio https://github.com/wdas/partio.git "$BOT_ROOT" $@
}

function BotInstall_osl {
  case `BotInstallCheckFlags "$1" OpenShadingLanguage` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  #BotCmakeInstallArk osl https://github.com/imageworks/OpenShadingLanguage/archive/Release-1.8.10.tar.gz "$BOT_ROOT" $@
  #BotCmakeInstallArk osl https://github.com/imageworks/OpenShadingLanguage/archive/Release-1.9.0dev.tar.gz "$BOT_ROOT" -DUSE_CPP=11 $@
  BotCmakeInstallGit osl https://github.com/marsupial/OpenShadingLanguage.git "$BOT_ROOT" -DUSE_CPP=11 $@
}

function BotInstall_libgit {
  case `BotInstallCheckFlags "$1" git2.h` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  BotCmakeInstallArk libgit https://github.com/libgit2/libgit2/archive/v0.26.0.tar.gz "$BOT_ROOT" $@
}

function BotInstall_tbb {
  case `BotInstallCheckFlags "$1" tbb` in
    0) return 0 ;;
    1) shift ;;
    2) ;;
  esac

  local TBB_VERS="$1";
  if [[ -z $TBB_VERS ]]; then TBB_VERS=tbb2017_20170604oss; fi

  #TBB_VERS=tbb2017_20161128oss
  #TBB_VERS=tbb2017_20161004oss
  #TBB_VERS=tbb43_20141023oss
  #https://www.threadingbuildingblocks.org/sites/default/files/software_releases/mac/${TBB_VERS}_osx.tgz
  #https://www.threadingbuildingblocks.org/sites/default/files/software_releases/linux/tbb43_20141023oss_lin.tgz -O /tmp/tbb.tgz;
  #https://www.threadingbuildingblocks.org/sites/default/files/software_releases/linux/tbb2017_20161128oss_lin.tgz

  local libs
  local plat
  if [[ $BOT_OS_NAME == 'linux' ]]; then
    plat=lin
    libs=lib/intel64/gcc4.7
  else
    plat=mac
    libs=lib
  fi

  pushd "$(BotExtractUrl tbb https://github.com/01org/tbb/releases/download/2017_U7/${TBB_VERS}_${plat}.tgz)"
    #BotRunCommand python python/setup.py install --prefix="$BOT_ROOT"
    BotRsyncToDir "$BOT_ROOT/" include $libs
  popd
  rm -f "$BOT_ROOT/lib/index.html"
  rm -f "$BOT_ROOT/include/index.html"
}

