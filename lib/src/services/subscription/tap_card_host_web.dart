import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:broker_wallet/src/services/subscription/tap_card_host.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

const String _sdkUrl = 'https://tap-sdks.b-cdn.net/card/1.0.2/index.js';

/// A local stand-in for the SDK, honoured in debug builds only.
const String _debugSdkUrl = String.fromEnvironment('BW_TAP_SDK_URL');

TapCardHost? createTapCardHost() => _WebTapCardHost();

int _nextView = 0;
Future<void>? _sdkLoad;

JSObject get _document => globalContext['document'] as JSObject;

JSObject? _elementById(String id) =>
    _document.callMethod<JSObject?>('getElementById'.toJS, id.toJS);

Future<void> _loadSdk() {
  if (globalContext['CardSDK'] != null) return Future.value();
  return _sdkLoad ??= () {
    final done = Completer<void>();
    final script =
        _document.callMethod<JSObject>('createElement'.toJS, 'script'.toJS);
    script['src'] =
        (kDebugMode && _debugSdkUrl.isNotEmpty ? _debugSdkUrl : _sdkUrl).toJS;
    script['async'] = true.toJS;
    script['onload'] = ((JSAny? _) {
      if (!done.isCompleted) done.complete();
    }).toJS;
    script['onerror'] = ((JSAny? _) {
      _sdkLoad = null;
      if (!done.isCompleted) done.completeError(StateError('tap_sdk_load'));
    }).toJS;
    (_document['head'] as JSObject)
        .callMethod<JSAny?>('appendChild'.toJS, script);
    return done.future.timeout(const Duration(seconds: 20));
  }();
}

JSAny? _member(JSObject sdk, String group, String name, String fallback) {
  final values = sdk[group];
  final value = values is JSObject ? values[name] : null;
  return value ?? fallback.toJS;
}

class _WebTapCardHost implements TapCardHost {
  _WebTapCardHost()
      : _viewType = 'bw-tap-card-${_nextView++}',
        _containerId = 'bw-tap-card-container-$_nextView' {
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final element =
          _document.callMethod<JSObject>('createElement'.toJS, 'div'.toJS);
      element['id'] = _containerId.toJS;
      final style = element['style'] as JSObject;
      style['width'] = '100%'.toJS;
      style['height'] = '100%'.toJS;
      return element;
    });
  }

  final String _viewType;
  final String _containerId;
  JSObject? _rendered;
  Completer<String>? _token;
  bool _disposed = false;

  @override
  Widget view() => HtmlElementView(viewType: _viewType);

  @override
  Future<void> mount(
    TapCardConfig config, {
    required VoidCallback onReady,
    required ValueChanged<bool> onValidity,
    required VoidCallback onFailure,
  }) async {
    await _loadSdk();
    for (var i = 0; i < 100 && _elementById(_containerId) == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (_disposed) return;
    }
    final sdk = globalContext['CardSDK'];
    if (sdk is! JSObject || _elementById(_containerId) == null) {
      throw StateError('tap_sdk_unavailable');
    }
    final options = <String, Object?>{
      'publicKey': config.publicKey,
      'transaction': {'amount': config.amount, 'currency': config.currency},
      'fields': {'cardHolder': true},
      // Saving the card for renewals is decided by the server's charge.
      'addons': {
        'loader': true,
        'saveCard': false,
        'displayPaymentBrands': true
      },
    }.jsify() as JSObject;
    options['interface'] = (<String, Object?>{}.jsify() as JSObject)
      ..['locale'] = _member(sdk, 'Locale', config.arabic ? 'AR' : 'EN',
          config.arabic ? 'ar' : 'en')
      ..['theme'] = _member(sdk, 'Theme', config.dark ? 'DARK' : 'LIGHT',
          config.dark ? 'dark' : 'light')
      ..['edges'] = _member(sdk, 'Edges', 'CURVED', 'curved')
      ..['direction'] = _member(sdk, 'Direction', config.arabic ? 'RTL' : 'LTR',
          config.arabic ? 'rtl' : 'ltr');
    options['onReady'] = (() => onReady()).toJS;
    options['onValidInput'] = ((JSAny? _) => onValidity(true)).toJS;
    options['onInvalidInput'] = ((JSAny? _) => onValidity(false)).toJS;
    options['onError'] = ((JSAny? _) {
      final pending = _token;
      _token = null;
      if (pending != null && !pending.isCompleted) {
        pending.completeError(StateError('tap_tokenize'));
      } else {
        onFailure();
      }
    }).toJS;
    options['onSuccess'] = ((JSAny? data) {
      final pending = _token;
      _token = null;
      if (pending == null || pending.isCompleted) return;
      final id = data is JSObject ? data['id'] : null;
      final text = id.isA<JSString>() ? (id as JSString).toDart : '';
      if (text.startsWith('tok_')) {
        pending.complete(text);
      } else {
        pending.completeError(StateError('tap_token_invalid'));
      }
    }).toJS;
    _rendered = sdk.callMethod<JSObject?>(
      'renderTapCard'.toJS,
      _containerId.toJS,
      options,
    );
  }

  @override
  Future<String> tokenize() {
    final sdk = globalContext['CardSDK'];
    if (sdk is! JSObject)
      return Future.error(StateError('tap_sdk_unavailable'));
    final pending = Completer<String>();
    _token = pending;
    sdk.callMethod<JSAny?>('tokenize'.toJS);
    return pending.future.timeout(const Duration(seconds: 45));
  }

  @override
  void dispose() {
    _disposed = true;
    final rendered = _rendered;
    _rendered = null;
    if (rendered != null && rendered['unmount'].isA<JSFunction>()) {
      try {
        rendered.callMethod<JSAny?>('unmount'.toJS);
      } catch (_) {
        // The component is going away with its element.
      }
    }
  }
}
