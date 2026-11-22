using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.StaticFiles;
using Microsoft.EntityFrameworkCore;
using TaskFlow.Api.Data;
using TaskFlow.Api.Models;
using WorkStatus = TaskFlow.Api.Models.TaskStatus;
namespace TaskFlow.Api.Controllers;

public record SaveTaskRequest(string Title, string Description = "", int? CategoryId = null, DateTime? DueAt = null, int Priority = 1, WorkStatus Status = WorkStatus.Todo, int? WorkspaceId = null, string? AssignedToUserId = null, int? ReminderIntervalMinutes = null, DateTime? ReminderUntil = null);
[ApiController, Route("api/tasks"), Authorize]
public class TasksController(AppDbContext db, IWebHostEnvironment environment) : ControllerBase
{
    string UserId => User.FindFirstValue(ClaimTypes.NameIdentifier)!;

    async Task<List<int>> LedGroupIds() => await db.WorkspaceMembers.Where(m => m.UserId == UserId && m.LeftAt == null && m.Role == "Leader").Select(m => m.WorkspaceId).ToListAsync();
    async Task<List<int>> ActiveGroupIds() => await db.WorkspaceMembers.Where(m => m.UserId == UserId && m.LeftAt == null).Select(m => m.WorkspaceId).ToListAsync();
    async Task<bool> CanManage(TaskItem task) =>
        User.IsInRole("Admin") ||
        task.OwnerId == UserId ||
        task.CreatedByUserId == UserId ||
        (task.WorkspaceId.HasValue && await db.WorkspaceMembers.AnyAsync(m => m.WorkspaceId == task.WorkspaceId && m.UserId == UserId && m.LeftAt == null));

    async Task<bool> CanView(TaskItem task) =>
        User.IsInRole("Admin") ||
        task.OwnerId == UserId ||
        task.CreatedByUserId == UserId ||
        (task.WorkspaceId.HasValue && await db.WorkspaceMembers.AnyAsync(m => m.WorkspaceId == task.WorkspaceId && m.UserId == UserId && m.LeftAt == null));

