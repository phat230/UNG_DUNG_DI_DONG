using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using TaskFlow.Api.Data;
using TaskFlow.Api.Models;
namespace TaskFlow.Api.Controllers;

public record RoleRequest(string Role);
public record MemberStatusRequest(bool IsActive);
public record AdminCreateMemberRequest(string UserName, string DisplayName, string Email, string Password, string Role = "Member", int? WorkspaceId = null);
[ApiController, Route("api/admin/members"), Authorize(Roles = "Admin")]
public class MembersController(UserManager<AppUser> users, RoleManager<IdentityRole> roles, AppDbContext db, IWebHostEnvironment environment) : ControllerBase
{
    [HttpGet] public async Task<IActionResult> List([FromQuery]string? q = null, [FromQuery]DateTime? createdFrom = null, [FromQuery]DateTime? createdTo = null)
    {
        var query = users.Users.AsQueryable();
        if (!string.IsNullOrWhiteSpace(q)) query = query.Where(u => u.DisplayName.Contains(q) || u.UserName!.Contains(q) || u.Email!.Contains(q));
        if (createdFrom.HasValue) query = query.Where(u => u.CreatedAt >= createdFrom.Value);
        if (createdTo.HasValue) query = query.Where(u => u.CreatedAt < createdTo.Value.Date.AddDays(1));
        var members = await query.OrderByDescending(u => u.CreatedAt).ToListAsync();
        var result = new List<object>();
        foreach (var user in members)
        {
            var workspaceId = await db.WorkspaceMembers.Where(m => m.UserId == user.Id && m.LeftAt == null).Select(m => (int?)m.WorkspaceId).FirstOrDefaultAsync();
            result.Add(new { user.Id, user.UserName, user.DisplayName, user.Email, user.IsActive, user.CreatedAt, workspaceId, roles = await users.GetRolesAsync(user) });
        }
        return Ok(result);
    }
    [HttpPost] public async Task<IActionResult> Create(AdminCreateMemberRequest input)
    {
        if (!await roles.RoleExistsAsync(input.Role)) return BadRequest(new { message = "Role không tồn tại." });
        if (input.WorkspaceId.HasValue && !await db.Workspaces.AnyAsync(w => w.Id == input.WorkspaceId)) return BadRequest(new { message = "Nhóm không tồn tại." });
        var user = new AppUser { UserName = input.UserName.Trim(), DisplayName = input.DisplayName.Trim(), Email = input.Email.Trim(), EmailConfirmed = true };
        var created = await users.CreateAsync(user, input.Password);
        if (!created.Succeeded) return BadRequest(created.Errors.Select(e => e.Description));
        await users.AddToRoleAsync(user, input.Role);
        if (input.WorkspaceId.HasValue)
        {
            if (await db.WorkspaceMembers.AnyAsync(m => m.UserId == user.Id && m.WorkspaceId == input.WorkspaceId && m.LeftAt == null)) return Conflict(new { message = "Tài khoản đã thuộc nhóm này." });
            db.WorkspaceMembers.Add(new WorkspaceMember { WorkspaceId = input.WorkspaceId.Value, UserId = user.Id, Role = "Member" });
            await db.SaveChangesAsync();
        }
        return Ok(new { user.Id, user.UserName, user.DisplayName, user.Email, user.IsActive, user.CreatedAt, role = input.Role, workspaceId = input.WorkspaceId });
    }
    [HttpPut("{id}/role")] public async Task<IActionResult> SetRole(string id, RoleRequest input)
    {
        if (!await roles.RoleExistsAsync(input.Role)) return BadRequest(new { message = "Role không tồn tại." });
        var user = await users.FindByIdAsync(id); if (user is null) return NotFound();
        var current = await users.GetRolesAsync(user); var remove = await users.RemoveFromRolesAsync(user, current); if (!remove.Succeeded) return BadRequest(remove.Errors);
        var add = await users.AddToRoleAsync(user, input.Role); return add.Succeeded ? NoContent() : BadRequest(add.Errors);
    }
    [HttpPut("{id}/status")] public async Task<IActionResult> SetStatus(string id, MemberStatusRequest input)
    { var user = await users.FindByIdAsync(id); if (user is null) return NotFound(); user.IsActive = input.IsActive; var result = await users.UpdateAsync(user); return result.Succeeded ? NoContent() : BadRequest(result.Errors); }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(string id)
    {
        var user = await users.FindByIdAsync(id);
        if (user is null) return NotFound();
        if (User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value == id)
            return Conflict(new { message = "Không thể xóa tài khoản đang đăng nhập." });

        var userRoles = await users.GetRolesAsync(user);
        if (userRoles.Contains("Admin") && await users.GetUsersInRoleAsync("Admin") is { Count: <= 1 })
            return Conflict(new { message = "Không thể xóa Admin cuối cùng." });

        var ledGroups = await db.Workspaces.Where(w => w.LeaderUserId == id).ToListAsync();
        foreach (var group in ledGroups)
        {
            if (await db.WorkspaceMembers.AnyAsync(m => m.WorkspaceId == group.Id && m.UserId != id && m.LeftAt == null))
                return Conflict(new { message = $"Tài khoản đang là trưởng nhóm '{group.Name}'. Hãy chuyển trưởng nhóm hoặc xóa thành viên khỏi nhóm trước." });
        }

        var taskIds = await db.Tasks.Where(t => t.OwnerId == id)
            .Select(t => t.Id).ToListAsync();
        var attachmentFiles = await db.TaskAttachments.Where(a => taskIds.Contains(a.TaskId))
            .Select(a => new { a.TaskId, a.StorageName }).ToListAsync();

        await using var transaction = await db.Database.BeginTransactionAsync();
        db.TaskPlans.RemoveRange(db.TaskPlans.Where(p => p.OwnerId == id));
        db.TaskComments.RemoveRange(db.TaskComments.Where(c => c.UserId == id));
        db.TaskReminders.RemoveRange(db.TaskReminders.Where(r => r.UserId == id));
        db.TaskNotices.RemoveRange(db.TaskNotices.Where(n => n.UserId == id));
        if (taskIds.Count > 0)
        {
            db.TaskPlanItems.RemoveRange(db.TaskPlanItems.Where(i => taskIds.Contains(i.TaskId)));
            db.Tasks.RemoveRange(db.Tasks.Where(t => taskIds.Contains(t.Id)));
        }
        db.Categories.RemoveRange(db.Categories.Where(c => c.OwnerId == id));
        foreach (var group in ledGroups) db.Workspaces.Remove(group);
        var deleted = await users.DeleteAsync(user);
        if (!deleted.Succeeded)
        {
            await transaction.RollbackAsync();
            return BadRequest(new { message = string.Join("; ", deleted.Errors.Select(e => e.Description)) });
        }
        await db.SaveChangesAsync();
        await transaction.CommitAsync();

        foreach (var file in attachmentFiles)
        {
            var path = Path.Combine(environment.ContentRootPath, "App_Data", "TaskFiles", file.TaskId.ToString(), file.StorageName);
            if (System.IO.File.Exists(path)) System.IO.File.Delete(path);
        }
        return NoContent();
    }
}
