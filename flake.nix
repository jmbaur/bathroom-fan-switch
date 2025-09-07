{
  description = "bathroom fan switch";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  outputs = inputs: {
    devShells = inputs.nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system: {
      default = (import inputs.nixpkgs { inherit system; }).callPackage (
        {
          gdb,
          mkShell,
          openocd-rp2040,
          zig_0_15,
        }:
        mkShell {
          packages = [
            gdb
            openocd-rp2040
            zig_0_15
          ];
        }
      ) { };
    });
  };
}
