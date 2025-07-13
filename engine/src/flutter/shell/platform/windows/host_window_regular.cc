// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/shell/platform/windows/host_window_regular.h"

#include "flutter/shell/platform/windows/dpi_utils.h"
#include "flutter/shell/platform/windows/flutter_windows_engine.h"

namespace flutter {
HostWindowRegular::HostWindowRegular(WindowManager* window_manager,
                                     FlutterWindowsEngine* engine,
                                     const WindowSizing& content_size)

    : HostWindow(
          window_manager,
          engine,
          WindowArchetype::kRegular,
          WS_OVERLAPPEDWINDOW,
          0,
          content_size,
          [&]() -> Rect {
            auto const constraints = content_size.GetBoxConstraints();
            std::optional<Size> const window_size = GetWindowSizeForClientSize(
                *engine->windows_proc_table(),
                Size(content_size.preferred_view_width,
                     content_size.preferred_view_height),
                constraints.smallest(), constraints.biggest(),
                WS_OVERLAPPEDWINDOW, 0, nullptr);
            return {{CW_USEDEFAULT, CW_USEDEFAULT},
                    window_size ? *window_size
                                : Size{CW_USEDEFAULT, CW_USEDEFAULT}};
          }(),
          nullptr) {
  // TODO(knopp): What about windows sized to content?
  FML_CHECK(content_size.has_preferred_view_size);
}

HostWindowTooltip::HostWindowTooltip(
    WindowManager* window_manager,
    FlutterWindowsEngine* engine,
    const WindowSizing& content_size,
    HWND owner_window,
    const TooltipWindowCreationRequest& request)

    : HostWindow(
          window_manager,
          engine,
          WindowArchetype::kTooltip,
          WS_POPUP,
          WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
          content_size,
          [&]() -> Rect {
            return {{CW_USEDEFAULT, CW_USEDEFAULT},
                    {CW_USEDEFAULT, CW_USEDEFAULT}};
          }(),
          owner_window),
      request_(request),
      isolate_(Isolate::Current()) {}

void HostWindowTooltip::ViewDidUpdateContents(const Size& size) {
  UINT const dpi = GetDpiForHWND(window_handle_);
  double const scale_factor =
      static_cast<double>(dpi) / USER_DEFAULT_SCREEN_DPI;
  FlutterWindowSize logical_size{size.width() / scale_factor,
                                 size.height() / scale_factor};

  HWND const owner_window_handle = GetWindow(GetWindowHandle(), GW_OWNER);
  RECT parent_rect;
  GetWindowRect(owner_window_handle, &parent_rect);

  HMONITOR parent_monitor =
      MonitorFromWindow(owner_window_handle, MONITOR_DEFAULTTONEAREST);

  // Rect for monitor
  MONITORINFO monitor_info = {.cbSize = sizeof(MONITORINFO)};
  GetMonitorInfo(parent_monitor, &monitor_info);

  RECT work_area = monitor_info.rcWork;
  RECT monitor_rect = monitor_info.rcMonitor;

  // Translate to screen coordinate space.
  FlutterWindowRect output_rect = {
      .left = (work_area.left - monitor_rect.left) / scale_factor,
      .top = (work_area.top - monitor_rect.top) / scale_factor,
      .width = ((work_area.right - work_area.left) - monitor_rect.left) /
               scale_factor,
      .height = ((work_area.bottom - work_area.top) - monitor_rect.top) /
                scale_factor};

  FlutterWindowRect parent_rect2{
      .left = (parent_rect.left - work_area.left) / scale_factor,
      .top = (parent_rect.top - work_area.top) / scale_factor,
      .width = ((parent_rect.right - parent_rect.left) - work_area.left) /
               scale_factor,
      .height = ((parent_rect.bottom - parent_rect.top) - work_area.left) /
                scale_factor};

  IsolateScope scope(isolate_);

  FlutterWindowRect* position =
      request_.on_get_window_position(logical_size, parent_rect2, output_rect);
  if (position != nullptr) {
    RECT converted{
        .left = static_cast<LONG>(position->left * scale_factor +
                                  monitor_rect.left),
        .top =
            static_cast<LONG>(position->top * scale_factor + monitor_rect.top),
        .right = static_cast<LONG>((position->left + position->width) *
                                   scale_factor) +
                 monitor_rect.left,
        .bottom = static_cast<LONG>((position->top + position->height) *
                                    scale_factor) +
                  monitor_rect.top,
    };

    SetWindowPos(GetWindowHandle(), nullptr, converted.left, converted.top,
                 converted.right - converted.left,
                 converted.bottom - converted.top,
                 SWP_NOACTIVATE | SWP_NOZORDER);

    free(position);
  }
}

}  // namespace flutter