using System.Diagnostics;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using OpenTee.Scorecard.Printing;
using OpenTee.Scorecard.ViewModels;

namespace OpenTee.Scorecard.Views;

public partial class MainWindow : Window
{
    public MainWindow() => InitializeComponent();

    private async void OnPrintClicked(object? sender, RoutedEventArgs e)
    {
        if (DataContext is not MainViewModel vm || vm.Model is null) return;
        var selected = vm.SelectedTeeCards();
        if (selected.Count == 0) return;

        var file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Save scorecard PDF",
            SuggestedFileName = $"{vm.Model.Course.CourseSlug}-scorecard.pdf",
            DefaultExtension = "pdf",
            FileTypeChoices = new[] { new FilePickerFileType("PDF") { Patterns = new[] { "*.pdf" } } },
        });
        if (file is null) return;

        try
        {
            var path = file.Path.LocalPath;
            ScorecardPdf.Write(vm.Model, selected, path);
            vm.Status = $"Saved {path}";
            // Hand the PDF to the OS default viewer; the user prints from its dialog.
            Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            vm.Status = $"PDF error: {ex.Message}";
        }
    }
}
