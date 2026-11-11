unit Atlas.Core.Designer.Neighbours;

// Räumliche Navigation im Designer (#745), ohne VCL und Windows: Nachbar
// einer Komponente in einer Richtung, Elternelement, erstes Kind und nächster
// Container derselben Ebene, alles auf Rechtecken im Client des Formulars.
// - Kandidaten: Geschwister (gleiches Elternelement), deren Mittelpunkt in
//   der Richtung jenseits der Kante des Bezugs liegt (kleine Toleranz für
//   Überlappung).
// - Gewichtung: Abstand in Bewegungsrichtung plus doppelt gewichteter
//   Versatz quer dazu; wer sich quer überlappt (gleiche Zeile bzw. Spalte),
//   geht vor.
// - Ohne Kandidaten und mit ACross: am Rand des Elternelements in dessen
//   Geschwister weiter, bei einem Container gleich in sein nächstes Kind.
// - Nichtvisuelle Komponenten nur untereinander, nie mit Steuerelementen.

interface

uses
  System.Types;

type
  TAtlasNeighbourItem = record
    Name: string;
    /// <summary>Name des Elternelements; '' = direkt auf dem Formular bzw. nichtvisuell.</summary>
    ParentName: string;
    /// <summary>Lage im Client des Formulars.</summary>
    Bounds: TRect;
    Visual: Boolean;
    /// <summary>Kann Steuerelemente aufnehmen (Panel, GroupBox …).</summary>
    Container: Boolean;
    class function Create(const AName, AParentName: string; const ABounds: TRect; AVisual,
      AContainer: Boolean): TAtlasNeighbourItem; static;
  end;

{$SCOPEDENUMS ON}
  TAtlasNeighbourDirection = (Left, Right, Up, Down);
{$SCOPEDENUMS OFF}

  TAtlasNeighbours = class
  public
    /// <summary>Index der Komponente AName; -1 ohne sie.</summary>
    class function IndexOf(const AItems: TArray<TAtlasNeighbourItem>; const AName: string): Integer; static;
    /// <summary>Nächste Komponente in ADirection von AFrom aus; -1 ohne.</summary>
    class function Find(const AItems: TArray<TAtlasNeighbourItem>; AFrom: Integer;
      ADirection: TAtlasNeighbourDirection; ACross: Boolean): Integer; static;
    /// <summary>Elternelement von AFrom; -1 direkt auf dem Formular.</summary>
    class function ParentOf(const AItems: TArray<TAtlasNeighbourItem>; AFrom: Integer): Integer; static;
    /// <summary>Kind oben links von AContainer; -1 ohne Kinder.</summary>
    class function FirstChild(const AItems: TArray<TAtlasNeighbourItem>; AContainer: Integer): Integer; static;
    /// <summary>Nächster (AForward) bzw. vorheriger Container auf der Ebene des Containers um AFrom, dort das
    /// erste Kind oder ohne Kinder der Container selbst; -1 ohne.</summary>
    class function NextContainer(const AItems: TArray<TAtlasNeighbourItem>; AFrom: Integer;
      AForward: Boolean): Integer; static;
  end;

implementation

uses
  System.SysUtils;

const
  /// <summary>Überlappung in Pixeln, die noch als „jenseits der Kante“ gilt.</summary>
  cTolerance = 4;
  /// <summary>Gewicht des Versatzes quer zur Bewegung.</summary>
  cCrossWeight = 2;

{ TAtlasNeighbourItem }

class function TAtlasNeighbourItem.Create(const AName, AParentName: string; const ABounds: TRect; AVisual,
  AContainer: Boolean): TAtlasNeighbourItem;
begin
  Result.Name := AName;
  Result.ParentName := AParentName;
  Result.Bounds := ABounds;
  Result.Visual := AVisual;
  Result.Container := AContainer;
end;

function CenterX(const ARect: TRect): Integer;
begin
  Result := (ARect.Left + ARect.Right) div 2;
end;

function CenterY(const ARect: TRect): Integer;
begin
  Result := (ARect.Top + ARect.Bottom) div 2;
end;

function Horizontal(ADirection: TAtlasNeighbourDirection): Boolean;
begin
  Result := ADirection in [TAtlasNeighbourDirection.Left, TAtlasNeighbourDirection.Right];
end;

