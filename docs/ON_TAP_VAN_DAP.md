# Ôn tập vấn đáp và thực hành TaskFlow

Tài liệu này giúp bạn **hiểu, trình bày và sửa được code thật**. Không ai biết chắc thầy sẽ hỏi gì; những phần dưới đây là các dạng thường được hỏi khi đồ án dùng Flutter, API, SQLite, SQL Server và phân quyền.

## Cách xử lý khi thầy giao sửa code

1. Nhắc lại yêu cầu để xác nhận mình hiểu đúng.
2. Nói rõ sẽ lần theo luồng: **màn Flutter → hàm gọi API → controller C# → entity/DbContext → SQL Server**. SQLite local nằm trong `TaskStore`.
3. Tìm tên hàm/route bằng tìm kiếm toàn dự án, không sửa mò.
4. Sửa phần nhỏ nhất, giữ các kiểm tra quyền và dữ liệu.
5. Chạy lại/build, thử thành công và dữ liệu sai/thiếu quyền.
6. Nói lại file đã đổi, request hoặc truy vấn nào chạy và ai được phép dùng.

Nếu chưa nhớ, có thể nói: “Em xin xác định luồng hiện tại trong code trước, sau đó trình bày và sửa ở đúng tầng.” Đừng giả vờ biết hoặc sửa vội. Thầy muốn thấy bạn hiểu cách tìm, giải thích và kiểm tra kết quả.

## Khả năng bài thực hành

| Yêu cầu có thể gặp | Cách làm theo luồng | Chỗ tìm trong repo |
|---|---|---|
| Thêm trường ưu tiên/hạn cho công việc | Thêm input; đưa vào JSON; nhận trong DTO C#; lưu vào entity; trả lại khi đọc. Kiểm tra kiểu ngày và mặc định. | `mobile/lib/main.dart`, `TasksController.cs`, `Models/Entities.cs` |
| Tìm việc theo từ khóa | Gửi `q` trên query string; API lọc `Title`/`Description`; giữ phân trang và tổng số. | `Api.getTaskPage`, `TasksController.List` |
| Lọc theo ngày | Gửi `from`/`to` ISO; giới hạn từ đầu ngày đến trước ngày kế tiếp để gồm cả ngày cuối. | `TasksController.List`, admin dashboard |
| Chặn xóa danh mục đang dùng | Truy vấn task có `CategoryId`; nếu còn trả `409 Conflict`; Flutter giải thích lý do. | `CategoriesController`, `Api.deleteCategory` |
| Chỉ Admin xóa thành viên | Bảo vệ endpoint `[Authorize(Roles = "Admin")]`; kiểm tra Admin cuối/trưởng nhóm; hiện xác nhận trên UI. | `MembersController`, `Api.deleteMember` |
| Giao nhiệm vụ nhóm | Gửi `WorkspaceId` và người nhận; API kiểm tra người gọi là Leader và người nhận còn ở nhóm. | `TaskEditorPage`, `TasksController.Create` |
| Hoàn thành/yêu cầu làm lại | API kiểm tra quyền và trạng thái; đổi status/lock; tạo thông báo cho người được giao. | `TasksController.SetStatus`, `RequestRework` |
| Lập kế hoạch nhiều việc | Tạo `TaskPlan`, thêm các liên kết `TaskPlanItem`, lưu thứ tự và giờ dự kiến. | `WorkPlansPage`, `WorkPlansController` |
| Viết báo cáo SQL | Luyện `WHERE`, `JOIN`, `GROUP BY`, `COUNT`, điều kiện ngày. | SQL Server Management Studio; ví dụ bên dưới |

## Câu hỏi miệng và câu trả lời mẫu

### “Kiến trúc đồ án của em thế nào?”

> “Flutter/Dart là giao diện. App gọi REST API viết bằng ASP.NET Core 10. API xác thực bằng ASP.NET Identity/JWT, kiểm tra quyền và thao tác dữ liệu dùng chung trên SQL Server. SQLite lưu dữ liệu cục bộ trên app điện thoại; thông báo nhắc việc được lên lịch trên thiết bị.”

### “SQLite và SQL Server có trùng nhau không?”

> “Không. SQLite ở thiết bị để lưu local/cache và hỗ trợ hàng đợi đồng bộ. SQL Server là dữ liệu trung tâm dùng chung giữa tài khoản và thiết bị. App không nối thẳng tới SQL Server; nó gọi API để API kiểm tra quyền rồi truy vấn database.”

### “Đăng nhập hoạt động ra sao?”

> “Flutter gửi tên đăng nhập/email và mật khẩu tới `/api/auth/login`. API tìm tài khoản bằng Identity, kiểm tra trạng thái và mật khẩu. Nếu đúng, API tạo JWT; app giữ token và gửi trong header `Authorization: Bearer ...` cho các request cần xác thực.”

### “Phân quyền kiểm tra ở đâu?”

> “Giao diện có thể ẩn nút để dễ dùng, nhưng API mới quyết định quyền thật. Controller dùng `[Authorize]` hoặc `[Authorize(Roles = "Admin")]`; với nhiệm vụ nhóm còn kiểm tra người gọi có phải thành viên hay trưởng nhóm không.”

### “OwnerId, CreatedByUserId, WorkspaceId khác nhau gì?”

> “OwnerId là người chịu trách nhiệm/được giao; CreatedByUserId là người tạo; WorkspaceId là nhóm chứa nhiệm vụ. Việc cá nhân thường không có WorkspaceId. Tách các trường này giúp biết ai làm, ai giao và việc thuộc không gian nào.”

### “Vì sao cần TaskPlanItem?”

