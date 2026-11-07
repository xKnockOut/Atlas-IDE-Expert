unit Atlas.Core.Editor.Overview;

// Übersichtsleiste an der Scrollleiste (#519), ohne VCL und OTA:
// - Marken (TAtlasOverviewMark) für die ganze Datei: Fehler, Warnungen und
//   Hinweise (#398), Treffer des markierten Texts, Änderungen gegenüber dem
//   Repository (#507), Haltepunkte, Lesezeichen der IDE und der Cursor.
//   Eigene Lesezeichen eines Moduls kommen über IAtlasOverviewBookmarks.
// - Kinds liest und schreibt editor.overviewRulerKinds ("diagnostics,
//   search, changes, breakpoints, bookmarks, cursor"); unbekannte Namen
//   fallen weg, die Reihenfolge ist fest.
// - Layout rechnet die Marken proportional zur Zeile auf die Höhe des
//   Streifens um, mit Mindesthöhe; gleiche Art auf demselben Pixel wird
//   zusammengefasst, wichtigere Arten liegen oben (Fehler über Warnung über
//   Treffer …). Jede Art hat ihre Spur: links Änderungen, in der Mitte
//   Treffer, Lesezeichen und Haltepunkte, rechts Diagnosen, der Cursor quer.
// - Hit findet die Marke unter einem Klick (mit Toleranz), LineAt sonst die
//   Zeile an der Stelle.
// - Occurrences sucht die Zeilen mit dem markierten Text (ohne
//   Groß-/Kleinschreibung wie Pascal), SearchTerm nimmt nur eine einzeilige
//   Markierung.
// Zeilen sind 0-basiert.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.OverviewKinds;

type
  /// <summary>Gruppe für editor.overviewRulerKinds (bei den Einstellungen, damit der Parser ohne diesen Kern
  /// auskommt).</summary>
  TAtlasOverviewKind = Atlas.Core.Settings.OverviewKinds.TAtlasOverviewKind;
  TAtlasOverviewKinds = Atlas.Core.Settings.OverviewKinds.TAtlasOverviewKinds;
{$SCOPEDENUMS ON}
  /// <summary>Art einer Marke; die Reihenfolge ist zugleich die Zeichenreihenfolge (spätere liegen oben).</summary>
  TAtlasOverviewMarkKind = (Cursor, Added, Modified, Deleted, Search, Bookmark, Breakpoint, Info, Warning, Error);
  /// <summary>Spur im Streifen.</summary>
  TAtlasOverviewLane = (Left, Middle, Right, Full);
{$SCOPEDENUMS OFF}

  TAtlasOverviewMark = record
    Kind: TAtlasOverviewMarkKind;
    Line: Integer;
    /// <summary>Zeilen ab Line (mindestens 1).</summary>
    Count: Integer;
    /// <summary>Beschreibung für die Vorschau (etwa die Meldung); '' ohne.</summary>
    Text: string;
    class function Create(AKind: TAtlasOverviewMarkKind; ALine, ACount: Integer): TAtlasOverviewMark; overload; static;
    class function Create(AKind: TAtlasOverviewMarkKind; ALine, ACount: Integer;
      const AText: string): TAtlasOverviewMark; overload; static;
  end;

  TAtlasOverviewMarks = TArray<TAtlasOverviewMark>;

  /// <summary>Eigene Lesezeichen eines Moduls für die Übersichtsleiste (#1104, #1455): Das Modul stellt die Quelle
  /// über seinen Scope bereit; die Leiste fragt bei jedem Sammeln die Registry. Nur im Hauptthread.</summary>
  IAtlasOverviewBookmarks = interface
    ['{CF205299-AA82-4210-8294-D1E4064066BA}']
    /// <summary>Lesezeichen für AFileName; False: keine eigenen, die Leiste zeigt die der IDE.</summary>
    function Marks(const AFileName: string; out AMarks: TAtlasOverviewMarks): Boolean;
  end;

  /// <summary>Gezeichneter Balken: Pixel von Top bis Bottom (ausschließlich) in seiner Spur.</summary>
  TAtlasOverviewBar = record
    Mark: Integer;
    Kind: TAtlasOverviewMarkKind;
    Lane: TAtlasOverviewLane;
    Top: Integer;
    Bottom: Integer;
  end;

  TAtlasOverviewBars = TArray<TAtlasOverviewBar>;

  TAtlasOverview = class
  public const
    cAllKinds = TAtlasOverviewKindNames.cAll;
    /// <summary>Höchstzahl der Trefferzeilen; mehr zeigt der Streifen nicht.</summary>
    cMaxSearchLines = 5000;
    /// <summary>Höchstlänge des Suchtexts.</summary>
    cMaxTermLength = 200;
  public
    class function Kinds(const AText: string): TAtlasOverviewKinds; static;
    class function KindsText(AKinds: TAtlasOverviewKinds): string; static;
    /// <summary>Bekannte Namen in fester Reihenfolge, ohne Doppelte.</summary>
    class function Normalize(const AText: string): string; static;
    class function GroupOf(AKind: TAtlasOverviewMarkKind): TAtlasOverviewKind; static;
    class function LaneOf(AKind: TAtlasOverviewMarkKind): TAtlasOverviewLane; static;
    /// <summary>Nur Marken, deren Gruppe in AKinds steht.</summary>
    class function Filter(const AMarks: TAtlasOverviewMarks; AKinds: TAtlasOverviewKinds): TAtlasOverviewMarks;
      static;
    /// <summary>Pixelzeile von ALine bei ALineCount Zeilen auf AHeight Pixeln.</summary>
    class function PixelOf(ALine, ALineCount, AHeight: Integer): Integer; static;
    /// <summary>Zeile an Pixel AY (geklemmt).</summary>
    class function LineAt(AY, ALineCount, AHeight: Integer): Integer; static;
    /// <summary>Balken in Zeichenreihenfolge (wichtigere zuletzt); jeder mindestens AMinHeight hoch.</summary>
    class function Layout(const AMarks: TAtlasOverviewMarks; ALineCount, AHeight,
      AMinHeight: Integer): TAtlasOverviewBars;
      static;
    /// <summary>Wichtigster Balken, der AY mit ATolerance Pixeln Spiel trifft; bei gleicher Art der nächste.</summary>
    class function Hit(const ABars: TAtlasOverviewBars; AY, ATolerance: Integer; out AMark: Integer): Boolean; static;
    /// <summary>Zeilen, die ATerm enthalten, aufsteigend, höchstens MaxSearchLines.</summary>
    class function Occurrences(const ALines: TArray<string>; const ATerm: string): TArray<Integer>; static;
    /// <summary>Suchtext aus der Markierung: nur einzeilig, nicht leer, höchstens MaxTermLength Zeichen.</summary>
    class function SearchTerm(const ASelection: string; out ATerm: string): Boolean; static;
    /// <summary>Gleiche Marken (für „nur bei Änderungen neu zeichnen“).</summary>
    class function Same(const A, B: TAtlasOverviewMarks): Boolean; static;
  end;

