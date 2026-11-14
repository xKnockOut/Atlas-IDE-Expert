unit Atlas.Core.Debug.BreakpointAnchors;

// Haltepunkte wandern mit dem Code (#841), Kern ohne IDE: Zu jedem
// Haltepunkt merkt sich Atlas einen Anker (TAtlasMethodAnchor, derselbe wie
// bei den Haltepunkt-Sätzen #586). Ändert sich der Text einer Datei, sagt
// Follow je Haltepunkt:
// - Keep: Zeile und Umfeld stehen noch an der Stelle des Haltepunkts (auch,
//   wenn die IDE ihn beim Bearbeiten selbst mitgenommen hat), oder die Suche
//   findet ihn dort.
// - Move: Die Suche über Methode und Zeilentext (TAtlasMethodAnchors.Find)
//   findet die Zeile woanders. Ist die Methode umbenannt, zählt ein Treffer
//   in der ganzen Datei mit gleichem Inhalt und Umfeld.
// - Orphan: nicht eindeutig; Line ist dann der Vorschlag (gleicher Abstand im
//   Rumpf der Methode, sonst die bisherige Zeile). Atlas löscht nichts still.
// JSON: {"format": 1, "breakpoints": [{"file", "at" (Zeile des Haltepunkts ab
// 1) und die Felder des Ankers}]}.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Editor.MethodAnchor;

type
  /// <summary>Haltepunkt mit seinem Anker.</summary>
  TAtlasAnchoredBreakpoint = record
    FileName: string;
    /// <summary>Zeile des Haltepunkts in der IDE, ab 0.</summary>
    Line: Integer;
    Anchor: TAtlasMethodAnchor;
    class function Create(const AFileName: string; ALine: Integer;
      const AAnchor: TAtlasMethodAnchor): TAtlasAnchoredBreakpoint; static;
  end;

  TAtlasAnchoredBreakpoints = TArray<TAtlasAnchoredBreakpoint>;

  {$SCOPEDENUMS ON}
  TAtlasAnchorStep = (Keep, Move, Orphan);
  {$SCOPEDENUMS OFF}

  TAtlasAnchorResult = record
    Step: TAtlasAnchorStep;
    /// <summary>Keep: bisherige Zeile; Move: neue Zeile; Orphan: Vorschlag (ab 0).</summary>
    Line: Integer;
  end;

  /// <summary>Verschiebung eines Haltepunkts (Zeilen ab 0), für das Nachziehen und „Rückgängig“.</summary>
  TAtlasAnchorMove = record
    FileName: string;
    FromLine: Integer;
    ToLine: Integer;
    class function Create(const AFileName: string; AFromLine, AToLine: Integer): TAtlasAnchorMove; static;
  end;

  TAtlasAnchorMoves = TArray<TAtlasAnchorMove>;

  /// <summary>Verwaister Haltepunkt mit Vorschlag (Zeile ab 0).</summary>
  TAtlasAnchorOrphan = record
    Item: TAtlasAnchoredBreakpoint;
    Suggestion: Integer;
  end;

  TAtlasAnchorOrphans = TArray<TAtlasAnchorOrphan>;

  TAtlasBreakpointAnchors = class
  public const
    cFormat = 1;
    /// <summary>So viele Zeilen mehr oder weniger auf einmal gelten als Änderung von außen (Formatierer,
    /// Code-Aktion, Einfügen).</summary>
    cBulkLines = 5;
  public
    /// <summary>Haltepunkte nachziehen? Ja bei einer Datei, die Atlas in dieser Sitzung noch nicht gesehen hat
    /// (Änderung bei geschlossener IDE), bei geänderter Datei auf der Platte (neu geladen, Branchwechsel) und bei
    /// cBulkLines oder mehr Zeilen Unterschied. Sonst bearbeitet der Benutzer die Datei, und die IDE nimmt ihre
    /// Haltepunkte selbst mit.</summary>
    class function IsExternal(AKnown, ADiskChanged: Boolean; AOldLines, ANewLines: Integer): Boolean; static;
    /// <summary>Reihenfolge, in der sich Verschiebungen nicht gegenseitig im Weg stehen: nach unten die untersten
    /// zuerst, dann nach oben die obersten zuerst; ohne Verschiebungen auf dieselbe Zeile.</summary>
    class function Ordered(const AMoves: TAtlasAnchorMoves): TAtlasAnchorMoves; static;
    /// <summary>Verschiebungen für „Rückgängig“: zurück an die alten Zeilen, in passender Reihenfolge.</summary>
    class function Reversed(const AMoves: TAtlasAnchorMoves): TAtlasAnchorMoves; static;
    /// <summary>Wohin gehört AItem im Text AText (Ablauf oben)?</summary>
    class function Follow(const AText: TAtlasMethodAnchorText;
      const AItem: TAtlasAnchoredBreakpoint): TAtlasAnchorResult; overload; static;
    class function Follow(const AText: string; const AItem: TAtlasAnchoredBreakpoint): TAtlasAnchorResult;
      overload; static;
    /// <summary>Schlüssel für Datei und Zeile (ohne Groß-/Kleinschreibung).</summary>
    class function Key(const AFileName: string; ALine: Integer): string; static;
    class function ToJson(const AItems: TAtlasAnchoredBreakpoints): string; static;
    /// <summary>False bei fremdem Format.</summary>
    class function Parse(const AJson: string; out AItems: TAtlasAnchoredBreakpoints): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Editor.LineAnchor,
  Atlas.Core.Editor.MethodToggle,
  Atlas.Text.Json;

