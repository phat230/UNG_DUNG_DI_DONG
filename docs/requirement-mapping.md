# Đối chiếu yêu cầu môn học với TaskFlow

Đề gốc mô tả ứng dụng bán hàng. TaskFlow là ứng dụng quản lý và nhắc việc nên một số chức năng được quy đổi theo nghiệp vụ tương đương. Bảng này mô tả đúng trạng thái code hiện tại; việc tính điểm quy đổi cần được giảng viên chấp thuận.

## Công nghệ bắt buộc

| Yêu cầu | Triển khai | Trạng thái |
|---|---|---|
| Flutter/Dart | App tại `mobile/` | Đã dùng |
| SQLite trên điện thoại | SQLite lưu và cache công việc; hàng đợi thao tác cục bộ | Đã dùng |
| REST API C# .NET 10 | ASP.NET Core controllers tại `server/TaskFlow.Api/` | Đã dùng |
| SQL Server | EF Core SQL Server lưu tài khoản, nhóm, task, kế hoạch và tệp metadata | Đã dùng |

## Quy đổi chức năng

| Chức năng trong rubric | Tương đương trong TaskFlow | Trạng thái hiện tại |
|---|---|---|
| Đăng ký/đăng nhập/đổi mật khẩu/logout | Tạo tài khoản cá nhân/nhóm; xác thực, đổi mật khẩu, kết thúc phiên | App/API đã có; đổi mật khẩu mở từ biểu tượng chìa khóa trên màn hình chính |
| Member, role, phân quyền | Admin quản lý tài khoản/role/trạng thái; Leader quản lý thành viên nhóm và giao việc | Có UI/API, search, lọc ngày tạo, tạo tài khoản, phân nhóm; endpoint quản trị giới hạn Admin |
| Danh mục CRUD và chặn xóa danh mục đang dùng | Danh mục công việc | Admin UI/API thêm/sửa/xóa; task được gắn CategoryId trong SQLite và SQL Server; bộ lọc danh mục trên màn hình tổng quan |
| Sản phẩm CRUD, upload, phân trang/tìm kiếm | Công việc, mô tả, deadline, mức ưu tiên, trạng thái, tệp đính kèm | Thêm/sửa/xóa, upload/download/xóa tệp; API phân trang/tìm kiếm/lọc; app có tải thêm trang. Xóa task có kế hoạch bị chặn đến khi gỡ khỏi kế hoạch |
| Trang chủ, mới nhất, theo danh mục, tìm kiếm, chi tiết | Tổng quan cá nhân/nhóm, task mới nhất, danh mục, search và chi tiết task | UI dùng sort mới nhất, lọc nhóm/cá nhân/danh mục, phân trang, search, chi tiết task và mở tệp |
| Giỏ hàng: thêm/xem/cập nhật/xóa/checkout | Kế hoạch công việc là danh sách task dự kiến trước khi xác nhận lịch làm | Có tab Kế hoạch, số task trên badge, tạo kế hoạch từ nhiều task, thêm/gỡ task, xếp giờ, xác nhận; kế hoạch đã xác nhận khóa chỉnh sửa |
| Chi tiết/tìm kiếm đơn hàng | Chi tiết kế hoạch và lịch sử nhóm/task | Danh sách kế hoạch hiển thị chi tiết task, trạng thái, thứ tự và thời gian dự kiến; có tìm trong task và lịch sử nhóm |
| Admin quản lý đơn hàng/trạng thái/lọc ngày | Admin theo dõi và cập nhật trạng thái task | Có search, lọc khoảng hạn, lọc trạng thái, tải thêm trang và thao tác đổi trạng thái |
| VNPay/VietQR | Thanh toán không phát sinh trong nghiệp vụ nhắc việc | Không triển khai; giải trình bằng xác nhận kế hoạch và theo dõi tiến độ, cần giảng viên đồng ý quy đổi |

## Điểm cộng và điều kiện ngoài repo

