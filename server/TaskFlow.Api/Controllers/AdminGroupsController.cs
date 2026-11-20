using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using TaskFlow.Api.Data;
using TaskFlow.Api.Models;
namespace TaskFlow.Api.Controllers;

public record AdminCreateGroupRequest(string Name, string LeaderUserId);
public record AddGroupMemberRequest(string UserId);
[ApiController, Route("api/admin/groups"), Authorize(Roles = "Admin")]
public class AdminGroupsController(AppDbContext db, UserManager<AppUser> users) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List([FromQuery]string? q = null, [FromQuery]DateTime? createdFrom = null, [FromQuery]DateTime? createdTo = null)
    {
        var query = db.Workspaces.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(q)) query = query.Where(g => g.Name.Contains(q) || g.JoinCode.Contains(q));
        if (createdFrom.HasValue) query = query.Where(g => g.CreatedAt >= createdFrom.Value);
        if (createdTo.HasValue) query = query.Where(g => g.CreatedAt < createdTo.Value.Date.AddDays(1));
        var groups = await query.OrderByDescending(g => g.CreatedAt).ToListAsync();
        var result = new List<object>();
        foreach (var workspace in groups)
        {
            var leader = await users.FindByIdAsync(workspace.LeaderUserId);
            var members = await (from m in db.WorkspaceMembers join u in db.Users on m.UserId equals u.Id where m.WorkspaceId == workspace.Id && m.LeftAt == null select new { u.Id, u.DisplayName, u.UserName, m.Role }).ToListAsync();
            result.Add(new { workspace.Id, workspace.Name, workspace.JoinCode, workspace.LeaderUserId, leaderName = leader?.DisplayName ?? "(đã xóa)", workspace.CreatedAt, members });
        }
        return Ok(result);
    }

    [HttpPost]
    public async Task<IActionResult> Create(AdminCreateGroupRequest input)
    {
        var leader = await users.FindByIdAsync(input.LeaderUserId);
        if (leader is null) return BadRequest(new { message = "Không tìm thấy tài khoản nhóm trưởng." });
        var workspace = new Workspace { Name = input.Name.Trim(), JoinCode = Guid.NewGuid().ToString("N")[..8].ToUpperInvariant(), LeaderUserId = leader.Id };
        db.Workspaces.Add(workspace); await db.SaveChangesAsync();
        db.WorkspaceMembers.Add(new WorkspaceMember { WorkspaceId = workspace.Id, UserId = leader.Id, Role = "Leader" }); await db.SaveChangesAsync();
        return CreatedAtAction(nameof(List), new { id = workspace.Id }, new { workspace.Id, workspace.Name, workspace.JoinCode, leaderName = leader.DisplayName, role = "Leader" });
    }

    [HttpPost("{groupId:int}/members")]
    public async Task<IActionResult> AddMember(int groupId, AddGroupMemberRequest input)
    {
        if (!await db.Workspaces.AnyAsync(g => g.Id == groupId)) return NotFound();
        if (await users.FindByIdAsync(input.UserId) is null) return BadRequest(new { message = "Không tìm thấy tài khoản." });
        if (await db.WorkspaceMembers.AnyAsync(m => m.WorkspaceId == groupId && m.UserId == input.UserId && m.LeftAt == null)) return Conflict(new { message = "Tài khoản đã thuộc nhóm này." });
        var oldMembership = await db.WorkspaceMembers.FirstOrDefaultAsync(m => m.WorkspaceId == groupId && m.UserId == input.UserId);
        if (oldMembership is null) db.WorkspaceMembers.Add(new WorkspaceMember { WorkspaceId = groupId, UserId = input.UserId, Role = "Member" });
        else { oldMembership.LeftAt = null; oldMembership.JoinedAt = DateTime.UtcNow; oldMembership.Role = "Member"; }
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpDelete("{groupId:int}/members/{userId}")]
    public async Task<IActionResult> RemoveMember(int groupId, string userId)
    {
        var member = await db.WorkspaceMembers.FirstOrDefaultAsync(m => m.WorkspaceId == groupId && m.UserId == userId && m.LeftAt == null);
        if (member is null) return NotFound();
        if (member.Role == "Leader") return Conflict(new { message = "Không thể xóa nhóm trưởng khỏi nhóm." });
        if (member.Role == "Leader") return Conflict(new { message = "Không thể xóa trưởng nhóm khỏi nhóm." });
        member.LeftAt = DateTime.UtcNow; await db.SaveChangesAsync(); return NoContent();
    }
}
