#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  bool Create(const std::wstring& title, const Point& origin, const Size& size);
  bool Show();
  void Destroy();

  void SetQuitOnClose(bool quit_on_close);
  void SetChildContent(HWND content);

  HWND GetHandle();

 protected:
  virtual bool OnCreate() = 0;
  virtual void OnDestroy() = 0;
  virtual LRESULT MessageHandler(HWND window, UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  RECT GetClientArea();

 private:
  struct WNDCLASS {
    const wchar_t* lpszClassName;
  };

  WNDCLASS RegisterWindowClass(const std::wstring& title);
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;
  bool window_class_registered_ = false;
  std::wstring window_class_name_;
  HWND window_handle_ = nullptr;
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