implementation

uses
  System.Math;

{ TAtlasOverviewMark }

class function TAtlasOverviewMark.Create(AKind: TAtlasOverviewMarkKind; ALine, ACount: Integer): TAtlasOverviewMark;
begin
  Result := Create(AKind, ALine, ACount, '');
end;

class function TAtlasOverviewMark.Create(AKind: TAtlasOverviewMarkKind; ALine, ACount: Integer;
  const AText: string): TAtlasOverviewMark;
begin
  Result.Kind := AKind;
  Result.Line := Max(0, ALine);
  Result.Count := Max(1, ACount);
  Result.Text := AText;
end;

{ TAtlasOverview }

class function TAtlasOverview.Kinds(const AText: string): TAtlasOverviewKinds;
begin
  Result := TAtlasOverviewKindNames.Parse(AText);
end;

class function TAtlasOverview.KindsText(AKinds: TAtlasOverviewKinds): string;
begin
  Result := TAtlasOverviewKindNames.Text(AKinds);
end;

class function TAtlasOverview.Normalize(const AText: string): string;
begin
  Result := TAtlasOverviewKindNames.Normalize(AText);
end;

class function TAtlasOverview.GroupOf(AKind: TAtlasOverviewMarkKind): TAtlasOverviewKind;
begin
  case AKind of
    TAtlasOverviewMarkKind.Cursor:
      Result := TAtlasOverviewKind.Cursor;
    TAtlasOverviewMarkKind.Added, TAtlasOverviewMarkKind.Modified, TAtlasOverviewMarkKind.Deleted:
      Result := TAtlasOverviewKind.Changes;
    TAtlasOverviewMarkKind.Search:
      Result := TAtlasOverviewKind.Search;
    TAtlasOverviewMarkKind.Bookmark:
      Result := TAtlasOverviewKind.Bookmarks;
    TAtlasOverviewMarkKind.Breakpoint:
      Result := TAtlasOverviewKind.Breakpoints;
  else
    Result := TAtlasOverviewKind.Diagnostics;
  end;
