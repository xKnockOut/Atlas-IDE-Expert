unit Atlas.Core.Designer.Wrap;

// Controls in einen Container einpacken und Container auflösen (#733), ohne
// VCL und Windows.
// - Rechteck: umschließendes Rechteck der Auswahl plus Innenrand, oben dazu
//   die Höhe der Beschriftung (GroupBox).
// - Koordinaten: im Container = im Parent minus Lage des Containers und
//   Abstand seines Clients; beim Auflösen umgekehrt.
// - TabOrder: Kinder behalten ihre Reihenfolge untereinander; beim Auflösen
//   kommen sie an der Stelle des Containers in die Reihe des Parents.
// - Anchors des Containers: die Seiten, an denen alle Kinder verankert sind;
//   ohne gemeinsame links und oben.
// - GridPanel: Zeilen nach Oberkante (± halbe Höhe), Spalten = längste Zeile,
//   Reihenfolge zeilenweise von links nach rechts.
// - Verweise im Code: Zeilen mit dem Namen als ganzem Wort, ohne die
//   Felddeklaration „Name: TKlasse;“ und ohne Kommentarzeilen.
// - Namenspräfix je Containerklasse (pnl, gbx, …); unbekannte Klassen: die
//   ersten drei Buchstaben ohne „T“, klein.

interface

uses
  System.Types,
  Atlas.Core.Designer.Anchors;

