# syntax=docker/dockerfile:1
#
# UltiMaker Cura 5.14.0 on Alpine Linux.
#
# Stage 1 (`builder`) installs the toolchain and builds the whole Cura stack
# from source, including pyUvula, which Alpine does not package. Stage 2
# contains only the runtime libraries and the files produced in stage 1.
#
# Every source ref is a build argument with a pinned default. The release
# workflow resolves the latest upstream refs and passes them with
# `--build-arg`; a plain `docker build .` uses the defaults below, which are the
# last manually verified set. See docs/release-pipeline.md.
#
# Build:
#   docker build -t cura-alpine .
#
# Run (X11):
#   docker run --rm -it \
#     -e DISPLAY="$DISPLAY" \
#     -v /tmp/.X11-unix:/tmp/.X11-unix \
#     -v "$XAUTHORITY:/home/cura/.Xauthority:ro" \
#     cura-alpine

ARG ALPINE_IMAGE=alpine:latest

# ---------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------
FROM ${ALPINE_IMAGE} AS builder

# Upstream refs. Tags and commit SHAs are both accepted by GitHub's
# /archive/<ref>.tar.gz endpoint.
ARG CURA_REF=5.14.0
ARG CURA_VERSION=5.14.0
ARG URANIUM_REF=5.14.0
ARG CURAENGINE_REF=5.14.0
ARG CURAENGINE_VERSION=5.14.0
ARG FDM_MATERIALS_REF=5.14.0
ARG LIBARCUS_REF=339c85a1abc7554e6c19bd36bbbc4c2d6f9f40b6
ARG LIBARCUS_VERSION=5.11.1
ARG PYARCUS_REF=72d052a24b9ecaba8821182cd6e84c04d9b3f3fe
ARG PYNEST2D_REF=73235af569bd36bb8c60e659f75057bd559426d8
ARG LIBNEST2D_REF=1c9dc3c05005cadcbc2b49062c3d37b60e962c7f
ARG LIBUVULA_REF=d15219eb49b7eedb7c2a03ab627e1415c04f79f6
ARG LIBUVULA_VERSION=1.1.0
ARG CURAFORMULAE_REF=c1257dd638dc7dc86377bb5aadd27803de008a59
ARG CURAFORMULAE_VERSION=1.2.1
ARG SCRIPTA_REF=b96045cd9b531d97f42dec8c9a0ef52f773f6b90
ARG ZEUS_REF=v1.4.0
ARG LEXY_REF=v2025.05.0
ARG GEOMETRY_REF=v2.0.3
ARG WAGYU_REF=0.5.0

ENV CMAKE_BUILD_PARALLEL_LEVEL=2
ENV PYTHONUNBUFFERED=1

RUN apk add --no-cache \
    build-base cmake samurai git patch pkgconf curl tar xz \
    python3 python3-dev py3-pip py3-wheel py3-setuptools \
    py3-sip py3-qt6 \
    gettext gettext-dev \
    boost-dev clipper-dev libpng-dev onetbb-dev protobuf-dev \
    range-v3-dev rapidjson-dev spdlog-dev fmt-dev stb \
    nlopt-dev \
    qt6-qtbase-dev qt6-qtdeclarative-dev qt6-qtsvg-dev \
    qt6-qt5compat-dev qt6-qtimageformats-dev

WORKDIR /src

# Alpine's py3-pybind11 package ships pybind11Config.cmake without the headers
# it points at (they live in py3-pybind11-dev under /usr/include, but the config
# resolves site-packages/pybind11/include). The pip wheel ships both together.
RUN pip install --no-cache-dir --break-system-packages pybind11==3.0.1

COPY patches /patches
COPY LICENSE /LICENSE

# ---------------------------------------------------------------------------
# zeus_expected (default v1.4.0)
#
# Backport of std::expected used by CuraFormulaeEngine and CuraEngine 5.14.
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p zeus; \
    curl -fsSL -o zeus.tar.gz \
      "https://github.com/zeus-cpp/expected/archive/${ZEUS_REF}.tar.gz"; \
    tar -xzf zeus.tar.gz -C zeus --strip-components=1; \
    cd zeus; \
    cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DZEUS_EXPECTED_BUILD_TESTS=OFF; \
    cmake --build build; \
    cmake --install build

