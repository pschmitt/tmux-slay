{
  lib,
  stdenv,
  makeWrapper,
  gawk,
  gnugrep,
  gnused,
  tmux,
}:

stdenv.mkDerivation rec {
  pname = "tmux-slay";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp $src/tmux-slay $out/bin/tmux-slay

    wrapProgram $out/bin/tmux-slay --prefix PATH : ${
      lib.makeBinPath [
        gawk
        gnugrep
        gnused
        tmux
      ]
    }
  '';

  meta = with lib; {
    description = "TMUX script to run commands in a background session. Similar to abduco/dtach.";
    homepage = "https://github.com/pschmitt/tmux-slay";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "tmux-slay";
    platforms = platforms.all;
  };
}
