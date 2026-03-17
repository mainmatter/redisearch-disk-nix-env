{
  description = "Build a RediSearch on Disk Rust library";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    redis-flake = {
      url = "github:mainmatter/redis-flake/rsd_big2_8.4";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    rltest-src = {
      url = "github:RedisLabsModules/RLTest/v0.7.18";
      flake = false;  # Use the source directly, not as a flake
    };

    python-terraform-src = {
      url = "github:beelit94/python-terraform/0.14.0";
      flake = false;  # Use the source directly, not as a flake
    };

    redisbench-admin-src = {
      url = "github:redis-performance/redisbench-admin";
      flake = false;  # Use the source directly, not as a flake
    };

    ftsb-src = {
      url = "github:RediSearch/ftsb/v0.5.0";
      flake = false;  # Use the source directly, not as a flake
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, redis-flake, rltest-src, python-terraform-src, redisbench-admin-src, ftsb-src, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
          config.allowUnfree = true;
        };
        redis-source = redis-flake.packages.${system}.redis;

        paramiko_3_5_1 = (pkgs.python313Packages.paramiko.overridePythonAttrs (old: rec {
          version = "3.5.1";

          src = pkgs.fetchPypi {
            inherit version;
            pname = "paramiko";
            hash = "sha256-ssZlvEWyshW9fX8DmQGxSwZ9oA86EeZkCZX9WPJmSCI=";
          };

          # Skip tests during build
          doCheck = false;
        }));

        # Custom RLTest package
        rltest = pkgs.python3Packages.buildPythonPackage rec {
          pname = "RLTest";
          version = "0.7.18";

          src = rltest-src;

          # Use pyproject.toml for building
          pyproject = true;
          build-system = with pkgs.python3Packages; [
            poetry-core
          ];

          # Runtime dependencies
          dependencies = with pkgs.python3Packages; [
            distro
            progressbar2
            psutil
            pytest
            pytest-cov
            redis-source
            setuptools  # Needed for pkg_resources
          ];

          # Skip tests during build
          doCheck = false;

          # Skip the runtime dependency version checking
          dontCheckRuntimeDeps = true;

          meta = with pkgs.lib; {
            description = "Redis Labs Test Framework";
            homepage = "https://github.com/RedisLabsModules/RLTest";
            license = licenses.bsd3;
          };
        };

        # Custom python-terraform package since it is not available in nixpkgs
        python-terraform = pkgs.python3Packages.buildPythonPackage rec {
          pname = "python-terraform";
          version = "0.14.0";

          src = python-terraform-src;

          format = "setuptools";

          meta = with pkgs.lib; {
            description = "Python wrapper for terraform command line tool";
            homepage = "https://github.com/beelit94/python-terraform";
            license = licenses.mit;
          };
        };

        # Custom redisbench-admin package
        redisbench-admin = pkgs.python3Packages.buildPythonPackage rec {
          pname = "redisbench-admin";
          version = "0.12.10";

          src = redisbench-admin-src;

          pyproject = true;
          build-system = with pkgs.python3Packages; [
            poetry-core
          ];

          dependencies = with pkgs.python3Packages; [
            flask
            flask-httpauth
            gitpython
            jinja2
            pyyaml
            boto3
            certifi
            daemonize
            flask-restx
            humanize
            jsonpath-ng
            matplotlib
            numpy
            pandas
            paramiko_3_5_1
            psutil
            # The newest version (9.0) has a different structure which causes the profiler to not get the `brand` key correctly
            # So we override the version to 5.0.0
            (py-cpuinfo.overridePythonAttrs (old: rec {
              version = "5.0.0";

              src = pkgs.fetchFromGitHub {
                owner = "workhorsy";
                repo = "py-cpuinfo";
                rev = "v5.0.0";
                hash = "sha256-EbeWNXjfdgb9yZAh3+kVLBDKMVFMipV/gOUr2YxNtFM=";
              };
            }))
            pygithub
            (pysftp.overridePythonAttrs (old: {
              # Fix dependency to use our custom paramiko version
              propagatedBuildInputs = map (dep: if dep == pkgs.python3Packages.paramiko then paramiko_3_5_1 else dep) old.propagatedBuildInputs;
            }))
            pytablewriter
            python-terraform
            redis
            requests
            slack-bolt
            slack-sdk
            (sshtunnel.overridePythonAttrs (old: {
              # Fix dependency to use our custom paramiko version
              dependencies = map (dep: if dep == pkgs.python3Packages.paramiko then paramiko_3_5_1 else dep) old.dependencies;
            }))
            toml
            tqdm
            watchdog
            wget
          ];

          # Skip tests during build
          doCheck = false;
          dontCheckRuntimeDeps = true;

          meta = with pkgs.lib; {
            description = "Redis benchmarking and performance analysis tool";
            homepage = "https://github.com/redis-performance/redisbench-admin";
            license = licenses.bsd3;
          };
        };

        # Custom ftsb package
        ftsb = pkgs.buildGoModule {
          pname = "ftsb";
          version = "0.5.0";

          src = ftsb-src;

          vendorHash = "sha256-2q1mFlhpYnyZ5rMCis4HZBflC1bgtqkLORnw7wVu4J0=";

          # Skip tests during build because I'm not installing docker for the tests
          doCheck = false;

          meta = with pkgs.lib; {
            description = "Full-Text Search Benchmarking tool for RediSearch";
            homepage = "https://github.com/RediSearch/ftsb";
            license = licenses.mit;
          };
        };

        # Custom gherkin-official package since it is not available in nixpkgs
        gherkin-official = pkgs.python3Packages.buildPythonPackage rec {
          pname = "gherkin-official";
          version = "29.0.0";

          src = pkgs.fetchPypi {
            pname = "gherkin_official";
            inherit version;
            hash = "sha256-2+oyVhFY8CKA11edF5sBkWDQcs4IMZdiXi+Apndrues=";
          };

          pyproject = true;
          build-system = with pkgs.python3Packages; [ setuptools ];
        };

        # The nix version is too old and doesn't have the latest features we need, so we override it with a newer version and add the gherkin-official dependency
        pytest-bdd-8 = pkgs.python3Packages.pytest-bdd.overridePythonAttrs (old: rec {
          version = "8.1.0";
          src = pkgs.fetchPypi {
            pname = "pytest_bdd";
            inherit version;
            hash = "sha256-7wiWxc1YgW3EmBDo/x1jL0oSAZ+z5JlZstNJ/8HJv7U=";
          };
          dependencies = old.dependencies ++ [ gherkin-official ];
          doCheck = false;
        });

        # Python environment with packages from requirements.txt
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          pip # Needed for readies to detect this python env
          gevent
          packaging
          deepdiff
          redis
          numpy
          scipy
          faker
          distro
          orderly-set
          rltest
          redisbench-admin
          ml-dtypes
          pytest-bdd-8
          pytest-xdist
        ]);
      in
      {
        devShells = {
          default =  pkgs.mkShell {
            hardeningDisable = [ "fortify" "stackprotector" "pic" "relro" ];
            # Shell hooks to create executable scripts in a local bin directory

            CMAKE_ARGS = "-DSVS_SHARED_LIB=OFF";
            shellHook = ''
              cargo_version=$(cargo --version 2>/dev/null)

              echo -e "\033[1;36m=== 🦀 Welcome to the RediSearch development environment ===\033[0m"
              echo -e "\033[1;33m• $cargo_version\033[0m"
              echo -e "\n\033[1;33m• Checking for any outdated packages...\033[0m\n"
              cd redisearch_disk && cargo outdated --root-deps-only

              # For libclang dependency to work
              export LIBCLANG_PATH="${pkgs.llvmPackages.libclang.lib}/lib"
              # For `sys/types.h` and `stddef.h` required by redismodules-rs
              export BINDGEN_EXTRA_CLANG_ARGS="-I${pkgs.glibc.dev}/include -I${pkgs.gcc-unwrapped}/lib/gcc/x86_64-unknown-linux-gnu/14.3.0/include"

              # Force SVS to build from source instead of using precompiled library
              export CMAKE_ARGS="-DSVS_SHARED_LIB=OFF"

              # Tell getpy3 to use our Nix Python directly, skipping version detection and PEP_668 logic
              export MYPY="${pkgs.python3}/bin/python3"

              # Needed to build speedb from source
              export NIX_CFLAGS_COMPILE="-Wno-error=format-truncation $NIX_CFLAGS_COMPILE"
            '';

            buildInputs = with pkgs; [
              # For LSP
              ccls

              # Dev dependencies based on developer.md
              cmake
              openssl.dev
              libxcrypt

              # For search on disk
              redis-source
              boost188
              liburing

              # Python environment for integration tests
              pythonEnv

              # Needed by python tests
              wget
              redis-source

              rust-bin.stable.latest.default

              # For redisbench-admin
              ftsb
              memtier-benchmark

              # Cache for faster rebuilds
              sccache
            ];

            packages = with pkgs; [
              rust-analyzer
              cargo-watch
              cargo-outdated
              cargo-nextest
              lldb
              vscode-extensions.vadimcn.vscode-lldb.adapter
            ];
          };

          nightly = pkgs.mkShell {
            hardeningDisable = [ "fortify" "stackprotector" "pic" "relro" ];
            # Shell hooks to create executable scripts in a local bin directory
            shellHook = ''
              cargo_version=$(cargo --version 2>/dev/null)

              echo -e "\033[1;36m=== 🦀 Welcome to the RediSearch development NIGHTLY environment ===\033[0m"
              echo -e "\033[1;33m• $cargo_version\033[0m"

              # For libclang dependency to work
              export LIBCLANG_PATH="${pkgs.llvmPackages.libclang.lib}/lib"
              # For `sys/types.h` and `stddef.h` required by redismodules-rs
              export BINDGEN_EXTRA_CLANG_ARGS="-I${pkgs.glibc.dev}/include -I${pkgs.gcc-unwrapped}/lib/gcc/x86_64-unknown-linux-gnu/14.3.0/include"

              # Tell getpy3 to use our Nix Python directly, skipping version detection and PEP_668 logic
              export MYPY="${pkgs.python3}/bin/python3"

              # Tell valgrind about the suppression file
              export VALGRINDFLAGS="--suppressions=$PWD/valgrind.supp"

              # Needed to build speedb from source
              export NIX_CFLAGS_COMPILE="-Wno-error=format-truncation $NIX_CFLAGS_COMPILE"

              export ASAN_OPTIONS="detect_odr_violation=0"
            '';

            buildInputs = with pkgs; [
              # Dev dependencies based on developer.md
              cmake
              openssl.dev
              libxcrypt

              # Python environment for integration tests
              pythonEnv

              # Needed by python tests
              wget

              # Redis with ASAN support for nightly testing
              (redis-source.overrideAttrs (old: {
                makeFlags = (old.makeFlags or []) ++ [
                  "SANITIZER=address"
                ];
              }))

              (rust-bin.nightly."2026-01-05".default.override {
                extensions = [ "rust-src" "miri" "llvm-tools-preview" ];
              })

              # To resolve ASAN symbols
              llvmPackages.bintools
            ];

            packages = with pkgs; [
              cargo-llvm-cov
              cargo-nextest
              lcov
            ];
          };
        };
      });
}
