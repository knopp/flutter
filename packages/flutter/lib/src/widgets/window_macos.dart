import 'dart:ffi' hide Size;
import 'dart:ui' show FlutterView;

import 'package:ffi/ffi.dart' as ffi;
import 'package:flutter/material.dart';
import 'package:flutter/src/foundation/binding.dart';
import 'package:flutter/src/widgets/window_positioning.dart';

class WindowingOwnerMacOS extends WindowingOwner {
  @override
  RegularWindowController createRegularWindowController({
    required Size size,
    required RegularWindowControllerDelegate delegate,
    BoxConstraints? sizeConstraints,
  }) {
    final RegularWindowControllerMacOS res = RegularWindowControllerMacOS(
      owner: this,
      delegate: delegate,
      size: size,
      sizeConstraints: sizeConstraints,
    );
    _activeControllers.add(res);
    return res;
  }

  @override
  bool hasTopLevelWindows() {
    return _activeControllers.isNotEmpty;
  }

  final List<WindowController> _activeControllers = <WindowController>[];

  @override
  PopupWindowController createPopupWindowController({
    BoxConstraints? sizeConstraints,
    Rect? anchorRect,
    required WindowPositioner position,
    required FlutterView parent,
    required Size size,
  }) {
    return PopupWindowControllerMacOS(
      parent: parent,
      size: size,
      anchorRect: anchorRect,
      position: position,
      sizeConstraints: sizeConstraints,
    );
  }
}

class PopupWindowControllerMacOS extends PopupWindowController {
  PopupWindowControllerMacOS({
    required FlutterView parent,
    required Size size,
    Rect? anchorRect,
    required WindowPositioner position,
    BoxConstraints? sizeConstraints,
  }) : super.empty() {
    final Pointer<Void> parentWindow = _getWindowHandle(
      PlatformDispatcher.instance.engineId!,
      parent.viewId,
    );
    final Pointer<_WindowCreationRequest> request =
        ffi.calloc<_WindowCreationRequest>()
          ..ref.width = size.width
          ..ref.height = size.height
          ..ref.minWidth = sizeConstraints?.minWidth ?? 0
          ..ref.minHeight = sizeConstraints?.minHeight ?? 0
          ..ref.maxWidth = sizeConstraints?.maxWidth ?? 0
          ..ref.maxHeight = sizeConstraints?.maxHeight ?? 0;
    final int viewId = _createWindow(PlatformDispatcher.instance.engineId!, parentWindow, request);
    ffi.calloc.free(request);
    final FlutterView flutterView = WidgetsBinding.instance.platformDispatcher.views.firstWhere(
      (FlutterView view) => view.viewId == viewId,
    );
    setView(flutterView);
    // This calculates absolute position using the [WindowPositioner]. On Linux it would instead convert
    // the positioner xdg_positioner and pass it to the window manager.
    _positionWindow(parentWindow, position, anchorRect);
  }

  void _positionWindow(Pointer<Void> parentWindow, WindowPositioner positioner, Rect? anchorRect) {
    final Rect actualAnchorRect = anchorRect ?? Offset.zero & size;
    final Rect position = positioner.placeWindow(
      childSize: size,
      anchorRect: actualAnchorRect,
      parentRect: Rect.zero,
      outputRect: _getDesktopBounds(parentWindow),
    );
    _setWindowPosition(getWindowHandle(), position);
  }

  void _setWindowPosition(Pointer<Void> windowHandle, Rect position) {
    // TODO: Implement FFI call to set window position.
  }

  Rect _getDesktopBounds(Pointer<Void> parentWindow) {
    // TODO: Implement FFI call to get usable desktop area for parent window screen.
    return Rect.zero;
  }

  Pointer<Void> getWindowHandle() {
    return _getWindowHandle(PlatformDispatcher.instance.engineId!, rootView.viewId);
  }

  @override
  void destroy() {
    if (_destroyed) {
      return;
    }
    _destroyed = true;
    _destroyWindow(PlatformDispatcher.instance.engineId!, getWindowHandle());
  }

  @override
  Size get size {
    final Pointer<_Size> size = ffi.calloc<_Size>();
    _getWindowSize(getWindowHandle(), size);
    final Size result = Size(size.ref.width, size.ref.height);
    ffi.calloc.free(size);
    return result;
  }

  @override
  WindowArchetype get type => WindowArchetype.popup;

  bool _destroyed = false;

  @Native<Int64 Function(Int64, Pointer<Void>, Pointer<_WindowCreationRequest>)>(
    symbol: 'flutter_create_popup_window',
  )
  external static int _createWindow(
    int engineId,
    Pointer<Void> parentHandle,
    Pointer<_WindowCreationRequest> request,
  );
}

