# TaskFlow — ứng dụng quản lý công việc cá nhân

Đồ án nhóm 2 thành viên. Ứng dụng di động dùng **Flutter/Dart**, lưu cục bộ bằng **SQLite**; REST API dùng **ASP.NET Core 10** và dữ liệu máy chủ dùng **SQL Server**. Tài khoản đăng ký theo chế độ cá nhân hoặc tạo nhóm; trưởng nhóm chia sẻ mã tham gia và giao việc cho thành viên. Mỗi việc có hạn, chu kỳ nhắc lặp và thời điểm dừng; hoàn thành việc sẽ hủy nhắc trên thiết bị.

## Ánh xạ đề bài mẫu sang đề tài

| Nhóm chức năng mẫu | Chức năng tương đương trong TaskFlow |
|---|---|
| Đăng ký, đăng nhập, đổi mật khẩu, member, role, logout, phân quyền | Tài khoản thành viên, quản trị viên; xác thực, quản lý tài khoản và vai trò |
| Danh mục, kiểm tra trước khi xóa | Danh mục công việc; chặn xóa khi đang được công việc sử dụng |
| Sản phẩm, ảnh, phân trang, tìm kiếm, chi tiết | Công việc, tệp đính kèm, phân trang, lọc/tìm kiếm và chi tiết |
| Trang chủ, sản phẩm mới, theo danh mục, liên quan | Tổng quan task mới, lọc theo danh mục, tìm kiếm và chi tiết task |
| Giỏ hàng, cập nhật số lượng, checkout, đơn hàng | Kế hoạch công việc: chọn nhiều task, xếp giờ, thêm/gỡ task và xác nhận kế hoạch |
| Quản lý đơn hàng, trạng thái, lọc ngày | Quản lý việc của nhóm, cập nhật trạng thái và lọc theo hạn |
| Thanh toán | Không phát sinh nghiệp vụ thanh toán; thay bằng xác nhận kế hoạch và theo dõi tiến độ |

Chức năng đã tích hợp gồm nhắc việc lặp, đăng nhập/liên kết Google, quên mật khẩu, upload tệp đính kèm, quản lý nhóm và phân quyền. Quên mật khẩu gửi token qua SMTP; trong Development khi chưa cấu hình SMTP, API trả token kiểm thử trong phản hồi.

Tài liệu hỗ trợ vấn đáp: [câu hỏi dự đoán và bài thực hành](docs/ON_TAP_VAN_DAP.md); [giải thích cơ chế, kiến trúc, database và API](docs/GIAI_THICH_CO_CHE_TASKFLOW.md).

## Cấu trúc

- `mobile/`: Flutter app, đăng nhập/đăng ký API, SQLite `tasks` và `sync_queue`.
- `server/TaskFlow.Api/`: ASP.NET Core API, Identity/role, SQL Server, CRUD công việc/danh mục/member, tệp đính kèm và kế hoạch.
- `TaskFlow.sln`: solution .NET.
- `docs/`: tài liệu ôn vấn đáp và giải thích cơ chế, kiến trúc, ERD, quyền và API.

## Chạy ứng dụng Flutter

Cài Flutter stable và Android SDK, sau đó chạy từ thư mục dự án:

```powershell
cd mobile
flutter pub get
# Điện thoại Android thật qua USB:
adb reverse tcp:5000 tcp:5000
flutter run --dart-define=TASKFLOW_API_URL=http://127.0.0.1:5000/api
# Android Emulator: dùng http://10.0.2.2:5000/api trong TASKFLOW_API_URL
```

## Chạy API

Cài .NET 10 SDK và SQL Server Express. Ở Development, API tự tạo/nâng schema và dữ liệu demo khi khởi chạy. Với điện thoại Android kết nối USB, chạy API trên cổng 5000:

```powershell
$env:ASPNETCORE_ENVIRONMENT = "Development"
dotnet user-secrets set "Jwt:Key" "<random-secret-at-least-32-bytes>" --project server/TaskFlow.Api
dotnet run --project server/TaskFlow.Api --urls http://0.0.0.0:5000
```

Dự án đã có User Secrets ID. Để gửi email quên mật khẩu qua Gmail SMTP, đặt `Smtp:Host=smtp.gmail.com`, `Smtp:Port=587`, `Smtp:EnableSsl=true`, `Smtp:Username=<email>`, `Smtp:From=<email>`, và `Smtp:Password=<Google App Password>` bằng `dotnet user-secrets set`. Không dùng Google OAuth client secret làm SMTP password; không commit secrets.

Điện thoại Android thật dùng `adb reverse tcp:5000 tcp:5000`; app gọi `http://127.0.0.1:5000/api`. Emulator có thể ghi đè bằng `flutter run --dart-define=TASKFLOW_API_URL=http://10.0.2.2:5000/api`.

Schema demo được khởi tạo/nâng cấp trong Development bằng `EnsureCreated` và seeder. JWT signing key cần được đặt bằng .NET User Secrets khi phát triển và biến môi trường/secret manager khi triển khai. API gửi email quên mật khẩu qua SMTP; cấu hình `Smtp:Host`, `Smtp:Port`, `Smtp:Username`, `Smtp:Password`, `Smtp:From` và `Smtp:EnableSsl` bằng User Secrets hoặc biến môi trường. Không đưa SMTP password, JWT key, khóa ký hoặc OAuth client secret lên GitHub. Trước khi triển khai thật, dùng EF Core migrations và tắt/đổi tài khoản demo.

Khi chạy ở Development, API tự tạo database `TaskFlow` và nâng schema hiện có mà không xóa dữ liệu. Hai tài khoản demo: `phat.nguyen` (Nguyễn Đức Phát, Admin và trưởng nhóm), `anh.bui` (Bùi Đức Anh, Member); mật khẩu `TaskFlow@2026`. Nhóm mẫu có mã `TFLOW26A`, 4 danh mục và 6 công việc giao cho hai thành viên. Đổi mật khẩu demo trước khi đưa app ra ngoài.

SQLite tạo file `taskflow.db` trên thiết bị lần đầu khởi chạy và chèn 6 đầu việc demo. Notifications được lập lịch trên thiết bị; Android có thể yêu cầu bật quyền thông báo và các chế độ tiết kiệm pin của máy có thể trì hoãn thông báo nền.

## Chia việc cho 2 thành viên

1. Thành viên A: Flutter UI, SQLite, thông báo cục bộ, đồng bộ và kiểm thử trên thiết bị.
2. Thành viên B: API/SQL Server, Identity/roles, CRUD, migration, triển khai và tài liệu API.
3. Cùng thống nhất DTO, phân quyền, use cases, tích hợp và viết báo cáo/demo.

> Trên máy Windows có đường dẫn dự án chứa dấu tiếng Việt, dùng junction `C:\tfmobile` để chạy Flutter do giới hạn xử lý Unicode của Flutter/Gradle trên Windows.
