unit Atlas.Core.Editor.RegionFolds;

// Regionen ({$REGION} … {$ENDREGION}) beim Öffnen einer Datei auf- oder
// zuklappen (editor.regionFolds), ohne Open Tools API: Werte der Einstellung,
// Regionen im Text und die Reihenfolge, in der die IDE-Seite sie faltet.
// Die IDE kennt keinen Befehl „alle Regionen zuklappen“, nur „nächsten Block
// zu- bzw. aufklappen“ an der Schreibmarke (IOTAElideActions). Deshalb setzt
// die IDE-Seite die Marke nacheinander auf die Kopfzeile jeder Region:
// - Zuklappen innen zuerst, damit eine äußere Region ihre inneren schon
//   gefaltet einschließt; beim Öffnen bleibt die Region mit der Schreibmarke
//   (und alle um sie herum) offen, sonst müsste die Marke in eine gefaltete
//   Zeile zurück.
// - Aufklappen außen zuerst, damit die Kopfzeilen innerer Regionen sichtbar
//   sind, bevor die Marke dorthin springt.
// Zeilen 1-basiert wie im Editor. Eine Region zählt nur, wenn {$REGION} bzw.
// (*$REGION*) am Zeilenanfang steht (Leerraum davor erlaubt), ein passendes
// {$ENDREGION} folgt und sie mehr als eine Zeile umfasst.

interface

type
{$SCOPEDENUMS ON}
  /// <summary>Keep: beim Öffnen nichts ändern (Befehle bleiben); Collapse/Expand: beim Öffnen alle zu- bzw.
  /// aufklappen; Off: weder beim Öffnen noch Befehle.</summary>
  TAtlasRegionFoldMode = (Keep, Collapse, Expand, Off);
  // Reihenfolge wie AtlasRegionFoldModes (Atlas.Core.Settings.Plugin.Store).
{$SCOPEDENUMS OFF}

  /// <summary>Eine Region: Kopf- und Schlusszeile (1-basiert), Tiefe 0 = äußerste.</summary>
  TAtlasRegion = record
    StartLine: Integer;
    EndLine: Integer;
    Depth: Integer;
    class function Create(AStartLine, AEndLine, ADepth: Integer): TAtlasRegion; static;
    /// <summary>Liegt ALine in der Region (Kopf- und Schlusszeile eingeschlossen)?</summary>
    function Contains(ALine: Integer): Boolean;
  end;

  TAtlasRegionFolds = class
  public
    /// <summary>Modus zum Wert der Einstellung; Unbekanntes gilt als Keep.</summary>
    class function ModeOf(const AValue: string): TAtlasRegionFoldMode; static;
    /// <summary>Pascal-Datei, in der die IDE Regionen faltet (.pas, .dpr, .dpk, .inc)?</summary>
    class function IsPascal(const AFileName: string): Boolean; static;
    /// <summary>Regionen im Text, nach Kopfzeile geordnet.</summary>
    class function Find(const AText: string): TArray<TAtlasRegion>; static;
    /// <summary>Kopfzeilen, auf die die IDE-Seite nacheinander die Marke setzt: Collapse innen zuerst ohne die
    /// Regionen um AKeepLine (0 = alle), Expand außen zuerst; Keep und Off nichts.</summary>
    class function Order(const ARegions: TArray<TAtlasRegion>; AMode: TAtlasRegionFoldMode;
      AKeepLine: Integer): TArray<Integer>; static;
    /// <summary>Wohin die Marke nach dem Zuklappen aller Regionen gehört: Kopfzeile der äußersten Region um
    /// ALine, sonst ALine.</summary>
    class function VisibleLine(const ARegions: TArray<TAtlasRegion>; ALine: Integer): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Core.Settings.Plugin.Store;

{$SCOPEDENUMS ON}

type
  /// <summary>Art einer Zeile für die Regionen.</summary>
  TRegionLine = (Other, Start, Finish);
  /// <summary>Reihenfolge der Regionen: nach Kopfzeile, innen zuerst, außen zuerst.</summary>
  TRegionOrder = (ByLine, InnerFirst, OuterFirst);
{$SCOPEDENUMS OFF}

/// <summary>Beginnt AText (ab dem ersten Zeichen) mit APrefix, ohne dass ein Bezeichner weitergeht?</summary>
function StartsWithWord(const AText, APrefix: string): Boolean;
var
  mNext: Char;