type
  TAtlasGridCells = record
    Columns: Integer;
    Rows: Integer;
    /// <summary>Indizes der Controls in Zellenreihenfolge (zeilenweise).</summary>
    Order: TArray<Integer>;
  end;

  TAtlasContainerWrap = class
  public
    class function Enclosing(const ABounds: TArray<TRect>): TRect; static;
    /// <summary>Lage des neuen Containers im Parent.</summary>
    class function ContainerBounds(const ABounds: TArray<TRect>; APadding, ACaptionHeight: Integer): TRect; static;
    /// <summary>Lage im Container: AClientOffset ist der Abstand des Clients zur Außenkante.</summary>
    class function IntoContainer(const ABounds, AContainer: TRect; const AClientOffset: TPoint): TRect; static;
    /// <summary>Lage im Parent des Containers (Auflösen).</summary>
    class function OutOfContainer(const ABounds, AContainer: TRect; const AClientOffset: TPoint): TRect; static;
    /// <summary>Indizes nach TabOrder.</summary>
    class function ByTabOrder(const ATabOrders: TArray<Integer>): TArray<Integer>; static;
    /// <summary>Neue TabOrder der Kinder beim Auflösen: ab der des Containers, in ihrer Reihenfolge.</summary>
    class function UnwrapTabOrders(AContainerTabOrder: Integer;
      const AChildOrders: TArray<Integer>): TArray<Integer>; static;
    class function ContainerAnchors(const AChildAnchors: TArray<TAtlasAnchorSet>): TAtlasAnchorSet; static;
    class function GridCells(const ABounds: TArray<TRect>): TAtlasGridCells; static;
    /// <summary>Zeilen (ab 1) im Quelltext, die AName als Wort nennen, ohne Deklaration und Kommentar.</summary>
    class function References(const ASource, AName: string): TArray<Integer>; static;
    /// <summary>Namenspräfix für einen Container der Klasse AClassName.</summary>
    class function PrefixFor(const AClassName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Character;

class function TAtlasContainerWrap.Enclosing(const ABounds: TArray<TRect>): TRect;
var
  mBounds: TRect;
begin
  if Length(ABounds) = 0 then
  begin
    Exit(TRect.Empty);
  end;
  Result := ABounds[0];
  for mBounds in ABounds do
  begin
    Result := TRect.Union(Result, mBounds);
  end;
end;

class function TAtlasContainerWrap.ContainerBounds(const ABounds: TArray<TRect>;
  APadding, ACaptionHeight: Integer): TRect;
begin
  Result := Enclosing(ABounds);
  Result := Rect(Result.Left - APadding, Result.Top - APadding - ACaptionHeight, Result.Right + APadding,
    Result.Bottom + APadding);
end;

class function TAtlasContainerWrap.IntoContainer(const ABounds, AContainer: TRect; const AClientOffset: TPoint): TRect;
begin
  Result := ABounds;
  Result.Offset(-AContainer.Left - AClientOffset.X, -AContainer.Top - AClientOffset.Y);
end;

class function TAtlasContainerWrap.OutOfContainer(const ABounds, AContainer: TRect; const AClientOffset: TPoint): TRect;
begin
  Result := ABounds;
  Result.Offset(AContainer.Left + AClientOffset.X, AContainer.Top + AClientOffset.Y);
end;

class function TAtlasContainerWrap.ByTabOrder(const ATabOrders: TArray<Integer>): TArray<Integer>;
var
  mOuter, mInner, mSwap: Integer;
begin
  Result := nil;
  SetLength(Result, Length(ATabOrders));
  for mOuter := 0 to High(Result) do
  begin
    Result[mOuter] := mOuter;
  end;
  for mOuter := 1 to High(Result) do
  begin
    mInner := mOuter;
    while (mInner > 0) and (ATabOrders[Result[mInner]] < ATabOrders[Result[mInner - 1]]) do
    begin
      mSwap := Result[mInner];
      Result[mInner] := Result[mInner - 1];
      Result[mInner - 1] := mSwap;
      Dec(mInner);
    end;
  end;
end;

class function TAtlasContainerWrap.UnwrapTabOrders(AContainerTabOrder: Integer;
  const AChildOrders: TArray<Integer>): TArray<Integer>;
var
  mOrder: TArray<Integer>;
  mIndex: Integer;
begin
  mOrder := ByTabOrder(AChildOrders);
  Result := nil;
  SetLength(Result, Length(AChildOrders));
  for mIndex := 0 to High(mOrder) do
  begin
    Result[mOrder[mIndex]] := AContainerTabOrder + mIndex;
  end;
end;

class function TAtlasContainerWrap.ContainerAnchors(const AChildAnchors: TArray<TAtlasAnchorSet>): TAtlasAnchorSet;
var
  mAnchors: TAtlasAnchorSet;
begin
  if Length(AChildAnchors) = 0 then
  begin
    Exit([TAtlasAnchorSide.Left, TAtlasAnchorSide.Top]);
  end;
  Result := [TAtlasAnchorSide.Left, TAtlasAnchorSide.Top, TAtlasAnchorSide.Right, TAtlasAnchorSide.Bottom];
  for mAnchors in AChildAnchors do
  begin
    Result := Result * mAnchors;
  end;
  if not ((TAtlasAnchorSide.Left in Result) or (TAtlasAnchorSide.Right in Result)) then
  begin
    Include(Result, TAtlasAnchorSide.Left);
  end;
  if not ((TAtlasAnchorSide.Top in Result) or (TAtlasAnchorSide.Bottom in Result)) then
  begin
    Include(Result, TAtlasAnchorSide.Top);
  end;
end;

function SortedBy(const ABounds: TArray<TRect>; const AIndices: TArray<Integer>; AByLeft: Boolean): TArray<Integer>;
var
  mOuter, mInner, mSwap: Integer;

  function Before(A, B: Integer): Boolean;
  begin
    if AByLeft then
    begin
      Result := ABounds[A].Left < ABounds[B].Left;
    end
    else
    begin
      Result := (ABounds[A].Top < ABounds[B].Top) or ((ABounds[A].Top = ABounds[B].Top) and
        (ABounds[A].Left < ABounds[B].Left));
    end;
  end;

begin
  Result := Copy(AIndices);
  for mOuter := 1 to High(Result) do
  begin
    mInner := mOuter;
    while (mInner > 0) and Before(Result[mInner], Result[mInner - 1]) do
    begin
      mSwap := Result[mInner];
      Result[mInner] := Result[mInner - 1];
      Result[mInner - 1] := mSwap;
      Dec(mInner);
    end;
  end;
end;

class function TAtlasContainerWrap.GridCells(const ABounds: TArray<TRect>): TAtlasGridCells;
var
  mAll, mRow: TArray<Integer>;
  mIndex, mRowTop, mRowHalf: Integer;

  procedure CloseRow;
  begin
    if Length(mRow) > 0 then
    begin
      Result.Order := Result.Order + SortedBy(ABounds, mRow, True);
      Result.Columns := Max(Result.Columns, Length(mRow));
      Inc(Result.Rows);
      mRow := nil;
    end;
  end;

begin
  Result.Columns := 0;
  Result.Rows := 0;
  Result.Order := nil;
  mAll := nil;
  for mIndex := 0 to High(ABounds) do
  begin
    mAll := mAll + [mIndex];
  end;
  mRow := nil;
  mRowTop := 0;
  mRowHalf := 0;
  for mIndex in SortedBy(ABounds, mAll, False) do
  begin
    if (Length(mRow) > 0) and (ABounds[mIndex].Top > mRowTop + mRowHalf) then
    begin
      CloseRow;
    end;
    if Length(mRow) = 0 then
    begin
      mRowTop := ABounds[mIndex].Top;
      mRowHalf := ABounds[mIndex].Height div 2;
    end;
    mRow := mRow + [mIndex];
  end;
  CloseRow;
end;

function IsWordAt(const ALine, AName: string; APos: Integer): Boolean;
var
  mAfter: Integer;
begin
  mAfter := APos + Length(AName);
  Result := ((APos = 1) or not (ALine[APos - 1].IsLetterOrDigit or (ALine[APos - 1] = '_'))) and
    ((mAfter > Length(ALine)) or not (ALine[mAfter].IsLetterOrDigit or (ALine[mAfter] = '_')));
end;

function NamesWord(const ALine, AName: string): Boolean;
var
  mLower, mName: string;
  mPos: Integer;
begin
  mLower := LowerCase(ALine);
  mName := LowerCase(AName);
  mPos := Pos(mName, mLower);
  while mPos > 0 do
  begin
    if IsWordAt(mLower, mName, mPos) then
    begin
      Exit(True);
    end;
    mPos := Pos(mName, mLower, mPos + 1);
  end;
  Result := False;
end;

function IsDeclaration(const ALine, AName: string): Boolean;
var
  mText: string;
begin
  mText := LowerCase(Trim(ALine));
  Result := mText.StartsWith(LowerCase(AName)) and Trim(Copy(mText, Length(AName) + 1, MaxInt)).StartsWith(':');
end;

function IsComment(const ALine: string): Boolean;
var
  mText: string;
begin
  mText := Trim(ALine);
  Result := mText.StartsWith('//') or mText.StartsWith('{') or mText.StartsWith('(*');
end;

class function TAtlasContainerWrap.References(const ASource, AName: string): TArray<Integer>;
var
  mLines: TArray<string>;
  mIndex: Integer;
begin
  Result := nil;
  mLines := ASource.Replace(#13#10, #10).Split([#10]);
  for mIndex := 0 to High(mLines) do
  begin
    if NamesWord(mLines[mIndex], AName) and not IsDeclaration(mLines[mIndex], AName) and
      not IsComment(mLines[mIndex]) then
    begin
      Result := Result + [mIndex + 1];
    end;
  end;
end;

class function TAtlasContainerWrap.PrefixFor(const AClassName: string): string;
const
  cClasses: array[0..6] of string = ('TPanel', 'TGroupBox', 'TFlowPanel', 'TGridPanel', 'TScrollBox', 'TPageControl',
    'TTabSheet');
  cPrefixes: array[0..6] of string = ('pnl', 'gbx', 'fpn', 'gpn', 'sbx', 'pgc', 'tsh');
  /// <summary>Andere Klassen: die ersten Buchstaben des Namens ohne „T“, so lang wie die bekannten Präfixe.</summary>
  cPrefixLength = 3;
var
  mIndex: Integer;
begin
  for mIndex := Low(cClasses) to High(cClasses) do
  begin
    if SameText(AClassName, cClasses[mIndex]) then
    begin
      Exit(cPrefixes[mIndex]);
    end;
  end;
  Result := AClassName;
  if (Length(Result) > 1) and ((Result[1] = 'T') or (Result[1] = 't')) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
  Result := LowerCase(Copy(Result, 1, cPrefixLength));
end;

end.
