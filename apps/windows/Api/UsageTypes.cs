namespace ClaudeBar.Api;

public enum UsageStatus
{
    Ok,
    Offline,
    RateLimited,
    Unauthenticated,
}

public sealed record UsageBucket(double Percent, DateTimeOffset? ResetsAt);

public sealed record UsageSnapshot(
    UsageBucket Session,
    UsageBucket Weekly,
    UsageStatus Status,
    DateTimeOffset FetchedAt)
{
    public static UsageSnapshot Empty(UsageStatus status) => new(
        new UsageBucket(0, null),
        new UsageBucket(0, null),
        status,
        DateTimeOffset.UtcNow);
}
