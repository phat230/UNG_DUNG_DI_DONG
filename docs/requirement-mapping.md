# Đối chiếu yêu cầu môn học với TaskFlow

Đề gốc là ứng dụng bán hàng. TaskFlow là ứng dụng quản lý và nhắc việc nên các đối tượng được quy đổi theo nghiệp vụ tương đương; không nên tuyên bố có giỏ hàng/thanh toán nếu ứng dụng không thực sự có những chức năng đó. Việc quy đổi điểm cuối cùng cần được giảng viên chấp thuận.

## Nền tảng bắt buộc

| Yêu cầu | Triển khai TaskFlow | Đánh giá |
|---|---|---|
| Flutter/Dart | App Android trong `mobile/` | Đã dùng |
| SQLite trên điện thoại | SQLite lưu task cục bộ và hàng đợi đồng bộ | Đã dùng |
| REST API C# .NET 10 | `server/TaskFlow.Api/`, ASP.NET Core controllers | Đã dùng; cần cài .NET 10 SDK để build/chạy |
| SQL Server | EF Core SQL Server, dữ liệu tài khoản/nhóm/task phía máy chủ | Đã dùng |

## Chức năng bắt buộc và quy đổi nghiệp vụ

| Nhóm yêu cầu gốc | Chức năng tương đương TaskFlow | Hiện trạng theo code | Việc cần làm để trình bày hoàn chỉnh |
|---|---|---|---|
| Đăng ký, đăng nhập, đổi mật khẩu, logout | Tạo tài khoản cá nhân/nhóm, đăng nhập, đổi mật khẩu, thoát | Đăng ký/đăng nhập/logout có giao diện. API đổi mật khẩu có, nhưng app chưa có màn hình/gọi API đổi mật khẩu | Thêm mục “Đổi mật khẩu” trong hồ sơ và nối endpoint `POST /api/auth/change-password` |
| Quản lý member, role, phân quyền | Admin quản lý tài khoản, trạng thái, vai trò; Leader quản lý thành viên nhóm | Có API và UI tìm tài khoản, lọc ngày tạo, tạo tài khoản, đổi Admin/Member, khóa/mở tài khoản, quản lý nhóm. API giới hạn admin/leader | Demo từng quyền bằng tài khoản Admin, Member và Leader; không dùng tài khoản Admin để chứng minh quyền Member |
| Danh mục CRUD, kiểm tra trước khi xóa | Danh mục công việc | API và màn hình admin thêm/sửa/xóa; API chặn xóa khi còn task liên kết | App hiện chưa gắn danh mục vào form tạo task/bộ lọc task; cần nối `CategoryId` xuyên suốt SQLite, API và UI |
| Sản phẩm CRUD, upload, phân trang/tìm kiếm | Công việc, mô tả, hạn, trạng thái, tệp đính kèm | API task có CRUD, tìm kiếm, lọc, phân trang; Flutter thêm/xóa task, tải lên/tải xuống/xóa tệp. API có cập nhật task nhưng app chưa có luồng sửa đầy đủ. App đang lấy trang 1 tối đa 100 task | Bổ sung sửa task trên app và nút tải thêm/trang tiếp theo. Trình bày ảnh như một loại tệp đính kèm, không gọi là quản lý ảnh sản phẩm |
| Trang chủ: mới nhất, theo danh mục, tìm kiếm, chi tiết, liên quan | Tổng quan task cá nhân/nhóm, task mới, theo danh mục, tìm kiếm, chi tiết | Có tổng quan, lọc cá nhân/nhóm/nhóm cũ, tìm kiếm, thống kê hôm nay. API tìm kiếm và lọc ngày/danh mục. Chưa có thứ tự task mới nhất riêng, bộ lọc danh mục trên app, màn hình chi tiết riêng hoặc task liên quan | Nối bộ lọc danh mục; sắp xếp mới nhất; mở trang chi tiết task có hạn, mô tả, người giao/nhận, tệp và lịch sử; task liên quan là điểm cộng |
| Giỏ hàng: thêm, xem, số lượng, cập nhật, xóa, checkout | “Danh sách việc chờ lập kế hoạch” tương đương tập hợp đầu việc trước khi xác nhận lịch/đợt làm | Task list hiện có thêm/xem/xóa và badge thống kê trong tổng quan; không có giỏ/kế hoạch tạm, số lượng hàng hay bước xác nhận checkout riêng. Sửa task trên app cũng chưa có | Để quy đổi chắc hơn, thêm “Kế hoạch công việc”: chọn nhiều task vào kế hoạch, sửa thứ tự/hạn, xem số task, xác nhận kế hoạch và chuyển task sang trạng thái đã lên lịch. Giải thích checkout là xác nhận lịch làm, không phải thanh toán |
| Chi tiết/tìm kiếm đơn hàng | Chi tiết kế hoạch và lịch sử hoàn thành task | Có lịch sử nhóm và tìm kiếm task; chưa có đối tượng kế hoạch/đợt việc và trang chi tiết lịch sử task hoàn chỉnh | Nếu triển khai kế hoạch, thêm trang xem chi tiết/tìm kế hoạch; nếu không, cần xin giảng viên chấp thuận quy đổi sang task history |
| Admin quản lý đơn hàng, trạng thái, lọc ngày | Admin/Leader theo dõi task thành viên và cập nhật trạng thái | API task hỗ trợ trạng thái, tìm kiếm, lọc hạn; admin có màn hình xem task tài khoản. UI admin hiện chưa có đầy đủ bộ lọc trạng thái/ngày và phân trang | Thêm bộ lọc trạng thái, khoảng hạn, nút cập nhật trạng thái và tải thêm; trình diễn leader yêu cầu làm lại task hoàn thành |
| VNPay/VietQR | Không có thanh toán trong ứng dụng nhắc việc | Không triển khai | Giải trình nghiệp vụ không phát sinh thanh toán; thay bằng xác nhận kế hoạch và thống kê tiến độ. Chỉ triển khai thanh toán nếu giảng viên yêu cầu bắt buộc không cho quy đổi |

