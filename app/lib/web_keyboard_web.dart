import 'dart:js_interop';

@JS('todoPrimeKeyboard')
external void _todoPrimeKeyboard();

/// Call from inside the tap that opens a text field, before the field is
/// built. A no-op when the page's helper is missing (an older index.html).
void primeWebKeyboard() {
  try {
    _todoPrimeKeyboard();
  } catch (_) {}
}
