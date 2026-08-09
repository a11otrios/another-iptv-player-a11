bool isLikelyRadioStation(String name, [String? categoryOrGroup]) {
  return [name, categoryOrGroup ?? ''].any((value) {
    final text = value.toLowerCase();
    return RegExp(r'(^|[^a-z0-9])radio([^a-z0-9]|$)').hasMatch(text) ||
        RegExp(r'(^|[^a-z0-9])fm([^a-z0-9]|$)').hasMatch(text) ||
        text.contains('\u03c1\u03b1\u03b4\u03b9\u03bf') ||
        text.contains('\u03c1\u03ac\u03b4\u03b9\u03bf') ||
        text.contains('\u0440\u0430\u0434\u0438\u043e') ||
        text.contains('\u0631\u0627\u062f\u064a\u0648');
  });
}