class RegularWindowControllerMacOS extends RegularWindowController {
  RegularWindowControllerMacOS({
    required WindowingOwnerMacOS owner,
    required RegularWindowControllerDelegate delegate,
    BoxConstraints? sizeConstraints,
    required Size size,
    String? title,
  }) : _owner = owner,
       _delegate = delegate,
       super.empty() {
    _onClose = NativeCallable<Void Function()>.isolateLocal(_handleOnClose);
    _onResize = NativeCallable<Void Function()>.isolateLocal(_handleOnResize);
    final Pointer<_WindowCreationRequest> request =
        ffi.calloc<_WindowCreationRequest>()
          ..ref.width = size.width
          ..ref.height = size.height
          ..ref.minWidth = sizeConstraints?.minWidth ?? 0
          ..ref.minHeight = sizeConstraints?.minHeight ?? 0
          ..ref.maxWidth = sizeConstraints?.maxWidth ?? 0
          ..ref.maxHeight = sizeConstraints?.maxHeight ?? 0
          ..ref.onClose = _onClose.nativeFunction
          ..ref.onSizeChange = _onResize.nativeFunction;

    final int viewId = _createWindow(PlatformDispatcher.instance.engineId!, request);
    ffi.calloc.free(request);
    final FlutterView flutterView = WidgetsBinding.instance.platformDispatcher.views.firstWhere(
      (FlutterView view) => view.viewId == viewId,
    );
    setView(flutterView);
    if (title != null) {
      setTitle(title);
    }
  }

  Pointer<Void> getWindowHandle() {
    return _getWindowHandle(PlatformDispatcher.instance.engineId!, rootView.viewId);
  }

  bool _destroyed = false;

  @override
  void destroy() {
    if (_destroyed) {
      return;
    }
    _destroyed = true;
    _owner._activeControllers.remove(this);
    _destroyWindow(PlatformDispatcher.instance.engineId!, getWindowHandle());
    _delegate.onWindowDestroyed();
    _onClose.close();
    _onResize.close();
  }

  void _handleOnClose() {
    _delegate.onWindowCloseRequested(this);
  }

  void _handleOnResize() {
    notifyListeners();
  }

  void setSize(Size size) {
    _setWindowSize(getWindowHandle(), size.width, size.height);
  }

  void setTitle(String title) {
    final Pointer<ffi.Utf8> titlePointer = title.toNativeUtf8();
    _setWindowTitle(getWindowHandle(), titlePointer);
    ffi.calloc.free(titlePointer);
  }

  @override
  void modify({Size? size, String? title, WindowState? state}) {
    if (size != null) {
      setSize(size);
    }
    if (title != null) {
      setTitle(title);
    }
    if (state != null) {
      setState(state);
    }
  }

  final WindowingOwnerMacOS _owner;
  final RegularWindowControllerDelegate _delegate;
  late final NativeCallable<Void Function()> _onClose;
  late final NativeCallable<Void Function()> _onResize;

  @override
  Size get size {
    final Pointer<_Size> size = ffi.calloc<_Size>();
    _getWindowSize(getWindowHandle(), size);
    final Size result = Size(size.ref.width, size.ref.height);
    ffi.calloc.free(size);
    return result;
  }

  @override
  WindowState get state => WindowState.values[_getWindowState(getWindowHandle())];

  void setState(WindowState state) {
    _setWindowState(getWindowHandle(), state.index);
  }

  @Native<Int64 Function(Int64, Pointer<_WindowCreationRequest>)>(
    symbol: 'flutter_create_regular_window',
  )
  external static int _createWindow(int engineId, Pointer<_WindowCreationRequest> request);
}

@Native<Pointer<Void> Function(Int64, Int64)>(symbol: 'flutter_get_window_handle')
external Pointer<Void> _getWindowHandle(int engineId, int viewId);

@Native<Void Function(Int64, Pointer<Void>)>(symbol: 'flutter_destroy_window')
external void _destroyWindow(int engineId, Pointer<Void> handle);

@Native<Void Function(Pointer<Void>, Pointer<_Size>)>(symbol: 'flutter_get_window_size')
external void _getWindowSize(Pointer<Void> windowHandle, Pointer<_Size> size);

@Native<Void Function(Pointer<Void>, Double, Double)>(symbol: 'flutter_set_window_size')
external void _setWindowSize(Pointer<Void> windowHandle, double width, double height);

@Native<Void Function(Pointer<Void>, Pointer<ffi.Utf8>)>(symbol: 'flutter_set_window_title')
external void _setWindowTitle(Pointer<Void> windowHandle, Pointer<ffi.Utf8> title);

@Native<Int64 Function(Pointer<Void>)>(symbol: 'flutter_get_window_state')
external int _getWindowState(Pointer<Void> windowHandle);

@Native<Void Function(Pointer<Void>, Int64)>(symbol: 'flutter_set_window_state')
external void _setWindowState(Pointer<Void> windowHandle, int state);

final class _WindowCreationRequest extends Struct {
  @Double()
  external double width;

  @Double()
  external double height;

  @Double()
  external double minWidth;

  @Double()
  external double minHeight;

  @Double()
  external double maxWidth;

  @Double()
  external double maxHeight;

  external Pointer<NativeFunction<Void Function()>> onClose;
  external Pointer<NativeFunction<Void Function()>> onSizeChange;
}

final class _Size extends Struct {
  @Double()
  external double width;

  @Double()
  external double height;
}
