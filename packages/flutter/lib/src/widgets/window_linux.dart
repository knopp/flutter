import 'dart:ffi' hide Size;
import 'dart:ui' show FlutterView;

import 'package:ffi/ffi.dart' as ffi;
import 'package:flutter/material.dart';
import 'package:flutter/src/foundation/binding.dart';
import 'package:flutter/src/widgets/window_positioning.dart';

class WindowingOwnerLinux extends WindowingOwner {
  @override
  RegularWindowController createRegularWindowController({
    required Size size,
    required RegularWindowControllerDelegate delegate,
    BoxConstraints? sizeConstraints,
  }) {
    final RegularWindowControllerLinux res = RegularWindowControllerLinux(
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
    return PopupWindowControllerLinux(
      parent: parent,
      size: size,
      anchorRect: anchorRect,
      position: position,
      sizeConstraints: sizeConstraints,
    );
  }
}

class PopupWindowControllerLinux extends PopupWindowController {
  PopupWindowControllerLinux({
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
    final Pointer<_PopupWindowCreationRequest> request =
        ffi.calloc<_PopupWindowCreationRequest>()
          ..ref.width = size.width
          ..ref.height = size.height
          ..ref.minWidth = sizeConstraints?.minWidth ?? 0
          ..ref.minHeight = sizeConstraints?.minHeight ?? 0
          ..ref.maxWidth = sizeConstraints?.maxWidth ?? 0
          ..ref.maxHeight = sizeConstraints?.maxHeight ?? 0;
    // TODO: Set fields for position and anchorRect.
    final int viewId = _createWindow(PlatformDispatcher.instance.engineId!, parentWindow, request);
    ffi.calloc.free(request);
    final FlutterView flutterView = WidgetsBinding.instance.platformDispatcher.views.firstWhere(
      (FlutterView view) => view.viewId == viewId,
    );
    view = flutterView;
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
    _destroyWindow(PlatformDispatcher.instance.engineId!, rootView.viewId);
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

  @Native<Int64 Function(Int64, Pointer<Void>, Pointer<_PopupWindowCreationRequest>)>(
    symbol: 'flutter_create_popup_window',
  )
  external static int _createWindow(
    int engineId,
    Pointer<Void> parentHandle,
    Pointer<_PopupWindowCreationRequest> request,
  );
}

class RegularWindowControllerLinux extends RegularWindowController {
  RegularWindowControllerLinux({
    required WindowingOwnerLinux owner,
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
    view = flutterView;
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
    _destroyWindow(PlatformDispatcher.instance.engineId!, rootView.viewId);
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

  final WindowingOwnerLinux _owner;
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

final class _PopupWindowCreationRequest extends Struct {
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

  // TODO:
  // Add fields for anchorRect and position.
}

@Native<Pointer<Void> Function(Int64, Int64)>(symbol: 'flutter_get_window_handle')
external Pointer<Void> _getWindowHandle(int engineId, int viewId);

@Native<Void Function(Int64, Int64)>(symbol: 'flutter_destroy_window')
external void _destroyWindow(int engineId, int viewId);

@Native<Void Function(Pointer<Void>, Pointer<_Size>)>(symbol: 'flutter_get_window_size')
external void _getWindowSize(Pointer<Void> windowHandle, Pointer<_Size> size);

@Native<Void Function(Pointer<Void>, Double, Double)>(symbol: 'gtk_window_resize')
external void _setWindowSize(Pointer<Void> windowHandle, double width, double height);

@Native<Void Function(Pointer<Void>, Pointer<ffi.Utf8>)>(symbol: 'gtk_window_set_title')
external void _setWindowTitle(Pointer<Void> windowHandle, Pointer<ffi.Utf8> title);

@Native<Int64 Function(Pointer<Void>)>(symbol: 'flutter_get_window_state')
external int _getWindowState(Pointer<Void> windowHandle);

@Native<Void Function(Pointer<Void>, Int64)>(symbol: 'flutter_set_window_state')
external void _setWindowState(Pointer<Void> windowHandle, int state);
