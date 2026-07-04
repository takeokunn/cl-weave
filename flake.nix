{
  description = "cl-weave: a modern Common Lisp testing framework";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = function:
        nixpkgs.lib.genAttrs systems (system:
          function (import nixpkgs { inherit system; }));
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.sbcl ];
        };
      });

      checks = forAllSystems (pkgs: {
        test = pkgs.stdenv.mkDerivation {
          name = "cl-weave-test";
          src = self;
          nativeBuildInputs = [ pkgs.coreutils pkgs.sbcl ];
          buildPhase = ''
            export CL_SOURCE_REGISTRY="$PWD//:"
            timeout 360s sbcl --noinform --non-interactive --load scripts/run-tests.lisp
          '';
          installPhase = "mkdir -p $out";
        };
      });

      packages = forAllSystems (pkgs: {
        default = pkgs.stdenv.mkDerivation {
          pname = "cl-weave";
          version = "0.1.0";
          src = self;
          dontBuild = true;
          installPhase = ''
            mkdir -p $out/share/common-lisp/source/cl-weave
            mkdir -p $out/bin
            cp -R . $out/share/common-lisp/source/cl-weave
            cat > $out/bin/cl-weave <<EOF
            #!${pkgs.runtimeShell}
            set -eu
            export CL_SOURCE_REGISTRY="$out/share/common-lisp/source//:\''${CL_SOURCE_REGISTRY:-}"
            exec ${pkgs.sbcl}/bin/sbcl --noinform --non-interactive \\
              --eval '(require :asdf)' \\
              --eval '(asdf:load-system :cl-weave)' \\
              --eval '(cl-weave/cli:main (uiop:command-line-arguments))' \\
              -- "\$@"
            EOF
            chmod +x $out/bin/cl-weave
          '';
          meta.mainProgram = "cl-weave";
        };
      });
    };
}
