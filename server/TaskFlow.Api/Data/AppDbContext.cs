using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using TaskFlow.Api.Models;

namespace TaskFlow.Api.Data;

public class AppUser : IdentityUser { public string DisplayName { get; set; } = ""; public string? GoogleSubject { get; set; } public bool IsActive { get; set; } = true; public DateTime CreatedAt { get; set; } = DateTime.UtcNow; }
public class AppDbContext(DbContextOptions<AppDbContext> options) : IdentityDbContext<AppUser>(options)
{
    public DbSet<Category> Categories => Set<Category>();
    public DbSet<TaskItem> Tasks => Set<TaskItem>();
    public DbSet<TaskComment> TaskComments => Set<TaskComment>();
    public DbSet<TaskReminder> TaskReminders => Set<TaskReminder>();
    public DbSet<Workspace> Workspaces => Set<Workspace>();
    public DbSet<WorkspaceMember> WorkspaceMembers => Set<WorkspaceMember>();
    public DbSet<TaskNotice> TaskNotices => Set<TaskNotice>();
    public DbSet<TaskAttachment> TaskAttachments => Set<TaskAttachment>();
    public DbSet<TaskPlan> TaskPlans => Set<TaskPlan>();
    public DbSet<TaskPlanItem> TaskPlanItems => Set<TaskPlanItem>();
    protected override void OnModelCreating(ModelBuilder b)
    {
        base.OnModelCreating(b);
        b.Entity<Category>().HasIndex(x => new { x.OwnerId, x.Name }).IsUnique();
        b.Entity<TaskItem>().HasIndex(x => new { x.OwnerId, x.DueAt, x.Status });
        b.Entity<TaskItem>().HasOne<Category>().WithMany().HasForeignKey(x => x.CategoryId).OnDelete(DeleteBehavior.SetNull);
        b.Entity<TaskComment>().HasOne<TaskItem>().WithMany().HasForeignKey(x => x.TaskId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<TaskReminder>().HasOne<TaskItem>().WithMany().HasForeignKey(x => x.TaskId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<TaskAttachment>().HasOne<TaskItem>().WithMany().HasForeignKey(x => x.TaskId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<TaskPlan>().HasIndex(x => new { x.OwnerId, x.CreatedAt });
        b.Entity<TaskPlanItem>().HasIndex(x => new { x.PlanId, x.TaskId }).IsUnique();
        b.Entity<TaskPlanItem>().HasOne<TaskPlan>().WithMany().HasForeignKey(x => x.PlanId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<TaskPlanItem>().HasOne<TaskItem>().WithMany().HasForeignKey(x => x.TaskId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<Workspace>().HasIndex(x => x.JoinCode).IsUnique();
        b.Entity<WorkspaceMember>().HasIndex(x => new { x.WorkspaceId, x.UserId }).IsUnique();
        b.Entity<AppUser>().HasIndex(x => x.GoogleSubject).IsUnique().HasFilter("[GoogleSubject] IS NOT NULL");
        b.Entity<WorkspaceMember>().HasOne<Workspace>().WithMany().HasForeignKey(x => x.WorkspaceId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<TaskItem>().HasOne<Workspace>().WithMany().HasForeignKey(x => x.WorkspaceId).OnDelete(DeleteBehavior.SetNull);
    }
}