## Chức năng cộng điểm

| Chức năng cộng điểm | Hiện trạng |
|---|---|
| Xác thực email | Chưa có xác minh email đăng ký |
| Quên mật khẩu | Có UI/API. API dùng token ASP.NET Identity; Development chưa có SMTP thì trả token thử nghiệm, Production cần cấu hình SMTP credentials để gửi email |
| Đăng nhập Google | Có luồng app/API xác minh ID token; để dùng trên thiết bị cần tạo Android OAuth client đúng package/SHA-1. Bản phát hành cần SHA-1 release/Play App Signing và API HTTPS |
| Facebook/Zalo | Chưa triển khai; là điểm cộng riêng, không cần để đạt phần bắt buộc nếu giảng viên đồng ý |
| Hình ảnh danh mục, sản phẩm liên quan | Danh mục có màu/icon; task chấp nhận tệp/ảnh đính kèm. Chưa có ảnh đại diện danh mục hoặc gợi ý task liên quan |
| Kiểm tra task trong kế hoạch trước khi xóa | Chưa có kế hoạch/đơn tương ứng; cần ràng buộc khi thêm đối tượng kế hoạch |

## Thứ tự ưu tiên để hoàn thiện

1. Làm chức năng đổi mật khẩu trong app.
2. Thêm sửa task và gắn danh mục vào form tạo/sửa, SQLite, API, bộ lọc.
3. Hoàn thiện danh sách task: phân trang tải thêm, sắp xếp mới nhất, trang chi tiết và lọc trạng thái/hạn cho Admin.
4. Xây “Kế hoạch công việc” nếu muốn quy đổi giỏ hàng/checkout/đơn hàng chắc chắn hơn; trình bày với giảng viên để xác nhận cách tính điểm tương đương.
5. Cấu hình SMTP thật cho quên mật khẩu và OAuth/HTTPS khi demo trên thiết bị ngoài máy phát triển.
6. Cập nhật báo cáo: sơ đồ use case, ERD, API, phân quyền, dữ liệu demo, ảnh chụp luồng cá nhân/nhóm/Admin, bảng đối chiếu này.

## Luồng demo nên chuẩn bị

- Member: đăng ký cá nhân → tạo task có hạn và nhắc lặp → hoàn thành → xem thông báo.
- Leader: tạo nhóm/lấy mã → thành viên nhập mã tham gia → giao task → yêu cầu làm lại → xem thành viên hoàn thành.
- Admin: tìm/lọc tài khoản → tạo tài khoản/đổi role/khóa tài khoản → quản lý danh mục → xem task của tài khoản.
- Offline/local: mở app khi API tạm mất kết nối, tạo task và giải thích SQLite + hàng đợi đồng bộ.
- Google/quên mật khẩu: chỉ demo sau khi cấu hình OAuth hoặc SMTP; nếu không, giải trình bằng mã thử nghiệm Development.

## API tiêu biểu

- Auth: `POST /api/auth/register`, `POST /api/auth/login`, `POST /api/auth/change-password`, `POST /api/auth/forgot-password`, `POST /api/auth/reset-password`, `POST /api/auth/google/login`.
- Danh mục: `GET/POST/PUT/DELETE /api/categories`.
- Task: `GET/POST /api/tasks`, `GET/PUT/DELETE /api/tasks/{id}`, `PATCH /api/tasks/{id}/status`, upload/download/delete attachments.
- Nhóm: `GET/POST /api/groups`, `POST /api/groups/join`, leave/history.
- Admin: `GET/POST /api/admin/members`, cập nhật role/status; admin group management.
