unit Atlas.Core.Debug.EvaluateRows;

// Entscheidungen des Fensters „Auswerten“ (#784) über die Zeilen, ohne IDE prüfbar (#1967): Ergebnis eines
// Auswerters an einen Knoten, Fehlertext „kein Zugriff“ (#840), Knoten neu auswerten, Felder aus dem Index beim
// Umschalten der Nebenwirkungen neu holen, Antwort der Feldanfrage, festgeheftete Zeilen beim Projektwechsel.
// Die IDE (Atlas.IDE.Debug.Evaluate) wertet aus, zeigt an und führt die Zeitscheiben.

interface

uses
  System.Generics.Collections,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.Evaluate;

type
  /// <summary>Kennzeichnung „kein Zugriff“: Beschriftung ('' abgeschaltet) und zusätzliche Muster.</summary>
  TAtlasEvalUnavailable = record
    Caption: string;
    Patterns: TArray<string>;
    class function Create(const ACaption: string; const APatterns: TArray<string>): TAtlasEvalUnavailable; static;
  end;

  TAtlasEvalRows = class
  public
    /// <summary>Fehlertext AText; mit Beschriftung davor, wenn er „kein Zugriff“ bedeutet.</summary>
    class function ErrorText(const AText: string; const AUnavailable: TAtlasEvalUnavailable): string; static;
    /// <summary>AValue an ANode in AList: Wert, Fehler oder (ohne Ergebnis) nicht verfügbar.</summary>
    class procedure PutValue(AList: TAtlasEvalList; ANode: TAtlasEvalNode; const AValue: TAtlasDebugValue;
      const AUnavailable: TAtlasEvalUnavailable); static;
    /// <summary>ANode und seine Felder neu auswerten; Teile entstehen aus dem neuen Wert.</summary>
    class procedure MarkPending(ANode: TAtlasEvalNode); static;
    /// <summary>Aufgeklappte Felder aus dem Index unter ANode leeren und ihre Schlüssel in AReload sammeln: Mit
    /// Nebenwirkungen kommen Eigenschaften dazu bzw. fallen weg.</summary>
    class procedure CollectIndexFields(ANode: TAtlasEvalNode; AReload: TList<string>); static;
    /// <summary>Schlüssel aller Wurzeln von AList wie CollectIndexFields.</summary>
    class function IndexFieldKeys(AList: TAtlasEvalList): TArray<string>; static;
    /// <summary>Gehört AKey zur Zeile ARowKey oder zu einem ihrer Felder?</summary>
    class function Covers(const ARowKey, AKey: string): Boolean; static;
    /// <summary>Felder AFields für ANode übernehmen; ohne Felder die Teile des Werts, ohne beides „(keine Felder)“.
    /// False, wenn nichts zu tun ist (Knoten weg oder Felder des Index schon da).</summary>
    class function AcceptFields(AList: TAtlasEvalList; ANode: TAtlasEvalNode;
      const AFields: TArray<string>): Boolean; static;
    /// <summary>Festgeheftete Zeilen von AList durch APinned ersetzen (jüngste zuerst gespeichert, angefügt älteste
    /// zuerst); ohne angehaltenen Prozess (AStopped) nicht verfügbar.</summary>
    class procedure ReplacePinned(AList: TAtlasEvalList; const APinned: TArray<string>; AStopped: Boolean); static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.Unavailable;

{ TAtlasEvalUnavailable }

class function TAtlasEvalUnavailable.Create(const ACaption: string;
  const APatterns: TArray<string>): TAtlasEvalUnavailable;
begin
  Result.Caption := ACaption;
  Result.Patterns := APatterns;
end;

{ TAtlasEvalRows }

class function TAtlasEvalRows.ErrorText(const AText: string; const AUnavailable: TAtlasEvalUnavailable): string;
begin
  Result := AText;
  if (AUnavailable.Caption <> '') and TAtlasDebugUnavailable.IsUnavailable(AText, AUnavailable.Patterns) then
  begin
    Result := AUnavailable.Caption + ' ' + Result;
  end;
end;

class procedure TAtlasEvalRows.PutValue(AList: TAtlasEvalList; ANode: TAtlasEvalNode;
  const AValue: TAtlasDebugValue; const AUnavailable: TAtlasEvalUnavailable);
begin
  case AValue.State of
    TAtlasDebugValueState.Value:
      AList.SetResult(ANode, True, AValue.Text);
    TAtlasDebugValueState.Failed:
      AList.SetResult(ANode, False, ErrorText(AValue.Text, AUnavailable));
  else
    ANode.State := TAtlasEvalState.Unavailable;
  end;
end;

class procedure TAtlasEvalRows.MarkPending(ANode: TAtlasEvalNode);
var
  mIndex: Integer;
begin
  if ANode.FromParts then
  begin
    ANode.ClearChildren;
  end;
  if ANode.Expression <> '' then
  begin
    ANode.State := TAtlasEvalState.Pending;
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    MarkPending(ANode.Children[mIndex]);
  end;
end;

class procedure TAtlasEvalRows.CollectIndexFields(ANode: TAtlasEvalNode; AReload: TList<string>);
var
  mIndex: Integer;
begin
  if ANode.Expanded and ANode.ChildrenLoaded and not ANode.FromParts then
  begin
    ANode.ClearChildren;
    AReload.Add(ANode.Key);
    Exit;
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    CollectIndexFields(ANode.Children[mIndex], AReload);
  end;
end;

class function TAtlasEvalRows.IndexFieldKeys(AList: TAtlasEvalList): TArray<string>;
var
  mReload: TList<string>;
  mIndex: Integer;
begin
  mReload := TList<string>.Create;
  try
    for mIndex := 0 to AList.Count - 1 do
    begin
      CollectIndexFields(AList.Roots[mIndex], mReload);
    end;
    Result := mReload.ToArray;
  finally
    mReload.Free;
  end;
end;

class function TAtlasEvalRows.Covers(const ARowKey, AKey: string): Boolean;
begin
  Result := (AKey <> '') and ((AKey = ARowKey) or AKey.StartsWith(ARowKey + #1));
end;

class function TAtlasEvalRows.AcceptFields(AList: TAtlasEvalList; ANode: TAtlasEvalNode;
  const AFields: TArray<string>): Boolean;
begin
  // Felder des Index ersetzen Teile, die der Wert inzwischen geliefert hat (SetResult bei aufgeklapptem Knoten).
  Result := (ANode <> nil) and not (ANode.ChildrenLoaded and not ANode.FromParts);
  if not Result then
  begin
    Exit;
  end;
  if Length(AFields) > 0 then
  begin
    AList.SetFields(ANode, AFields);
  end
  else if not ANode.ChildrenLoaded and not AList.SetParts(ANode) then
  begin
    // Weder Felder noch Teile: aufgeklappt mit „(keine Felder)“.
    AList.SetFields(ANode, nil);
  end;
end;

class procedure TAtlasEvalRows.ReplacePinned(AList: TAtlasEvalList; const APinned: TArray<string>;
  AStopped: Boolean);
var
  mIndex: Integer;
  mNode: TAtlasEvalNode;
begin
  for mIndex := AList.Count - 1 downto 0 do
  begin
    if AList.Roots[mIndex].Pinned then
    begin
      AList.Delete(mIndex);
    end;
  end;
  for mIndex := High(APinned) downto 0 do
  begin
    mNode := AList.Add(APinned[mIndex]);
    if mNode = nil then
    begin
      Continue;
    end;
    mNode.Pinned := True;
    if not AStopped then
    begin
      mNode.State := TAtlasEvalState.Unavailable;
    end;
  end;
end;

end.