end;

class function TAtlasOverview.LaneOf(AKind: TAtlasOverviewMarkKind): TAtlasOverviewLane;
begin
  case AKind of
    TAtlasOverviewMarkKind.Cursor:
      Result := TAtlasOverviewLane.Full;
    TAtlasOverviewMarkKind.Added, TAtlasOverviewMarkKind.Modified, TAtlasOverviewMarkKind.Deleted:
      Result := TAtlasOverviewLane.Left;
    TAtlasOverviewMarkKind.Search, TAtlasOverviewMarkKind.Bookmark, TAtlasOverviewMarkKind.Breakpoint:
      Result := TAtlasOverviewLane.Middle;
  else
    Result := TAtlasOverviewLane.Right;
  end;
end;

class function TAtlasOverview.Filter(const AMarks: TAtlasOverviewMarks; AKinds: TAtlasOverviewKinds):
  TAtlasOverviewMarks;
var
  mMark: TAtlasOverviewMark;
begin
  Result := nil;
  for mMark in AMarks do
  begin
    if GroupOf(mMark.Kind) in AKinds then
    begin
      Result := Result + [mMark];
    end;
  end;
end;

class function TAtlasOverview.PixelOf(ALine, ALineCount, AHeight: Integer): Integer;
begin
  if (ALineCount <= 0) or (AHeight <= 0) then
  begin
    Exit(0);
  end;
  Result := EnsureRange(Integer((Int64(ALine) * AHeight) div ALineCount), 0, AHeight - 1);
end;

class function TAtlasOverview.LineAt(AY, ALineCount, AHeight: Integer): Integer;
begin
  if (ALineCount <= 0) or (AHeight <= 0) then
  begin
    Exit(0);
  end;
  // Das unterste Pixel erreicht die letzte Zeile.
  if AY >= AHeight - 1 then
  begin
    Exit(ALineCount - 1);
  end;
  Result := EnsureRange(Integer((Int64(Max(0, AY)) * ALineCount) div AHeight), 0, ALineCount - 1);
end;

/// <summary>Marken der Art AKind nach Zeile (Einfügen; die Listen sind meist schon sortiert).</summary>
function MarksOfKind(const AMarks: TAtlasOverviewMarks; AKind: TAtlasOverviewMarkKind): TArray<Integer>;
var
  mIndex, mPosition, mMoved: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AMarks) do
  begin
    if AMarks[mIndex].Kind = AKind then
    begin
      Result := Result + [mIndex];
      mPosition := High(Result);
      while (mPosition > 0) and (AMarks[Result[mPosition - 1]].Line > AMarks[mIndex].Line) do
      begin
        mMoved := Result[mPosition - 1];
        Result[mPosition - 1] := Result[mPosition];
        Result[mPosition] := mMoved;
        Dec(mPosition);
      end;
    end;
  end;
end;

/// <summary>Pixelbereich einer Marke, mindestens AMinHeight hoch und innerhalb von AHeight.</summary>
procedure MarkPixels(const AMark: TAtlasOverviewMark; ALineCount, AHeight, AMinHeight: Integer;
  out ATop, ABottom: Integer);
begin
  ATop := TAtlasOverview.PixelOf(Min(AMark.Line, ALineCount - 1), ALineCount, AHeight);
  ABottom := Max(TAtlasOverview.PixelOf(Min(AMark.Line + AMark.Count, ALineCount), ALineCount, AHeight),
    ATop + Max(1, AMinHeight));
  if ABottom > AHeight then
  begin
    ABottom := AHeight;
    ATop := Max(0, Min(ATop, AHeight - Max(1, AMinHeight)));
  end;
end;

/// <summary>Balken der Marken AOrder (alle von einer Art); Überlappungen fasst es zusammen.</summary>
procedure AddKindBars(const AMarks: TAtlasOverviewMarks; const AOrder: TArray<Integer>;
  ALineCount, AHeight, AMinHeight: Integer; var ABars: TAtlasOverviewBars);
var
  mIndex, mTop, mBottom, mLast: Integer;
  mBar: TAtlasOverviewBar;