| Điểm cộng | Trạng thái / điều kiện |
|---|---|
| Xác minh email đăng ký | Chưa triển khai |
| Quên mật khẩu | Có form/API token ASP.NET Identity. Development chưa có SMTP thì trả mã thử nghiệm; production cần cấu hình SMTP bằng secret ngoài Git |
| Đăng nhập Google | App/API có luồng xác minh ID token. Web Client ID cấu hình Development; phải tạo Android OAuth client với package `vn.edu.taskflow.taskflow_mobile` và SHA‑1 debug/release. File OAuth Installed/Desktop không thay thế Android client |
| Facebook/Zalo | Chưa triển khai; là điểm cộng riêng |
| Ảnh danh mục/ảnh đại diện task, task liên quan | Ảnh dùng như tệp đính kèm; chưa có ảnh đại diện danh mục hoặc gợi ý task liên quan |
| Bảo vệ task nằm trong “đơn hàng” trước khi xóa | Task nằm trong kế hoạch không thể xóa; phải gỡ task hoặc xóa kế hoạch trước |

## Việc cần cấu hình trên từng môi trường

- **Máy phát triển:** đặt `Jwt:Key` bằng .NET User Secrets; SMTP chưa đặt thì quên mật khẩu trả token thử nghiệm chỉ trong Development.
- **Email thật:** đặt `Smtp:Host`, `Smtp:Port`, `Smtp:Username`, `Smtp:Password`, `Smtp:From`, `Smtp:EnableSsl` bằng User Secrets hoặc secret manager. Không commit mật khẩu SMTP.
- **Google Android:** tạo Android OAuth client cho package và từng chứng thư ký cần dùng. Bản Play Store cần SHA‑1 app signing lấy từ Play Console.
- **Phát hành app:** triển khai API ở địa chỉ HTTPS công khai, rồi build Flutter với `--dart-define=TASKFLOW_API_URL=https://<api-domain>/api`. `127.0.0.1` và `adb reverse` chỉ dùng khi phát triển.
- **SQL Server production:** bản demo Development tự tạo/nâng schema và seed dữ liệu mẫu; trước khi triển khai thật nên dùng EF Core migrations, không seed tài khoản demo và đặt JWT/SMTP secrets trên server.

## Luồng demo chấm điểm

1. Member đăng ký cá nhân, đổi mật khẩu, tạo task có deadline/nhắc lặp, gắn danh mục, sửa và hoàn thành task.
2. Leader tạo nhóm/lấy mã; member khác nhập mã tham gia; leader giao task, xem hoàn thành, yêu cầu làm lại và xem thông báo.
3. Tạo kế hoạch: chọn nhiều task → xếp giờ → xác nhận → thử xóa task đang nằm trong kế hoạch để minh họa ràng buộc.
4. Admin tìm/lọc tài khoản, lọc ngày tạo, tạo account, đổi role, khóa/mở account; lọc task theo hạn/trạng thái và đổi trạng thái.
5. Tắt tạm API để minh họa SQLite cache và hàng đợi đồng bộ cục bộ.
6. Chỉ demo email/Google trực tiếp khi đã cấu hình SMTP và Android OAuth; nếu không, nói rõ môi trường Development dùng token thử nghiệm.

## API chính

- Auth: `POST /api/auth/register`, `/login`, `/change-password`, `/forgot-password`, `/reset-password`, `/google/login`, `/google/link`.
- Categories: `GET/POST/PUT/DELETE /api/categories`.
- Tasks: `GET/POST /api/tasks`, `GET/PUT/DELETE /api/tasks/{id}`, `PATCH /api/tasks/{id}/status`, upload/download/delete attachments, notices/rework.
- Plans: `GET/POST /api/plans`, thêm/cập nhật/gỡ task, xác nhận và xóa kế hoạch.
- Groups: `GET/POST /api/groups`, `/join`, leave/history.
- Admin: `/api/admin/members`, `/api/admin/groups`.
