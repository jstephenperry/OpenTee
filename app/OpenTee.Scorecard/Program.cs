using Avalonia;
using QuestPDF.Infrastructure;

namespace OpenTee.Scorecard;

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        QuestPDF.Settings.License = LicenseType.Community;

        // Headless mode: generate a scorecard PDF without a display.
        //   dotnet run -- --pdf <course-slug> [--out file.pdf] [--tees Blue,White]
        if (args.Contains("--pdf"))
            return PdfCli.Run(args);

        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        return 0;
    }

    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
}
