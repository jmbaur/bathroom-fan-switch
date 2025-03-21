{
  description = "bathroom fan switch";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  outputs = inputs: {
    devShells = inputs.nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
      system:
      let
        inherit (import inputs.nixpkgs { inherit system; }) zig_0_14 mkShell;
      in
      {
        default = mkShell { packages = [ zig_0_14 ]; };
      }
    );
  };
}
