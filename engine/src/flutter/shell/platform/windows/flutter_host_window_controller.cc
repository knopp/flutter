// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/shell/platform/windows/flutter_host_window_controller.h"

#include <dwmapi.h>
#include <optional>
#include <vector>

#include "embedder.h"
#include "flutter/shell/platform/common/windowing.h"
#include "flutter/shell/platform/windows/flutter_windows_engine.h"
#include "flutter/shell/platform/windows/flutter_windows_view_controller.h"
#include "fml/logging.h"
#include "shell/platform/windows/client_wrapper/include/flutter/flutter_view.h"
#include "shell/platform/windows/flutter_host_window.h"
#include "shell/platform/windows/flutter_windows_view.h"

namespace flutter {

struct WindowingInitRequest {
  void (*on_message)(WindowsMessage*);
};

struct WindowCreationRequest {
  double width;
  double height;
  double min_width;
  double min_height;
  double max_width;
  double max_height;
};
}  // namespace flutter

extern "C" {

FLUTTER_EXPORT
void flutter_windowing_initialize(
    int64_t engine_id,
    const flutter::WindowingInitRequest* request) {
  flutter::FlutterWindowsEngine* engine =
      flutter::FlutterWindowsEngine::GetEngineForId(engine_id);
  engine->get_host_window_controller()->Initialize(request);
}

FLUTTER_EXPORT
int64_t flutter_create_regular_window(
    int64_t engine_id,
    const flutter::WindowCreationRequest* request) {
  flutter::FlutterWindowsEngine* engine =
      flutter::FlutterWindowsEngine::GetEngineForId(engine_id);
  return engine->get_host_window_controller()->CreateWindow_(request);
}

FLUTTER_EXPORT
HWND flutter_get_window_handle(int64_t engine_id, FlutterViewId view_id) {
  flutter::FlutterWindowsEngine* engine =
      flutter::FlutterWindowsEngine::GetEngineForId(engine_id);
  flutter::FlutterWindowsView* view = engine->view(view_id);
  if (view == nullptr) {
    return nullptr;
  } else {
    return GetAncestor(view->GetWindowHandle(), GA_ROOT);
  }
}

struct Size {
  double width;
  double height;
};

FLUTTER_EXPORT
void flutter_get_window_size(HWND hwnd, Size* size) {
  RECT rect;
  GetClientRect(hwnd, &rect);
  double const dpr = FlutterDesktopGetDpiForHWND(hwnd) /
                     static_cast<double>(USER_DEFAULT_SCREEN_DPI);
  double const width = rect.right / dpr;
  double const height = rect.bottom / dpr;
  size->width = width;
  size->height = height;
}

FLUTTER_EXPORT
int64_t flutter_get_window_state(HWND hwnd) {
  if (IsIconic(hwnd)) {
    return static_cast<int64_t>(flutter::WindowState::kMinimized);
  } else if (IsZoomed(hwnd)) {
    return static_cast<int64_t>(flutter::WindowState::kMaximized);
  } else {
    return static_cast<int64_t>(flutter::WindowState::kRestored);
  }
}

FLUTTER_EXPORT
void flutter_set_window_state(HWND hwnd, int64_t state) {
  switch (static_cast<flutter::WindowState>(state)) {
    case flutter::WindowState::kRestored:
      ShowWindow(hwnd, SW_RESTORE);
      break;
    case flutter::WindowState::kMaximized:
      ShowWindow(hwnd, SW_MAXIMIZE);
      break;
    case flutter::WindowState::kMinimized:
      ShowWindow(hwnd, SW_MINIMIZE);
      break;
  }
}

FLUTTER_EXPORT void flutter_set_window_size(HWND hwnd,
                                            double width,
                                            double height) {
  flutter::FlutterHostWindow* window =
      flutter::FlutterHostWindow::GetThisFromHandle(hwnd);
  if (window) {
    window->SetClientSize(flutter::Size(width, height));
  }
}

}  // extern "C"

namespace flutter {

FlutterHostWindowController::FlutterHostWindowController(
    FlutterWindowsEngine* engine)
    : engine_(engine) {}

void FlutterHostWindowController::Initialize(
    const WindowingInitRequest* request) {
  on_message_ = request->on_message;
  isolate_ = Isolate();

  for (WindowsMessage& message : pending_messages_) {
    IsolateScope scope(*isolate_);
    on_message_(&message);
  }
  pending_messages_.clear();
}

FlutterViewId FlutterHostWindowController::CreateWindow_(
    const WindowCreationRequest* request) {
  WindowCreationSettings settings;
  settings.size = Size(request->width, request->height);
  settings.min_size = Size(request->min_width, request->min_height);
  if (request->max_width != 0 && request->max_height != 0) {
    settings.max_size = Size(request->max_width, request->max_height);
  }
  auto window = std::make_unique<FlutterHostWindow>(this, settings);

  if (!window->GetWindowHandle()) {
    FML_LOG(ERROR) << "Failed to create host window";
    return 0;
  }
  FlutterViewId const view_id = window->view_controller_->view()->view_id();
  WindowState const state = window->state_;
  active_windows_[window->GetWindowHandle()] = std::move(window);
  return view_id;
}

void FlutterHostWindowController::OnEngineShutdown() {
  // Don't send any more messages to isolate.
  on_message_ = nullptr;
  std::vector<HWND> active_handles;
  active_handles.reserve(active_windows_.size());
  for (auto& [hwnd, window] : active_windows_) {
    active_handles.push_back(hwnd);
  }
  for (auto hwnd : active_handles) {
    // This will destroy the window, which will in turn remove the
    // FlutterHostWindow from map when handling WM_NCDESTROY inside
    // HandleMessage.
    DestroyWindow(hwnd);
  }
}

std::optional<LRESULT> FlutterHostWindowController::HandleMessage(
    HWND hwnd,
    UINT message,
    WPARAM wparam,
    LPARAM lparam) {
  if (message == WM_NCDESTROY) {
    active_windows_.erase(hwnd);
  }

  FlutterWindowsView* view = engine_->GetViewFromTopLevelWindow(hwnd);
  if (!view) {
    FML_LOG(WARNING) << "Received message for unknown view";
    return std::nullopt;
  }

  WindowsMessage message_struct = {.view_id = view->view_id(),
                                   .hwnd = hwnd,
                                   .message = message,
                                   .wParam = wparam,
                                   .lParam = lparam,
                                   .result = 0,
                                   .handled = false};

  // Not initialized yet.
  if (!isolate_) {
    pending_messages_.push_back(message_struct);
    return std::nullopt;
  }

  IsolateScope scope(*isolate_);
  on_message_(&message_struct);
  if (message_struct.handled) {
    return message_struct.result;
  } else {
    return std::nullopt;
  }
}

FlutterWindowsEngine* FlutterHostWindowController::engine() const {
  return engine_;
}

}  // namespace flutter
