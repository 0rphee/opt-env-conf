final: prev:
with final.lib;
with final.haskell.lib;
{
  optEnvConfRelease =
    final.symlinkJoin {
      name = "opt-env-conf-release";
      paths = final.lib.attrValues final.haskellPackages.optEnvConfPackages;
    };
  haskellPackages = prev.haskellPackages.override (old: {
    overrides = final.lib.composeExtensions (old.overrides or (_: _: { }))
      (
        self: super:
          let
            optEnvConfPkg = name:
              buildFromSdist (overrideCabal (self.callPackage (../${name}/default.nix) { }) (old: {
                configureFlags = (old.configureFlags or [ ]) ++ [
                  # Optimisations
                  "--ghc-options=-O2"
                  # Extra warnings
                  "--ghc-options=-Wall"
                  "--ghc-options=-Wincomplete-uni-patterns"
                  "--ghc-options=-Wincomplete-record-updates"
                  "--ghc-options=-Wpartial-fields"
                  "--ghc-options=-Widentities"
                  "--ghc-options=-Wredundant-constraints"
                  "--ghc-options=-Wcpp-undef"
                  "--ghc-options=-Werror"
                ];
                doBenchmark = true;
                doHaddock = false;
                doCoverage = false;
                doHoogle = false;
                doCheck = false; # Only for coverage
                hyperlinkSource = false;
                enableLibraryProfiling = false;
                enableExecutableProfiling = false;
                # Ugly hack because we can't just add flags to the 'test' invocation.
                # Show test output as we go, instead of all at once afterwards.
                testTarget = (old.testTarget or "") + " --show-details=direct";
              }));

            optEnvConfPackages = {
              opt-env-conf = optEnvConfPkg "opt-env-conf";
              opt-env-conf-test = optEnvConfPkg "opt-env-conf-test";
            };

            installManpage = exeNames: drv: overrideCabal drv (old: {
              postInstall = (drv.postInstall or "") + ''
                mkdir -p $out/share/man/man1/
                # ${pkgs.help2man}/bin/help2man "''${!outputBin}/bin/${exeName}"
              '';
            });
            installCompletions = exeNames: drv: { };
            installManpageAndCompletions = exeNames: drv: installManpage exeNames (installCompletions exeNames drv);
          in
          {
            inherit optEnvConfPackages;
          } // optEnvConfPackages
      );
  });
}