# ---------------------------------------------------------------------------
# lexy (default v2025.05.0)
#
# Parser library required by CuraFormulaeEngine. Not packaged by Alpine.
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p lexy; \
    curl -fsSL -o lexy.tar.gz \
      "https://github.com/foonathan/lexy/archive/${LEXY_REF}.tar.gz"; \
    tar -xzf lexy.tar.gz -C lexy --strip-components=1; \
    cd lexy; \
    cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DLEXY_BUILD_TESTS=OFF \
      -DLEXY_BUILD_EXAMPLES=OFF \
      -DLEXY_BUILD_BENCHMARKS=OFF \
      -DLEXY_BUILD_DOCS=OFF; \
    cmake --build build; \
    cmake --install build

# ---------------------------------------------------------------------------
# CuraFormulaeEngine (default 1.2.1, commit c1257dd6)
#
# CuraEngine 5.14 requires this library and links it. Upstream has no tags and
# only a Conan recipe, so the commit is pinned and a CMake package config is
# installed alongside it.
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p cura-formulae-engine; \
    curl -fsSL -o CuraFormulaeEngine.tar.gz \
      "https://github.com/Ultimaker/CuraFormulaeEngine/archive/${CURAFORMULAE_REF}.tar.gz"; \
    tar -xzf CuraFormulaeEngine.tar.gz -C cura-formulae-engine --strip-components=1; \
    cd cura-formulae-engine; \
    patch -p1 < /patches/cura-formulae-engine/cmake.patch; \
    cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DCURA_FORMULA_VERSION_VERSION=${CURAFORMULAE_VERSION} \
      -DENABLE_TESTS=OFF \
      -DENABLE_APPS=OFF \
      -DEXTENSIVE_WARNINGS=OFF; \
    cmake --build build; \
    cmake --install build; \
    install -Dm644 /patches/cura-formulae-engine/cura-formulae-engineConfig.cmake \
      /usr/lib/cmake/cura-formulae-engine/cura-formulae-engineConfig.cmake

# ---------------------------------------------------------------------------
# libArcus (default 5.11.1, commit 339c85a1)
#
# Public tags stop at 5.3.0; `main` at this commit declares 5.11.1, which is
# what CuraEngine 5.14 requires.
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p libArcus; \
    curl -fsSL -o libArcus.tar.gz \
      "https://github.com/Ultimaker/libArcus/archive/${LIBARCUS_REF}.tar.gz"; \
    tar -xzf libArcus.tar.gz -C libArcus --strip-components=1; \
    cd libArcus; \
    for p in cmake-build.patch ArcusConfig.patch protobuf-31.patch; do \
        patch -p1 < "/patches/libarcus/$p"; \
    done; \
    cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_BINDIR=bin \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_INSTALL_INCLUDEDIR=include \
      -DBUILD_SHARED_LIBS=ON \
      -DARCUS_VERSION=${LIBARCUS_VERSION}; \
    cmake --build build; \
    cmake --install build

# ---------------------------------------------------------------------------
# pyArcus (default 5.12.0, commit 72d052a2)
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p pyArcus; \
    curl -fsSL -o pyArcus.tar.gz \
      "https://github.com/Ultimaker/pyArcus/archive/${PYARCUS_REF}.tar.gz"; \
    tar -xzf pyArcus.tar.gz -C pyArcus --strip-components=1; \
    cd pyArcus; \
    for p in cmake.patch cmake-helpers.patch pyproject.patch; do \
        patch -p1 < "/patches/pyarcus/$p"; \
    done; \
    cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_INSTALL_INCLUDEDIR=include \
      -DBUILD_SHARED_LIBS=ON; \
    cmake --build build; \
    cmake --install build