{ TAtlasAnchoredBreakpoint }

class function TAtlasAnchoredBreakpoint.Create(const AFileName: string; ALine: Integer;
  const AAnchor: TAtlasMethodAnchor): TAtlasAnchoredBreakpoint;
begin
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Anchor := AAnchor;
end;

{ TAtlasAnchorMove }

class function TAtlasAnchorMove.Create(const AFileName: string; AFromLine, AToLine: Integer): TAtlasAnchorMove;
begin
  Result.FileName := AFileName;
  Result.FromLine := AFromLine;
  Result.ToLine := AToLine;
end;

{ TAtlasBreakpointAnchors }

class function TAtlasBreakpointAnchors.IsExternal(AKnown, ADiskChanged: Boolean;
  AOldLines, ANewLines: Integer): Boolean;
begin
  Result := (not AKnown) or ADiskChanged or (Abs(ANewLines - AOldLines) >= cBulkLines);
end;

/// <summary>Rang einer Verschiebung: nach unten vor nach oben.</summary>
function Downward(const AMove: TAtlasAnchorMove): Boolean;
begin
  Result := AMove.ToLine > AMove.FromLine;
end;

function CompareMoves(const ALeft, ARight: TAtlasAnchorMove): Integer;
begin
  if Downward(ALeft) <> Downward(ARight) then
  begin
    Exit(Ord(Downward(ARight)) - Ord(Downward(ALeft)));
  end;
  if ALeft.FromLine <> ARight.FromLine then
  begin
    Result := ALeft.FromLine - ARight.FromLine;
    if Downward(ALeft) then
    begin
      Result := -Result;
    end;
    Exit;
  end;
  Result := CompareText(ALeft.FileName, ARight.FileName);
end;

class function TAtlasBreakpointAnchors.Ordered(const AMoves: TAtlasAnchorMoves): TAtlasAnchorMoves;
var
  mMove: TAtlasAnchorMove;
  mCount: Integer;
begin
  SetLength(Result, Length(AMoves));
  mCount := 0;
  for mMove in AMoves do
  begin
    if mMove.FromLine <> mMove.ToLine then
    begin
      Result[mCount] := mMove;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
  TArray.Sort<TAtlasAnchorMove>(Result, TComparer<TAtlasAnchorMove>.Construct(CompareMoves));
end;

class function TAtlasBreakpointAnchors.Reversed(const AMoves: TAtlasAnchorMoves): TAtlasAnchorMoves;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AMoves));
  for mIndex := 0 to High(AMoves) do
  begin
    Result[mIndex] := TAtlasAnchorMove.Create(AMoves[mIndex].FileName, AMoves[mIndex].ToLine,
      AMoves[mIndex].FromLine);
  end;
  Result := Ordered(Result);
end;

/// <summary>Gleicher Inhalt und gleiches Umfeld, gleich an welcher Zeile.</summary>
function SameContext(const AHere, AAnchor: TAtlasLineAnchor): Boolean;
var
  mAnchor: TAtlasLineAnchor;
begin
  mAnchor := AAnchor;
  mAnchor.Line := AHere.Line;
  Result := AHere.SameAs(mAnchor);
end;

function StepResult(AStep: TAtlasAnchorStep; ALine: Integer): TAtlasAnchorResult;
begin
  Result.Step := AStep;
  Result.Line := ALine;
end;

/// <summary>Vorschlag für einen verwaisten Haltepunkt: gleicher Abstand im ersten Rumpf der Methode, sonst die
/// bisherige Zeile (in der Datei).</summary>
function Suggestion(const AText: TAtlasMethodAnchorText; const AItem: TAtlasAnchoredBreakpoint): Integer;
var
  mPlace: TAtlasMethodPlace;
begin
  Result := EnsureRange(AItem.Line, 0, Max(0, High(AText.Lines)));
  if AItem.Anchor.Method = '' then
  begin
    Exit;
  end;
  for mPlace in AText.Places do
  begin
    if mPlace.IsBody and SameText(mPlace.Name, AItem.Anchor.Method) then
    begin
      Exit(Min(mPlace.FirstLine + AItem.Anchor.Offset, mPlace.LastLine));
    end;
  end;