/// <summary>Liegt der Mittelpunkt von ACandidate in ADirection jenseits der Kante von AFrom?</summary>
function Ahead(const AFrom, ACandidate: TRect; ADirection: TAtlasNeighbourDirection): Boolean;
begin
  case ADirection of
    TAtlasNeighbourDirection.Left:
      Result := (CenterX(ACandidate) <= AFrom.Left + cTolerance) and (CenterX(ACandidate) < CenterX(AFrom));
    TAtlasNeighbourDirection.Right:
      Result := (CenterX(ACandidate) >= AFrom.Right - cTolerance) and (CenterX(ACandidate) > CenterX(AFrom));
    TAtlasNeighbourDirection.Up:
      Result := (CenterY(ACandidate) <= AFrom.Top + cTolerance) and (CenterY(ACandidate) < CenterY(AFrom));
  else
    Result := (CenterY(ACandidate) >= AFrom.Bottom - cTolerance) and (CenterY(ACandidate) > CenterY(AFrom));
  end;
end;

/// <summary>Abstand in Bewegungsrichtung von Kante zu Kante, nie negativ.</summary>
function Along(const AFrom, ACandidate: TRect; ADirection: TAtlasNeighbourDirection): Integer;
begin
  case ADirection of
    TAtlasNeighbourDirection.Left:
      Result := AFrom.Left - ACandidate.Right;
    TAtlasNeighbourDirection.Right:
      Result := ACandidate.Left - AFrom.Right;
    TAtlasNeighbourDirection.Up:
      Result := AFrom.Top - ACandidate.Bottom;
  else
    Result := ACandidate.Top - AFrom.Bottom;
  end;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

/// <summary>Überlappen sich die Rechtecke quer zur Bewegung (gleiche Zeile bzw. Spalte)?</summary>
function Overlaps(const AFrom, ACandidate: TRect; ADirection: TAtlasNeighbourDirection): Boolean;
begin
  if Horizontal(ADirection) then
  begin
    Result := (ACandidate.Top < AFrom.Bottom) and (ACandidate.Bottom > AFrom.Top);
  end
  else
  begin
    Result := (ACandidate.Left < AFrom.Right) and (ACandidate.Right > AFrom.Left);
  end;
end;

/// <summary>Gewichteter Abstand: in Bewegungsrichtung plus doppelter Versatz quer, quer überlappend ohne Versatz.
/// </summary>
function Score(const AFrom, ACandidate: TRect; ADirection: TAtlasNeighbourDirection): Integer;
var
  mCross: Integer;
begin
  mCross := 0;
  if not Overlaps(AFrom, ACandidate, ADirection) then
  begin
    if Horizontal(ADirection) then
    begin
      mCross := Abs(CenterY(ACandidate) - CenterY(AFrom));
    end
    else
    begin
      mCross := Abs(CenterX(ACandidate) - CenterX(AFrom));
    end;
  end;
  Result := Along(AFrom, ACandidate, ADirection) + cCrossWeight * mCross;
end;

/// <summary>Ist ACandidate besser als ABest? Quer überlappend vor allen anderen, dann der kleinere Abstand.
/// </summary>
function Better(const AFrom, ACandidate, ABest: TRect; ADirection: TAtlasNeighbourDirection): Boolean;
var
  mCandidateOverlaps, mBestOverlaps: Boolean;
begin
  mCandidateOverlaps := Overlaps(AFrom, ACandidate, ADirection);
  mBestOverlaps := Overlaps(AFrom, ABest, ADirection);
  if mCandidateOverlaps <> mBestOverlaps then
  begin
    Exit(mCandidateOverlaps);
  end;
  Result := Score(AFrom, ACandidate, ADirection) < Score(AFrom, ABest, ADirection);
end;

/// <summary>Bester Kandidat aus ACandidates zum Bezug AFrom; -1 ohne.</summary>
function Best(const AItems: TArray<TAtlasNeighbourItem>; const AFrom: TRect; const ACandidates: TArray<Integer>;
  ADirection: TAtlasNeighbourDirection): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex in ACandidates do
  begin
    if (Result < 0) or Better(AFrom, AItems[mIndex].Bounds, AItems[Result].Bounds, ADirection) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Komponenten mit Elternelement AParentName und der Art AVisual, ohne AExcept.</summary>
function ChildrenOf(const AItems: TArray<TAtlasNeighbourItem>; const AParentName: string; AVisual: Boolean;
  AExcept: Integer): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AItems) do
  begin
    if (mIndex <> AExcept) and (AItems[mIndex].Visual = AVisual) and SameText(AItems[mIndex].ParentName,
      AParentName) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

