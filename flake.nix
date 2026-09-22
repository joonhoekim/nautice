{
  description = "nautice — a notification CLI that lets an agent get a human's attention";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  # No x86_64-darwin: nixpkgs-unstable no longer evaluates Intel Macs (release
  # note x86_64-darwin-26.11). Use nixpkgs-26.05-darwin if needed.

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in {
      packages = forAll (pkgs:
        let
          inherit (pkgs) lib stdenv;
          # macOS ships say, afplay and osascript. Linux gets espeak-ng (TTS) and
          # libnotify (banners); the audio player comes from the system
          # (pw-play, paplay or aplay).
          runtime = [ pkgs.flock ]
            ++ lib.optionals stdenv.hostPlatform.isLinux [ pkgs.espeak-ng pkgs.libnotify ];
        in rec {
          nautice = stdenv.mkDerivation {
            pname = "nautice";
            version = "0.4.0";
            src = ./.;

            nativeBuildInputs = [ pkgs.makeWrapper ];
            buildInputs = runtime;

            doCheck = true;
            nativeCheckInputs = [ pkgs.shellcheck ];
            checkPhase = ''
              shellcheck bin/nautice test/conformance install.sh tools/release-notes
            '';

            installPhase = ''
              runHook preInstall
              install -Dm755 bin/nautice $out/bin/nautice
              mkdir -p $out/share/nautice/sounds
              cp share/sounds/*.wav $out/share/nautice/sounds/
              # bin/nautice finds ../share/nautice/sounds relative to itself.
              wrapProgram $out/bin/nautice \
                --prefix PATH : ${lib.makeBinPath runtime}
              runHook postInstall
            '';

            meta = {
              description = "Notification CLI that lets an agent get a human's attention";
              mainProgram = "nautice";
              license = lib.licenses.mit;
              platforms = lib.platforms.darwin ++ lib.platforms.linux;
            };
          };
          default = nautice;
        });

      apps = forAll (pkgs: rec {
        nautice = { type = "app"; program = "${self.packages.${pkgs.system}.nautice}/bin/nautice"; };
        default = nautice;
      });

      checks = forAll (pkgs: { inherit (self.packages.${pkgs.system}) nautice; });
    };
}
