# TaskFlow mobile

## Đăng nhập và liên kết Google

Ứng dụng hỗ trợ đăng nhập Google và liên kết Google với tài khoản TaskFlow hiện có. Google ID token được API xác minh trước khi tạo phiên hoặc liên kết tài khoản.

Cần cấu hình OAuth trước khi nút Google hoạt động:

1. Trong Google Cloud Console tạo OAuth client loại **Android** với package `vn.edu.taskflow.taskflow_mobile` và SHA-1 debug `94:F6:9E:BA:EB:D3:3A:FB:BF:64:BE:3B:E2:CC:02:9D:55:D9:C4:DE`.
2. Tạo thêm OAuth client loại **Web application**. Dùng client ID Web làm `GOOGLE_SERVER_CLIENT_ID` cho Flutter.
3. Chạy API với biến môi trường `Google__ClientIds` chứa client ID Web và Android, phân tách bằng dấu phẩy. Ví dụ PowerShell:

   ```powershell
   $env:Google__ClientIds = "WEB_CLIENT_ID,ANDROID_CLIENT_ID"
   dotnet run --project server/TaskFlow.Api/TaskFlow.Api.csproj
   ```

4. Build app truyền Web client ID:

   ```powershell
   flutter build apk --debug --dart-define=GOOGLE_SERVER_CLIENT_ID=WEB_CLIENT_ID --dart-define=TASKFLOW_API_URL=http://127.0.0.1:5000/api
   ```

Thiết bị Android cần kết nối cùng API hoặc dùng `adb reverse tcp:5000 tcp:5000` khi API chạy trên máy phát triển. SHA-1 phía trên là debug keystore trên máy hiện tại; bản release cần đăng ký SHA-1 của release keystore riêng.