begin
  Result := StartsText(APrefix, AText);
  if Result and (Length(AText) > Length(APrefix)) then
  begin
    mNext := AText[Length(APrefix) + 1];
    Result := not CharInSet(mNext, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
  end;
end;

/// <summary>Kopf, Schluss oder sonst etwas; Kopf und Schluss in einer Zeile falten nichts.</summary>
function KindOf(const ALine: string): TRegionLine;
var
  mText: string;
begin
  Result := TRegionLine.Other;
  mText := TrimLeft(ALine);
  if (StartsWithWord(mText, '{$REGION') or StartsWithWord(mText, '(*$REGION')) and
    not ContainsText(mText, '$ENDREGION') then
  begin
    Result := TRegionLine.Start;
  end
  else if StartsWithWord(mText, '{$ENDREGION') or StartsWithWord(mText, '(*$ENDREGION') then
  begin
    Result := TRegionLine.Finish;
  end;
end;

/// <summary>Kommt A vor B in der Reihenfolge AOrder? Gleich tiefe Regionen nach der Kopfzeile.</summary>
function Before(const A, B: TAtlasRegion; AOrder: TRegionOrder): Boolean;
begin
  if (AOrder = TRegionOrder.ByLine) or (A.Depth = B.Depth) then
  begin
    Result := A.StartLine < B.StartLine;
  end
  else
  begin
    Result := (A.Depth > B.Depth) = (AOrder = TRegionOrder.InnerFirst);
  end;
end;

/// <summary>Ordnet AItems durch Einfügen (stabil, eindeutig über die Kopfzeile); Regionen einer Datei sind wenige.
/// </summary>
procedure SortRegions(var AItems: TArray<TAtlasRegion>; AOrder: TRegionOrder);
var
  mIndex, mPos: Integer;
  mItem: TAtlasRegion;
begin
  for mIndex := 1 to High(AItems) do
  begin
    mItem := AItems[mIndex];
    mPos := mIndex;
    while (mPos > 0) and Before(mItem, AItems[mPos - 1], AOrder) do
    begin
      AItems[mPos] := AItems[mPos - 1];
      Dec(mPos);
    end;
    AItems[mPos] := mItem;
  end;
end;

/// <summary>Schlusszeile ALine: schließt die zuletzt geöffnete Region; Schluss ohne Kopf und einzeilige Regionen
/// zählen nicht.</summary>
procedure CloseRegion(AOpen: TStack<Integer>; AFound: TList<TAtlasRegion>; ALine: Integer);
var
  mStart: Integer;
begin
  if AOpen.Count = 0 then
  begin
    Exit;
  end;
  mStart := AOpen.Pop;
  if ALine > mStart then
  begin
    AFound.Add(TAtlasRegion.Create(mStart, ALine, AOpen.Count));
  end;
end;

{ TAtlasRegion }

class function TAtlasRegion.Create(AStartLine, AEndLine, ADepth: Integer): TAtlasRegion;
begin
  Result.StartLine := AStartLine;
  Result.EndLine := AEndLine;
  Result.Depth := ADepth;
end;

function TAtlasRegion.Contains(ALine: Integer): Boolean;
begin
  Result := (ALine >= StartLine) and (ALine <= EndLine);
end;

{ TAtlasRegionFolds }

class function TAtlasRegionFolds.ModeOf(const AValue: string): TAtlasRegionFoldMode;
var
  mMode: TAtlasRegionFoldMode;
begin
  Result := TAtlasRegionFoldMode.Keep;
  for mMode := Low(TAtlasRegionFoldMode) to High(TAtlasRegionFoldMode) do
  begin
    if SameText(AValue, AtlasRegionFoldModes[Ord(mMode)]) then
    begin
      Result := mMode;
    end;
  end;
end;

class function TAtlasRegionFolds.IsPascal(const AFileName: string): Boolean;
var
  mExt: string;
begin
  mExt := LowerCase(ExtractFileExt(AFileName));
  Result := (mExt = '.pas') or (mExt = '.dpr') or (mExt = '.dpk') or (mExt = '.inc');
end;

class function TAtlasRegionFolds.Find(const AText: string): TArray<TAtlasRegion>;
var
  mLines: TArray<string>;
  mOpen: TStack<Integer>;
  mFound: TList<TAtlasRegion>;
  mIndex: Integer;
begin
  mLines := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  mOpen := TStack<Integer>.Create;
  mFound := TList<TAtlasRegion>.Create;
  try
    for mIndex := 0 to High(mLines) do
    begin
      case KindOf(mLines[mIndex]) of
        TRegionLine.Start:
          mOpen.Push(mIndex + 1);
        TRegionLine.Finish:
          CloseRegion(mOpen, mFound, mIndex + 1);
      end;
    end;
    Result := mFound.ToArray;
    // Gefunden in der Reihenfolge der Schlusszeilen (innere zuerst).
    SortRegions(Result, TRegionOrder.ByLine);
  finally
    mFound.Free;
    mOpen.Free;
  end;
end;

class function TAtlasRegionFolds.Order(const ARegions: TArray<TAtlasRegion>; AMode: TAtlasRegionFoldMode;
  AKeepLine: Integer): TArray<Integer>;
var
  mItems: TArray<TAtlasRegion>;
  mRegion: TAtlasRegion;
  mList: TList<Integer>;
begin
  Result := nil;
  if not (AMode in [TAtlasRegionFoldMode.Collapse, TAtlasRegionFoldMode.Expand]) then
  begin
    Exit;
  end;
  mItems := Copy(ARegions);
  if AMode = TAtlasRegionFoldMode.Collapse then
  begin
    SortRegions(mItems, TRegionOrder.InnerFirst);
  end
  else
  begin
    SortRegions(mItems, TRegionOrder.OuterFirst);
  end;
  mList := TList<Integer>.Create;
  try
    for mRegion in mItems do
    begin
      if (AMode = TAtlasRegionFoldMode.Expand) or (AKeepLine <= 0) or not mRegion.Contains(AKeepLine) then
      begin
        mList.Add(mRegion.StartLine);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TAtlasRegionFolds.VisibleLine(const ARegions: TArray<TAtlasRegion>; ALine: Integer): Integer;
var
  mRegion: TAtlasRegion;
  mDepth: Integer;
begin
  Result := ALine;
  mDepth := MaxInt;
  for mRegion in ARegions do
  begin
    if mRegion.Contains(ALine) and (mRegion.Depth < mDepth) then
    begin
      Result := mRegion.StartLine;
      mDepth := mRegion.Depth;
    end;
  end;
end;

end.
