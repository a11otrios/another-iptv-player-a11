#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr LONG_PTR kRestorableFrameStyleMask =
    WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU;

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  framed_window_style_ = GetWindowLongPtr(GetHandle(), GWL_STYLE);
  RegisterWindowChannel();
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN:
      if (wparam == VK_F11) {
        RecoverWindowFrame();
        return 0;
      }
      break;

    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::RegisterWindowChannel() {
  window_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "another_iptv_player/window",
      &flutter::StandardMethodCodec::GetInstance());

  window_channel_->SetMethodCallHandler(
      [this](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<
              flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto& method = call.method_name();

        if (method == "setBorderless") {
          const auto* enabled = std::get_if<bool>(call.arguments());
          if (enabled == nullptr) {
            result->Error("invalid_arguments", "Expected a boolean value.");
            return;
          }
          if (!SetBorderless(*enabled)) {
            result->Error("window_error", "Could not update the window frame.");
            return;
          }
          result->Success();
          return;
        }

        if (method == "setAlwaysOnTop") {
          const auto* enabled = std::get_if<bool>(call.arguments());
          if (enabled == nullptr) {
            result->Error("invalid_arguments", "Expected a boolean value.");
            return;
          }
          if (!SetAlwaysOnTop(*enabled)) {
            result->Error(
                "window_error", "Could not update the window z-order.");
            return;
          }
          result->Success();
          return;
        }

        if (method == "startDrag") {
          ReleaseCapture();
          SendMessage(GetHandle(), WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success();
          return;
        }

        if (method == "minimize") {
          ShowWindow(GetHandle(), SW_MINIMIZE);
          result->Success();
          return;
        }

        if (method == "toggleMaximized") {
          result->Success(flutter::EncodableValue(ToggleMaximized()));
          return;
        }

        if (method == "isMaximized") {
          result->Success(
              flutter::EncodableValue(IsZoomed(GetHandle()) != FALSE));
          return;
        }

        if (method == "close") {
          result->Success();
          PostMessage(GetHandle(), WM_CLOSE, 0, 0);
          return;
        }

        result->NotImplemented();
      });
}

bool FlutterWindow::SetBorderless(bool enabled) {
  HWND window = GetHandle();
  if (window == nullptr || framed_window_style_ == 0) {
    return false;
  }

  LONG_PTR style = GetWindowLongPtr(window, GWL_STYLE);
  if (enabled) {
    style &= ~static_cast<LONG_PTR>(WS_CAPTION);
  } else {
    style = (style & ~kRestorableFrameStyleMask) |
            (framed_window_style_ & kRestorableFrameStyleMask);
  }

  SetLastError(0);
  const LONG_PTR previous_style =
      SetWindowLongPtr(window, GWL_STYLE, style);
  if (previous_style == 0 && GetLastError() != 0) {
    return false;
  }

  if (SetWindowPos(
          window, nullptr, 0, 0, 0, 0,
          SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER) ==
      FALSE) {
    return false;
  }

  borderless_enabled_ = enabled;
  ResizeChildContent();
  FocusChildContent();
  return true;
}

bool FlutterWindow::SetAlwaysOnTop(bool enabled) {
  HWND window = GetHandle();
  if (window == nullptr) {
    return false;
  }

  if (SetWindowPos(window, enabled ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE) == FALSE) {
    return false;
  }

  always_on_top_enabled_ = enabled;
  ResizeChildContent();
  FocusChildContent();
  return true;
}

bool FlutterWindow::ToggleMaximized() {
  HWND window = GetHandle();
  if (window == nullptr) {
    return false;
  }

  const bool should_maximize = IsZoomed(window) == FALSE;
  ShowWindow(window, should_maximize ? SW_MAXIMIZE : SW_RESTORE);
  ResizeChildContent();
  FocusChildContent();
  return should_maximize;
}

bool FlutterWindow::RecoverWindowFrame() {
  bool ok = true;
  if (always_on_top_enabled_) {
    ok = SetAlwaysOnTop(false) && ok;
  }
  if (borderless_enabled_) {
    ok = SetBorderless(false) && ok;
  }
  return ok;
}
