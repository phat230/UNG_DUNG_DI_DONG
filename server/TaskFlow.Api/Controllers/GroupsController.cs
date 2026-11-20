using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using TaskFlow.Api.Data;
using TaskFlow.Api.Models;
namespace TaskFlow.Api.Controllers;

public record JoinGroupRequest(string JoinCode);
public record CreateGroupRequest(string Name);
[ApiController, Route("api/groups"), Authorize]
public class GroupsController(AppDbContext db) : ControllerBase
{
    string UserId => User.FindFirstValue(ClaimTypes.NameIdentifier)!;

    [HttpGet("mine")] public async Task<IActionResult> Mine()
    {
        var membership = await db.WorkspaceMembers.FirstOrDefaultAsync(m => m.UserId == UserId && m.LeftAt == null);
        if (membership is null) return Ok(new { group = (object?)null });
        var workspace = await db.Workspaces.FindAsync(membership.WorkspaceId);
        if (workspace is null) return Ok(new { group = (object?)null });
        var members = await (from m in db.WorkspaceMembers join u in db.Users on m.UserId equals u.Id where m.WorkspaceId == workspace.Id && m.LeftAt == null select new { u.Id, u.DisplayName, u.UserName, m.Role }).ToListAsync();
        return Ok(new { group = new { workspace.Id, workspace.Name, workspace.JoinCode, membership.Role, members } });
    }

    [HttpGet("mine/all")]
    public async Task<IActionResult> MineAll()
    {
        var memberships = await (from m in db.WorkspaceMembers.AsNoTracking()
            join w in db.Workspaces.AsNoTracking() on m.WorkspaceId equals w.Id
            where m.UserId == UserId && m.LeftAt == null
            orderby w.Name
            select new { w.Id, w.Name, w.JoinCode, m.Role, m.JoinedAt }).ToListAsync();
        return Ok(memberships);
    }

    [HttpGet("{workspaceId:int}")]
    public async Task<IActionResult> Get(int workspaceId)
    {
        var membership = await db.WorkspaceMembers.AsNoTracking()
            .FirstOrDefaultAsync(m => m.WorkspaceId == workspaceId && m.UserId == UserId);
        if (membership is null) return NotFound();
        var workspace = await db.Workspaces.AsNoTracking().FirstOrDefaultAsync(w => w.Id == workspaceId);
        if (workspace is null) return NotFound();
        var members = await (from m in db.WorkspaceMembers.AsNoTracking()
            join u in db.Users on m.UserId equals u.Id
            where m.WorkspaceId == workspaceId && m.LeftAt == null
            select new { u.Id, u.DisplayName, u.UserName, m.Role }).ToListAsync();
        return Ok(new { group = new { workspace.Id, workspace.Name, workspace.JoinCode, membership.Role, isCurrent = membership.LeftAt == null, members } });
    }

    [HttpPost] public async Task<IActionResult> Create(CreateGroupRequest input)
    {
        if (string.IsNullOrWhiteSpace(input.Name)) return BadRequest(new { message = "Tên nhóm không được để trống." });
        var group = new Workspace { Name = input.Name.Trim(), JoinCode = Guid.NewGuid().ToString("N")[..8].ToUpperInvariant(), LeaderUserId = UserId };
        db.Workspaces.Add(group); await db.SaveChangesAsync();
        db.WorkspaceMembers.Add(new WorkspaceMember { WorkspaceId = group.Id, UserId = UserId, Role = "Leader" }); await db.SaveChangesAsync();
        return Ok(new { group.Id, group.Name, group.JoinCode, role = "Leader" });
    }

    [HttpPost("join")] public async Task<IActionResult> Join(JoinGroupRequest input)
    {
        var code = input.JoinCode.Trim().ToUpperInvariant();
        var group = await db.Workspaces.FirstOrDefaultAsync(g => g.JoinCode == code);
        if (group is null) return NotFound(new { message = "Không tìm thấy nhóm với mã này." });
        if (await db.WorkspaceMembers.AnyAsync(m => m.WorkspaceId == group.Id && m.UserId == UserId && m.LeftAt == null)) return Conflict(new { message = "Tài khoản đã ở trong nhóm này." });
        var oldMembership = await db.WorkspaceMembers.FirstOrDefaultAsync(m => m.WorkspaceId == group.Id && m.UserId == UserId);
        if (oldMembership is null) db.WorkspaceMembers.Add(new WorkspaceMember { WorkspaceId = group.Id, UserId = UserId, Role = "Member" });
        else { oldMembership.LeftAt = null; oldMembership.JoinedAt = DateTime.UtcNow; oldMembership.Role = "Member"; }
        await db.SaveChangesAsync();
        return Ok(new { group.Id, group.Name, group.JoinCode, role = "Member" });
    }

    [HttpPost("{workspaceId:int}/leave")]
    public async Task<IActionResult> Leave(int workspaceId)
    {
        var membership = await db.WorkspaceMembers.FirstOrDefaultAsync(m => m.WorkspaceId == workspaceId && m.UserId == UserId && m.LeftAt == null);
        if (membership is null) return NotFound(new { message = "Tài khoản hiện không thuộc nhóm nào." });
        if (membership.Role == "Leader" && await db.WorkspaceMembers.AnyAsync(m => m.WorkspaceId == membership.WorkspaceId && m.LeftAt == null && m.UserId != UserId))
            return Conflict(new { message = "Trưởng nhóm cần chuyển quyền trưởng nhóm trước khi rời nhóm." });
        membership.LeftAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpGet("history")]
    public async Task<IActionResult> History()
    {
        var memberships = await (from m in db.WorkspaceMembers
            join w in db.Workspaces on m.WorkspaceId equals w.Id
            where m.UserId == UserId
            orderby m.JoinedAt descending
            select new { Membership = m, Workspace = w }).ToListAsync();
        var result = new List<object>();
        foreach (var item in memberships)
        {
            var tasks = await db.Tasks.AsNoTracking()
                .Where(t => t.WorkspaceId == item.Workspace.Id && t.OwnerId == UserId)
                .OrderByDescending(t => t.UpdatedAt)
                .Select(t => new { t.Id, t.Title, t.Description, t.Status, t.DueAt, t.CreatedAt, t.UpdatedAt })
                .ToListAsync();
            result.Add(new { groupId = item.Workspace.Id, groupName = item.Workspace.Name, joinCode = item.Workspace.JoinCode, role = item.Membership.Role, joinedAt = item.Membership.JoinedAt, leftAt = item.Membership.LeftAt, isCurrent = item.Membership.LeftAt == null, tasks });
        }
        return Ok(result);
    }
}
