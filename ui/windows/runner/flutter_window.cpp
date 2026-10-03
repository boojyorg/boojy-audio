#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

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
  RegisterPlugins(flutter_controller_->engine());

  pointer_hold_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "boojy_audio/pointer_hold",
          &flutter::StandardMethodCodec::GetInstance());
  pointer_hold_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "hold") {
          HoldPointer();
          result->Success();
        } else if (call.method_name() == "release") {
          ReleasePointer();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
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
  ReleasePointer();
  pointer_hold_channel_ = nullptr;
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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_INPUT:
      OnRawMouseInput(hwnd, lparam);
      break;
    case WM_ACTIVATEAPP:
      // Never leave the pointer hidden behind another app.
      if (!wparam) {
        ReleasePointer();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::HoldPointer() {
  // Only mid-drag: a hold that started after the button came up would never
  // see the button-up that ends it.
  const bool button_down = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) ||
                           (GetAsyncKeyState(VK_RBUTTON) & 0x8000) ||
                           (GetAsyncKeyState(VK_MBUTTON) & 0x8000);
  if (pointer_held_ || !button_down) {
    return;
  }
  POINT at;
  GetCursorPos(&at);
  // A one-pixel cage keeps the pointer where the drag started; raw input
  // still reports how far the mouse moves.
  RECT cage{at.x, at.y, at.x + 1, at.y + 1};
  ClipCursor(&cage);
  ShowCursor(FALSE);
  RAWINPUTDEVICE mouse{0x01, 0x02, 0, GetHandle()};  // generic desktop mouse
  RegisterRawInputDevices(&mouse, 1, sizeof(mouse));
  pointer_held_ = true;
}

void FlutterWindow::ReleasePointer() {
  if (!pointer_held_) {
    return;
  }
  pointer_held_ = false;
  RAWINPUTDEVICE mouse{0x01, 0x02, RIDEV_REMOVE, nullptr};
  RegisterRawInputDevices(&mouse, 1, sizeof(mouse));
  ClipCursor(nullptr);
  ShowCursor(TRUE);
}

void FlutterWindow::OnRawMouseInput(HWND hwnd, LPARAM lparam) {
  if (!pointer_held_) {
    return;
  }
  RAWINPUT raw;
  UINT size = sizeof(raw);
  if (GetRawInputData(reinterpret_cast<HRAWINPUT>(lparam), RID_INPUT, &raw,
                      &size, sizeof(RAWINPUTHEADER)) == static_cast<UINT>(-1) ||
      raw.header.dwType != RIM_TYPEMOUSE) {
    return;
  }
  const RAWMOUSE& mouse = raw.data.mouse;
  if (mouse.usButtonFlags &
      (RI_MOUSE_LEFT_BUTTON_UP | RI_MOUSE_RIGHT_BUTTON_UP |
       RI_MOUSE_MIDDLE_BUTTON_UP)) {
    ReleasePointer();
    return;
  }
  if ((mouse.usFlags & MOUSE_MOVE_ABSOLUTE) ||
      (mouse.lLastX == 0 && mouse.lLastY == 0)) {
    return;
  }
  // Raw counts are device pixels; Dart works in logical ones.
  const double scale = FlutterDesktopGetDpiForHWND(hwnd) / 96.0;
  pointer_hold_channel_->InvokeMethod(
      "move", std::make_unique<flutter::EncodableValue>(flutter::EncodableList{
                  flutter::EncodableValue(mouse.lLastX / scale),
                  flutter::EncodableValue(mouse.lLastY / scale)}));
}
