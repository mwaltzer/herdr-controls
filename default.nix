{ lib, stdenv, swift, swiftpm }:

let
  # Single version source, shared with release/package.sh.
  version = lib.removeSuffix "\n" (builtins.readFile ./VERSION);
in
stdenv.mkDerivation {
  pname = "sketchy-controls";
  inherit version;
  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: type:
      let name = baseNameOf (toString path);
      in name != ".build" && name != ".swiftpm" && name != "dist";
  };

  nativeBuildInputs = [ swift swiftpm ];

  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR"
    swift build -c release --disable-sandbox --jobs 1
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    .build/release/SketchyControlsCoreChecks
  '';

  installPhase = ''
    runHook preInstall
    app="$out/Applications/Herdr Controls.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$out/bin"
    cp .build/release/SketchyControls "$app/Contents/MacOS/SketchyControls"
    cp Sources/SketchyControls/Resources/herdr-mask.svg "$app/Contents/Resources/"
    cp Sources/SketchyControls/Resources/tailscale-icon.svg "$app/Contents/Resources/"
    cp Resources/herdr-tailnet-sessions Resources/herdr-open-tailnet-session "$app/Contents/Resources/"
    chmod +x "$app/Contents/Resources/herdr-tailnet-sessions" "$app/Contents/Resources/herdr-open-tailnet-session"
    substitute release/Info.plist.in "$app/Contents/Info.plist" \
      --replace-fail "@SHORT_VERSION@" "${version}" \
      --replace-fail "@BUILD_VERSION@" "${version}"
    printf 'APPL????' > "$app/Contents/PkgInfo"
    cp .build/release/SketchyControlsCLI "$out/bin/sketchy-controls"
    runHook postInstall
  '';
}
