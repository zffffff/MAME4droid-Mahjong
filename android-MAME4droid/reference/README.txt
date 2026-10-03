Basic flavor CI/local builds need the mj2-era libMAME4droid.so (upstream MAME 1.38.1).

Place either file here (not committed; .so is gitignored):

  FeiJuchang-1.38.1-mj2-basic-release.apk
  mj2-basic-reference.apk

Or set GitHub Actions secret BASIC_MAME_REFERENCE_APK_URL to a downloadable
copy of that APK, or BASIC_MAME_SO_URL to a direct arm64 libMAME4droid.so URL.

Expected mj2 lib md5: 413ea92831c298abb281500c91c1e41f