# ---------------------------------------------------------------------------
# CuraEngine (default 5.14.0) and its bundled Scripta / geometry.hpp / wagyu
#
# Scripta has no 1.1.0 tag; `main` (default b96045c) declares 1.1.0-alpha.0 and
# is the newest public source for the version CuraEngine 5.14 expects.
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p CuraEngine Scripta geometry wagyu; \
    curl -fsSL -o CuraEngine.tar.gz \
      "https://github.com/Ultimaker/CuraEngine/archive/${CURAENGINE_REF}.tar.gz"; \
    curl -fsSL -o Scripta.tar.gz \
      "https://github.com/Ultimaker/Scripta_public/archive/${SCRIPTA_REF}.tar.gz"; \
    curl -fsSL -o geometry.tar.gz \
      "https://github.com/mapbox/geometry.hpp/archive/${GEOMETRY_REF}.tar.gz"; \
    curl -fsSL -o wagyu.tar.gz \
      "https://github.com/mapbox/wagyu/archive/${WAGYU_REF}.tar.gz"; \
    tar -xzf CuraEngine.tar.gz -C CuraEngine --strip-components=1; \
    tar -xzf Scripta.tar.gz -C Scripta --strip-components=1; \
    tar -xzf geometry.tar.gz -C geometry --strip-components=1; \
    tar -xzf wagyu.tar.gz -C wagyu --strip-components=1; \
    cd CuraEngine; \
    patch -p1 < /patches/curaengine/cmake.patch; \
    patch -p1 < /patches/curaengine/cmake-helpers.patch; \
    patch -p1 < /patches/curaengine/32bit-min.patch; \
    mkdir -p bundled/include/mapbox bundled/lib/cmake/mapbox-wagyu \
             bundled/lib/cmake/scripta; \
    cp -r ../wagyu/include/mapbox/. bundled/include/mapbox/; \
    cp -r ../geometry/include/mapbox/geometry/. bundled/include/mapbox/geometry/; \
    cp -r ../Scripta/include/scripta/. bundled/include/scripta/; \
    cp /patches/curaengine/mapbox-wagyuConfig.cmake bundled/lib/cmake/mapbox-wagyu/; \
    cp /patches/curaengine/scriptaConfig.cmake bundled/lib/cmake/scripta/; \
    cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_BINDIR=bin \
      -DCURA_ENGINE_VERSION=${CURAENGINE_VERSION} \
      -DCMAKE_PREFIX_PATH="$PWD/bundled" \
      -DENABLE_PLUGINS=OFF \
      -DENABLE_REMOTE_PLUGINS=OFF \
      -DENABLE_CURAVIZ=OFF \
      -DENABLE_SENTRY=OFF; \
    cmake --build build; \
    cmake --install build

# ---------------------------------------------------------------------------
# libnest2d (default 5.11.0-alpha.0, commit 1c9dc3c0)
#
# Alpine 3.24 does not package libnest2d. The library is header-only at this
# point; pynest2d links the system clipper, nlopt, boost and spdlog directly.
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p libnest2d; \
    curl -fsSL -o libnest2d.tar.gz \
      "https://github.com/Ultimaker/libnest2d/archive/${LIBNEST2D_REF}.tar.gz"; \
    tar -xzf libnest2d.tar.gz -C libnest2d --strip-components=1; \
    mkdir -p /usr/include/libnest2d; \
    cp -r libnest2d/include/libnest2d/. /usr/include/libnest2d/

# ---------------------------------------------------------------------------
# py3-pynest2d (default 5.11.0-alpha.0, commit 73235af5)
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p pynest2d; \
    curl -fsSL -o pynest2d.tar.gz \
      "https://github.com/Ultimaker/pynest2d/archive/${PYNEST2D_REF}.tar.gz"; \
    tar -xzf pynest2d.tar.gz -C pynest2d --strip-components=1; \
    cd pynest2d; \
    mv ./python ./src; \
    for p in cmake.patch cmake-helpers.patch pyproject.patch; do \
        patch -p1 < "/patches/pynest2d/$p"; \
    done; \
    cp /patches/pynest2d/FindClipper.cmake cmake/; \
    cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_INCLUDEDIR=include \
      -DBUILD_SHARED_LIBS=ON; \
    cmake --build build; \
    cmake --install build

# ---------------------------------------------------------------------------
# libUvula / pyUvula (default 1.1.0, commit d15219e)
#
# The component Alpine is missing. The patch removes Ultimaker's
# standardprojectsettings helper, uses Alpine's Clipper target instead of the
# Conan one, and adds the install rules upstream lacks.
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p libUvula; \
    curl -fsSL -o libUvula.tar.gz \
      "https://github.com/Ultimaker/libUvula/archive/${LIBUVULA_REF}.tar.gz"; \
    tar -xzf libUvula.tar.gz -C libUvula --strip-components=1; \
    cd libUvula; \
    patch -p1 < /patches/libuvula/cmake.patch; \
    cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -Dpybind11_DIR="$(python3 -m pybind11 --cmakedir)" \
      -DUVULA_VERSION=${LIBUVULA_VERSION} \
      -DPYUVULA_VERSION=${LIBUVULA_VERSION} \
      -DWITH_PYTHON_BINDINGS=ON \
      -DWITH_JS_BINDINGS=OFF \
      -DWITH_CLI=OFF \
      -DEXTENSIVE_WARNINGS=OFF; \
    cmake --build build; \
    cmake --install build

