using OpenTee.Scorecard.Data;
using OpenTee.Scorecard.Printing;

namespace OpenTee.Scorecard;

/// <summary>
/// Headless PDF generation: `--pdf <course-slug> [--out file.pdf] [--tees Blue,White]`.
/// Used for scripted printing and for verifying the data->PDF pipeline in CI.
/// </summary>
internal static class PdfCli
{
    public static int Run(string[] args)
    {
        try
        {
            return RunAsync(args).GetAwaiter().GetResult();
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"error: {ex.Message}");
            return 1;
        }
    }

    private static async Task<int> RunAsync(string[] args)
    {
        var slug = args.SkipWhile(a => a != "--pdf").Skip(1).FirstOrDefault(a => !a.StartsWith("--"));
        if (slug is null)
        {
            Console.Error.WriteLine("usage: --pdf <course-slug> [--out file.pdf] [--tees Blue,White]");
            return 2;
        }
        var output = ArgValue(args, "--out") ?? $"{slug}-scorecard.pdf";
        var teeFilter = ArgValue(args, "--tees")?.Split(',', StringSplitOptions.TrimEntries);

        var repo = new ScorecardRepository();
        var course = await repo.FindCourseBySlugAsync(slug);
        if (course is null)
        {
            Console.Error.WriteLine($"error: no active course with slug '{slug}'");
            return 1;
        }

        var tees = (await repo.GetTeesAsync(course.CourseId)).Where(t => t.IsComplete).ToList();
        if (teeFilter is not null)
            tees = tees.Where(t => teeFilter.Contains(t.Name, StringComparer.OrdinalIgnoreCase)).ToList();
        if (tees.Count == 0)
        {
            Console.Error.WriteLine("error: no complete tees match the selection");
            return 1;
        }

        var model = await repo.GetScorecardAsync(course, tees);
        ScorecardPdf.Write(model, model.Tees, output);
        Console.WriteLine($"wrote {output}: {course.Title}, {course.HoleCount} holes, " +
                          $"tees: {string.Join(", ", tees.Select(t => t.Name))}");
        return 0;
    }

    private static string? ArgValue(string[] args, string name)
    {
        var i = Array.IndexOf(args, name);
        return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
    }
}
