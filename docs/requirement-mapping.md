# Đối chiếu yêu cầu Flutter của giảng viên

Nguồn: [Requirement Flutter – CEB](https://ceb.net.vn/flutter/requirement.html). Đề gốc là ví dụ ứng dụng bán hàng. TaskFlow giữ đúng nền tảng bắt buộc và thay nghiệp vụ bán hàng bằng các nghiệp vụ tương đương của quản lý công việc.

| Yêu cầu gốc | Chức năng TaskFlow | Trạng thái hiện tại |
|---|---|---|
| Flutter/Dart + SQLite + REST API .NET 10 + SQL Server | Mobile Flutter, SQLite cục bộ, ASP.NET Core API, SQL Server EF Core | Bộ khung đã chọn đúng công nghệ; API cần .NET 10 để chạy |
| Đăng ký/đăng nhập/đổi mật khẩu/logout | Tài khoản thành viên và phiên đăng nhập | API đăng ký, đăng nhập, đổi mật khẩu; app có form đăng ký/đăng nhập và logout |
| Member, role, phân quyền Admin/Member | Quản lý thành viên và vai trò nhóm | API quản lý member, đổi role, khóa/mở member; admin-only |
| Danh mục, CRUD, kiểm tra liên kết trước khi xóa | Danh mục công việc | API CRUD; trả 409 nếu còn công việc đang tham chiếu |
| Sản phẩm, CRUD, upload ảnh, phân trang/tìm kiếm | Công việc, tệp đính kèm, lọc/tìm kiếm/phân trang | API CRUD công việc và phân trang/tìm kiếm; upload chưa triển khai |
| Trang chủ, mới nhất, theo danh mục, chi tiết, liên quan | Tổng quan việc, việc mới, theo danh mục/dự án, chi tiết | Danh sách API và SQLite đã có; các bộ lọc UI còn cần phát triển |
| Giỏ hàng, số lượng, checkout, đơn hàng | Checklist/đợt công việc và cập nhật trạng thái | Được quy đổi theo nghiệp vụ; chưa có màn hình checklist/đợt việc |
| Quản lý đơn hàng, trạng thái, lọc ngày | Quản lý tiến độ công việc và lọc hạn | API có trạng thái, lọc ngày và tìm kiếm; giao diện admin còn cần phát triển |
| VNPay/VietQR | Không có nghiệp vụ tương ứng hợp lý | Thay bằng nhắc việc, lặp lại, thống kê tiến độ |
| Chức năng cộng điểm | Xác minh email, quên mật khẩu, đăng nhập mạng xã hội, tệp, bình luận, nhắc thông báo | Reminder API đã có; các phần còn lại để mở rộng |

## Vai trò nhóm demo

- Nguyễn Đức Phát (`phat.nguyen`): Admin/nhóm trưởng.
- Bùi Đức Anh (`anh.bui`): Member.
- Mật khẩu demo cục bộ: `TaskFlow@2026`.

## API chính

- `POST /api/auth/register`, `POST /api/auth/login`, `POST /api/auth/change-password`
- `GET/POST/PUT/DELETE /api/categories`
- `GET/POST /api/tasks`, `GET/PUT/DELETE /api/tasks/{id}`
- `GET/POST/DELETE /api/tasks/{taskId}/reminders`
- `GET /api/admin/members`, `PUT /api/admin/members/{id}/role`, `PUT /api/admin/members/{id}/status`
