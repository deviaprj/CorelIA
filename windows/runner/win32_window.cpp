#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"

namespace {

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

constexpr int kDefaultWindowWidth = 1280;
constexpr int kDefaultWindowHeight = 800;

LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

}  // namespace

void EnableFullDpiSupportIfAvailable() {
  HMODULE user32_module = LoadLibraryA("user32.dll");
  if (!user32_module) {
    return;
  }
  using EnableNonClientDpiScalingPtr = BOOL __stdcall (HWND hwnd);
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScalingPtr*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
    FreeLibrary(user32_module);
  }
}

Win32Window::Win32Window() {}

Win32Window::~Win32Window() {
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  WNDCLASS window_class = RegisterWindowClass(title);
  if (window_class.lpszClassName == nullptr) {
    return false;
  }

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class.lpszClassName, title.c_str(),
      WS_OVERLAPPEDWINDOW | WS_VISIBLE,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);
  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(GetHandle(), SW_SHOWNORMAL);
}

void Win32Window::Destroy() {
  OnDestroy();
  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (window_class_registered_) {
    UnregisterClass(window_class_name_.c_str(), nullptr);
    window_class_registered_ = false;
  }
}

Win32Window::WNDCLASS Win32Window::RegisterWindowClass(const std::wstring& title) {
  if (window_class_registered_) {
    return {window_class_name_.c_str()};
  }

  window_class_name_ = kWindowClassName;
  window_class_name_ += std::to_wstring(reinterpret_cast<uintptr_t>(this));

  WNDCLASS wc = {};
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.lpszClassName = window_class_name_.c_str();
  wc.style = CS_HREDRAW | CS_VREDRAW;
  wc.cbClsExtra = 0;
  wc.cbWndExtra = 0;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.hIcon = LoadIcon(wc.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
  wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
  wc.lpszMenuName = nullptr;
  wc.lpfnWndProc = WndProc;
  RegisterClass(&wc);
  window_class_registered_ = true;
  return wc;
}

LRESULT Win32Window::MessageHandler(HWND hwnd, UINT message,
                                    WPARAM wparam, LPARAM lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;
    case WM_DPICHANGED: {
      RECT* new_rect = reinterpret_cast<RECT*>(lparam);
      LONG new_width = new_rect->right - new_rect->left;
      LONG new_height = new_rect->bottom - new_rect->top;
      SetWindowPos(hwnd, nullptr, new_rect->left, new_rect->top, new_width,
                   new_height, SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        SetWindowPos(child_content_, nullptr, rect.left, rect.top,
                     rect.right - rect.left, rect.bottom - rect.top,
                     SWP_NOZORDER);
      }
      return 0;
    }
    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;
    case WM_GETMINMAXINFO: {
      MINMAXINFO* info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize.x = 800;
      info->ptMinTrackSize.y = 600;
      return 0;
    }
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

void Win32Window::UpdateTheme(HWND const window) {
  BOOL use_dark_mode = TRUE;
  DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                        &use_dark_mode, sizeof(use_dark_mode));
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(child_content_, window_handle_);
  RECT frame = GetClientArea();
  SetWindowPos(child_content_, nullptr, frame.left, frame.top,
               frame.right - frame.left, frame.bottom - frame.top,
               SWP_NOZORDER);
  SetFocus(child_content_);
}

namespace {

LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto cs = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(hwnd, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
  }
  auto that = reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (that) {
    return that->MessageHandler(hwnd, message, wparam, lparam);
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

}  // namespace
