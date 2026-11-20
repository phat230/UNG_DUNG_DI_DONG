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
public class MembersController(UserManager<AppUser> users, RoleManager<IdentityRole> roles, AppDbContext db) : ControllerBase
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
}
