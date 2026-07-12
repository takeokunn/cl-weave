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
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.perl
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
              src = self;
              nativeBuildInputs = [
                pkgs.perl
                pkgs.sbcl
              ];
              buildPhase = ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"
                export CL_SOURCE_REGISTRY="$PWD//:"
                perl -e 'alarm shift; exec @ARGV' -- \
                  ${toString timeoutSeconds} \
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
              "sbcl"
              "--dynamic-space-size"
              "4096"
              "--noinform"
              "--non-interactive"
              "--load"
              "scripts/run-tests.lisp"
            ];
          };

          json-results-artifact = mkCheck {
            name = "cl-weave-json-results-artifact";
            timeoutSeconds = 360;
            command = [
              "env"
              "CL_WEAVE_REPORTER=json"
              "CL_WEAVE_OUTPUT_FILE=cl-weave-results.json"
              "sbcl"
              "--dynamic-space-size"
              "4096"
              "--noinform"
              "--non-interactive"
              "--load"
              "scripts/run-tests.lisp"
            ];
            artifacts = [ "cl-weave-results.json" ];
          };

          jsonl-events-artifact = mkCheck {
            name = "cl-weave-jsonl-events-artifact";
            timeoutSeconds = 360;
            command = [
              "env"
              "CL_WEAVE_REPORTER=jsonl"
              "CL_WEAVE_OUTPUT_FILE=cl-weave-events.jsonl"
              "sbcl"
              "--dynamic-space-size"
              "4096"
              "--noinform"
              "--non-interactive"
              "--load"
              "scripts/run-tests.lisp"
            ];
            artifacts = [ "cl-weave-events.jsonl" ];
          };

          coverage-artifact = mkCheck {
            name = "cl-weave-coverage-gate";
            timeoutSeconds = 360;
            command = [
              "sh"
              "scripts/run-coverage-gate.sh"
            ];
            artifacts = [
              "cl-weave.coverage"
              "cl-weave-coverage-summary.json"
              "cl-weave-coverage-report"
            ];
          };

          coverage-gate-unit = mkCheck {
            name = "cl-weave-coverage-gate-unit";
            timeoutSeconds = 30;
            command = [
              "perl"
              "scripts/test-coverage-gate.pl"
            ];
          };

          cli-json-results = mkCheck {
            name = "cl-weave-cli-json-results";
            timeoutSeconds = 360;
            command = [
              packaged-cli
              "run"
              "cl-weave-tests"
              "--reporter"
              "json"
              "--filter"
              "filtering > runs only tests matching a path substring"
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
              "cl-weave-tests"
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
              "cl-weave-tests"
              "--reporter"
              "json"
              "--filter"
              "filtering > runs only tests matching a path substring"
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
              "cl-weave-tests"
              "--once"
              "--reporter"
              "json"
              "--filter"
              "filtering > runs only tests matching a path substring"
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
              "cl-weave-tests"
              "--reporter"
              "tap"
              "--filter"
              "filtering > runs only tests matching a path substring"
              "--output"
              "cl-weave-tap.txt"
            ];
            artifacts = [ "cl-weave-tap.txt" ];
          };

          filtered-smoke = mkCheck {
            name = "cl-weave-filtered-smoke";
            timeoutSeconds = 60;
            command = [
              "env"
              "CL_WEAVE_TEST_FILTER=filtering > runs only tests matching a path substring"
              "sbcl"
              "--dynamic-space-size"
              "4096"
              "--noinform"
              "--non-interactive"
              "--load"
              "scripts/run-tests.lisp"
            ];
          };

          junit-artifact = mkCheck {
            name = "cl-weave-junit-artifact";
            timeoutSeconds = 360;
            command = [
              "env"
              "CL_WEAVE_REPORTER=junit"
              "CL_WEAVE_OUTPUT_FILE=cl-weave-junit.xml"
              "sbcl"
              "--dynamic-space-size"
              "4096"
              "--noinform"
              "--non-interactive"
              "--load"
              "scripts/run-tests.lisp"
            ];
            artifacts = [ "cl-weave-junit.xml" ];
          };

          paredit-lint = paredit-cli.lib.${pkgs.stdenv.hostPlatform.system}.mkLintCheck {
            src = self;
            name = "cl-weave-paredit-lint";
          };
        }
      );

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
            exec ${pkgs.sbcl}/bin/sbcl --dynamic-space-size 4096 --noinform --non-interactive \\
              --eval '(require :asdf)' \\
              --eval '(asdf:initialize-output-translations (quote (:output-translations (t (:home ".cache" "common-lisp" :implementation)) :ignore-inherited-configuration)))' \\
              --eval '(asdf:load-system :cl-weave)' \\
              --eval '(cl-weave/cli:main (uiop:command-line-arguments))' \\
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
