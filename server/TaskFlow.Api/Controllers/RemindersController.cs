using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using TaskFlow.Api.Data;
using TaskFlow.Api.Models;
namespace TaskFlow.Api.Controllers;

public record ReminderRequest(DateTime RemindAt);
[ApiController, Route("api/tasks/{taskId:int}/reminders"), Authorize]
public class RemindersController(AppDbContext db) : ControllerBase
{
    string UserId => User.FindFirstValue(ClaimTypes.NameIdentifier)!;
    [HttpGet] public async Task<IActionResult> List(int taskId)
    { if (!await db.Tasks.AnyAsync(t => t.Id == taskId && t.OwnerId == UserId)) return NotFound(); return Ok(await db.TaskReminders.Where(r => r.TaskId == taskId && r.UserId == UserId).OrderBy(r => r.RemindAt).ToListAsync()); }
    [HttpPost] public async Task<IActionResult> Create(int taskId, ReminderRequest input)
    { if (!await db.Tasks.AnyAsync(t => t.Id == taskId && t.OwnerId == UserId)) return NotFound(); var reminder = new TaskReminder { TaskId = taskId, UserId = UserId, RemindAt = input.RemindAt.ToUniversalTime() }; db.TaskReminders.Add(reminder); await db.SaveChangesAsync(); return CreatedAtAction(nameof(List), new { taskId }, reminder); }
    [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int taskId, int id)
    { var reminder = await db.TaskReminders.FirstOrDefaultAsync(r => r.Id == id && r.TaskId == taskId && r.UserId == UserId); if (reminder is null) return NotFound(); db.Remove(reminder); await db.SaveChangesAsync(); return NoContent(); }
}
