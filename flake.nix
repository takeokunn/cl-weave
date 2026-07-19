{
  description = "cl-weave: a modern Common Lisp testing framework";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.paredit-cli = {
    url = "github:takeokunn/paredit-cli";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      paredit-cli,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems =
        function: nixpkgs.lib.genAttrs systems (system: function (import nixpkgs { inherit system; }));
      source = nixpkgs.lib.cleanSourceWith {
        src = self;
        filter =
          path: type: nixpkgs.lib.cleanSourceFilter path type && builtins.baseNameOf path != ".direnv";
      };

      mkDocs =
        pkgs:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "cl-weave-docs";
          version = "0.7.0";
          src = pkgs.lib.fileset.toSource {
            root = ./docs;
            fileset = pkgs.lib.fileset.unions [
              ./docs/book.toml
              ./docs/src
            ];
          };
          nativeBuildInputs = [ pkgs.mdbook ];
          buildPhase = ''
            runHook preBuild
            mdbook build --dest-dir "$out" .
            runHook postBuild
          '';
          dontInstall = true;
          meta = {
            description = "Rendered mdBook documentation for cl-weave";
            homepage = "https://github.com/takeokunn/cl-weave";
            license = pkgs.lib.licenses.mit;
          };
        };
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.coreutils
            pkgs.sbcl
            paredit-cli.packages.${pkgs.stdenv.hostPlatform.system}.default
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);

      checks = forAllSystems (
        pkgs:
        let
          lib = pkgs.lib;
          packaged-cli = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/cl-weave";
          mkCheck =
            {
              name,
              timeoutSeconds,
              command,
              artifacts ? [ ],
            }:
            pkgs.stdenv.mkDerivation {
              inherit name;
              src = source;
              nativeBuildInputs = [
                pkgs.coreutils
                pkgs.sbcl
              ];
              buildPhase = ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"
                export CL_SOURCE_REGISTRY="$PWD//:"
                timeout ${toString timeoutSeconds}s \
                  ${lib.escapeShellArgs command}
                ${lib.concatMapStringsSep "\n" (artifact: "test -e ${lib.escapeShellArg artifact}") artifacts}
              '';
              installPhase = ''
                mkdir -p "$out"
                ${lib.concatMapStringsSep "\n" (
                  artifact: "cp -R ${lib.escapeShellArg artifact} \"$out/\""
                ) artifacts}
              '';
            };
        in
        {
          test = mkCheck {
            name = "cl-weave-test";
            timeoutSeconds = 360;
            command = [
              packaged-cli
              "run"
              "cl-weave/tests"
            ];
          };

          json-results-artifact = mkCheck {
            name = "cl-weave-json-results-artifact";
            timeoutSeconds = 360;
            command = [
              packaged-cli
              "run"
              "cl-weave/tests"
              "--reporter"
              "json"
              "--output"
              "cl-weave-results.json"
            ];
            artifacts = [ "cl-weave-results.json" ];
          };

          jsonl-events-artifact = mkCheck {
            name = "cl-weave-jsonl-events-artifact";
            timeoutSeconds = 360;
            command = [
              packaged-cli
              "run"
              "cl-weave/tests"
              "--reporter"
              "jsonl"
              "--output"
              "cl-weave-events.jsonl"
            ];
            artifacts = [ "cl-weave-events.jsonl" ];
          };

          cli-json-results = mkCheck {
            name = "cl-weave-cli-json-results";
            timeoutSeconds = 360;
            command = [
              packaged-cli
              "run"
              "cl-weave/tests"
              "--reporter"
              "json"
              "--filter"
              "filtering > runs only tests matching a path substring"
              "--fail-with-no-tests"
              "--output"
              "cl-weave-cli-results.json"
            ];
            artifacts = [ "cl-weave-cli-results.json" ];
          };

          ai-metadata-artifact = mkCheck {
            name = "cl-weave-ai-metadata-artifact";
            timeoutSeconds = 120;
            command = [
              packaged-cli
              "metadata"
              "cl-weave/tests"
              "--reporter"
              "json"
              "--output"
              "cl-weave-metadata.json"
            ];
            artifacts = [ "cl-weave-metadata.json" ];
          };

          plan-artifact = mkCheck {
            name = "cl-weave-plan-artifact";
            timeoutSeconds = 120;
            command = [
              packaged-cli
              "list"
              "cl-weave/tests"
              "--reporter"
              "json"
              "--filter"
              "filtering > runs only tests matching a path substring"
              "--fail-with-no-tests"
              "--output"
              "cl-weave-plan.json"
            ];
            artifacts = [ "cl-weave-plan.json" ];
          };

          watch-once-artifact = mkCheck {
            name = "cl-weave-watch-once-artifact";
            timeoutSeconds = 120;
            command = [
              packaged-cli
              "watch"
              "cl-weave/tests"
              "--once"
              "--reporter"
              "json"
              "--filter"
              "filtering > runs only tests matching a path substring"
              "--fail-with-no-tests"
              "--output"
              "cl-weave-watch-once.json"
            ];
            artifacts = [ "cl-weave-watch-once.json" ];
          };

          tap-artifact = mkCheck {
            name = "cl-weave-tap-artifact";
            timeoutSeconds = 120;
            command = [
              packaged-cli
              "run"
              "cl-weave/tests"
              "--reporter"
              "tap"
              "--filter"
              "filtering > runs only tests matching a path substring"
              "--fail-with-no-tests"
              "--output"
              "cl-weave-tap.txt"
            ];
            artifacts = [ "cl-weave-tap.txt" ];
          };

          filtered-smoke = mkCheck {
            name = "cl-weave-filtered-smoke";
            timeoutSeconds = 60;
            command = [
              packaged-cli
              "run"
              "cl-weave/tests"
              "--filter"
              "filtering > runs only tests matching a path substring"
              "--fail-with-no-tests"
            ];
          };

          junit-artifact = mkCheck {
            name = "cl-weave-junit-artifact";
            timeoutSeconds = 360;
            command = [
              packaged-cli
              "run"
              "cl-weave/tests"
              "--reporter"
              "junit"
              "--output"
              "cl-weave-junit.xml"
            ];
            artifacts = [ "cl-weave-junit.xml" ];
          };

          coverage-artifact = mkCheck {
            name = "cl-weave-coverage-artifact";
            timeoutSeconds = 360;
            command = [
              packaged-cli
              "run"
              "cl-weave/tests"
              "--coverage"
              "--coverage-output"
              "cl-weave.coverage"
              "--coverage-report-directory"
              "cl-weave-coverage-report/"
              "--coverage-system"
              "cl-weave"
              "--coverage-min-expression"
              "1"
              "--coverage-min-branch"
              "1"
            ];
            artifacts = [
              "cl-weave.coverage"
              "cl-weave-coverage-report/"
            ];
          };

          paredit-lint = paredit-cli.lib.${pkgs.stdenv.hostPlatform.system}.mkLintCheck {
            src = source;
            name = "cl-weave-paredit-lint";
          };
        }
      );

      packages = forAllSystems (pkgs: {
        docs = mkDocs pkgs;

        default = pkgs.stdenv.mkDerivation {
          pname = "cl-weave";
          version = "0.7.0";
          src = source;
          dontBuild = true;
          installPhase = ''
            mkdir -p $out/share/common-lisp/source/cl-weave
            mkdir -p $out/bin
            cp -R . $out/share/common-lisp/source/cl-weave
            cat > $out/bin/cl-weave <<EOF
            #!${pkgs.runtimeShell}
            set -eu
            export CL_SOURCE_REGISTRY="$out/share/common-lisp/source//:\''${CL_SOURCE_REGISTRY:-}"
            exec ${pkgs.sbcl}/bin/sbcl --dynamic-space-size 4096 --noinform --non-interactive \\
              --eval '(require :asdf)' \\
              --eval '(asdf:initialize-output-translations (quote (:output-translations (t (:home ".cache" "common-lisp" :implementation)) :ignore-inherited-configuration)))' \\
              --eval '(asdf:load-system :cl-weave)' \\
              --eval '(cl-weave/cli:main)' \\
              -- "\$@"
            EOF
            chmod +x $out/bin/cl-weave
          '';
          meta = {
            description = "A modern, Vitest-inspired Common Lisp testing framework";
            homepage = "https://github.com/takeokunn/cl-weave";
            license = pkgs.lib.licenses.mit;
            platforms = pkgs.lib.platforms.unix;
            mainProgram = "cl-weave";
          };
        };
      });

      overlays.default = final: prev: {
        cl-weave = self.packages.${final.stdenv.hostPlatform.system}.default;
      };

      apps = forAllSystems (
        pkgs:
        let
          package = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
          program = "${package}/bin/cl-weave";
        in
        {
          default = {
            type = "app";
            inherit program;
            meta = {
              description = "cl-weave CLI application";
              mainProgram = "cl-weave";
            };
          };

          cl-weave = {
            type = "app";
            inherit program;
            meta = {
              description = "cl-weave CLI application";
              mainProgram = "cl-weave";
            };
          };
        }
      );
    };
}
