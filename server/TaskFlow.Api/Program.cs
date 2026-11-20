using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using TaskFlow.Api.Data;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllers();
builder.Services.AddOpenApi();
builder.Services.AddDbContext<AppDbContext>(o => o.UseSqlServer(builder.Configuration.GetConnectionString("Default")));
builder.Services.AddIdentityCore<AppUser>(o => { o.User.RequireUniqueEmail = true; o.Password.RequiredLength = 8; o.Password.RequireDigit = true; o.Password.RequireUppercase = false; })
    .AddRoles<IdentityRole>().AddEntityFrameworkStores<AppDbContext>().AddSignInManager();
var key = builder.Configuration["Jwt:Key"] ?? throw new InvalidOperationException("Configure Jwt:Key using user secrets or environment variables.");
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(o => o.TokenValidationParameters = new TokenValidationParameters { ValidateIssuer = true, ValidateAudience = true, ValidateLifetime = true, ValidateIssuerSigningKey = true, ValidIssuer = builder.Configuration["Jwt:Issuer"], ValidAudience = builder.Configuration["Jwt:Audience"], IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key)) });
builder.Services.AddAuthorization();
builder.Services.AddCors(o => o.AddPolicy("mobile", p => p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));
var app = builder.Build();
if (app.Environment.IsDevelopment()) await DatabaseSeeder.InitializeAsync(app.Services);
if (app.Environment.IsDevelopment()) app.MapOpenApi();
app.UseCors("mobile"); app.UseAuthentication(); app.UseAuthorization(); app.MapControllers();
app.Run();
