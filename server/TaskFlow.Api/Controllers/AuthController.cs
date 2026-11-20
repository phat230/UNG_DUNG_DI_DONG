using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Google.Apis.Auth;
using Microsoft.IdentityModel.Tokens;
using TaskFlow.Api.Data;
using TaskFlow.Api.Models;
namespace TaskFlow.Api.Controllers;

public record RegisterRequest(string UserName, string DisplayName, string Email, string Password, string AccountType = "Personal", string? GroupName = null);
public record LoginRequest(string UserName, string Password);
public record ChangePasswordRequest(string CurrentPassword, string NewPassword);
public record GoogleTokenRequest(string IdToken);
public record ForgotPasswordRequest(string Email);
public record ResetPasswordRequest(string Email, string Token, string NewPassword);

[ApiController, Route("api/auth")]
public class AuthController(UserManager<AppUser> users, SignInManager<AppUser> signIn, IConfiguration config, AppDbContext db, IWebHostEnvironment environment, ILogger<AuthController> logger) : ControllerBase
{
    [HttpPost("register")]
    public async Task<IActionResult> Register(RegisterRequest input)
    {
        var user = new AppUser { UserName = input.UserName.Trim(), DisplayName = input.DisplayName.Trim(), Email = input.Email.Trim() };
        var result = await users.CreateAsync(user, input.Password);
        if (!result.Succeeded) return BadRequest(result.Errors.Select(e => e.Description));
        await users.AddToRoleAsync(user, "Member");
        object? group = null;
        if (string.Equals(input.AccountType, "Group", StringComparison.OrdinalIgnoreCase))
        {
            var workspace = new Workspace { Name = string.IsNullOrWhiteSpace(input.GroupName) ? $"Nhóm của {user.DisplayName}" : input.GroupName.Trim(), JoinCode = Guid.NewGuid().ToString("N")[..8].ToUpperInvariant(), LeaderUserId = user.Id };
            db.Workspaces.Add(workspace);
            await db.SaveChangesAsync();
            db.WorkspaceMembers.Add(new WorkspaceMember { WorkspaceId = workspace.Id, UserId = user.Id, Role = "Leader" });
            await db.SaveChangesAsync();
            group = new { workspace.Id, workspace.Name, workspace.JoinCode };
        }
        return Ok(new { user.Id, user.UserName, user.DisplayName, user.Email, role = "Member", group });
    }

    [HttpPost("login")]
    public async Task<IActionResult> Login(LoginRequest input)
    {
        var user = await users.FindByNameAsync(input.UserName) ?? await users.FindByEmailAsync(input.UserName);
        if (user is null || !user.IsActive || !(await signIn.CheckPasswordSignInAsync(user, input.Password, false)).Succeeded) return Unauthorized(new { message = "Tên đăng nhập hoặc mật khẩu không đúng." });
        var roles = await users.GetRolesAsync(user);
        return Ok(CreateSession(user, roles));
    }

    [HttpPost("forgot-password")]
    public async Task<IActionResult> ForgotPassword(ForgotPasswordRequest input)
    {
        const string message = "Nếu email thuộc một tài khoản TaskFlow, hướng dẫn đặt lại mật khẩu sẽ được gửi.";
        var user = await users.FindByEmailAsync(input.Email.Trim());
        if (user is null || string.IsNullOrWhiteSpace(user.Email)) return Ok(new { message });

        var token = await users.GeneratePasswordResetTokenAsync(user);
        var smtp = config.GetSection("Smtp");
        var host = smtp["Host"];
        if (!string.IsNullOrWhiteSpace(host))
        {
            try
            {
                using var mail = new System.Net.Mail.MailMessage
                {
                    From = new System.Net.Mail.MailAddress(smtp["From"] ?? smtp["Username"] ?? "noreply@taskflow.local", "TaskFlow"),
                    Subject = "Đặt lại mật khẩu TaskFlow",
                    Body = $"Mã đặt lại mật khẩu của bạn:\n\n{token}\n\nMã này chỉ dùng một lần. Nếu bạn không yêu cầu, hãy bỏ qua email này.",
                    IsBodyHtml = false
                };
                mail.To.Add(user.Email);
                using var client = new System.Net.Mail.SmtpClient(host, int.TryParse(smtp["Port"], out var port) ? port : 587)
                {
                    EnableSsl = !bool.TryParse(smtp["EnableSsl"], out var enableSsl) || enableSsl,
                    DeliveryMethod = System.Net.Mail.SmtpDeliveryMethod.Network,
                    UseDefaultCredentials = false,
                    Credentials = new System.Net.NetworkCredential(smtp["Username"], smtp["Password"])
                };
                await client.SendMailAsync(mail);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Failed to send password reset email.");
                return StatusCode(StatusCodes.Status503ServiceUnavailable, new { message = "Chưa gửi được email đặt lại mật khẩu. Hãy thử lại sau." });
            }
        }
        else if (!environment.IsDevelopment())
        {
            logger.LogError("SMTP is not configured; password reset email cannot be sent.");
            return StatusCode(StatusCodes.Status503ServiceUnavailable, new { message = "Chức năng email đặt lại mật khẩu chưa được cấu hình." });
        }

        // In local development only, return the Identity token so the feature can be exercised before SMTP is configured.
        if (environment.IsDevelopment() && string.IsNullOrWhiteSpace(host)) return Ok(new { message, debugResetToken = token });
        return Ok(new { message });
    }

