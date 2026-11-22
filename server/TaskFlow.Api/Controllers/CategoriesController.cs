using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.StaticFiles;
using Microsoft.EntityFrameworkCore;
using TaskFlow.Api.Data;
using TaskFlow.Api.Models;

namespace TaskFlow.Api.Controllers;

[ApiController, Route("api/categories"), Authorize]
public class CategoriesController(AppDbContext db, IWebHostEnvironment environment) : ControllerBase
{
    private static readonly HashSet<string> AllowedExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".png", ".jpg", ".jpeg", ".gif", ".webp"
    };

    void DeleteCategoryImage(string? storageName)
    {
        if (string.IsNullOrWhiteSpace(storageName)) return;
        var path = Path.Combine(environment.ContentRootPath, "App_Data", "CategoryImages", storageName);
        if (System.IO.File.Exists(path)) System.IO.File.Delete(path);
    }

    [HttpGet]
    public async Task<IActionResult> List() =>
        Ok(await db.Categories.AsNoTracking().OrderBy(c => c.Name).ToListAsync());

    [HttpPost, Authorize(Roles = "Admin")]
    public async Task<IActionResult> Create(Category input)
    {
        input.Id = 0;
        input.OwnerId = User.FindFirstValue(ClaimTypes.NameIdentifier)!;
        db.Categories.Add(input);
        try
        {
            await db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            return Conflict(new { message = "Tên danh mục đã tồn tại." });
        }
        return CreatedAtAction(nameof(List), new { id = input.Id }, input);
    }

    [HttpPut("{id:int}"), Authorize(Roles = "Admin")]
    public async Task<IActionResult> Update(int id, Category input)
    {
        var item = await db.Categories.FindAsync(id);
        if (item is null) return NotFound();
        item.Name = input.Name;
        item.Color = input.Color;
        try
        {
            await db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            return Conflict(new { message = "Tên danh mục đã tồn tại." });
        }
        return Ok(item);
    }

    [HttpDelete("{id:int}"), Authorize(Roles = "Admin")]
    public async Task<IActionResult> Delete(int id)
    {
        var item = await db.Categories.FindAsync(id);
        if (item is null) return NotFound();
        if (await db.Tasks.AnyAsync(t => t.CategoryId == id))
            return Conflict(new { message = "Không thể xóa danh mục đang được công việc sử dụng." });

        // Xóa hình ảnh kèm theo danh mục
        DeleteCategoryImage(item.ImageStorageName);

        db.Categories.Remove(item);
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("{id:int}/image"), Authorize(Roles = "Admin"), RequestSizeLimit(10_000_000)]
    public async Task<IActionResult> UploadImage(int id, [FromForm] IFormFile? file)
    {
        var item = await db.Categories.FindAsync(id);
        if (item is null) return NotFound();
        if (file is null || file.Length == 0) return BadRequest(new { message = "Bạn chưa chọn ảnh." });
        if (file.Length > 10 * 1024 * 1024) return BadRequest(new { message = "Ảnh không được lớn hơn 10 MB." });

        var safeName = Path.GetFileName(file.FileName);
        var extension = Path.GetExtension(safeName).ToLowerInvariant();
        if (!AllowedExtensions.Contains(extension))
            return BadRequest(new { message = "Định dạng file không hợp lệ (chỉ hỗ trợ .png, .jpg, .jpeg, .gif, .webp)." });

        // Nếu đã có ảnh cũ, xóa ảnh cũ trước khi lưu ảnh mới
        DeleteCategoryImage(item.ImageStorageName);

        var storageName = $"{Guid.NewGuid():N}{extension}";
        var directory = Path.Combine(environment.ContentRootPath, "App_Data", "CategoryImages");
        Directory.CreateDirectory(directory);
        var storagePath = Path.Combine(directory, storageName);

        await using (var output = System.IO.File.Create(storagePath))
        {
            await file.CopyToAsync(output);
        }

        item.ImageStorageName = storageName;
        item.ImageUrl = $"/api/categories/{id}/image";
        await db.SaveChangesAsync();

        return Ok(new { item.Id, item.Name, item.Color, item.ImageUrl });
    }

    [HttpDelete("{id:int}/image"), Authorize(Roles = "Admin")]
    public async Task<IActionResult> DeleteImage(int id)
    {
        var item = await db.Categories.FindAsync(id);
        if (item is null) return NotFound();

        DeleteCategoryImage(item.ImageStorageName);
        item.ImageStorageName = null;
        item.ImageUrl = null;
        await db.SaveChangesAsync();

        return NoContent();
    }

    [HttpGet("{id:int}/image"), AllowAnonymous]
    public async Task<IActionResult> GetImage(int id)
    {
        var item = await db.Categories.AsNoTracking().FirstOrDefaultAsync(c => c.Id == id);
        if (item is null || string.IsNullOrWhiteSpace(item.ImageStorageName))
            return NotFound();

        var path = Path.Combine(environment.ContentRootPath, "App_Data", "CategoryImages", item.ImageStorageName);
        if (!System.IO.File.Exists(path)) return NotFound();

        var types = new FileExtensionContentTypeProvider();
        if (!types.TryGetContentType(path, out var contentType)) contentType = "application/octet-stream";

        return PhysicalFile(path, contentType);
    }
}
