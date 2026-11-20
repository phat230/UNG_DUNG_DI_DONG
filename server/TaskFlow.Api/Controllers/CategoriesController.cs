using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using TaskFlow.Api.Data;
using TaskFlow.Api.Models;
namespace TaskFlow.Api.Controllers;

[ApiController, Route("api/categories"), Authorize]
public class CategoriesController(AppDbContext db) : ControllerBase
{
    [HttpGet] public async Task<IActionResult> List() => Ok(await db.Categories.AsNoTracking().OrderBy(c => c.Name).ToListAsync());
    [HttpPost, Authorize(Roles = "Admin")] public async Task<IActionResult> Create(Category input)
    { input.Id = 0; input.OwnerId = User.FindFirstValue(ClaimTypes.NameIdentifier)!; db.Categories.Add(input); try { await db.SaveChangesAsync(); } catch (DbUpdateException) { return Conflict(new { message = "Tên danh mục đã tồn tại." }); } return CreatedAtAction(nameof(List), new { id = input.Id }, input); }
    [HttpPut("{id:int}"), Authorize(Roles = "Admin")] public async Task<IActionResult> Update(int id, Category input)
    { var item = await db.Categories.FindAsync(id); if (item is null) return NotFound(); item.Name = input.Name; item.Color = input.Color; try { await db.SaveChangesAsync(); } catch (DbUpdateException) { return Conflict(new { message = "Tên danh mục đã tồn tại." }); } return Ok(item); }
    [HttpDelete("{id:int}"), Authorize(Roles = "Admin")] public async Task<IActionResult> Delete(int id)
    { var item = await db.Categories.FindAsync(id); if (item is null) return NotFound(); if (await db.Tasks.AnyAsync(t => t.CategoryId == id)) return Conflict(new { message = "Không thể xóa danh mục đang được công việc sử dụng." }); db.Categories.Remove(item); await db.SaveChangesAsync(); return NoContent(); }
}
