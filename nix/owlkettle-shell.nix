{
  pkgs ? import <nixpkgs> {}
}:
pkgs.mkShell {
  buildInputs = with pkgs; [
    nim
    nimble
    pkg-config
    gtk4
    glib
    pango
    cairo
    graphene
    gdk-pixbuf
    openssl
  ];

  shellHook = ''
    echo "Nix shell ready for GTK/OwlKettle development"
    echo "Run: nimble build"
  '';
}