> “Một kế hoạch có nhiều công việc và một công việc có thể xuất hiện trong nhiều kế hoạch. TaskPlan lưu thông tin chung; TaskPlanItem là bảng liên kết, lưu task, thứ tự và thời gian dự kiến.”

### “Phân trang hoạt động thế nào?”

> “App gửi `page` và `pageSize`. API lọc trước, đếm `total`, sắp xếp rồi bỏ qua `(page - 1) * pageSize` và lấy `pageSize` dòng. App dựa vào total để biết còn tải tiếp không.”

### “Nhắc lặp mỗi 5 phút đến 10 giờ tối ra sao?”

> “Task lưu thời hạn, chu kỳ nhắc và thời điểm dừng. Flutter đặt lịch notification cục bộ theo các mốc đó. Khi task hoàn thành/xóa, app hủy thông báo tương ứng. Android vẫn có thể trì hoãn do quyền hoặc tiết kiệm pin.”

### “Trưởng nhóm yêu cầu làm lại thì sao?”

> “API xác nhận người gọi là Leader cùng nhóm và task đang Done; sau đó chuyển về Todo, mở khóa và tạo TaskNotice cho thành viên được giao.”

## SQL nên luyện gõ

Các bảng thường dùng theo entity hiện tại: `Tasks`, `AspNetUsers`, `Workspaces`, `WorkspaceMembers`, `TaskPlans`, `TaskPlanItems`. Kiểm tra schema thật trên máy nếu tên đã thay đổi.

### Đếm nhiệm vụ theo trạng thái

```sql
SELECT Status, COUNT(*) AS SoLuong
FROM dbo.Tasks
GROUP BY Status
ORDER BY Status;
```

Mã: `0 Todo`, `1 InProgress`, `2 Done`, `3 Archived`.

### Tìm việc chưa hoàn thành trong tháng

```sql
DECLARE @TuNgay date = '2026-11-01';
DECLARE @DenNgay date = '2026-11-30';

SELECT Id, Title, OwnerId, WorkspaceId, DueAt, Status
FROM dbo.Tasks
WHERE Status <> 2
  AND DueAt >= @TuNgay
  AND DueAt < DATEADD(day, 1, @DenNgay)
ORDER BY DueAt;
```

Điều kiện `< ngày kế tiếp` giữ cả nhiệm vụ có giờ vào ngày cuối.

### Đếm việc mỗi tài khoản đang sở hữu

```sql
SELECT u.UserName, u.DisplayName, COUNT(t.Id) AS SoViec
FROM dbo.AspNetUsers AS u
LEFT JOIN dbo.Tasks AS t ON t.OwnerId = u.Id
GROUP BY u.UserName, u.DisplayName
ORDER BY SoViec DESC;
```

`LEFT JOIN` vẫn hiện tài khoản chưa có việc; `INNER JOIN` sẽ bỏ tài khoản đó.

### Xem nhiệm vụ trong kế hoạch

```sql
DECLARE @PlanId int = 1;
SELECT p.Name, pi.SortOrder, pi.PlannedFor, t.Title, t.Status, t.DueAt
FROM dbo.TaskPlans AS p
JOIN dbo.TaskPlanItems AS pi ON pi.PlanId = p.Id
JOIN dbo.Tasks AS t ON t.Id = pi.TaskId
WHERE p.Id = @PlanId
ORDER BY pi.SortOrder, pi.Id;
```

## Chuẩn bị máy trước buổi vấn đáp

- Kiểm tra SQL Server, connection string, API và app chạy được trước giờ học.
- Điện thoại USB thường cần `adb reverse tcp:5000 tcp:5000`; Android Emulator thường dùng API URL `http://10.0.2.2:5000/api`.
- Tài khoản demo Development: `phat.nguyen` (Admin/trưởng nhóm), `anh.bui` (Member), mật khẩu `TaskFlow@2026`. Chỉ dùng demo local, đổi trước khi phát hành.
- Thử một vòng: đăng nhập → xem/tạo/sửa việc → hoàn thành → xem thông báo → admin tìm/xóa → tạo kế hoạch.
- Biết cách mở log API và đọc mã HTTP. Không đưa JWT key, mật khẩu SMTP hay OAuth secret lên GitHub.

> **Quan trọng về Web:** commit hiện tại dùng `_webTasks` trong bộ nhớ cho phần local trên trình duyệt vì SQLite plugin không chạy như app điện thoại. Tải lại trang có thể làm mất local data. Nếu thầy chấm SQLite, trình diễn trên Android Emulator/điện thoại và nói rõ ranh giới này.

## Nguyên tắc khi sửa trực tiếp

- Dữ liệu máy chủ phải đi qua API; không chỉ thêm nút Flutter.
- Không tin `role`, `userId` hay membership do client tự gửi; API lấy danh tính từ JWT và tự kiểm tra.
- Với xóa, xem dữ liệu liên quan, khóa ngoại và file vật lý.
- Với lọc/phân trang: lọc → đếm → sắp xếp → `Skip/Take`.
- Với ngày giờ, thống nhất UTC khi gửi API và hiển thị theo giờ thiết bị.
- Phân biệt HTTP: `400` dữ liệu sai, `401` chưa xác thực, `403` thiếu quyền, `404` không thấy, `409` xung đột.
- Chỉ khẳng định chức năng nào đã chạy thử được.

## Checklist tự ôn

- [ ] Trình bày được luồng từ nút Flutter tới database.
- [ ] Giải thích JWT, Admin/Member và kiểm tra quyền phía API.
- [ ] Viết được truy vấn có JOIN và truy vấn GROUP BY.
- [ ] Demo được việc cá nhân, nhóm, nhắc việc và kế hoạch.
- [ ] Nói rõ SQLite native, SQL Server backend, khác biệt bản Web và cấu hình SMTP/OAuth.