    [HttpGet]
    public async Task<IActionResult> List([FromQuery] int page = 1, [FromQuery] int pageSize = 20, [FromQuery] string? q = null, [FromQuery] WorkStatus? status = null, [FromQuery] int? categoryId = null, [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null, [FromQuery] string? ownerId = null, [FromQuery] int? workspaceId = null, [FromQuery] bool personalOnly = false, [FromQuery] string? sort = null)
    {
        page = Math.Max(1, page); pageSize = Math.Clamp(pageSize, 1, 100);
        var query = db.Tasks.AsNoTracking().AsQueryable();
        if (!User.IsInRole("Admin"))
        {
            var groupIds = await ActiveGroupIds();
            if (workspaceId.HasValue)
            {
                var wasMember = await db.WorkspaceMembers.AnyAsync(m => m.WorkspaceId == workspaceId && m.UserId == UserId);
                if (!wasMember) return Forbid();
                var isActive = groupIds.Contains(workspaceId.Value);
                query = query.Where(t => t.WorkspaceId == workspaceId && (isActive || t.OwnerId == UserId));
            }
            else if (personalOnly) query = query.Where(t => t.WorkspaceId == null && t.OwnerId == UserId);
            else query = query.Where(t => (t.WorkspaceId == null && t.OwnerId == UserId) || (t.WorkspaceId.HasValue && groupIds.Contains(t.WorkspaceId.Value)));
        }
        else if (!string.IsNullOrWhiteSpace(ownerId)) query = query.Where(t => t.OwnerId == ownerId);
        if (!string.IsNullOrWhiteSpace(q)) query = query.Where(t => t.Title.Contains(q) || t.Description.Contains(q));
        if (status.HasValue) query = query.Where(t => t.Status == status);
        if (categoryId.HasValue) query = query.Where(t => t.CategoryId == categoryId);
        if (from.HasValue) query = query.Where(t => t.DueAt >= from);
        if (to.HasValue) query = query.Where(t => t.DueAt < to.Value.AddDays(1));
        var total = await query.CountAsync();
        var items = string.Equals(sort, "newest", StringComparison.OrdinalIgnoreCase)
            ? await query.OrderByDescending(t => t.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync()
            : await query.OrderBy(t => t.Status).ThenBy(t => t.DueAt).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync();
        return Ok(new { items, total, page, pageSize });
    }

    [HttpGet("{id:int}")]
    public async Task<IActionResult> Get(int id)
    { var task = await db.Tasks.AsNoTracking().FirstOrDefaultAsync(t => t.Id == id); return task is null || !await CanView(task) ? NotFound() : Ok(task); }

    [HttpPost]
    public async Task<IActionResult> Create(SaveTaskRequest input)
    {
        if (string.IsNullOrWhiteSpace(input.Title)) return BadRequest(new { message = "Tên công việc không được để trống." });
        if (input.ReminderIntervalMinutes is <= 0 or > 1440) return BadRequest(new { message = "Chu kỳ nhắc phải từ 1 đến 1440 phút." });
        var ownerId = UserId;
        if (input.WorkspaceId.HasValue)
        {
            var leader = await db.WorkspaceMembers.AnyAsync(m => m.WorkspaceId == input.WorkspaceId && m.UserId == UserId && m.Role == "Leader" && m.LeftAt == null);
            if (!leader) return Forbid();
            if (!string.IsNullOrWhiteSpace(input.AssignedToUserId))
            {
                var assigned = await db.WorkspaceMembers.AnyAsync(m => m.WorkspaceId == input.WorkspaceId && m.UserId == input.AssignedToUserId && m.LeftAt == null);
                if (!assigned) return BadRequest(new { message = "Người được giao không thuộc nhóm." });
                ownerId = input.AssignedToUserId;
            }
        }
        else if (!string.IsNullOrWhiteSpace(input.AssignedToUserId)) return BadRequest(new { message = "Chỉ công việc nhóm mới được giao cho thành viên khác." });
        var task = new TaskItem { OwnerId = ownerId, CreatedByUserId = UserId, WorkspaceId = input.WorkspaceId, Title = input.Title.Trim(), Description = input.Description.Trim(), CategoryId = input.CategoryId, DueAt = input.DueAt?.ToUniversalTime(), Priority = (TaskPriority)Math.Clamp(input.Priority, 0, 3), Status = input.Status, ReminderIntervalMinutes = input.ReminderIntervalMinutes, ReminderUntil = input.ReminderUntil?.ToUniversalTime(), CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow };
        db.Tasks.Add(task); await db.SaveChangesAsync();
        return CreatedAtAction(nameof(Get), new { id = task.Id }, task);
    }

    [HttpPut("{id:int}")]
    public async Task<IActionResult> Update(int id, SaveTaskRequest input)
    {
        var task = await db.Tasks.FirstOrDefaultAsync(t => t.Id == id); if (task is null || !await CanManage(task)) return NotFound();
        task.Title = input.Title.Trim(); task.Description = input.Description.Trim(); task.CategoryId = input.CategoryId; task.DueAt = input.DueAt?.ToUniversalTime(); task.Priority = (TaskPriority)Math.Clamp(input.Priority, 0, 3); task.Status = input.Status; task.ReminderIntervalMinutes = input.ReminderIntervalMinutes; task.ReminderUntil = input.ReminderUntil?.ToUniversalTime(); task.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(); return Ok(task);
    }

    [HttpPatch("{id:int}/status")]
    public async Task<IActionResult> SetStatus(int id, [FromBody] WorkStatus status)
    {
        var task = await db.Tasks.FirstOrDefaultAsync(t => t.Id == id);
        if (task is null || !await CanManage(task)) return NotFound();
        if (task.IsLocked && status != WorkStatus.Done) return Conflict(new { message = "Công việc đã khóa hoàn thành. Trưởng nhóm có thể yêu cầu làm lại." });
        task.Status = status;
        task.IsLocked = status == WorkStatus.Done;
        task.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return Ok(task);
    }

    [HttpPost("{id:int}/request-rework")]
    public async Task<IActionResult> RequestRework(int id)
    {
        var task = await db.Tasks.FirstOrDefaultAsync(t => t.Id == id);
        if (task is null || !task.WorkspaceId.HasValue || task.OwnerId == UserId) return NotFound();
        var isLeader = await db.WorkspaceMembers.AnyAsync(m => m.WorkspaceId == task.WorkspaceId && m.UserId == UserId && m.Role == "Leader" && m.LeftAt == null);
        if (!isLeader) return Forbid();
        if (task.Status != WorkStatus.Done) return Conflict(new { message = "Chỉ có thể yêu cầu làm lại công việc đã hoàn thành." });
        task.Status = WorkStatus.Todo;
        task.IsLocked = false;
        task.UpdatedAt = DateTime.UtcNow;
        db.TaskNotices.Add(new TaskNotice { UserId = task.OwnerId, TaskId = task.Id, Message = $"Trưởng nhóm yêu cầu bạn làm lại công việc: {task.Title}" });
        await db.SaveChangesAsync();
        return Ok(task);
    }

    [HttpGet("notices")]
    public async Task<IActionResult> Notices()
    {
        var items = await db.TaskNotices.AsNoTracking().Where(n => n.UserId == UserId && n.ReadAt == null).OrderBy(n => n.CreatedAt).ToListAsync();
        return Ok(items);
    }

    [HttpGet("notices/history")]
    public async Task<IActionResult> NoticeHistory()
    {
        var items = await db.TaskNotices.AsNoTracking().Where(n => n.UserId == UserId)
            .OrderByDescending(n => n.CreatedAt).Take(100).ToListAsync();
        return Ok(items);
    }

    [HttpPut("notices/{id:int}/read")]
    public async Task<IActionResult> ReadNotice(int id)
    {
        var notice = await db.TaskNotices.FirstOrDefaultAsync(n => n.Id == id && n.UserId == UserId);
        if (notice is null) return NotFound();
        notice.ReadAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpGet("{id:int}/attachments")]
    public async Task<IActionResult> Attachments(int id)
    {
        var task = await db.Tasks.AsNoTracking().FirstOrDefaultAsync(t => t.Id == id);
        if (task is null || !await CanView(task)) return NotFound();
        var files = await db.TaskAttachments.AsNoTracking().Where(a => a.TaskId == id)
            .OrderBy(a => a.CreatedAt)
            .Select(a => new { a.Id, a.FileName, a.ContentType, a.Size, a.CreatedAt })
            .ToListAsync();
        return Ok(files);
    }

    [HttpPost("{id:int}/attachments"), RequestSizeLimit(16_000_000)]
    public async Task<IActionResult> UploadAttachment(int id, [FromForm] IFormFile? file)
    {
        var task = await db.Tasks.FirstOrDefaultAsync(t => t.Id == id);
        if (task is null || !await CanManage(task)) return NotFound();
        if (file is null || file.Length == 0) return BadRequest(new { message = "Bạn chưa chọn tệp." });
        if (file.Length > 15 * 1024 * 1024) return BadRequest(new { message = "Tệp không được lớn hơn 15 MB." });
        var safeName = Path.GetFileName(file.FileName);
        var extension = Path.GetExtension(safeName).ToLowerInvariant();
        var allowed = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        { ".png", ".jpg", ".jpeg", ".gif", ".webp", ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".txt", ".csv", ".zip" };
        if (!allowed.Contains(extension)) return BadRequest(new { message = "Định dạng tệp này chưa được hỗ trợ." });
        var storageName = $"{Guid.NewGuid():N}{extension}";
        var directory = Path.Combine(environment.ContentRootPath, "App_Data", "TaskFiles", id.ToString());
        Directory.CreateDirectory(directory);
        var storagePath = Path.Combine(directory, storageName);
        await using (var output = System.IO.File.Create(storagePath)) await file.CopyToAsync(output);
        var types = new FileExtensionContentTypeProvider();
        if (!types.TryGetContentType(safeName, out var contentType)) contentType = "application/octet-stream";
        var attachment = new TaskAttachment { TaskId = id, FileName = safeName, StorageName = storageName, ContentType = contentType, Size = file.Length, UploadedByUserId = UserId };
        db.TaskAttachments.Add(attachment);
        await db.SaveChangesAsync();
        return Ok(new { attachment.Id, attachment.FileName, attachment.ContentType, attachment.Size, attachment.CreatedAt });
    }

    [HttpGet("{taskId:int}/attachments/{attachmentId:int}/download")]
    public async Task<IActionResult> DownloadAttachment(int taskId, int attachmentId)
    {
        var task = await db.Tasks.AsNoTracking().FirstOrDefaultAsync(t => t.Id == taskId);
        var attachment = await db.TaskAttachments.AsNoTracking().FirstOrDefaultAsync(a => a.Id == attachmentId && a.TaskId == taskId);
        if (task is null || attachment is null || !await CanView(task)) return NotFound();
        var path = Path.Combine(environment.ContentRootPath, "App_Data", "TaskFiles", taskId.ToString(), attachment.StorageName);
        if (!System.IO.File.Exists(path)) return NotFound();
        return PhysicalFile(path, attachment.ContentType, attachment.FileName);
    }

    [HttpDelete("{taskId:int}/attachments/{attachmentId:int}")]
    public async Task<IActionResult> DeleteAttachment(int taskId, int attachmentId)
    {
        var task = await db.Tasks.FirstOrDefaultAsync(t => t.Id == taskId);
        var attachment = await db.TaskAttachments.FirstOrDefaultAsync(a => a.Id == attachmentId && a.TaskId == taskId);
        if (task is null || attachment is null || !await CanManage(task)) return NotFound();
        DeleteAttachmentFile(taskId, attachment.StorageName);
        db.TaskAttachments.Remove(attachment);
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var task = await db.Tasks.FirstOrDefaultAsync(t => t.Id == id);
        if (task is null) return NotFound();
        var allowed = User.IsInRole("Admin");
        if (!allowed && !task.WorkspaceId.HasValue && task.OwnerId == UserId) allowed = true;
        if (!allowed && task.WorkspaceId.HasValue)
            allowed = await db.WorkspaceMembers.AnyAsync(m => m.WorkspaceId == task.WorkspaceId && m.UserId == UserId && m.Role == "Leader" && m.LeftAt == null);
        if (!allowed) return Forbid();
        var planItems = db.TaskPlanItems.Where(i => i.TaskId == id);
        if (await planItems.AnyAsync())
        {
            if (!User.IsInRole("Admin")) return Conflict(new { message = "Công việc đang nằm trong kế hoạch. Hãy gỡ khỏi kế hoạch trước khi xóa." });
            db.TaskPlanItems.RemoveRange(planItems);
        }
        var files = await db.TaskAttachments.Where(a => a.TaskId == id).Select(a => a.StorageName).ToListAsync();
        foreach (var file in files) DeleteAttachmentFile(id, file);
        DeleteTaskImage(task.ImageStorageName);
        db.Tasks.Remove(task);
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("{id:int}/image"), RequestSizeLimit(10_000_000)]
    public async Task<IActionResult> UploadImage(int id, [FromForm] IFormFile? file)
    {
        var task = await db.Tasks.FirstOrDefaultAsync(t => t.Id == id);
        if (task is null || !await CanManage(task)) return NotFound();
        if (file is null || file.Length == 0) return BadRequest(new { message = "Bạn chưa chọn ảnh." });
        if (file.Length > 10 * 1024 * 1024) return BadRequest(new { message = "Ảnh không được lớn hơn 10 MB." });

        var safeName = Path.GetFileName(file.FileName);
        var extension = Path.GetExtension(safeName).ToLowerInvariant();
        var allowed = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".png", ".jpg", ".jpeg", ".gif", ".webp" };
        if (!allowed.Contains(extension)) return BadRequest(new { message = "Định dạng file không hợp lệ (chỉ hỗ trợ .png, .jpg, .jpeg, .gif, .webp)." });

        // Sửa sản phẩm: nếu upload ảnh mới thì xóa ảnh cũ trên server
        DeleteTaskImage(task.ImageStorageName);

        var storageName = $"{Guid.NewGuid():N}{extension}";
        var directory = Path.Combine(environment.ContentRootPath, "App_Data", "TaskImages");
        Directory.CreateDirectory(directory);
        var storagePath = Path.Combine(directory, storageName);

        await using (var output = System.IO.File.Create(storagePath))
        {
            await file.CopyToAsync(output);
        }

        task.ImageStorageName = storageName;
        task.ImageUrl = $"/api/tasks/{id}/image";
        task.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();

        return Ok(new { task.Id, task.Title, task.ImageUrl });
    }

    [HttpDelete("{id:int}/image")]
    public async Task<IActionResult> DeleteImage(int id)
    {
        var task = await db.Tasks.FirstOrDefaultAsync(t => t.Id == id);
        if (task is null || !await CanManage(task)) return NotFound();

        DeleteTaskImage(task.ImageStorageName);
        task.ImageStorageName = null;
        task.ImageUrl = null;
        task.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();

        return NoContent();
    }

    [HttpGet("{id:int}/image"), AllowAnonymous]
    public async Task<IActionResult> GetImage(int id)
    {
        var task = await db.Tasks.AsNoTracking().FirstOrDefaultAsync(t => t.Id == id);
        if (task is null || string.IsNullOrWhiteSpace(task.ImageStorageName))
            return NotFound();

        var path = Path.Combine(environment.ContentRootPath, "App_Data", "TaskImages", task.ImageStorageName);
        if (!System.IO.File.Exists(path)) return NotFound();

        var types = new FileExtensionContentTypeProvider();
        if (!types.TryGetContentType(path, out var contentType)) contentType = "application/octet-stream";

        return PhysicalFile(path, contentType);
    }

    void DeleteTaskImage(string? storageName)
    {
        if (string.IsNullOrWhiteSpace(storageName)) return;
        var path = Path.Combine(environment.ContentRootPath, "App_Data", "TaskImages", storageName);
        if (System.IO.File.Exists(path)) System.IO.File.Delete(path);
    }

    void DeleteAttachmentFile(int taskId, string storageName)
    {
        var path = Path.Combine(environment.ContentRootPath, "App_Data", "TaskFiles", taskId.ToString(), storageName);
        if (System.IO.File.Exists(path)) System.IO.File.Delete(path);
    }
}
