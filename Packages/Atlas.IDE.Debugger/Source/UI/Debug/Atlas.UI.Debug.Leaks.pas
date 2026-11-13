unit Atlas.UI.Debug.Leaks;

// Texte des Fensters „Atlas-Lecks“ (#1875): Statuszeile, Zeile je Name mit
// Vergleich zum letzten Lauf, Kandidat mit Bewertung, Gruppe mit
// Erzeugungsstelle, Hinweis bei Strings. Sprache aus Atlas.UI.Debug.Strings.

interface

uses
  Atlas.Core.Debug.LeakCapture,
  Atlas.Core.Debug.LeakView;

type
  TAtlasLeakTexts = class
  public
    /// <summary>Bewertung des Servers als Text; unbekannte Namen unverändert.</summary>
    class function RatingText(const ARating: string): string; static;
    /// <summary>Zeile im Baum.</summary>
    class function RowText(const ARow: TAtlasLeakRow): string; static;
    /// <summary>Statuszeile: Zahl der Lecks, Namen und Quelle.</summary>
    class function Summary(const ACapture: TAtlasLeakCapture): string; static;
    /// <summary>Gesamtzahl der Lecks im Bericht.</summary>
    class function LeakCount(const ACapture: TAtlasLeakCapture): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.LeakReport,
  Atlas.UI.Debug.Strings;

const
  cRatings: array[0..6] of string = ('neverFreed', 'returned', 'passed', 'fieldFreed', 'owned', 'localFreed',
    'notInProgram');
  cRatingIds: array[0..6] of TAtlasDebugTextId = (TAtlasDebugTextId.LeaksRatingNeverFreed,
    TAtlasDebugTextId.LeaksRatingReturned, TAtlasDebugTextId.LeaksRatingPassed,
    TAtlasDebugTextId.LeaksRatingFieldFreed, TAtlasDebugTextId.LeaksRatingOwned,
    TAtlasDebugTextId.LeaksRatingLocalFreed, TAtlasDebugTextId.LeaksRatingNotInProgram);

class function TAtlasLeakTexts.RatingText(const ARating: string): string;
var
  mIndex: Integer;
begin
  for mIndex := Low(cRatings) to High(cRatings) do
  begin
    if SameText(cRatings[mIndex], ARating) then
    begin
      Exit(TAtlasDebugStrings.Text(cRatingIds[mIndex]));
    end;
  end;
  Result := ARating;
end;

/// <summary>Zusatz hinter dem Namen: neu bzw. mehr geworden, bekannt.</summary>
function Marks(const AEntry: TAtlasLeakEntry): string;
begin
  Result := '';
  if AEntry.IsNew and (AEntry.PreviousCount = 0) then
  begin
    Result := '  (' + TAtlasDebugStrings.Text(TAtlasDebugTextId.LeaksNew) + ')';
  end
  else if AEntry.IsNew then
  begin
    Result := '  (' + TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LeaksMore,
      [AEntry.Count - AEntry.PreviousCount]) + ')';
  end;
  if AEntry.Known then
  begin
    Result := Result + '  [' + TAtlasDebugStrings.Text(TAtlasDebugTextId.LeaksKnownMark) + ']';
  end;
end;

function NameText(const ARow: TAtlasLeakRow): string;
begin
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LeaksNameLine, [ARow.Entry.Name, ARow.Entry.Count]) +
    Marks(ARow.Entry);
  if (ARow.Entry.Kind = TLeakKind.Instance) and (ARow.PlaceCount = 0) then
  begin
    Result := Result + '  ·  ' + TAtlasDebugStrings.Text(TAtlasDebugTextId.LeaksNoPlaces);
  end;
end;

function GroupText(const ARow: TAtlasLeakRow): string;
var
  mFrame: TLeakFrame;
begin
  if ARow.Group.Site < 0 then
  begin
    Exit(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LeaksGroupNoSite, [ARow.Group.Count]));
  end;
  mFrame := ARow.Group.Frames[ARow.Group.Site];
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LeaksGroupLine, [ExtractFileName(mFrame.FileName), mFrame.Line,
    mFrame.Routine, ARow.Group.Count]);
end;

class function TAtlasLeakTexts.RowText(const ARow: TAtlasLeakRow): string;
begin
  case ARow.Kind of
    TAtlasLeakRowKind.Place:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LeaksPlaceLine, [ExtractFileName(ARow.Place.FileName),
        ARow.Place.Line + 1, ARow.Place.Routine, RatingText(ARow.Place.Rating)]);
    TAtlasLeakRowKind.Group:
      Result := GroupText(ARow);
    TAtlasLeakRowKind.Hint:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.LeaksFollowsFromObjects);
  else
    Result := NameText(ARow);
  end;
end;

class function TAtlasLeakTexts.LeakCount(const ACapture: TAtlasLeakCapture): Integer;
var
  mCount: TLeakCount;
begin
  Result := 0;
  for mCount in ACapture.Report.Counts do
  begin
    Inc(Result, mCount.Count);
  end;
end;

class function TAtlasLeakTexts.Summary(const ACapture: TAtlasLeakCapture): string;
var
  mSource: string;
begin
  if ACapture.IsEmpty then
  begin
    Exit(TAtlasDebugStrings.Text(TAtlasDebugTextId.LeaksEmpty));
  end;
  if ACapture.Source = TAtlasLeakSource.LogFile then
  begin
    mSource := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LeaksFromLogFile, [ExtractFileName(ACapture.FileName)]);
  end
  else
  begin
    mSource := TAtlasDebugStrings.Text(TAtlasDebugTextId.LeaksFromMessageBox);
  end;
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LeaksSummary, [LeakCount(ACapture),
    Length(ACapture.Report.Counts), mSource]);
end;

end.
