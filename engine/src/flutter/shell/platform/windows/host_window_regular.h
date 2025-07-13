// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SHELL_PLATFORM_WINDOWS_HOST_WINDOW_REGULAR_H_
#define FLUTTER_SHELL_PLATFORM_WINDOWS_HOST_WINDOW_REGULAR_H_

#include "host_window.h"

namespace flutter {
class HostWindowRegular : public HostWindow {
 public:
  HostWindowRegular(WindowManager* window_manager,
                    FlutterWindowsEngine* engine,
                    const WindowSizing& content_size);
};

class HostWindowTooltip : public HostWindow {
 public:
  HostWindowTooltip(WindowManager* window_manager,
                    FlutterWindowsEngine* engine,
                    const WindowSizing& content_size,
                    HWND owner_window,
                    const TooltipWindowCreationRequest& request);

 protected:
  void ViewDidUpdateContents(const Size& size) override;

 private:
  Isolate isolate_;
  TooltipWindowCreationRequest request_;
};
}  // namespace flutter

#endif  // FLUTTER_SHELL_PLATFORM_WINDOWS_HOST_WINDOW_REGULAR_H_