    [HttpPost("reset-password")]
    public async Task<IActionResult> ResetPassword(ResetPasswordRequest input)
    {
        var user = await users.FindByEmailAsync(input.Email.Trim());
        if (user is null) return BadRequest(new { message = "Email hoặc mã đặt lại mật khẩu không hợp lệ." });
        var result = await users.ResetPasswordAsync(user, input.Token, input.NewPassword);
        return result.Succeeded
            ? Ok(new { message = "Mật khẩu đã được cập nhật. Bạn có thể đăng nhập bằng mật khẩu mới." })
            : BadRequest(new { message = string.Join(" ", result.Errors.Select(e => e.Description)) });
    }
    [HttpPost("google/login")]
    public async Task<IActionResult> GoogleLogin(GoogleTokenRequest input)
    {
        var payload = await ValidateGoogleToken(input.IdToken);
        if (payload is null) return Unauthorized(new { message = "Token Google không hợp lệ hoặc chưa cấu hình OAuth Client ID." });
        var user = await users.Users.FirstOrDefaultAsync(u => u.GoogleSubject == payload.Subject);
        if (user is null)
        {
            if (string.IsNullOrWhiteSpace(payload.Email) || payload.EmailVerified != true)
                return Unauthorized(new { message = "Google cần cung cấp email đã xác thực." });
            if (await users.FindByEmailAsync(payload.Email) is not null)
                return Conflict(new { message = "Email này đã có tài khoản TaskFlow. Hãy đăng nhập bằng mật khẩu rồi liên kết Google trong hồ sơ." });
            var baseName = payload.Email.Split('@')[0];
            var userName = $"google_{Guid.NewGuid():N}"[..18];
            user = new AppUser { UserName = userName, Email = payload.Email, EmailConfirmed = true, DisplayName = string.IsNullOrWhiteSpace(payload.Name) ? baseName : payload.Name, GoogleSubject = payload.Subject };
            var created = await users.CreateAsync(user);
            if (!created.Succeeded) return BadRequest(new { message = "Không thể tạo tài khoản Google." });
            await users.AddToRoleAsync(user, "Member");
        }
        if (!user.IsActive) return Unauthorized(new { message = "Tài khoản đã bị khóa." });
        var roles = await users.GetRolesAsync(user);
        return Ok(CreateSession(user, roles));
    }

    [Authorize, HttpPost("google/link")]
    public async Task<IActionResult> LinkGoogle(GoogleTokenRequest input)
    {
        var payload = await ValidateGoogleToken(input.IdToken);
        if (payload is null || payload.EmailVerified != true) return Unauthorized(new { message = "Token Google không hợp lệ hoặc email chưa xác thực." });
        var user = await users.GetUserAsync(User);
        if (user is null) return Unauthorized();
        var linkedUser = await users.Users.FirstOrDefaultAsync(u => u.GoogleSubject == payload.Subject);
        if (linkedUser is not null && linkedUser.Id != user.Id)
            return Conflict(new { message = "Tài khoản Google này đã được liên kết với tài khoản TaskFlow khác." });
        if (!string.IsNullOrEmpty(user.GoogleSubject) && user.GoogleSubject != payload.Subject)
            return Conflict(new { message = "Tài khoản TaskFlow này đã liên kết với một tài khoản Google khác." });
        user.GoogleSubject = payload.Subject;
        var update = await users.UpdateAsync(user);
        if (!update.Succeeded) return BadRequest(update.Errors.Select(e => e.Description));
        return Ok(new { linked = true, email = payload.Email });
    }

    [Authorize, HttpGet("me")]
    public async Task<IActionResult> Me()
    {
        var user = await users.GetUserAsync(User);
        return user is null ? Unauthorized() : Ok(new { user.Id, user.UserName, user.DisplayName, user.Email, googleLinked = !string.IsNullOrEmpty(user.GoogleSubject) });
    }

    async Task<GoogleJsonWebSignature.Payload?> ValidateGoogleToken(string idToken)
    {
        var clientIds = (config["Google:ClientIds"] ?? "").Split([',', ';'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (clientIds.Length == 0 || string.IsNullOrWhiteSpace(idToken)) return null;
        try
        {
            return await GoogleJsonWebSignature.ValidateAsync(idToken, new GoogleJsonWebSignature.ValidationSettings { Audience = clientIds });
        }
        catch (InvalidJwtException) { return null; }
    }

    object CreateSession(AppUser user, IList<string> roles)
    {
        var claims = new List<Claim> { new(ClaimTypes.NameIdentifier, user.Id), new(ClaimTypes.Name, user.UserName!), new(ClaimTypes.Email, user.Email ?? ""), new("display_name", user.DisplayName) };
        claims.AddRange(roles.Select(r => new Claim(ClaimTypes.Role, r)));
        var signingKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(config["Jwt:Key"]!));
        var token = new JwtSecurityToken(config["Jwt:Issuer"], config["Jwt:Audience"], claims, expires: DateTime.UtcNow.AddHours(12), signingCredentials: new SigningCredentials(signingKey, SecurityAlgorithms.HmacSha256));
        return new { token = new JwtSecurityTokenHandler().WriteToken(token), expiresAt = token.ValidTo, user = new { user.Id, user.UserName, user.DisplayName, user.Email, roles } };
    }

    [Authorize, HttpPost("change-password")]
    public async Task<IActionResult> ChangePassword(ChangePasswordRequest input)
    {
        var user = await users.GetUserAsync(User); if (user is null) return Unauthorized();
        var result = await users.ChangePasswordAsync(user, input.CurrentPassword, input.NewPassword);
        return result.Succeeded ? NoContent() : BadRequest(new { message = string.Join(" ", result.Errors.Select(e => e.Description)) });
    }
}


