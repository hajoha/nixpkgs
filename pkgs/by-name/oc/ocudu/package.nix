# pkgs/by-name/oc/ocudu/package.nix
{
  lib,
  stdenv,
  cmake,
  fetchFromGitLab,
  pkg-config,
  fftwFloat,
  lksctp-tools,
  mbedtls,
  yaml-cpp,
  gtest,
  uhd,
  zeromq,
  czmq,
  boost,
  # Global -march / -mcpu. Upstream defaults to "native", which is neither
  # reproducible nor safe to cache, so fall back to the platform baseline.
  march ? "x86-64-v3",
  mcpu ? stdenv.hostPlatform.gcc.cpu or "generic",
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "ocudu";
  version = "26.04";

  src = fetchFromGitLab {
    owner = "ocudu";
    repo = "ocudu";
    tag = "release_${lib.replaceStrings [ "." ] [ "_" ] finalAttrs.version}";
    hash = "sha256-o1y/d9BM05DL61rtYTOui2g+lfkTHiYzhB4xEEpU+BY=";
    # fetchSubmodules = true;  # if external/ turns out to be submodules
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    boost
    fftwFloat
    lksctp-tools
    mbedtls
    yaml-cpp
    uhd
    zeromq
    czmq
  ];

  nativeCheckInputs = [ gtest ];

  cmakeFlags = [
    (lib.cmakeBool "ENABLE_WERROR" false)
    (lib.cmakeBool "BUILD_TESTING" finalAttrs.doCheck)

    # Pin every autodetected optional dependency so the result does not
    # depend on what happens to be in the build closure.
    (lib.cmakeBool "ENABLE_FFTW" true)
    (lib.cmakeBool "ENABLE_UHD" true)
    (lib.cmakeBool "ENABLE_ZEROMQ" true)
    (lib.cmakeBool "ENABLE_MKL" false) # unfree
    (lib.cmakeBool "ENABLE_SIDEKIQ" false) # proprietary
    (lib.cmakeBool "ENABLE_FFTZ" false)
    (lib.cmakeBool "ENABLE_ARMPL" false)
    (lib.cmakeBool "ENABLE_DPDK" false)
    (lib.cmakeBool "ENABLE_LIBNUMA" false)
    (lib.cmakeBool "ENABLE_BACKWARD" false) # would pull in elfutils
  ]
  ++ lib.optionals stdenv.hostPlatform.isx86_64 [
    (lib.cmakeFeature "MARCH" march)
    (lib.cmakeFeature "MTUNE" "generic")
  ]
  ++ lib.optional stdenv.hostPlatform.isAarch64 (lib.cmakeFeature "MCPU" mcpu);

  doCheck = false; # integration/benchmark suites are heavy; enable selectively
  postPatch = ''
    # cmake-sbom's per-binary SPDX scripts assert on ''${CMAKE_INSTALL_PREFIX}/bin/...
    # and fail at install time with an absolute store prefix. Skip them; the
    # package-level SBOM in share/ is still generated.
    substituteInPlace CMakeLists.txt \
      --replace-fail 'function(notify_binary_target)' 'function(notify_binary_target)
    return()'
  '';
  meta = {
    description = "O-RAN compliant 5G NR CU/DU implementation";
    longDescription = "x86-64-v3 because AVX is not supported on older CPUs";
    homepage = "https://ocudu.org";
    changelog = "https://gitlab.com/ocudu/ocudu/-/releases/${finalAttrs.src.tag}";
    license = lib.licenses.bsd3OpenMpi;
    maintainers = with lib.maintainers; [ hajoha ];
    mainProgram = "gnb";
    platforms = lib.platforms.linux;
  };
})
