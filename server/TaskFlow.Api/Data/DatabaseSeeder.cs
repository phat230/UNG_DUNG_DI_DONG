using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using TaskFlow.Api.Models;
using WorkStatus = TaskFlow.Api.Models.TaskStatus;

namespace TaskFlow.Api.Data;

public static class DatabaseSeeder
{
    public static async Task InitializeAsync(IServiceProvider services)
    {
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var users = scope.ServiceProvider.GetRequiredService<UserManager<AppUser>>();
        var roles = scope.ServiceProvider.GetRequiredService<RoleManager<IdentityRole>>();
        await db.Database.EnsureCreatedAsync();
        await db.Database.ExecuteSqlRawAsync("""
            IF COL_LENGTH('Categories', 'ImageUrl') IS NULL ALTER TABLE [Categories] ADD [ImageUrl] nvarchar(500) NULL;
            IF COL_LENGTH('Categories', 'ImageStorageName') IS NULL ALTER TABLE [Categories] ADD [ImageStorageName] nvarchar(150) NULL;
            IF COL_LENGTH('Tasks', 'ImageUrl') IS NULL ALTER TABLE [Tasks] ADD [ImageUrl] nvarchar(500) NULL;
            IF COL_LENGTH('Tasks', 'ImageStorageName') IS NULL ALTER TABLE [Tasks] ADD [ImageStorageName] nvarchar(150) NULL;
            IF COL_LENGTH('AspNetUsers', 'GoogleSubject') IS NULL ALTER TABLE [AspNetUsers] ADD [GoogleSubject] nvarchar(255) NULL;
            IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_AspNetUsers_GoogleSubject' AND object_id=OBJECT_ID('AspNetUsers'))
                EXEC(N'CREATE UNIQUE INDEX [IX_AspNetUsers_GoogleSubject] ON [AspNetUsers]([GoogleSubject]) WHERE [GoogleSubject] IS NOT NULL');
            IF COL_LENGTH('Tasks', 'CreatedByUserId') IS NULL ALTER TABLE [Tasks] ADD [CreatedByUserId] nvarchar(450) NULL;
            IF COL_LENGTH('Tasks', 'WorkspaceId') IS NULL ALTER TABLE [Tasks] ADD [WorkspaceId] int NULL;
            IF COL_LENGTH('Tasks', 'ReminderIntervalMinutes') IS NULL ALTER TABLE [Tasks] ADD [ReminderIntervalMinutes] int NULL;
            IF COL_LENGTH('Tasks', 'ReminderUntil') IS NULL ALTER TABLE [Tasks] ADD [ReminderUntil] datetime2 NULL;
            IF COL_LENGTH('Tasks', 'IsLocked') IS NULL ALTER TABLE [Tasks] ADD [IsLocked] bit NOT NULL CONSTRAINT [DF_Tasks_IsLocked] DEFAULT 0;
            IF OBJECT_ID('Workspaces', 'U') IS NULL
            BEGIN
                CREATE TABLE [Workspaces] ([Id] int IDENTITY(1,1) NOT NULL CONSTRAINT [PK_Workspaces] PRIMARY KEY, [Name] nvarchar(200) NOT NULL, [JoinCode] nvarchar(32) NOT NULL, [LeaderUserId] nvarchar(450) NOT NULL, [CreatedAt] datetime2 NOT NULL);
                CREATE UNIQUE INDEX [IX_Workspaces_JoinCode] ON [Workspaces]([JoinCode]);
            END;
            IF OBJECT_ID('WorkspaceMembers', 'U') IS NULL
            BEGIN
                CREATE TABLE [WorkspaceMembers] ([Id] int IDENTITY(1,1) NOT NULL CONSTRAINT [PK_WorkspaceMembers] PRIMARY KEY, [WorkspaceId] int NOT NULL, [UserId] nvarchar(450) NOT NULL, [Role] nvarchar(32) NOT NULL, [JoinedAt] datetime2 NOT NULL,
                    CONSTRAINT [FK_WorkspaceMembers_Workspaces_WorkspaceId] FOREIGN KEY ([WorkspaceId]) REFERENCES [Workspaces]([Id]) ON DELETE CASCADE,
                    CONSTRAINT [FK_WorkspaceMembers_AspNetUsers_UserId] FOREIGN KEY ([UserId]) REFERENCES [AspNetUsers]([Id]) ON DELETE CASCADE);
                CREATE UNIQUE INDEX [IX_WorkspaceMembers_WorkspaceId_UserId] ON [WorkspaceMembers]([WorkspaceId],[UserId]);
            END;
            IF COL_LENGTH('WorkspaceMembers', 'LeftAt') IS NULL ALTER TABLE [WorkspaceMembers] ADD [LeftAt] datetime2 NULL;
            IF OBJECT_ID('TaskNotices', 'U') IS NULL
            BEGIN
                CREATE TABLE [TaskNotices] ([Id] int IDENTITY(1,1) NOT NULL CONSTRAINT [PK_TaskNotices] PRIMARY KEY, [UserId] nvarchar(450) NOT NULL, [TaskId] int NOT NULL, [Message] nvarchar(500) NOT NULL, [CreatedAt] datetime2 NOT NULL, [ReadAt] datetime2 NULL,
                    CONSTRAINT [FK_TaskNotices_AspNetUsers_UserId] FOREIGN KEY ([UserId]) REFERENCES [AspNetUsers]([Id]) ON DELETE CASCADE,
                    CONSTRAINT [FK_TaskNotices_Tasks_TaskId] FOREIGN KEY ([TaskId]) REFERENCES [Tasks]([Id]) ON DELETE CASCADE);
            END;
            IF OBJECT_ID('TaskAttachments', 'U') IS NULL
            BEGIN
                CREATE TABLE [TaskAttachments] ([Id] int IDENTITY(1,1) NOT NULL CONSTRAINT [PK_TaskAttachments] PRIMARY KEY, [TaskId] int NOT NULL, [FileName] nvarchar(260) NOT NULL, [StorageName] nvarchar(100) NOT NULL, [ContentType] nvarchar(150) NOT NULL, [Size] bigint NOT NULL, [UploadedByUserId] nvarchar(450) NOT NULL, [CreatedAt] datetime2 NOT NULL,
                    CONSTRAINT [FK_TaskAttachments_Tasks_TaskId] FOREIGN KEY ([TaskId]) REFERENCES [Tasks]([Id]) ON DELETE CASCADE);
                CREATE INDEX [IX_TaskAttachments_TaskId] ON [TaskAttachments]([TaskId]);
            END;
            IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='FK_Tasks_Workspaces_WorkspaceId')
                ALTER TABLE [Tasks] ADD CONSTRAINT [FK_Tasks_Workspaces_WorkspaceId] FOREIGN KEY ([WorkspaceId]) REFERENCES [Workspaces]([Id]) ON DELETE SET NULL;
            IF OBJECT_ID('TaskPlans', 'U') IS NULL
            BEGIN
                CREATE TABLE [TaskPlans] ([Id] int IDENTITY(1,1) NOT NULL CONSTRAINT [PK_TaskPlans] PRIMARY KEY, [OwnerId] nvarchar(450) NOT NULL, [Name] nvarchar(200) NOT NULL, [CreatedAt] datetime2 NOT NULL, [ConfirmedAt] datetime2 NULL,
                    CONSTRAINT [FK_TaskPlans_AspNetUsers_OwnerId] FOREIGN KEY ([OwnerId]) REFERENCES [AspNetUsers]([Id]) ON DELETE CASCADE);
                CREATE INDEX [IX_TaskPlans_OwnerId_CreatedAt] ON [TaskPlans]([OwnerId],[CreatedAt]);
            END;
            IF OBJECT_ID('TaskPlanItems', 'U') IS NULL
            BEGIN
                CREATE TABLE [TaskPlanItems] ([Id] int IDENTITY(1,1) NOT NULL CONSTRAINT [PK_TaskPlanItems] PRIMARY KEY, [PlanId] int NOT NULL, [TaskId] int NOT NULL, [SortOrder] int NOT NULL, [PlannedFor] datetime2 NULL,
                    CONSTRAINT [FK_TaskPlanItems_TaskPlans_PlanId] FOREIGN KEY ([PlanId]) REFERENCES [TaskPlans]([Id]) ON DELETE CASCADE,
                    CONSTRAINT [FK_TaskPlanItems_Tasks_TaskId] FOREIGN KEY ([TaskId]) REFERENCES [Tasks]([Id]) ON DELETE NO ACTION);
                CREATE UNIQUE INDEX [IX_TaskPlanItems_PlanId_TaskId] ON [TaskPlanItems]([PlanId],[TaskId]);
                CREATE INDEX [IX_TaskPlanItems_TaskId] ON [TaskPlanItems]([TaskId]);
            END;
            """);

        foreach (var role in new[] { "Admin", "Member" })
            if (!await roles.RoleExistsAsync(role))
                await roles.CreateAsync(new IdentityRole(role));

        // Demo password is development-only. Change it immediately for a real deployment.
        const string demoPassword = "TaskFlow@2026";
        var phat = await FindOrCreate("phat.nguyen", "Nguyễn Đức Phát", "phat.nguyen@taskflow.local", "Admin");
        var ducAnh = await FindOrCreate("anh.bui", "Bùi Đức Anh", "anh.bui@taskflow.local", "Member");

        var group = await db.Workspaces.FirstOrDefaultAsync(w => w.LeaderUserId == phat.Id);
        if (group is null)
        {
            group = new Workspace { Name = "TaskFlow - Nhóm đồ án", JoinCode = "TFLOW26A", LeaderUserId = phat.Id };
            db.Workspaces.Add(group);
            await db.SaveChangesAsync();
        }
        if (!await db.WorkspaceMembers.AnyAsync(m => m.WorkspaceId == group.Id && m.UserId == phat.Id)) db.WorkspaceMembers.Add(new WorkspaceMember { WorkspaceId = group.Id, UserId = phat.Id, Role = "Leader" });
        if (!await db.WorkspaceMembers.AnyAsync(m => m.WorkspaceId == group.Id && m.UserId == ducAnh.Id)) db.WorkspaceMembers.Add(new WorkspaceMember { WorkspaceId = group.Id, UserId = ducAnh.Id, Role = "Member" });
        await db.SaveChangesAsync();
        await db.Tasks.Where(t => t.WorkspaceId == null && (t.OwnerId == phat.Id || t.OwnerId == ducAnh.Id))
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.WorkspaceId, group.Id).SetProperty(t => t.CreatedByUserId, phat.Id));

        async Task<AppUser> FindOrCreate(string userName, string displayName, string email, string role)
        {
            var user = await users.FindByNameAsync(userName);
            if (user is null)
            {
                user = new AppUser { UserName = userName, Email = email, EmailConfirmed = true, DisplayName = displayName };
                var result = await users.CreateAsync(user, demoPassword);
                if (!result.Succeeded) throw new InvalidOperationException(string.Join("; ", result.Errors.Select(e => e.Description)));
            }
            if (!await users.IsInRoleAsync(user, role)) await users.AddToRoleAsync(user, role);
            return user;
        }

        if (!await db.Categories.AnyAsync())
        {
            db.Categories.AddRange(
                new Category { OwnerId = phat.Id, Name = "Đồ án", Color = "#4759D6" },
                new Category { OwnerId = phat.Id, Name = "Học tập", Color = "#13A88A" },
                new Category { OwnerId = ducAnh.Id, Name = "Backend", Color = "#F2994A" },
                new Category { OwnerId = ducAnh.Id, Name = "Cá nhân", Color = "#A855F7" });
            await db.SaveChangesAsync();
        }

        if (!await db.Tasks.AnyAsync())
        {
            var categories = await db.Categories.ToListAsync();
            int CategoryId(string name) => categories.Single(c => c.Name == name).Id;
            var today = DateTime.UtcNow.Date;
            db.Tasks.AddRange(
                new TaskItem { OwnerId = phat.Id, CreatedByUserId = phat.Id, WorkspaceId = group.Id, CategoryId = CategoryId("Đồ án"), Title = "Chốt yêu cầu và sơ đồ use case", Description = "Thống nhất chức năng, vai trò và luồng chính của TaskFlow.", DueAt = today.AddDays(1).AddHours(10), Priority = TaskPriority.High },
                new TaskItem { OwnerId = phat.Id, CreatedByUserId = phat.Id, WorkspaceId = group.Id, CategoryId = CategoryId("Đồ án"), Title = "Thiết kế cơ sở dữ liệu SQL Server", Description = "Hoàn thiện quan hệ thành viên, danh mục, công việc và nhắc việc.", DueAt = today.AddDays(2).AddHours(15), Priority = TaskPriority.Urgent, Status = WorkStatus.InProgress },
                new TaskItem { OwnerId = phat.Id, CreatedByUserId = phat.Id, WorkspaceId = group.Id, CategoryId = CategoryId("Học tập"), Title = "Soạn nội dung báo cáo giữa kỳ", DueAt = today.AddDays(5).AddHours(17), Priority = TaskPriority.Normal },
                new TaskItem { OwnerId = ducAnh.Id, CreatedByUserId = phat.Id, WorkspaceId = group.Id, CategoryId = CategoryId("Backend"), Title = "Xây dựng API quản lý công việc", Description = "Tạo các endpoint CRUD, phân trang và lọc theo hạn.", DueAt = today.AddDays(3).AddHours(17), Priority = TaskPriority.High, Status = WorkStatus.InProgress },
                new TaskItem { OwnerId = ducAnh.Id, CreatedByUserId = phat.Id, WorkspaceId = group.Id, CategoryId = CategoryId("Backend"), Title = "Tạo API danh mục công việc", Description = "Không cho xóa danh mục đang được công việc sử dụng.", DueAt = today.AddDays(4).AddHours(17), Priority = TaskPriority.Normal },
                new TaskItem { OwnerId = ducAnh.Id, CreatedByUserId = phat.Id, WorkspaceId = group.Id, CategoryId = CategoryId("Cá nhân"), Title = "Kiểm tra giao diện trên điện thoại", DueAt = today.AddDays(6).AddHours(12), Priority = TaskPriority.Low });
            await db.SaveChangesAsync();
        }
    }
}
