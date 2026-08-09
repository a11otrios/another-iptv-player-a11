enum PlayerAspectRatioMode {
  original,
  ratio16x9,
  ratio4x3,
  ratio21x9,
  stretch,
  zoom;

  String get label {
    return switch (this) {
      PlayerAspectRatioMode.original => 'Original',
      PlayerAspectRatioMode.ratio16x9 => '16:9',
      PlayerAspectRatioMode.ratio4x3 => '4:3',
      PlayerAspectRatioMode.ratio21x9 => '21:9',
      PlayerAspectRatioMode.stretch => 'Stretch',
      PlayerAspectRatioMode.zoom => 'Zoom',
    };
  }

  double? get ratio {
    return switch (this) {
      PlayerAspectRatioMode.ratio16x9 => 16 / 9,
      PlayerAspectRatioMode.ratio4x3 => 4 / 3,
      PlayerAspectRatioMode.ratio21x9 => 21 / 9,
      PlayerAspectRatioMode.original ||
      PlayerAspectRatioMode.stretch ||
      PlayerAspectRatioMode.zoom => null,
    };
  }
}