/// <summary>Lesereihenfolge: weiter oben zuerst, in einer Zeile (Toleranz) weiter links.</summary>
function ReadsBefore(const A, B: TRect): Boolean;
begin
  if Abs(A.Top - B.Top) > cTolerance then
  begin
    Exit(A.Top < B.Top);
  end;
  Result := A.Left < B.Left;
end;

{ TAtlasNeighbours }

class function TAtlasNeighbours.IndexOf(const AItems: TArray<TAtlasNeighbourItem>; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems) do
  begin
    if SameText(AItems[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasNeighbours.ParentOf(const AItems: TArray<TAtlasNeighbourItem>; AFrom: Integer): Integer;
begin
  Result := -1;
  if (AFrom >= 0) and (AFrom <= High(AItems)) and (AItems[AFrom].ParentName <> '') then
  begin
    Result := IndexOf(AItems, AItems[AFrom].ParentName);
  end;
end;

class function TAtlasNeighbours.FirstChild(const AItems: TArray<TAtlasNeighbourItem>; AContainer: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  if (AContainer < 0) or (AContainer > High(AItems)) then
  begin
    Exit;
  end;
  for mIndex in ChildrenOf(AItems, AItems[AContainer].Name, True, AContainer) do
  begin
    if (Result < 0) or ReadsBefore(AItems[mIndex].Bounds, AItems[Result].Bounds, False) then
    begin
      Result := mIndex;
    end;
  end;
end;

class function TAtlasNeighbours.Find(const AItems: TArray<TAtlasNeighbourItem>; AFrom: Integer;
  ADirection: TAtlasNeighbourDirection; ACross: Boolean): Integer;
var
  mCandidates: TArray<Integer>;
  mIndex, mParent, mNext: Integer;
begin
  if (AFrom < 0) or (AFrom > High(AItems)) then
  begin
    Exit(-1);
  end;
  mCandidates := nil;
  for mIndex in ChildrenOf(AItems, AItems[AFrom].ParentName, AItems[AFrom].Visual, AFrom) do
  begin
    if Ahead(AItems[AFrom].Bounds, AItems[mIndex].Bounds, ADirection) then
    begin
      mCandidates := mCandidates + [mIndex];
    end;
  end;
  Result := Best(AItems, AItems[AFrom].Bounds, mCandidates, ADirection);
  mParent := ParentOf(AItems, AFrom);
  if (Result >= 0) or not ACross or (mParent < 0) then
  begin
    Exit;
  end;
  // Am Rand des Elternelements: in dessen Geschwister weiter, bei einem Container in sein nächstes Kind.
  mNext := Find(AItems, mParent, ADirection, True);
  Result := mNext;
  if (mNext >= 0) and AItems[mNext].Container then
  begin
    mIndex := Best(AItems, AItems[AFrom].Bounds, ChildrenOf(AItems, AItems[mNext].Name, True, mNext), ADirection);
    if mIndex >= 0 then
    begin
      Result := mIndex;
    end;
  end;
end;

class function TAtlasNeighbours.NextContainer(const AItems: TArray<TAtlasNeighbourItem>; AFrom: Integer;
  AForward: Boolean): Integer;
var
  mHome, mIndex: Integer;
begin
  Result := -1;
  mHome := ParentOf(AItems, AFrom);
  if (mHome < 0) and (AFrom >= 0) and (AFrom <= High(AItems)) and AItems[AFrom].Container then
  begin
    mHome := AFrom;
  end;
  if mHome < 0 then
  begin
    Exit;
  end;
  // Nächster in Lesereihenfolge nach (bzw. vor) dem eigenen Container.
  for mIndex in ChildrenOf(AItems, AItems[mHome].ParentName, True, mHome) do
  begin
    if not AItems[mIndex].Container or
      (ReadsBefore(AItems[mIndex].Bounds, AItems[mHome].Bounds, False) = AForward) then
    begin
      Continue;
    end;
    if (Result < 0) or (ReadsBefore(AItems[mIndex].Bounds, AItems[Result].Bounds, False) = AForward) then
    begin
      Result := mIndex;
    end;
  end;
  if FirstChild(AItems, Result) >= 0 then
  begin
    Result := FirstChild(AItems, Result);
  end;
end;

end.