# ---------------------------------------------------------------------------
# Uranium (default 5.14.0)
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p Uranium; \
    curl -fsSL -o Uranium.tar.gz \
      "https://github.com/Ultimaker/Uranium/archive/${URANIUM_REF}.tar.gz"; \
    tar -xzf Uranium.tar.gz -C Uranium --strip-components=1; \
    cd Uranium; \
    py_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")'); \
    for p in cmake.patch fix-logger-used-but-not-imported.patch \
             qt-try-ints-then-bytes.patch cmake-helpers.patch; do \
        patch -p1 < "/patches/uranium/$p"; \
    done; \
    cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=MinSizeRel \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DPython_VERSION=${py_version} \
      -DGETTEXT_MSGINIT_EXECUTABLE=msginit \
      -DCURA_BINARY_DATA_DIRECTORY=/usr/share/cura; \
    cmake --build build; \
    cmake --install build; \
    mkdir -p /usr/share/uranium/cmake; \
    mv /usr/share/cmake-*/Modules/* /usr/share/uranium/cmake/ 2>/dev/null || true

# ---------------------------------------------------------------------------
# fdm-materials (default 5.14.0)
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p fdm_materials; \
    curl -fsSL -o fdm_materials.tar.gz \
      "https://github.com/Ultimaker/fdm_materials/archive/${FDM_MATERIALS_REF}.tar.gz"; \
    tar -xzf fdm_materials.tar.gz -C fdm_materials --strip-components=1; \
    cd fdm_materials; \
    cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DCMAKE_INSTALL_PREFIX=/usr; \
    cmake --build build; \
    cmake --install build

# ---------------------------------------------------------------------------
# Cura (default 5.14.0)
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p Cura; \
    curl -fsSL -o Cura.tar.gz \
      "https://github.com/Ultimaker/Cura/archive/${CURA_REF}.tar.gz"; \
    tar -xzf Cura.tar.gz -C Cura --strip-components=1; \
    cd Cura; \
    py_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")'); \
    for p in AppDesktopData.patch CuraVersion.patch cmake-helpers.patch cmake.patch; do \
        patch -p1 < "/patches/cura/$p"; \
    done; \
    cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=minsizerel \
      -DCURA_VERSION=${CURA_VERSION} \
      -DPython_VERSION=${py_version} \
      -DURANIUM_DIR=/usr/share/uranium \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DGETTEXT_MSGINIT_EXECUTABLE=msginit \
      -DCURA_BINARY_DATA_DIRECTORY=/usr/share/cura; \
    cmake --build build; \
    cmake --install build; \
    mv /usr/bin/cura_app.py /usr/bin/cura; \
    rm -rf /usr/lib/cura/plugins/SliceInfoPlugin; \
    mkdir -p /usr/share/locale; \
    mv /usr/share/cura/resources/i18n/* /usr/share/locale/

# Uranium requires numpy-stl; Cura's TrimeshReader plugin requires trimesh.
# Alpine 3.24 does not package either, so install them without dependencies to
# avoid rebuilding numpy/scipy on musl.
RUN pip install --no-cache-dir --no-deps --break-system-packages \
      numpy-stl trimesh python-utils typing-extensions

# Stage the Python packages in a version-independent directory. The runtime
# stage discovers the interpreter's site-packages path (Alpine decides the
# Python minor) and copies these into it. This avoids hardcoding
# /usr/lib/python3.X/site-packages in a COPY instruction.
RUN set -eux; \
    sitelib=$(python3 -c 'import sysconfig; print(sysconfig.get_path("platlib"))'); \
    rm -rf /staging/python; \
    mkdir -p /staging/python; \
    cp -a "$sitelib"/UM "$sitelib"/cura "$sitelib"/stl "$sitelib"/trimesh \
          "$sitelib"/python_utils "$sitelib"/typing_extensions.py /staging/python/; \
    cp -a "$sitelib"/pyArcus.* "$sitelib"/pynest2d* "$sitelib"/pyUvula* \
          "$sitelib"/numpy_stl* /staging/python/