end;

/// <summary>Methode umbenannt oder Zeile verschwunden: in der ganzen Datei suchen. Gleicher Inhalt verschiebt,
/// sonst verwaist mit Vorschlag.</summary>
function FollowInFile(const AText: TAtlasMethodAnchorText; const AItem: TAtlasAnchoredBreakpoint): TAtlasAnchorResult;
var
  mAnchor: TAtlasLineAnchor;
  mLine: Integer;
  mMatch: TAtlasLineMatch;
begin
  mAnchor := AItem.Anchor.Anchor;
  mAnchor.Line := AItem.Line;
  mMatch := TAtlasLineAnchors.Locate(AText.Lines, mAnchor, mLine);
  if mMatch = TAtlasLineMatch.Same then
  begin
    Exit(StepResult(TAtlasAnchorStep.Keep, AItem.Line));
  end;
  if mMatch = TAtlasLineMatch.Moved then
  begin
    Exit(StepResult(TAtlasAnchorStep.Move, mLine));
  end;
  Result := StepResult(TAtlasAnchorStep.Orphan, Suggestion(AText, AItem));
end;

class function TAtlasBreakpointAnchors.Follow(const AText: TAtlasMethodAnchorText;
  const AItem: TAtlasAnchoredBreakpoint): TAtlasAnchorResult;
var
  mHere, mAnchor: TAtlasMethodAnchor;
  mLine: Integer;
begin
  mHere := TAtlasMethodAnchors.Capture(AText, AItem.Line);
  if (AItem.Line <= High(AText.Lines)) and SameContext(mHere.Anchor, AItem.Anchor.Anchor) then
  begin
    Exit(StepResult(TAtlasAnchorStep.Keep, AItem.Line));
  end;
  mAnchor := AItem.Anchor;
  mAnchor.Anchor.Line := AItem.Line;
  if TAtlasMethodAnchors.Find(AText, mAnchor, mLine) = TAtlasLineMatch.Orphaned then
  begin
    Exit(FollowInFile(AText, AItem));
  end;
  if mLine = AItem.Line then
  begin
    Exit(StepResult(TAtlasAnchorStep.Keep, mLine));
  end;
  Result := StepResult(TAtlasAnchorStep.Move, mLine);
end;

class function TAtlasBreakpointAnchors.Follow(const AText: string;
  const AItem: TAtlasAnchoredBreakpoint): TAtlasAnchorResult;
begin
  Result := Follow(TAtlasMethodAnchorText.Create(AText), AItem);
end;

class function TAtlasBreakpointAnchors.Key(const AFileName: string; ALine: Integer): string;
begin
  Result := LowerCase(AFileName) + '|' + IntToStr(ALine);
end;

class function TAtlasBreakpointAnchors.ToJson(const AItems: TAtlasAnchoredBreakpoints): string;
var
  mRoot, mObject: TJSONObject;
  mList: TJSONArray;
  mItem: TAtlasAnchoredBreakpoint;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(cFormat));
    mList := TJSONArray.Create;
    mRoot.AddPair('breakpoints', mList);
    for mItem in AItems do
    begin
      mObject := TJSONObject.Create;
      mList.AddElement(mObject);
      mObject.AddPair('file', mItem.FileName);
      mObject.AddPair('at', TJSONNumber.Create(mItem.Line + 1));
      TAtlasMethodAnchors.AddTo(mObject, mItem.Anchor);
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

class function TAtlasBreakpointAnchors.Parse(const AJson: string; out AItems: TAtlasAnchoredBreakpoints): Boolean;
var
  mValue: TJSONValue;
  mRoot, mObject: TJSONObject;
  mList: TJSONArray;
  mIndex: Integer;
begin
  AItems := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    mRoot := TJsonRead.AsObject(mValue);
    Result := (mRoot <> nil) and (TJsonRead.IntOr(mRoot, 'format', 0) = cFormat);
    mList := nil;
    if Result then
    begin
      mList := TJsonRead.Items(mRoot, 'breakpoints');
    end;
    if mList = nil then
    begin
      Exit;
    end;
    for mIndex := 0 to mList.Count - 1 do
    begin
      mObject := TJsonRead.AsObject(mList.Items[mIndex]);
      if (mObject <> nil) and (TJsonRead.Text(mObject, 'file') <> '') then
      begin
        AItems := AItems + [TAtlasAnchoredBreakpoint.Create(TJsonRead.Text(mObject, 'file'),
          Max(0, TJsonRead.IntOr(mObject, 'at', 1) - 1), TAtlasMethodAnchors.ReadFrom(mObject))];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

end.
