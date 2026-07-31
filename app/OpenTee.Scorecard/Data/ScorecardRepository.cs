using Npgsql;
using OpenTee.Scorecard.Models;

namespace OpenTee.Scorecard.Data;

/// <summary>
/// Read-only data access against the OpenTee schema. Connection string comes
/// from OPENTEE_DB (falling back to a local dev database).
/// </summary>
public sealed class ScorecardRepository
{
    public static string ConnectionString { get; } =
        Environment.GetEnvironmentVariable("OPENTEE_DB")
        ?? "Host=localhost;Database=opentee_dev;Username=postgres";

    private readonly NpgsqlDataSource _dataSource = NpgsqlDataSource.Create(ConnectionString);

    public async Task<IReadOnlyList<CourseSummary>> SearchCoursesAsync(string query, CancellationToken ct = default)
    {
        const string sql = """
            SELECT c.id, c.name, c.slug, f.name, f.city, f.state_province, f.country, c.hole_count
            FROM courses c
            JOIN facilities f ON f.id = c.facility_id
            WHERE c.status = 'active' AND f.status = 'active'
              AND ($1 = '' OR f.name ILIKE '%' || $1 || '%'
                          OR c.name ILIKE '%' || $1 || '%'
                          OR f.city ILIKE '%' || $1 || '%')
            ORDER BY f.name, c.name
            LIMIT 50
            """;
        await using var cmd = _dataSource.CreateCommand(sql);
        cmd.Parameters.AddWithValue(query.Trim());
        var results = new List<CourseSummary>();
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            results.Add(new CourseSummary(
                reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.GetString(3),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetString(5),
                reader.GetString(6), reader.GetInt16(7)));
        }
        return results;
    }

    public async Task<IReadOnlyList<TeeOption>> GetTeesAsync(Guid courseId, CancellationToken ct = default)
    {
        const string sql = """
            SELECT t.id, t.name, t.color_hex, t.unit, t.display_order, s.is_complete, s.computed_total_length
            FROM tees t
            JOIN v_tee_summaries s ON s.tee_id = t.id
            WHERE t.course_id = $1
            ORDER BY t.display_order
            """;
        var tees = new List<(Guid Id, string Name, string? Hex, string Unit, int Order, bool Complete, int? Total)>();
        await using (var cmd = _dataSource.CreateCommand(sql))
        {
            cmd.Parameters.AddWithValue(courseId);
            await using var reader = await cmd.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                tees.Add((reader.GetGuid(0), reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2).Trim(),
                    reader.GetString(3), reader.GetInt16(4), reader.GetBoolean(5),
                    reader.IsDBNull(6) ? null : reader.GetInt32(6)));
            }
        }

        var ratings = new Dictionary<Guid, List<TeeRating>>();
        const string ratingsSql = """
            SELECT tee_id, gender, course_rating, slope_rating
            FROM tee_ratings WHERE tee_id = ANY($1)
            ORDER BY tee_id, gender
            """;
        await using (var cmd = _dataSource.CreateCommand(ratingsSql))
        {
            cmd.Parameters.AddWithValue(tees.Select(t => t.Id).ToArray());
            await using var reader = await cmd.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                var teeId = reader.GetGuid(0);
                if (!ratings.TryGetValue(teeId, out var list)) ratings[teeId] = list = new List<TeeRating>();
                list.Add(new TeeRating(reader.GetString(1), reader.GetDecimal(2), reader.GetInt16(3)));
            }
        }

        return tees
            .Select(t => new TeeOption(t.Id, t.Name, t.Hex, t.Unit, t.Order, t.Complete, t.Total,
                ratings.TryGetValue(t.Id, out var r) ? r : Array.Empty<TeeRating>()))
            .ToList();
    }

    /// <summary>Loads the full card (holes + lengths) for the given tees of a course.</summary>
    public async Task<ScorecardModel> GetScorecardAsync(CourseSummary course, IReadOnlyList<TeeOption> tees, CancellationToken ct = default)
    {
        const string sql = """
            SELECT hole_number, hole_name, tee_id, length,
                   par_men, stroke_index_men, par_women, stroke_index_women,
                   par_unisex, stroke_index_unisex
            FROM v_scorecards
            WHERE course_id = $1 AND tee_id = ANY($2)
            ORDER BY hole_number, display_order
            """;
        var holes = new SortedDictionary<int, HoleInfo>();
        var lengths = tees.ToDictionary(t => t.TeeId, _ => new Dictionary<int, int>());

        await using var cmd = _dataSource.CreateCommand(sql);
        cmd.Parameters.AddWithValue(course.CourseId);
        cmd.Parameters.AddWithValue(tees.Select(t => t.TeeId).ToArray());
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            int hole = reader.GetInt16(0);
            holes.TryAdd(hole, new HoleInfo(hole,
                reader.IsDBNull(1) ? null : reader.GetString(1),
                Int(reader, 4), Int(reader, 5), Int(reader, 6), Int(reader, 7), Int(reader, 8), Int(reader, 9)));
            var teeId = reader.GetGuid(2);
            lengths[teeId][hole] = reader.GetInt32(3);
        }

        return new ScorecardModel(course, holes.Values.ToList(),
            tees.Select(t => new TeeCard(t, lengths[t.TeeId])).ToList());

        static int? Int(NpgsqlDataReader r, int i) => r.IsDBNull(i) ? null : r.GetInt16(i);
    }

    /// <summary>
    /// Looks a course up by slug directly. Deliberately NOT built on SearchCoursesAsync,
    /// which is LIMITed for the UI list and would silently fail to find courses beyond
    /// that limit. Slugs are unique per facility, so an unqualified slug can legitimately
    /// match more than once; pass "facility-slug/course-slug" to disambiguate.
    /// </summary>
    public async Task<CourseSummary?> FindCourseBySlugAsync(string slug, CancellationToken ct = default)
    {
        string? facilitySlug = null;
        var parts = slug.Split('/', 2);
        if (parts.Length == 2) { facilitySlug = parts[0]; slug = parts[1]; }

        const string sql = """
            SELECT c.id, c.name, c.slug, f.name, f.city, f.state_province, f.country, c.hole_count
            FROM courses c
            JOIN facilities f ON f.id = c.facility_id
            WHERE c.slug = $1 AND c.status = 'active' AND f.status = 'active'
              AND ($2::text IS NULL OR f.slug = $2)
            ORDER BY f.name
            """;
        await using var cmd = _dataSource.CreateCommand(sql);
        cmd.Parameters.AddWithValue(slug);
        cmd.Parameters.AddWithValue((object?)facilitySlug ?? DBNull.Value);

        var matches = new List<CourseSummary>();
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            matches.Add(new CourseSummary(
                reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.GetString(3),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetString(5),
                reader.GetString(6), reader.GetInt16(7)));
        }

        if (matches.Count > 1)
        {
            Console.Error.WriteLine(
                $"note: '{slug}' matches {matches.Count} courses; using {matches[0].Title}. " +
                "Qualify it as <facility-slug>/<course-slug> to pick a different one:");
            foreach (var m in matches)
                Console.Error.WriteLine($"  {m.CourseSlug} @ {m.FacilityName} ({m.City})");
        }
        return matches.FirstOrDefault();
    }
}
