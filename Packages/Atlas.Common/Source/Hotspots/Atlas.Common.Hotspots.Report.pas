unit Atlas.Common.Hotspots.Report;

// Ausgaben der Hotspots (#1354): JSON (Format 1, für das Fenster
// „Atlas-Hotspots“ und atlas/hotspots), Markdown, eigenständige HTML-Seite mit
// Blasendiagramm (x = Änderungen, y = Komplexität, Größe = Zeilen; SVG ohne
// Skript) und der kompakte Text für get_hotspots.
//
// JSON:
//   {"format":1,"title","vcs":"git"|"svn","head","months","since":ISO,
//    "commits":n,"level":"unit"|"method",
//    "units":[Eintrag…],"methods":[Eintrag…],"coupling":[Paar…]}
//   Eintrag {"unit","path","method"?,"line","endLine","changes","authors",
//    "authorNames":[…],"added","deleted" (-1 unbekannt),"lastChange":ISO,
//    "complexity","lines","pastComplexity" (-1 unbekannt),"trend",
//    "score","history":[{"revision","author","date","summary","added",
//    "deleted"}]}
//   Paar {"first":{"unit","path"},"second":{…},"shared","firstChanges",
//    "secondChanges","ratio"}
//   Pfade relativ zur Wurzel der Arbeitskopie mit "/"; die Wurzel selbst
//   steht nur in der Antwort des Servers, nicht im Bericht.

interface

uses
  System.SysUtils,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.Analysis;

type
{$SCOPEDENUMS ON}
  /// <summary>Abschnitt des Textes für get_hotspots.</summary>
  THotspotSection = (Hotspots, Coupling);
{$SCOPEDENUMS OFF}

  THotspotReport = record
  public const
    /// <summary>Vorgabe für die Länge der Listen in get_hotspots.</summary>
    TextLimit = 20;
    /// <summary>Höchstens so viele Blasen im HTML-Bericht.</summary>
    ChartLimit = 200;
    JsonFormat = 1;
  public
    class function ParseSection(const AText: string; out ASection: THotspotSection): Boolean; static;
    class function SectionName(ASection: THotspotSection): string; static;
    class function Json(const AResult: THotspotResult): string; static;
    class function Markdown(const AResult: THotspotResult): string; static;
    class function Html(const AResult: THotspotResult): string; static;
    /// <summary>HTML für .html/.htm, JSON für .json, sonst Markdown.</summary>
    class function ForFile(const AResult: THotspotResult; const AFileName: string): string; static;
    /// <summary>Kompakter Text eines Abschnitts; Listen auf ALimit gekürzt mit Gesamtzahl.</summary>
    class function Text(const AResult: THotspotResult; ASection: THotspotSection; ALimit: Integer): string; static;
    /// <summary>"Git, 12 Monate seit 2025-10-29, 431 Commits".</summary>
    class function RangeText(const AResult: THotspotResult): string; static;
    /// <summary>"steigend", "gleich", "fallend", "neu" oder "".</summary>
    class function TrendCaption(ATrend: THotspotTrend): string; static;
    /// <summary>Einträge der Ebene des Ergebnisses (Methoden bzw. Units).</summary>
    class function Entries(const AResult: THotspotResult): TArray<THotspotEntry>; static;
    /// <summary>"Unit" bzw. "TFoo.Bar" und Fundstelle "Pfad:Zeile".</summary>
    class function EntryName(const AEntry: THotspotEntry): string; static;
  end;

implementation

uses
  System.Math,
  Atlas.Common.Metrics.Report;

const
  cLineBreak = #13#10;

function JsonText(const AText: string): string;
begin
  Result := TMetricsReport.JsonString(AText);
end;

function JsonNumber(AValue: Double): string;
begin
  Result := FormatFloat('0.####', AValue, TFormatSettings.Invariant);
end;

function DateText(ADate: TDateTime): string;
begin
  if ADate <= 0 then
    Result := ''
  else
    Result := FormatDateTime('yyyy"-"mm"-"dd', ADate);
