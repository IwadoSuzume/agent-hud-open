// WinHTTP, the Windows HTTP client the port sends provider requests with: it follows the system proxy settings, as
// URLSession does on macOS (docs/windows-port/PORTING_PLAN.md). Built on Windows only.
#include <windows.h>
#include <winhttp.h>
