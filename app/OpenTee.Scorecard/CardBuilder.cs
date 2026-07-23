using OpenTee.Scorecard.Models;

namespace OpenTee.Scorecard;

public enum CardRowKind { Header, HoleNames, Tee, Par, StrokeIndex, Score }

/// <summary>One horizontal row of the scorecard table (label + one cell per column).</summary>
public sealed record CardRow(string Label, string? ColorHex, IReadOnlyList<string> Cells, CardRowKind Kind);

/// <summary>
/// Turns a ScorecardModel into the row/column layout of a printed card:
/// holes as columns (with OUT/IN/TOT for 18-hole courses), one row per tee,
/// then par and stroke-index rows per published gender.
/// Shared by the on-screen preview and the PDF so they can never disagree.
/// </summary>
public static class CardBuilder
{
    public static IReadOnlyList<string> ColumnLabels(ScorecardModel model)
    {
        var cols = new List<string>();
        bool split = model.Course.HoleCount == 18;
        foreach (var h in model.Holes)
        {
            if (split && h.Number == 10) cols.Add("OUT");
            cols.Add(h.Number.ToString());
        }
        if (split) cols.Add("IN");
        cols.Add("TOT");
        return cols;
    }

    public static IReadOnlyList<CardRow> BuildRows(ScorecardModel model, IReadOnlyList<TeeCard> selectedTees, int scoreRows = 0)
    {
        bool split = model.Course.HoleCount == 18;
        var rows = new List<CardRow>
        {
            new("HOLE", null, ColumnLabels(model), CardRowKind.Header),
        };

        if (model.Holes.Any(h => !string.IsNullOrWhiteSpace(h.Name)))
            rows.Add(Row("NAME", null, h => Abbreviate(h.Name), null, null, null, CardRowKind.HoleNames));

        foreach (var tee in selectedTees)
        {
            rows.Add(Row(tee.Tee.Name.ToUpperInvariant(), tee.Tee.ColorHex,
                h => tee.Lengths.TryGetValue(h.Number, out var l) ? l.ToString() : "",
                hs => hs.Sum(h => tee.Lengths.TryGetValue(h.Number, out var l) ? l : 0).ToString(),
                hs => hs.Sum(h => tee.Lengths.TryGetValue(h.Number, out var l) ? l : 0).ToString(),
                hs => hs.Sum(h => tee.Lengths.TryGetValue(h.Number, out var l) ? l : 0).ToString(),
                CardRowKind.Tee));
        }

        AddParAndSi(rows, model, "PAR", h => h.ParUnisex, h => h.SiUnisex, "HCP");
        AddParAndSi(rows, model, "PAR", h => h.ParMen, h => h.SiMen, "HCP");
        AddParAndSi(rows, model, "PAR (W)", h => h.ParWomen, h => h.SiWomen, "HCP (W)");

        for (var i = 1; i <= scoreRows; i++)
            rows.Add(Row($"PLAYER {i}", null, _ => "", null, null, null, CardRowKind.Score));

        return rows;

        CardRow Row(string label, string? hex,
            Func<HoleInfo, string> cell,
            Func<IEnumerable<HoleInfo>, string>? outTotal,
            Func<IEnumerable<HoleInfo>, string>? inTotal,
            Func<IEnumerable<HoleInfo>, string>? grandTotal,
            CardRowKind kind)
        {
            var cells = new List<string>();
            var front = model.Holes.Where(h => h.Number <= 9).ToList();
            var back = model.Holes.Where(h => h.Number > 9).ToList();
            foreach (var h in model.Holes)
            {
                if (split && h.Number == 10) cells.Add(outTotal?.Invoke(front) ?? "");
                cells.Add(cell(h));
            }
            if (split) cells.Add(inTotal?.Invoke(back) ?? "");
            cells.Add(grandTotal?.Invoke(model.Holes) ?? "");
            return new CardRow(label, hex, cells, kind);
        }

        void AddParAndSi(List<CardRow> rows, ScorecardModel m, string parLabel,
            Func<HoleInfo, int?> par, Func<HoleInfo, int?> si, string siLabel)
        {
            if (m.Holes.Any(h => par(h) is not null))
                rows.Add(Row(parLabel, null,
                    h => par(h)?.ToString() ?? "",
                    hs => hs.Sum(h => par(h) ?? 0).ToString(),
                    hs => hs.Sum(h => par(h) ?? 0).ToString(),
                    hs => hs.Sum(h => par(h) ?? 0).ToString(),
                    CardRowKind.Par));
            if (m.Holes.Any(h => si(h) is not null))
                rows.Add(Row(siLabel, null, h => si(h)?.ToString() ?? "", null, null, null, CardRowKind.StrokeIndex));
        }
    }

    /// <summary>The unit note for the card footer ("all lengths in yards"), or per-tee if mixed.</summary>
    public static string UnitNote(IReadOnlyList<TeeCard> selectedTees)
    {
        var units = selectedTees.Select(t => t.Tee.Unit).Distinct().ToList();
        return units.Count switch
        {
            0 => "",
            1 => $"All lengths in {units[0]}.",
            _ => string.Join("; ", selectedTees.Select(t => $"{t.Tee.Name}: {t.Tee.Unit}")) + ".",
        };
    }

    public static string RatingsNote(IReadOnlyList<TeeCard> selectedTees)
    {
        var rated = selectedTees.Where(t => t.Tee.Ratings.Count > 0).ToList();
        if (rated.Count == 0) return "No published course rating.";
        return string.Join("   ", rated.Select(t =>
            $"{t.Tee.Name}: " + string.Join(" · ", t.Tee.Ratings.Select(r =>
                $"{Cap(r.Gender)} {r.CourseRating}/{r.SlopeRating}"))));

        static string Cap(string g) => g switch
        {
            "men" => "Men", "women" => "Women", _ => "Rating",
        };
    }

    private static string Abbreviate(string? name) =>
        string.IsNullOrWhiteSpace(name) ? "" : name.Length <= 9 ? name : name[..8] + "…";
}
