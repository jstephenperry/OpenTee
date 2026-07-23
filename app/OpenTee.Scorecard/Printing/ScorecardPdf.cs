using OpenTee.Scorecard.Models;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace OpenTee.Scorecard.Printing;

/// <summary>
/// Renders a print-ready scorecard PDF (landscape Letter). Avalonia has no
/// cross-platform print API, so the app prints by handing this PDF to the
/// OS default viewer's print dialog.
/// </summary>
public static class ScorecardPdf
{
    public static void Write(ScorecardModel model, IReadOnlyList<TeeCard> selectedTees, string path)
    {
        var rows = CardBuilder.BuildRows(model, selectedTees, scoreRows: 4);
        var columnCount = rows[0].Cells.Count;

        Document.Create(doc => doc.Page(page =>
        {
            page.Size(PageSizes.Letter.Landscape());
            page.Margin(28);
            page.DefaultTextStyle(t => t.FontSize(9));

            page.Header().Column(col =>
            {
                col.Item().Text(model.Course.Title).FontSize(18).Bold();
                col.Item().Text(model.Course.Subtitle).FontSize(10).FontColor(Colors.Grey.Darken1);
                col.Item().PaddingTop(6);
            });

            page.Content().Table(table =>
            {
                table.ColumnsDefinition(cols =>
                {
                    cols.ConstantColumn(78);
                    for (var i = 0; i < columnCount; i++) cols.RelativeColumn();
                });

                foreach (var row in rows)
                {
                    var (bg, bold, fontSize) = row.Kind switch
                    {
                        CardRowKind.Header => (Colors.Grey.Lighten2, true, 9f),
                        CardRowKind.Par => (Colors.Grey.Lighten4, true, 9f),
                        CardRowKind.HoleNames => (Colors.White, false, 5.5f),
                        CardRowKind.StrokeIndex => (Colors.White, false, 8f),
                        _ => (Colors.White, false, 9f),
                    };

                    table.Cell().Element(c => Cell(c, bg)).Row(r =>
                    {
                        if (row.ColorHex is not null)
                            r.AutoItem().PaddingRight(4).PaddingTop(1).Width(8).Height(8)
                                .Background(Color.FromHex(row.ColorHex)).Border(0.5f).BorderColor(Colors.Grey.Darken2);
                        r.RelativeItem().Text(row.Label).Bold().FontSize(row.Kind == CardRowKind.HoleNames ? 6f : 8.5f);
                    });

                    foreach (var (cell, i) in row.Cells.Select((c, i) => (c, i)))
                    {
                        var isTotalCol = rows[0].Cells[i] is "OUT" or "IN" or "TOT";
                        var cellBg = row.Kind == CardRowKind.Header ? bg
                            : isTotalCol ? Colors.Grey.Lighten3
                            : bg;
                        var emphasize = bold || isTotalCol;
                        table.Cell().Element(c => Cell(c, cellBg).AlignCenter().AlignMiddle()).Text(t =>
                        {
                            var span = t.Span(cell).FontSize(fontSize);
                            if (emphasize) span.SemiBold();
                        });
                    }
                }

                static QuestPDF.Infrastructure.IContainer Cell(QuestPDF.Infrastructure.IContainer container, Color background) =>
                    container.Border(0.5f).BorderColor(Colors.Grey.Darken1)
                        .Background(background).PaddingVertical(4).PaddingHorizontal(2);
            });

            page.Footer().PaddingTop(8).Column(col =>
            {
                col.Item().Text(CardBuilder.RatingsNote(selectedTees)).FontSize(8);
                col.Item().Text(CardBuilder.UnitNote(selectedTees)).FontSize(8).FontColor(Colors.Grey.Darken1);
                col.Item().Text($"OpenTee · course data as published · generated {DateTime.Now:yyyy-MM-dd}")
                    .FontSize(7).FontColor(Colors.Grey.Darken1);
            });
        })).GeneratePdf(path);
    }
}
