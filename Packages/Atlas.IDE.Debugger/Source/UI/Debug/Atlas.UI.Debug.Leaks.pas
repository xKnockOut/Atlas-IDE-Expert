unit Atlas.UI.Debug.Leaks;

// Texte des Fensters „Atlas-Lecks“ (#1875): Statuszeile, Zeile je Name mit
// Vergleich zum letzten Lauf, Kandidat mit Bewertung, Gruppe mit
// Erzeugungsstelle, Hinweis bei Strings. Sprache aus Atlas.UI.Debug.Leaks.Strings.

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
  Atlas.UI.Debug.Leaks.Strings;

const
  cRatings: array[0..6] of string = ('neverFreed', 'returned', 'passed', 'fieldFreed', 'owned', 'localFreed',
    'notInProgram');
  cRatingIds: array[0..6] of TAtlasLeaksTextId = (TAtlasLeaksTextId.LeaksRatingNeverFreed,
    TAtlasLeaksTextId.LeaksRatingReturned, TAtlasLeaksTextId.LeaksRatingPassed,
    TAtlasLeaksTextId.LeaksRatingFieldFreed, TAtlasLeaksTextId.LeaksRatingOwned,
    TAtlasLeaksTextId.LeaksRatingLocalFreed, TAtlasLeaksTextId.LeaksRatingNotInProgram);

{ TAtlasLeakTexts }

class function TAtlasLeakTexts.RatingText(const ARating: string): string;
var
  mIndex: Integer;
begin
  for mIndex := Low(cRatings) to High(cRatings) do
  begin
    if SameText(cRatings[mIndex], ARating) then
    begin
      Exit(TAtlasLeaksStrings.Text(cRatingIds[mIndex]));
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
    Result := '  (' + TAtlasLeaksStrings.Text(TAtlasLeaksTextId.LeaksNew) + ')';
  end
  else if AEntry.IsNew then
  begin
    Result := '  (' + TAtlasLeaksStrings.Fmt(TAtlasLeaksTextId.LeaksMore,
      [AEntry.Count - AEntry.PreviousCount]) + ')';
  end;
  if AEntry.Known then
  begin
    Result := Result + '  [' + TAtlasLeaksStrings.Text(TAtlasLeaksTextId.LeaksKnownMark) + ']';
  end;
end;

function NameText(const ARow: TAtlasLeakRow): string;
begin
  Result := TAtlasLeaksStrings.Fmt(TAtlasLeaksTextId.LeaksNameLine, [ARow.Entry.Name, ARow.Entry.Count]) +
    Marks(ARow.Entry);
  if (ARow.Entry.Kind = TLeakKind.Instance) and (ARow.PlaceCount = 0) then
  begin
    Result := Result + '  ·  ' + TAtlasLeaksStrings.Text(TAtlasLeaksTextId.LeaksNoPlaces);
  end;
end;

function GroupText(const ARow: TAtlasLeakRow): string;
var
  mFrame: TLeakFrame;
begin
  if ARow.Group.Site < 0 then
  begin
    Exit(TAtlasLeaksStrings.Fmt(TAtlasLeaksTextId.LeaksGroupNoSite, [ARow.Group.Count]));
  end;
  mFrame := ARow.Group.Frames[ARow.Group.Site];
  Result := TAtlasLeaksStrings.Fmt(TAtlasLeaksTextId.LeaksGroupLine, [ExtractFileName(mFrame.FileName), mFrame.Line,
    mFrame.Routine, ARow.Group.Count]);
end;

class function TAtlasLeakTexts.RowText(const ARow: TAtlasLeakRow): string;
begin
  case ARow.Kind of
    TAtlasLeakRowKind.Place:
      Result := TAtlasLeaksStrings.Fmt(TAtlasLeaksTextId.LeaksPlaceLine, [ExtractFileName(ARow.Place.FileName),
        ARow.Place.Line + 1, ARow.Place.Routine, RatingText(ARow.Place.Rating)]);
    TAtlasLeakRowKind.Group:
      Result := GroupText(ARow);
    TAtlasLeakRowKind.Hint:
      Result := TAtlasLeaksStrings.Text(TAtlasLeaksTextId.LeaksFollowsFromObjects);
  else
    Result := NameText(ARow);
  end;
end;

class function TAtlasLeakTexts.Summary(const ACapture: TAtlasLeakCapture): string;
var
  mSource: string;
begin
  if ACapture.IsEmpty then
  begin
    Exit(TAtlasLeaksStrings.Text(TAtlasLeaksTextId.LeaksEmpty));
  end;
  if ACapture.Source = TAtlasLeakSource.LogFile then
  begin
    mSource := TAtlasLeaksStrings.Fmt(TAtlasLeaksTextId.LeaksFromLogFile, [ExtractFileName(ACapture.FileName)]);
  end
  else
  begin
    mSource := TAtlasLeaksStrings.Text(TAtlasLeaksTextId.LeaksFromMessageBox);
  end;
  Result := TAtlasLeaksStrings.Fmt(TAtlasLeaksTextId.LeaksSummary, [LeakCount(ACapture),
    Length(ACapture.Report.Counts), mSource]);
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

end.
