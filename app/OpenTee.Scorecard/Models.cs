namespace OpenTee.Scorecard.Models;

/// <summary>A course row in the search results.</summary>
public sealed record CourseSummary(
    Guid CourseId,
    string CourseName,
    string CourseSlug,
    string FacilityName,
    string? City,
    string? StateProvince,
    string Country,
    int HoleCount)
{
    public string Title => FacilityName == CourseName ? FacilityName : $"{FacilityName} — {CourseName}";

    public string Subtitle
    {
        get
        {
            var place = string.Join(", ", new[] { City, StateProvince }.Where(s => !string.IsNullOrWhiteSpace(s)));
            return $"{(place.Length > 0 ? place + " · " : "")}{Country} · {HoleCount} holes";
        }
    }
}

/// <summary>One per-gender rating line for a tee.</summary>
public sealed record TeeRating(string Gender, decimal CourseRating, int SlopeRating);

/// <summary>A tee on the selected course, with data-quality signals from v_tee_summaries.</summary>
public sealed record TeeOption(
    Guid TeeId,
    string Name,
    string? ColorHex,
    string Unit,
    int DisplayOrder,
    bool IsComplete,
    int? ComputedTotalLength,
    IReadOnlyList<TeeRating> Ratings)
{
    public string RatingsSummary => Ratings.Count == 0
        ? "unrated"
        : string.Join(" · ", Ratings.Select(r =>
            $"{(r.Gender == "men" ? "M" : r.Gender == "women" ? "W" : "U")} {r.CourseRating}/{r.SlopeRating}"));
}

/// <summary>Per-hole facts that do not vary by tee (par/SI per gender, name).</summary>
public sealed record HoleInfo(
    int Number,
    string? Name,
    int? ParMen, int? SiMen,
    int? ParWomen, int? SiWomen,
    int? ParUnisex, int? SiUnisex);

/// <summary>One tee's published lengths, keyed by hole number.</summary>
public sealed record TeeCard(TeeOption Tee, IReadOnlyDictionary<int, int> Lengths);

/// <summary>Everything needed to render a scorecard for a course.</summary>
public sealed record ScorecardModel(
    CourseSummary Course,
    IReadOnlyList<HoleInfo> Holes,
    IReadOnlyList<TeeCard> Tees);
