{
  description = "nautice — 에이전트가 사람의 주의를 끄는 알림 CLI";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  # x86_64-darwin 은 빠져 있다 — nixpkgs-unstable 이 Intel Mac 평가를 거부한다
  # (릴리스 노트 x86_64-darwin-26.11). 필요하면 nixpkgs-26.05-darwin 을 쓴다.

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in {
      packages = forAll (pkgs:
        let
          inherit (pkgs) lib stdenv;
          # macOS 는 say/afplay 가 OS 내장이라 넣을 게 없다. Linux 는 TTS 백엔드가
          # 없으면 아무것도 못 하므로 espeak-ng 를 딸려 보낸다. 재생기는 시스템이
          # 준다 (PipeWire 의 pw-play, PulseAudio 의 paplay, ALSA 의 aplay).
          # Linux 는 TTS 도 배너도 시스템이 안 준다. macOS 는 say·afplay·osascript 가
          # 다 OS 내장이라 넣을 게 없다.
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
              shellcheck bin/nautice test/conformance
            '';

            installPhase = ''
              runHook preInstall
              install -Dm755 bin/nautice $out/bin/nautice
              mkdir -p $out/share/nautice/sounds
              cp share/sounds/*.wav $out/share/nautice/sounds/
              # bin/nautice 는 자기 위치에서 ../share/nautice/sounds 를 찾는다.
              wrapProgram $out/bin/nautice \
                --prefix PATH : ${lib.makeBinPath runtime}
              runHook postInstall
            '';

            meta = {
              description = "에이전트가 사람의 주의를 끄는 알림 CLI";
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