# Collect the license texts of everything built above. The release tarball
# ships this tree, and the runtime image keeps it for the same reason.
RUN set -eux; \
    L=/usr/share/licenses/cura-alpine; \
    rm -rf "$L"; \
    mkdir -p "$L"; \
    for d in Cura Uranium CuraEngine fdm_materials libArcus pyArcus pynest2d \
             libnest2d libUvula cura-formulae-engine Scripta geometry wagyu \
             zeus lexy; do \
        mkdir -p "$L/$d"; \
        find "/src/$d" -maxdepth 4 -type f \
            \( -iname 'LICENSE' -o -iname 'LICENSE.*' \
               -o -iname 'COPYING' -o -iname 'COPYING.*' \
               -o -iname 'NOTICE' -o -iname 'NOTICE.*' \
               -o -path '*/LICENSES/*' \) \
            -exec cp {} "$L/$d/" \; 2>/dev/null || true; \
    done; \
    mkdir -p "$L/cura-alpine"; \
    cp /LICENSE "$L/cura-alpine/LICENSE"

# Fail the build if the Python imports that break the Alpine package fail.
RUN python3 -c "import pyUvula; assert pyUvula.__version__ == '${LIBUVULA_VERSION}'; print('pyUvula', pyUvula.__version__)" && \
    python3 -c "import UM, cura, pyArcus, pynest2d; print('imports ok')" && \
    python3 -c "import cura.ApplicationMetadata as m; print('Cura', m.CuraVersion)" && \
    CuraEngine help | grep -m1 'Cura_SteamEngine version'

# ---------------------------------------------------------------------------
# Runtime image
# ---------------------------------------------------------------------------
FROM ${ALPINE_IMAGE}

ARG CURA_VERSION=5.14.0
LABEL org.opencontainers.image.title="cura-alpine" \
      org.opencontainers.image.version="${CURA_VERSION}" \
      org.opencontainers.image.description="Unofficial UltiMaker Cura ${CURA_VERSION} build for Alpine Linux"

RUN apk add --no-cache \
    python3 py3-qt6 py3-numpy py3-scipy py3-cryptography \
    py3-pyclipper py3-zeroconf py3-pyserial py3-requests py3-keyring \
    py3-networkx \
    libstdc++ protobuf onetbb libpng clipper nlopt spdlog fmt boost-libs \
    qt6-qtbase qt6-qtdeclarative qt6-qtsvg qt6-qt5compat \
    qt6-qtimageformats qt6-qttranslations \
    mesa-dri-gallium mesa-gl \
    libx11 libxkbcommon libxcb libxi libxrender libsm libice libxext \
    font-noto font-dejavu

COPY --from=builder /usr/lib/libArcus.so* /usr/lib/
COPY --from=builder /usr/lib/libcura-formulae-engine.so* /usr/lib/
COPY --from=builder /usr/bin/cura /usr/bin/cura
COPY --from=builder /usr/bin/CuraEngine /usr/bin/CuraEngine
COPY --from=builder /usr/lib/cura /usr/lib/cura
COPY --from=builder /usr/lib/uranium /usr/lib/uranium
COPY --from=builder /usr/share/cura /usr/share/cura
COPY --from=builder /usr/share/uranium /usr/share/uranium
COPY --from=builder /usr/share/locale /usr/share/locale
COPY --from=builder /usr/share/licenses/cura-alpine /usr/share/licenses/cura-alpine
COPY --from=builder /staging/python /staging/python

# Install the Python packages into whatever site-packages the runtime's Python
# reports. Alpine owns the Python minor version, so nothing below hardcodes
# /usr/lib/python3.X.
RUN set -eux; \
    sitelib=$(python3 -c 'import sysconfig; print(sysconfig.get_path("platlib"))'); \
    mkdir -p "$sitelib"; \
    cp -a /staging/python/. "$sitelib/"; \
    rm -rf /staging; \
    python3 -c "import pyUvula, UM, cura, pyArcus, pynest2d; print('runtime imports ok')" && \
    python3 -c "import cura.ApplicationMetadata as m; print('Cura', m.CuraVersion)"

RUN adduser -D -h /home/cura cura && \
    mkdir -p /home/cura/.local/share/cura /home/cura/.config/cura && \
    chown -R cura:cura /home/cura

USER cura
WORKDIR /home/cura
ENV HOME=/home/cura
ENV QT_QPA_PLATFORM=xcb
ENV LIBGL_ALWAYS_SOFTWARE=1

ENTRYPOINT ["/usr/bin/cura"]
