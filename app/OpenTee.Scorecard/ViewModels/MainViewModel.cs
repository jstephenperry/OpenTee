using System.Collections.ObjectModel;
using Avalonia.Media;
using CommunityToolkit.Mvvm.ComponentModel;
using OpenTee.Scorecard.Data;
using OpenTee.Scorecard.Models;

namespace OpenTee.Scorecard.ViewModels;

public partial class TeeOptionViewModel : ObservableObject
{
    private readonly Action _onToggled;

    public TeeOptionViewModel(TeeOption tee, Action onToggled)
    {
        Tee = tee;
        _onToggled = onToggled;
        _isSelected = tee.IsComplete;
    }

    public TeeOption Tee { get; }

    [ObservableProperty] private bool _isSelected;

    partial void OnIsSelectedChanged(bool value) => _onToggled();

    public bool IsEnabled => Tee.IsComplete;
    public string Name => Tee.Name;
    public IBrush Swatch => Tee.ColorHex is { } hex && Color.TryParse(hex, out var c)
        ? new SolidColorBrush(c) : Brushes.Transparent;
    public string Subtitle => Tee.IsComplete
        ? $"{Tee.ComputedTotalLength:N0} {Tee.Unit} · {Tee.RatingsSummary}"
        : "incomplete — per-hole data not yet in the database";
}

public sealed class CardRowViewModel
{
    public CardRowViewModel(CardRow row)
    {
        Row = row;
        Swatch = row.ColorHex is { } hex && Color.TryParse(hex, out var c)
            ? new SolidColorBrush(c) : Brushes.Transparent;
        Background = row.Kind switch
        {
            CardRowKind.Header => new SolidColorBrush(Color.Parse("#e3e3e3")),
            CardRowKind.Par => new SolidColorBrush(Color.Parse("#f2f2f2")),
            _ => Brushes.White,
        };
        FontWeight = row.Kind is CardRowKind.Header or CardRowKind.Par
            ? Avalonia.Media.FontWeight.SemiBold : Avalonia.Media.FontWeight.Normal;
    }

    public CardRow Row { get; }
    public string Label => Row.Label;
    public IReadOnlyList<string> Cells => Row.Cells;
    public IBrush Swatch { get; }
    public IBrush Background { get; }
    public FontWeight FontWeight { get; }
    public bool HasSwatch => Row.ColorHex is not null;
}

public partial class MainViewModel : ObservableObject
{
    private readonly ScorecardRepository _repo = new();
    private CancellationTokenSource _searchCts = new();
    private ScorecardModel? _fullModel;   // card data for every complete tee of the selected course

    public MainViewModel()
    {
        _ = RunSearchAsync("");
    }

    [ObservableProperty] private string _searchText = "";
    [ObservableProperty] private CourseSummary? _selectedCourse;
    [ObservableProperty] private string _status = $"Database: {ScorecardRepository.ConnectionString}";
    [ObservableProperty] private bool _hasCourse;
    [ObservableProperty] private bool _canPrint;

    public ObservableCollection<CourseSummary> Results { get; } = new();
    public ObservableCollection<TeeOptionViewModel> Tees { get; } = new();
    public ObservableCollection<CardRowViewModel> CardRows { get; } = new();

    partial void OnSearchTextChanged(string value) => _ = DebouncedSearchAsync(value);

    partial void OnSelectedCourseChanged(CourseSummary? value) => _ = LoadCourseAsync(value);

    private async Task DebouncedSearchAsync(string query)
    {
        _searchCts.Cancel();
        _searchCts = new CancellationTokenSource();
        var ct = _searchCts.Token;
        try
        {
            await Task.Delay(250, ct);
            await RunSearchAsync(query, ct);
        }
        catch (OperationCanceledException) { }
    }

    private async Task RunSearchAsync(string query, CancellationToken ct = default)
    {
        try
        {
            var results = await _repo.SearchCoursesAsync(query, ct);
            if (ct.IsCancellationRequested) return;
            Results.Clear();
            foreach (var r in results) Results.Add(r);
        }
        catch (Exception ex)
        {
            Status = $"Database error: {ex.Message}";
        }
    }

    private async Task LoadCourseAsync(CourseSummary? course)
    {
        Tees.Clear();
        CardRows.Clear();
        _fullModel = null;
        HasCourse = course is not null;
        CanPrint = false;
        if (course is null) return;

        try
        {
            var tees = await _repo.GetTeesAsync(course.CourseId);
            var complete = tees.Where(t => t.IsComplete).ToList();
            _fullModel = complete.Count > 0
                ? await _repo.GetScorecardAsync(course, complete)
                : new ScorecardModel(course, Array.Empty<HoleInfo>(), Array.Empty<TeeCard>());

            foreach (var tee in tees)
                Tees.Add(new TeeOptionViewModel(tee, RebuildPreview));
            RebuildPreview();
            Status = $"Database: {ScorecardRepository.ConnectionString}";
        }
        catch (Exception ex)
        {
            Status = $"Database error: {ex.Message}";
        }
    }

    public IReadOnlyList<TeeCard> SelectedTeeCards()
    {
        if (_fullModel is null) return Array.Empty<TeeCard>();
        var selected = Tees.Where(t => t.IsSelected).Select(t => t.Tee.TeeId).ToHashSet();
        return _fullModel.Tees.Where(t => selected.Contains(t.Tee.TeeId)).ToList();
    }

    public ScorecardModel? Model => _fullModel;

    private void RebuildPreview()
    {
        CardRows.Clear();
        var selected = SelectedTeeCards();
        CanPrint = _fullModel is not null && selected.Count > 0;
        if (_fullModel is null || selected.Count == 0) return;
        foreach (var row in CardBuilder.BuildRows(_fullModel, selected))
            CardRows.Add(new CardRowViewModel(row));
    }
}
