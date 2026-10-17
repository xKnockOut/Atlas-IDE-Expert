unit Atlas.Core.Editor.Overview;

// Übersichtsleiste an der Scrollleiste (#519), ohne VCL und OTA:
// - Marken (TAtlasOverviewMark) für die ganze Datei: Fehler, Warnungen und
//   Hinweise (#398), Treffer des markierten Texts, Änderungen gegenüber dem
//   Repository (#507), Haltepunkte, Lesezeichen der IDE und der Cursor.
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
    AllKinds = TAtlasOverviewKindNames.All;
    /// <summary>Höchstzahl der Trefferzeilen; mehr zeigt der Streifen nicht.</summary>
    MaxSearchLines = 5000;
    /// <summary>Höchstlänge des Suchtexts.</summary>
    MaxTermLength = 200;
  public
    /// <summary>Name in editor.overviewRulerKinds.</summary>
    class function KindName(AKind: TAtlasOverviewKind): string; static;
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
    class function Layout(const AMarks: TAtlasOverviewMarks; ALineCount, AHeight, AMinHeight: Integer): TAtlasOverviewBars;
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

class function TAtlasOverview.KindName(AKind: TAtlasOverviewKind): string;
begin
  Result := TAtlasOverviewKindNames.Name(AKind);
end;

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
  Mark: TAtlasOverviewMark;
begin
  Result := nil;
  for Mark in AMarks do
    if GroupOf(Mark.Kind) in AKinds then
      Result := Result + [Mark];
end;

class function TAtlasOverview.PixelOf(ALine, ALineCount, AHeight: Integer): Integer;
begin
  if (ALineCount <= 0) or (AHeight <= 0) then
    Exit(0);
  Result := EnsureRange(Integer((Int64(ALine) * AHeight) div ALineCount), 0, AHeight - 1);
end;

class function TAtlasOverview.LineAt(AY, ALineCount, AHeight: Integer): Integer;
begin
  if (ALineCount <= 0) or (AHeight <= 0) then
    Exit(0);
  // Das unterste Pixel erreicht die letzte Zeile.
  if AY >= AHeight - 1 then
    Exit(ALineCount - 1);
  Result := EnsureRange(Integer((Int64(Max(0, AY)) * ALineCount) div AHeight), 0, ALineCount - 1);
end;

class function TAtlasOverview.Layout(const AMarks: TAtlasOverviewMarks; ALineCount, AHeight,
  AMinHeight: Integer): TAtlasOverviewBars;
var
  Kind: TAtlasOverviewMarkKind;
  Order: TArray<Integer>;
  Index, Position, Moved, Top, Bottom, Last: Integer;
  Bar: TAtlasOverviewBar;
begin
  Result := nil;
  if (ALineCount <= 0) or (AHeight <= 0) then
    Exit;
  // Je Art in Zeichenreihenfolge; innerhalb der Art aufsteigend, Überlappungen zusammengefasst.
  for Kind := Low(TAtlasOverviewMarkKind) to High(TAtlasOverviewMarkKind) do
  begin
    // Marken dieser Art nach Zeile (Einfügen; die Listen sind meist schon sortiert).
    Order := nil;
    for Index := 0 to High(AMarks) do
      if AMarks[Index].Kind = Kind then
      begin
        Order := Order + [Index];
        Position := High(Order);
        while (Position > 0) and (AMarks[Order[Position - 1]].Line > AMarks[Index].Line) do
        begin
          Moved := Order[Position - 1];
          Order[Position - 1] := Order[Position];
          Order[Position] := Moved;
          Dec(Position);
        end;
      end;
    Last := -1;
    for Index in Order do
    begin
      Top := PixelOf(Min(AMarks[Index].Line, ALineCount - 1), ALineCount, AHeight);
      Bottom := Max(PixelOf(Min(AMarks[Index].Line + AMarks[Index].Count, ALineCount), ALineCount, AHeight),
        Top + Max(1, AMinHeight));
      if Bottom > AHeight then
      begin
        Bottom := AHeight;
        Top := Max(0, Min(Top, AHeight - Max(1, AMinHeight)));
      end;
      if (Last >= 0) and (Top <= Result[Last].Bottom) then
      begin
        // Liegt auf (oder direkt an) dem vorigen Balken derselben Art: verlängern.
        Result[Last].Bottom := Max(Result[Last].Bottom, Bottom);
        Continue;
      end;
      Bar.Mark := Index;
      Bar.Kind := Kind;
      Bar.Lane := LaneOf(Kind);
      Bar.Top := Top;
      Bar.Bottom := Bottom;
      Result := Result + [Bar];
      Last := High(Result);
    end;
  end;
end;

class function TAtlasOverview.Hit(const ABars: TAtlasOverviewBars; AY, ATolerance: Integer;
  out AMark: Integer): Boolean;
var
  Index, Distance, Best, BestDistance: Integer;
begin
  AMark := -1;
  Best := -1;
  BestDistance := MaxInt;
  for Index := 0 to High(ABars) do
  begin
    // Der Cursor ist kein Sprungziel.
    if ABars[Index].Kind = TAtlasOverviewMarkKind.Cursor then
      Continue;
    if AY < ABars[Index].Top then
      Distance := ABars[Index].Top - AY
    else if AY >= ABars[Index].Bottom then
      Distance := AY - ABars[Index].Bottom + 1
    else
      Distance := 0;
    if Distance > ATolerance then
      Continue;
    // Wichtigere Art gewinnt, bei gleicher Art der nähere Balken.
    if (Best < 0) or (ABars[Index].Kind > ABars[Best].Kind) or
      ((ABars[Index].Kind = ABars[Best].Kind) and (Distance < BestDistance)) then
    begin
      Best := Index;
      BestDistance := Distance;
    end;
  end;
  Result := Best >= 0;
  if Result then
    AMark := ABars[Best].Mark;
end;

class function TAtlasOverview.Occurrences(const ALines: TArray<string>; const ATerm: string): TArray<Integer>;
var
  Term: string;
  Index: Integer;
begin
  Result := nil;
  if ATerm = '' then
    Exit;
  Term := AnsiLowerCase(ATerm);
  for Index := 0 to High(ALines) do
    if Pos(Term, AnsiLowerCase(ALines[Index])) > 0 then
    begin
      Result := Result + [Index];
      if Length(Result) >= MaxSearchLines then
        Exit;
    end;
end;

class function TAtlasOverview.SearchTerm(const ASelection: string; out ATerm: string): Boolean;
begin
  ATerm := '';
  Result := (ASelection <> '') and (Trim(ASelection) <> '') and (Pos(#10, ASelection) = 0) and
    (Pos(#13, ASelection) = 0) and (Length(ASelection) <= MaxTermLength);
  if Result then
    ATerm := ASelection;
end;

class function TAtlasOverview.Same(const A, B: TAtlasOverviewMarks): Boolean;
var
  Index: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then
    Exit;
  for Index := 0 to High(A) do
    if (A[Index].Kind <> B[Index].Kind) or (A[Index].Line <> B[Index].Line) or (A[Index].Count <> B[Index].Count) or
      (A[Index].Text <> B[Index].Text) then
      Exit(False);
end;

end.
