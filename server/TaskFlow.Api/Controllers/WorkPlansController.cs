using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using TaskFlow.Api.Data;
using TaskFlow.Api.Models;

namespace TaskFlow.Api.Controllers;

public record CreateTaskPlanRequest(string Name, List<int> TaskIds);
public record AddTaskPlanItemRequest(int TaskId, int SortOrder = 0, DateTime? PlannedFor = null);
public record UpdateTaskPlanItemRequest(int SortOrder, DateTime? PlannedFor = null);

[ApiController, Route("api/plans"), Authorize]
public class WorkPlansController(AppDbContext db) : ControllerBase
{
    string UserId => User.FindFirstValue(ClaimTypes.NameIdentifier)!;

    [HttpGet]
    public async Task<IActionResult> List()
    {
        var plans = await db.TaskPlans.AsNoTracking().Where(p => p.OwnerId == UserId)
            .OrderByDescending(p => p.CreatedAt).ToListAsync();
        var ids = plans.Select(p => p.Id).ToArray();
        var items = await (from item in db.TaskPlanItems.AsNoTracking()
                           join task in db.Tasks.AsNoTracking() on item.TaskId equals task.Id
                           where ids.Contains(item.PlanId)
                           orderby item.SortOrder, item.Id
                           select new { item.Id, item.PlanId, item.TaskId, task.Title, task.Description, task.DueAt, task.Status, task.CategoryId, item.SortOrder, item.PlannedFor })
            .ToListAsync();
        return Ok(plans.Select(p => new { p.Id, p.Name, p.CreatedAt, p.ConfirmedAt, items = items.Where(i => i.PlanId == p.Id).ToList() }));
    }

    [HttpPost]
    public async Task<IActionResult> Create(CreateTaskPlanRequest input)
    {
        if (string.IsNullOrWhiteSpace(input.Name)) return BadRequest(new { message = "Tên kế hoạch không được để trống." });
        var taskIds = input.TaskIds.Distinct().ToArray();
        if (taskIds.Length == 0) return BadRequest(new { message = "Chọn ít nhất một công việc cho kế hoạch." });
        var activeGroupIds = await db.WorkspaceMembers.Where(m => m.UserId == UserId && m.LeftAt == null).Select(m => m.WorkspaceId).ToArrayAsync();
        var allowed = await db.Tasks.Where(t => taskIds.Contains(t.Id) &&
            ((!t.WorkspaceId.HasValue && t.OwnerId == UserId) || (t.WorkspaceId.HasValue && activeGroupIds.Contains(t.WorkspaceId.Value))))
            .Select(t => t.Id).ToListAsync();
        if (allowed.Count != taskIds.Length) return BadRequest(new { message = "Một số công việc không thuộc tài khoản hoặc nhóm đang tham gia." });
        var plan = new TaskPlan { OwnerId = UserId, Name = input.Name.Trim(), CreatedAt = DateTime.UtcNow };
        db.TaskPlans.Add(plan);
        await db.SaveChangesAsync();
        db.TaskPlanItems.AddRange(taskIds.Select((id, index) => new TaskPlanItem { PlanId = plan.Id, TaskId = id, SortOrder = index }));
        await db.SaveChangesAsync();
        return CreatedAtAction(nameof(List), new { id = plan.Id }, new { plan.Id, plan.Name, plan.CreatedAt, plan.ConfirmedAt, itemCount = taskIds.Length });
    }

    [HttpPost("{planId:int}/items")]
    public async Task<IActionResult> AddItem(int planId, AddTaskPlanItemRequest input)
    {
        var plan = await db.TaskPlans.FirstOrDefaultAsync(p => p.Id == planId && p.OwnerId == UserId);
        if (plan is null) return NotFound();
        if (plan.ConfirmedAt is not null) return Conflict(new { message = "Kế hoạch đã xác nhận, không thể sửa." });
        var activeGroupIds = await db.WorkspaceMembers.Where(m => m.UserId == UserId && m.LeftAt == null).Select(m => m.WorkspaceId).ToArrayAsync();
        var task = await db.Tasks.FirstOrDefaultAsync(t => t.Id == input.TaskId &&
            ((!t.WorkspaceId.HasValue && t.OwnerId == UserId) || (t.WorkspaceId.HasValue && activeGroupIds.Contains(t.WorkspaceId.Value))));
        if (task is null) return NotFound(new { message = "Không tìm thấy công việc trong phạm vi của bạn." });
        if (await db.TaskPlanItems.AnyAsync(i => i.PlanId == planId && i.TaskId == input.TaskId)) return Conflict(new { message = "Công việc đã nằm trong kế hoạch." });
        db.TaskPlanItems.Add(new TaskPlanItem { PlanId = planId, TaskId = input.TaskId, SortOrder = input.SortOrder, PlannedFor = input.PlannedFor?.ToUniversalTime() });
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPut("{planId:int}/items/{taskId:int}")]
    public async Task<IActionResult> UpdateItem(int planId, int taskId, UpdateTaskPlanItemRequest input)
    {
        var plan = await db.TaskPlans.FirstOrDefaultAsync(p => p.Id == planId && p.OwnerId == UserId);
        if (plan is null) return NotFound();
        if (plan.ConfirmedAt is not null) return Conflict(new { message = "Kế hoạch đã xác nhận, không thể sửa." });
        var item = await db.TaskPlanItems.FirstOrDefaultAsync(i => i.PlanId == planId && i.TaskId == taskId);
        if (item is null) return NotFound();
        item.SortOrder = Math.Max(0, input.SortOrder);
        item.PlannedFor = input.PlannedFor?.ToUniversalTime();
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpDelete("{planId:int}/items/{taskId:int}")]
    public async Task<IActionResult> RemoveItem(int planId, int taskId)
    {
        var plan = await db.TaskPlans.FirstOrDefaultAsync(p => p.Id == planId && p.OwnerId == UserId);
        if (plan is null) return NotFound();
        if (plan.ConfirmedAt is not null) return Conflict(new { message = "Kế hoạch đã xác nhận, không thể sửa." });
        var item = await db.TaskPlanItems.FirstOrDefaultAsync(i => i.PlanId == planId && i.TaskId == taskId);
        if (item is null) return NotFound();
        db.TaskPlanItems.Remove(item);
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("{planId:int}/confirm")]
    public async Task<IActionResult> Confirm(int planId)
    {
        var plan = await db.TaskPlans.FirstOrDefaultAsync(p => p.Id == planId && p.OwnerId == UserId);
        if (plan is null) return NotFound();
        if (!await db.TaskPlanItems.AnyAsync(i => i.PlanId == planId)) return Conflict(new { message = "Kế hoạch chưa có công việc." });
        plan.ConfirmedAt ??= DateTime.UtcNow;
        await db.SaveChangesAsync();
        return Ok(new { plan.Id, plan.Name, plan.ConfirmedAt });
    }

    [HttpDelete("{planId:int}")]
    public async Task<IActionResult> Delete(int planId)
    {
        var plan = await db.TaskPlans.FirstOrDefaultAsync(p => p.Id == planId && p.OwnerId == UserId);
        if (plan is null) return NotFound();
        db.TaskPlans.Remove(plan);
        await db.SaveChangesAsync();
        return NoContent();
    }
}