begin
  mLast := -1;
  for mIndex in AOrder do
  begin
    MarkPixels(AMarks[mIndex], ALineCount, AHeight, AMinHeight, mTop, mBottom);
    if (mLast >= 0) and (mTop <= ABars[mLast].Bottom) then
    begin
      // Liegt auf (oder direkt an) dem vorigen Balken derselben Art: verlängern.
      ABars[mLast].Bottom := Max(ABars[mLast].Bottom, mBottom);
    end
    else
    begin
      mBar.Mark := mIndex;
      mBar.Kind := AMarks[mIndex].Kind;
      mBar.Lane := TAtlasOverview.LaneOf(mBar.Kind);
      mBar.Top := mTop;
      mBar.Bottom := mBottom;
      ABars := ABars + [mBar];
      mLast := High(ABars);
    end;
  end;
end;

class function TAtlasOverview.Layout(const AMarks: TAtlasOverviewMarks; ALineCount, AHeight,
  AMinHeight: Integer): TAtlasOverviewBars;
var
  mKind: TAtlasOverviewMarkKind;
begin
  Result := nil;
  if (ALineCount > 0) and (AHeight > 0) then
  begin
    // Je Art in Zeichenreihenfolge; innerhalb der Art aufsteigend, Überlappungen zusammengefasst.
    for mKind := Low(TAtlasOverviewMarkKind) to High(TAtlasOverviewMarkKind) do
    begin
      AddKindBars(AMarks, MarksOfKind(AMarks, mKind), ALineCount, AHeight, AMinHeight, Result);
    end;
  end;
end;

class function TAtlasOverview.Hit(const ABars: TAtlasOverviewBars; AY, ATolerance: Integer;
  out AMark: Integer): Boolean;
var
  mIndex, mDistance, mBest, mBestDistance: Integer;
begin
  AMark := -1;
  mBest := -1;
  mBestDistance := MaxInt;
  for mIndex := 0 to High(ABars) do
  begin
    // Der Cursor ist kein Sprungziel.
    if ABars[mIndex].Kind = TAtlasOverviewMarkKind.Cursor then
    begin
      Continue;
    end;
    if AY < ABars[mIndex].Top then
    begin
      mDistance := ABars[mIndex].Top - AY;
    end
    else if AY >= ABars[mIndex].Bottom then
    begin
      mDistance := AY - ABars[mIndex].Bottom + 1;
    end
    else
    begin
      mDistance := 0;
    end;
    if mDistance > ATolerance then
    begin
      Continue;
    end;
    // Wichtigere Art gewinnt, bei gleicher Art der nähere Balken.
    if (mBest < 0) or (ABars[mIndex].Kind > ABars[mBest].Kind) or
      ((ABars[mIndex].Kind = ABars[mBest].Kind) and (mDistance < mBestDistance)) then
    begin
      mBest := mIndex;
      mBestDistance := mDistance;
    end;
  end;
  Result := mBest >= 0;
  if Result then
  begin
    AMark := ABars[mBest].Mark;
  end;
end;

class function TAtlasOverview.Occurrences(const ALines: TArray<string>; const ATerm: string): TArray<Integer>;
var
  mTerm: string;
  mIndex: Integer;
begin
  Result := nil;
  if ATerm = '' then
  begin
    Exit;
  end;
  mTerm := AnsiLowerCase(ATerm);
  for mIndex := 0 to High(ALines) do
  begin
    if Pos(mTerm, AnsiLowerCase(ALines[mIndex])) > 0 then
    begin
      Result := Result + [mIndex];
      if Length(Result) >= cMaxSearchLines then
      begin
        Exit;
      end;
    end;
  end;
end;

class function TAtlasOverview.SearchTerm(const ASelection: string; out ATerm: string): Boolean;
begin
  ATerm := '';
  Result := (ASelection <> '') and (Trim(ASelection) <> '') and (Pos(#10, ASelection) = 0) and
    (Pos(#13, ASelection) = 0) and (Length(ASelection) <= cMaxTermLength);
  if Result then
  begin
    ATerm := ASelection;
  end;
end;

class function TAtlasOverview.Same(const A, B: TAtlasOverviewMarks): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(A) do
  begin
    if (A[mIndex].Kind <> B[mIndex].Kind) or (A[mIndex].Line <> B[mIndex].Line) or
      (A[mIndex].Count <> B[mIndex].Count) or
      (A[mIndex].Text <> B[mIndex].Text) then
    begin
      Exit(False);
    end;
  end;
end;

end.