end;

function IsoText(ADate: TDateTime): string;
begin
  if ADate <= 0 then
    Result := ''
  else
    Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"', ADate);
end;

function HtmlEscape(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

function Cell(const AText: string): string;
begin
  Result := StringReplace(AText, '|', '\|', [rfReplaceAll]);
end;

function ScoreText(AValue: Double): string;
begin
  Result := FormatFloat('0.00', AValue);
end;

function ChurnText(const AChanges: THotspotChanges): string;
begin
  if AChanges.Added < 0 then
    Result := ''
  else
    Result := Format('+%d/−%d', [AChanges.Added, AChanges.Deleted]);
end;

function TrendText(const AEntry: THotspotEntry): string;
begin
  Result := THotspotReport.TrendCaption(AEntry.Trend);
  if (Result <> '') and (AEntry.PastComplexity >= 0) then
    Result := Format('%s (%d → %d)', [Result, AEntry.PastComplexity, AEntry.Complexity]);
end;

{ THotspotReport }

class function THotspotReport.ParseSection(const AText: string; out ASection: THotspotSection): Boolean;
begin
  Result := True;
  if (AText = '') or SameText(AText, 'hotspots') then
    ASection := THotspotSection.Hotspots
  else if SameText(AText, 'coupling') then
    ASection := THotspotSection.Coupling
  else
  begin
    ASection := THotspotSection.Hotspots;
    Result := False;
  end;
end;

class function THotspotReport.SectionName(ASection: THotspotSection): string;
begin
  if ASection = THotspotSection.Coupling then
    Result := 'coupling'
  else
    Result := 'hotspots';
end;

class function THotspotReport.TrendCaption(ATrend: THotspotTrend): string;
begin
  case ATrend of
    THotspotTrend.Rising:
      Result := 'steigend';
    THotspotTrend.Steady:
      Result := 'gleich';
    THotspotTrend.Falling:
      Result := 'fallend';
    THotspotTrend.New:
      Result := 'neu';
  else
    Result := '';
  end;
end;

class function THotspotReport.Entries(const AResult: THotspotResult): TArray<THotspotEntry>;
begin
  if AResult.Level = THotspotLevel.Methods then
    Result := AResult.Methods
  else
    Result := AResult.Units;
end;

class function THotspotReport.EntryName(const AEntry: THotspotEntry): string;
begin
  if AEntry.Method <> '' then
    Result := Format('%s (%s:%d)', [AEntry.Method, AEntry.Path, AEntry.Line])
  else
    Result := Format('%s (%s)', [AEntry.UnitName, AEntry.Path]);
end;

class function THotspotReport.RangeText(const AResult: THotspotResult): string;
var
  mKind: string;
begin
  case AResult.Kind of
    THotspotVcsKind.Git:
      mKind := 'Git';
    THotspotVcsKind.Svn:
      mKind := 'SVN';
  else
    mKind := '';
  end;
  Result := Format('%s, %d Monate seit %s, %d Commits', [mKind, AResult.Months, DateText(AResult.Since),
    AResult.Commits]);
end;

function EntryJson(const AEntry: THotspotEntry): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
  mCommit: THotspotLineCommit;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('{"unit":').Append(JsonText(AEntry.UnitName));
    mBuilder.Append(',"path":').Append(JsonText(AEntry.Path));
    if AEntry.Method <> '' then
      mBuilder.Append(',"method":').Append(JsonText(AEntry.Method));
    mBuilder.Append(',"line":').Append(AEntry.Line);
    mBuilder.Append(',"endLine":').Append(AEntry.EndLine);
    mBuilder.Append(',"changes":').Append(AEntry.Changes.Changes);
    mBuilder.Append(',"authors":').Append(Length(AEntry.Changes.Authors));
    mBuilder.Append(',"authorNames":[');
    for mIndex := 0 to High(AEntry.Changes.Authors) do
    begin
      if mIndex > 0 then
        mBuilder.Append(',');
      mBuilder.Append(JsonText(AEntry.Changes.Authors[mIndex]));
    end;
    mBuilder.Append('],"added":').Append(AEntry.Changes.Added);
    mBuilder.Append(',"deleted":').Append(AEntry.Changes.Deleted);
    mBuilder.Append(',"lastChange":').Append(JsonText(IsoText(AEntry.Changes.LastChange)));
    mBuilder.Append(',"complexity":').Append(AEntry.Complexity);
    mBuilder.Append(',"lines":').Append(AEntry.Lines);
    mBuilder.Append(',"pastComplexity":').Append(AEntry.PastComplexity);
    mBuilder.Append(',"trend":').Append(JsonText(THotspots.TrendKey(AEntry.Trend)));
    mBuilder.Append(',"score":').Append(JsonNumber(AEntry.Score));
    mBuilder.Append(',"history":[');
    for mIndex := 0 to High(AEntry.Changes.History) do
    begin
      mCommit := AEntry.Changes.History[mIndex];
      if mIndex > 0 then
        mBuilder.Append(',');
      mBuilder.Append('{"revision":').Append(JsonText(mCommit.Revision));
      mBuilder.Append(',"author":').Append(JsonText(mCommit.Author));
      mBuilder.Append(',"date":').Append(JsonText(IsoText(mCommit.Date)));
      mBuilder.Append(',"summary":').Append(JsonText(mCommit.Summary));
      mBuilder.Append(',"added":').Append(mCommit.Added);
      mBuilder.Append(',"deleted":').Append(mCommit.Deleted);
      mBuilder.Append('}');
    end;
    mBuilder.Append(']}');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function EntriesJson(const AEntries: TArray<THotspotEntry>): string;
var
  mIndex: Integer;
begin
  Result := '[';
  for mIndex := 0 to High(AEntries) do
  begin
    if mIndex > 0 then
      Result := Result + ',';
    Result := Result + EntryJson(AEntries[mIndex]);
  end;
  Result := Result + ']';
end;

function UnitJson(const AUnit: THotspotUnit): string;
begin
  Result := '{"unit":' + JsonText(AUnit.UnitName) + ',"path":' + JsonText(AUnit.Path) + '}';
end;

class function THotspotReport.Json(const AResult: THotspotResult): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
  mPair: THotspotCoupling;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('{"format":').Append(JsonFormat);
    mBuilder.Append(',"title":').Append(JsonText(AResult.Title));
    mBuilder.Append(',"vcs":').Append(JsonText(THotspots.KindName(AResult.Kind)));
    mBuilder.Append(',"head":').Append(JsonText(AResult.Head));
    mBuilder.Append(',"months":').Append(AResult.Months);
    mBuilder.Append(',"since":').Append(JsonText(IsoText(AResult.Since)));
    mBuilder.Append(',"commits":').Append(AResult.Commits);
    mBuilder.Append(',"level":').Append(JsonText(THotspots.LevelKey(AResult.Level)));
    mBuilder.Append(',"units":').Append(EntriesJson(AResult.Units));
    mBuilder.Append(',"methods":').Append(EntriesJson(AResult.Methods));
    mBuilder.Append(',"coupling":[');
    for mIndex := 0 to High(AResult.Coupling) do
    begin
      mPair := AResult.Coupling[mIndex];
      if mIndex > 0 then
        mBuilder.Append(',');
      mBuilder.Append('{"first":').Append(UnitJson(mPair.First));
      mBuilder.Append(',"second":').Append(UnitJson(mPair.Second));
      mBuilder.Append(',"shared":').Append(mPair.Shared);
      mBuilder.Append(',"firstChanges":').Append(mPair.FirstChanges);
      mBuilder.Append(',"secondChanges":').Append(mPair.SecondChanges);
      mBuilder.Append(',"ratio":').Append(JsonNumber(mPair.Ratio));
      mBuilder.Append('}');
    end;
    mBuilder.Append(']}');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function CouplingLine(const APair: THotspotCoupling): string;
begin
  Result := Format('%s ↔ %s: %d gemeinsame Commits (%d %%; %d bzw. %d)', [APair.First.Path, APair.Second.Path,
    APair.Shared, Round(APair.Ratio * 100), APair.FirstChanges, APair.SecondChanges]);
end;

class function THotspotReport.Text(const AResult: THotspotResult; ASection: THotspotSection; ALimit: Integer): string;
var
  mBuilder: TStringBuilder;
  mEntries: TArray<THotspotEntry>;
  mEntry: THotspotEntry;
  mIndex, mLimit: Integer;
  mLevel, mTrend, mChurn: string;
begin
  mLimit := ALimit;
  if mLimit <= 0 then
    mLimit := MaxInt;
  mBuilder := TStringBuilder.Create;
  try
    if ASection = THotspotSection.Coupling then
    begin
      mBuilder.Append(Format('Änderungskopplung (%s): Paare ohne uses-Kante, die fast immer zusammen geändert ' +
        'werden, %d von %d:', [RangeText(AResult), Min(mLimit, Length(AResult.Coupling)),
        Length(AResult.Coupling)])).Append(cLineBreak);
      for mIndex := 0 to Min(mLimit, Length(AResult.Coupling)) - 1 do
        mBuilder.Append('- ').Append(CouplingLine(AResult.Coupling[mIndex])).Append(cLineBreak);
      if Length(AResult.Coupling) = 0 then
        mBuilder.Append('Keine Paare.').Append(cLineBreak);
    end
    else
    begin
      mEntries := Entries(AResult);
      if AResult.Level = THotspotLevel.Methods then
        mLevel := 'Methoden'
      else
        mLevel := 'Units';
      mBuilder.Append(Format('Hotspots (%s), %s, %d von %d; Wert = normierte Änderungen × normierte kognitive ' +
        'Komplexität:', [RangeText(AResult), mLevel, Min(mLimit, Length(mEntries)), Length(mEntries)]))
        .Append(cLineBreak);
      for mIndex := 0 to Min(mLimit, Length(mEntries)) - 1 do
      begin
        mEntry := mEntries[mIndex];
        mTrend := TrendText(mEntry);
        if mTrend <> '' then
          mTrend := ' · Trend ' + mTrend;
        mChurn := ChurnText(mEntry.Changes);
        if mChurn <> '' then
          mChurn := ' · ' + mChurn + ' Zeilen';
        mBuilder.Append(Format('%d. %s: Wert %s · %d Änderungen · %d Autoren · kognitiv %d · %d Zeilen%s%s · ' +
          'zuletzt %s', [mIndex + 1, EntryName(mEntry), ScoreText(mEntry.Score), mEntry.Changes.Changes,
          Length(mEntry.Changes.Authors), mEntry.Complexity, mEntry.Lines, mChurn, mTrend,
          DateText(mEntry.Changes.LastChange)])).Append(cLineBreak);
      end;
      if Length(mEntries) = 0 then
        mBuilder.Append('Keine geänderten Units im Zeitraum.').Append(cLineBreak);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

procedure MarkdownTable(ABuilder: TStringBuilder; const AEntries: TArray<THotspotEntry>; AMethods: Boolean);
var
  mIndex: Integer;
  mEntry: THotspotEntry;
  mName: string;
begin
  ABuilder.Append('| # | ');
  if AMethods then
    ABuilder.Append('Methode')
  else
    ABuilder.Append('Unit');
  ABuilder.Append(' | Wert | Änderungen | Autoren | Komplexität | Zeilen | Geändert | Trend | Zuletzt |')
    .Append(cLineBreak);
  ABuilder.Append('|---:|---|---:|---:|---:|---:|---:|---|---|---|').Append(cLineBreak);
  for mIndex := 0 to High(AEntries) do
  begin
    mEntry := AEntries[mIndex];
    if AMethods then
      mName := Format('%s (`%s:%d`)', [mEntry.Method, mEntry.Path, mEntry.Line])
    else
      mName := Format('%s (`%s`)', [mEntry.UnitName, mEntry.Path]);
    ABuilder.Append(Format('| %d | %s | %s | %d | %d | %d | %d | %s | %s | %s |', [mIndex + 1, Cell(mName),
      ScoreText(mEntry.Score), mEntry.Changes.Changes, Length(mEntry.Changes.Authors), mEntry.Complexity, mEntry.Lines,
      ChurnText(mEntry.Changes), Cell(TrendText(mEntry)), DateText(mEntry.Changes.LastChange)])).Append(cLineBreak);
  end;
end;

class function THotspotReport.Markdown(const AResult: THotspotResult): string;
var
  mBuilder: TStringBuilder;
  mPair: THotspotCoupling;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('# Hotspots ').Append(AResult.Title).Append(cLineBreak).Append(cLineBreak);
    mBuilder.Append(RangeText(AResult)).Append('. Wert = normierte Änderungen × normierte kognitive Komplexität ' +
      '(0–1); Trend gegenüber dem Stand vor 3 Monaten.').Append(cLineBreak).Append(cLineBreak);
    mBuilder.Append('## Units').Append(cLineBreak).Append(cLineBreak);
    if Length(AResult.Units) = 0 then
      mBuilder.Append('Keine geänderten Units im Zeitraum.').Append(cLineBreak)
    else
      MarkdownTable(mBuilder, AResult.Units, False);
    if AResult.Level = THotspotLevel.Methods then
    begin
      mBuilder.Append(cLineBreak).Append('## Methoden').Append(cLineBreak).Append(cLineBreak);
      if Length(AResult.Methods) = 0 then
        mBuilder.Append('Keine geänderten Methoden im Zeitraum.').Append(cLineBreak)
      else
        MarkdownTable(mBuilder, AResult.Methods, True);
    end;
    mBuilder.Append(cLineBreak).Append('## Änderungskopplung').Append(cLineBreak).Append(cLineBreak);
    mBuilder.Append('Paare ohne uses-Kante, die fast immer zusammen geändert werden.').Append(cLineBreak)
      .Append(cLineBreak);
    if Length(AResult.Coupling) = 0 then
      mBuilder.Append('Keine Paare.').Append(cLineBreak)
    else
      for mPair in AResult.Coupling do
        mBuilder.Append('- ').Append(Cell(CouplingLine(mPair))).Append(cLineBreak);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Farbe einer Blase nach Wert: grün (0) über gelb nach rot (1).</summary>
function ScoreColor(AScore: Double): string;
var
  mHue: Integer;
begin
  mHue := Round(120 * (1 - EnsureRange(AScore, 0, 1)));
  Result := Format('hsl(%d,70%%,45%%)', [mHue]);
end;

function Coordinate(AValue: Double): string;
begin
  Result := FormatFloat('0.#', AValue, TFormatSettings.Invariant);
end;

procedure HtmlChart(ABuilder: TStringBuilder; const AEntries: TArray<THotspotEntry>);
const
  cWidth = 760;
  cHeight = 420;
  cLeft = 56;
  cRight = 24;
  cTop = 16;
  cBottom = 44;
var
  mMaxChanges, mMaxComplexity, mMaxLines, mIndex, mCount: Integer;
  mEntry: THotspotEntry;
  mX, mY, mRadius: Double;
begin
  mCount := Min(Length(AEntries), THotspotReport.ChartLimit);
  mMaxChanges := 1;
  mMaxComplexity := 1;
  mMaxLines := 1;
  for mIndex := 0 to mCount - 1 do
  begin
    mMaxChanges := Max(mMaxChanges, AEntries[mIndex].Changes.Changes);
    mMaxComplexity := Max(mMaxComplexity, AEntries[mIndex].Complexity);
    mMaxLines := Max(mMaxLines, AEntries[mIndex].Lines);
  end;
  ABuilder.Append(Format('<svg class="chart" viewBox="0 0 %d %d" role="img" aria-label="Blasendiagramm">',
    [cWidth, cHeight])).Append(cLineBreak);
  ABuilder.Append(Format('<line x1="%d" y1="%d" x2="%d" y2="%d" class="axis"/>', [cLeft, cHeight - cBottom,
    cWidth - cRight, cHeight - cBottom]));
  ABuilder.Append(Format('<line x1="%d" y1="%d" x2="%d" y2="%d" class="axis"/>', [cLeft, cTop, cLeft,
    cHeight - cBottom])).Append(cLineBreak);
  ABuilder.Append(Format('<text x="%d" y="%d" class="label" text-anchor="middle">Änderungen (0–%d)</text>',
    [(cLeft + cWidth - cRight) div 2, cHeight - 10, mMaxChanges]));
  ABuilder.Append(Format('<text x="14" y="%d" class="label" text-anchor="middle" transform="rotate(-90 14 %d)">' +
    'Komplexität (0–%d)</text>', [(cTop + cHeight - cBottom) div 2, (cTop + cHeight - cBottom) div 2,
    mMaxComplexity])).Append(cLineBreak);
  // Größte Blasen zuerst, damit kleine darüber sichtbar bleiben.
  for mIndex := mCount - 1 downto 0 do
  begin
    mEntry := AEntries[mIndex];
    mX := cLeft + (cWidth - cLeft - cRight) * mEntry.Changes.Changes / mMaxChanges;
    mY := (cHeight - cBottom) - (cHeight - cTop - cBottom) * mEntry.Complexity / mMaxComplexity;
    mRadius := 3 + 22 * Sqrt(mEntry.Lines / mMaxLines);
    ABuilder.Append(Format('<circle cx="%s" cy="%s" r="%s" fill="%s"><title>%s: %d Änderungen, kognitiv %d, ' +
      '%d Zeilen, Wert %s</title></circle>', [Coordinate(mX), Coordinate(mY), Coordinate(mRadius),
      ScoreColor(mEntry.Score), HtmlEscape(THotspotReport.EntryName(mEntry)), mEntry.Changes.Changes,
      mEntry.Complexity, mEntry.Lines, ScoreText(mEntry.Score)])).Append(cLineBreak);
  end;
  ABuilder.Append('</svg>').Append(cLineBreak);
end;

procedure HtmlTable(ABuilder: TStringBuilder; const AEntries: TArray<THotspotEntry>; AMethods: Boolean);
var
  mIndex: Integer;
  mEntry: THotspotEntry;
  mName: string;
begin
  ABuilder.Append('<table><thead><tr><th>#</th><th>');
  if AMethods then
    ABuilder.Append('Methode')
  else
    ABuilder.Append('Unit');
  ABuilder.Append('</th><th>Wert</th><th>Änderungen</th><th>Autoren</th><th>Komplexität</th><th>Zeilen</th>' +
    '<th>Geändert</th><th>Trend</th><th>Zuletzt</th></tr></thead><tbody>').Append(cLineBreak);
  for mIndex := 0 to High(AEntries) do
  begin
    mEntry := AEntries[mIndex];
    if AMethods then
      mName := Format('%s <span class="path">%s:%d</span>', [HtmlEscape(mEntry.Method), HtmlEscape(mEntry.Path),
        mEntry.Line])
    else
      mName := Format('%s <span class="path">%s</span>', [HtmlEscape(mEntry.UnitName), HtmlEscape(mEntry.Path)]);
    ABuilder.Append(Format('<tr><td>%d</td><td>%s</td><td>%s</td><td>%d</td><td title="%s">%d</td><td>%d</td>' +
      '<td>%d</td><td>%s</td><td>%s</td><td>%s</td></tr>', [mIndex + 1, mName, ScoreText(mEntry.Score),
      mEntry.Changes.Changes, HtmlEscape(string.Join(', ', mEntry.Changes.Authors)), Length(mEntry.Changes.Authors),
      mEntry.Complexity, mEntry.Lines, HtmlEscape(ChurnText(mEntry.Changes)), HtmlEscape(TrendText(mEntry)),
      DateText(mEntry.Changes.LastChange)])).Append(cLineBreak);
  end;
  ABuilder.Append('</tbody></table>').Append(cLineBreak);
end;

class function THotspotReport.Html(const AResult: THotspotResult): string;
var
  mBuilder: TStringBuilder;
  mPair: THotspotCoupling;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('<!DOCTYPE html>').Append(cLineBreak).Append('<html lang="de"><head><meta charset="utf-8">')
      .Append('<meta name="viewport" content="width=device-width, initial-scale=1">')
      .Append('<title>Hotspots ').Append(HtmlEscape(AResult.Title)).Append('</title>').Append(cLineBreak);
    mBuilder.Append('<style>:root{color-scheme:light dark;--fg:#1f2328;--bg:#fff;--line:#d0d7de;--muted:#656d76}' +
      '@media (prefers-color-scheme:dark){:root{--fg:#e6edf3;--bg:#0d1117;--line:#30363d;--muted:#8d96a0}}' +
      'body{font:14px/1.45 "Segoe UI",system-ui,sans-serif;color:var(--fg);background:var(--bg);margin:24px;' +
      'max-width:1100px}h1{font-size:22px}h2{font-size:17px;margin-top:28px}.chart{width:100%;max-width:760px;' +
      'border:1px solid var(--line);border-radius:6px}.axis{stroke:var(--muted)}.label{fill:var(--muted);' +
      'font-size:12px}circle{fill-opacity:.7;stroke:var(--bg)}table{border-collapse:collapse;width:100%}' +
      'th,td{border-bottom:1px solid var(--line);padding:4px 8px;text-align:right}th:nth-child(2),' +
      'td:nth-child(2){text-align:left}.path{color:var(--muted);font-size:12px}.note{color:var(--muted)}' +
      '</style></head><body>').Append(cLineBreak);
    mBuilder.Append('<h1>Hotspots ').Append(HtmlEscape(AResult.Title)).Append('</h1>').Append(cLineBreak);
    mBuilder.Append('<p class="note">').Append(HtmlEscape(RangeText(AResult))).Append('. Wert = normierte ' +
      'Änderungen × normierte kognitive Komplexität (0–1); Blasengröße = Zeilen; Trend gegenüber dem Stand vor ' +
      '3 Monaten.</p>').Append(cLineBreak);
    HtmlChart(mBuilder, Entries(AResult));
    mBuilder.Append('<h2>Units</h2>').Append(cLineBreak);
    if Length(AResult.Units) = 0 then
      mBuilder.Append('<p>Keine geänderten Units im Zeitraum.</p>').Append(cLineBreak)
    else
      HtmlTable(mBuilder, AResult.Units, False);
    if AResult.Level = THotspotLevel.Methods then
    begin
      mBuilder.Append('<h2>Methoden</h2>').Append(cLineBreak);
      if Length(AResult.Methods) = 0 then
        mBuilder.Append('<p>Keine geänderten Methoden im Zeitraum.</p>').Append(cLineBreak)
      else
        HtmlTable(mBuilder, AResult.Methods, True);
    end;
    mBuilder.Append('<h2>Änderungskopplung</h2>').Append(cLineBreak);
    mBuilder.Append('<p class="note">Paare ohne uses-Kante, die fast immer zusammen geändert werden.</p>')
      .Append(cLineBreak);
    if Length(AResult.Coupling) = 0 then
      mBuilder.Append('<p>Keine Paare.</p>').Append(cLineBreak)
    else
    begin
      mBuilder.Append('<ul>');
      for mPair in AResult.Coupling do
        mBuilder.Append('<li>').Append(HtmlEscape(CouplingLine(mPair))).Append('</li>');
      mBuilder.Append('</ul>').Append(cLineBreak);
    end;
    mBuilder.Append('</body></html>').Append(cLineBreak);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function THotspotReport.ForFile(const AResult: THotspotResult; const AFileName: string): string;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  if (mExtension = '.html') or (mExtension = '.htm') then
    Result := Html(AResult)
  else if mExtension = '.json' then
    Result := Json(AResult)
  else
    Result := Markdown(AResult);
end;

end.
