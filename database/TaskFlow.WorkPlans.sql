-- Apply this idempotent script to an existing TaskFlow SQL Server database
-- before deploying an API build that uses work plans.
IF OBJECT_ID(N'dbo.TaskPlans', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.TaskPlans
    (
        Id int IDENTITY(1,1) NOT NULL CONSTRAINT PK_TaskPlans PRIMARY KEY,
        OwnerId nvarchar(450) NOT NULL,
        Name nvarchar(200) NOT NULL,
        CreatedAt datetime2 NOT NULL,
        ConfirmedAt datetime2 NULL,
        CONSTRAINT FK_TaskPlans_AspNetUsers_OwnerId
            FOREIGN KEY (OwnerId) REFERENCES dbo.AspNetUsers(Id) ON DELETE CASCADE
    );
    CREATE INDEX IX_TaskPlans_OwnerId_CreatedAt ON dbo.TaskPlans(OwnerId, CreatedAt);
END;

IF OBJECT_ID(N'dbo.TaskPlanItems', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.TaskPlanItems
    (
        Id int IDENTITY(1,1) NOT NULL CONSTRAINT PK_TaskPlanItems PRIMARY KEY,
        PlanId int NOT NULL,
        TaskId int NOT NULL,
        SortOrder int NOT NULL,
        PlannedFor datetime2 NULL,
        CONSTRAINT FK_TaskPlanItems_TaskPlans_PlanId
            FOREIGN KEY (PlanId) REFERENCES dbo.TaskPlans(Id) ON DELETE CASCADE,
        CONSTRAINT FK_TaskPlanItems_Tasks_TaskId
            FOREIGN KEY (TaskId) REFERENCES dbo.Tasks(Id) ON DELETE NO ACTION
    );
    CREATE UNIQUE INDEX IX_TaskPlanItems_PlanId_TaskId ON dbo.TaskPlanItems(PlanId, TaskId);
    CREATE INDEX IX_TaskPlanItems_TaskId ON dbo.TaskPlanItems(TaskId);
END;
