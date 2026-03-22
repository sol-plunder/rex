{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
    in {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          ghcEnv = pkgs.haskellPackages.ghcWithPackages (hp: with hp; [
            text pretty-show containers deepseq mtl extra transformers
            optics vector wl-pprint ansi-wl-pprint
          ]);
        in {
          default = pkgs.mkShell {
            packages = [
              ghcEnv
              pkgs.rlwrap
              pkgs.haskellPackages.ghcid
              pkgs.haskellPackages.stylish-haskell
              pkgs.haskellPackages.cabal-install
            ];
          };
        });
    };
}
