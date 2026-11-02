unit Atlas.Core.UnitSearch.UseUnit;

// Modi „Unit verwenden“ (Alt+F11) und „Formulare suchen“ (Umschalt+F12) des
// Fensters „Units suchen“ (#786), Teil ohne VCL und Open Tools API:
// - Parse liest die Antwort von atlas.useUnitInfo ({"found", "unit", "file",
//   "inUses", "cycles": [{"name", "file", "interfacePath", "path"}],
//   "generation"}).
// - Marks ordnet jeder Zeile des Fensters zu, ob die Unit schon in einer
//   uses-Liste der aktiven Unit steht (auch kurz geschrieben, etwa SysUtils
//   für System.SysUtils, oder die aktive Unit selbst) und welcher Kreis ihre
//   Aufnahme schlösse.
// - CycleState: Ins interface aufgenommen schließt ein Rückweg nur über
//   interface-uses einen Kreis, den der Compiler ablehnt (Warnung); jeder
//   andere Kreis ist erlaubt und nur ein Hinweis.
// - Addable lässt Units weg, die schon in uses stehen, die aktive Unit und
//   Include-Dateien; AddUsesArguments baut [uri, [Namen], {"section"}] für
//   atlas.server.addUses.
// - Formulare suchen setzt den Filter FormsFilter (Tippsyntax) bzw. die Arten
//   FormKinds.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.UnitSearch.Model;

type
{$SCOPEDENUMS ON}
  TAtlasUnitSearchMode = (Search, UseUnit, Forms);
  TAtlasUseUnitSection = (Interface_, Implementation_);
  TAtlasUseUnitCycleState = (None, Hint, Warning);
{$SCOPEDENUMS OFF}

  TAtlasUseUnitCycle = record
    Name: string;
    FileName: string;
    /// <summary>Kreis nur über interface-uses ("A → B → A"); '' ohne.</summary>
    InterfacePath: string;
    /// <summary>Kürzester Kreis über alle uses.</summary>
    Path: string;
  end;

  TAtlasUseUnitInfo = record
    Found: Boolean;
    UnitName: string;
    FileName: string;
    /// <summary>Einträge beider uses-Listen der aktiven Unit, wie geschrieben.</summary>
    InUses: TArray<string>;
    Cycles: TArray<TAtlasUseUnitCycle>;
    Generation: Int64;
  end;

  /// <summary>Zustand einer Zeile im Modus „Unit verwenden“.</summary>
  TAtlasUseUnitMark = record
    /// <summary>Steht schon in uses oder ist die aktive Unit selbst.</summary>
    InUses: Boolean;
    /// <summary>Index in TAtlasUseUnitInfo.Cycles; -1 ohne Kreis.</summary>
    Cycle: Integer;
  end;

  TAtlasUseUnit = class
  public const
    Command = 'atlas.useUnitInfo';
    FormsFilter = 't:form|frame|dm';
  public
    /// <summary>[uri] für atlas.useUnitInfo.</summary>
    class function Arguments(const AUri: string): string; static;
    /// <summary>Antwort von atlas.useUnitInfo; False bei leerer oder unlesbarer Antwort.</summary>
    class function Parse(const AJson: string; out AInfo: TAtlasUseUnitInfo): Boolean; static;
    /// <summary>Steht AName schon in uses (oder ist es die aktive Unit)?</summary>
    class function InUses(const AInfo: TAtlasUseUnitInfo; const AName: string): Boolean; static;
    /// <summary>Je Eintrag von AEntries: schon in uses, Kreis.</summary>
    class function Marks(const AInfo: TAtlasUseUnitInfo; const AEntries: TAtlasUnitEntries): TArray<TAtlasUseUnitMark>;
      static;
    /// <summary>Warnung, Hinweis oder nichts für die Aufnahme in ASection.</summary>
    class function CycleState(const ACycle: TAtlasUseUnitCycle; ASection: TAtlasUseUnitSection):
      TAtlasUseUnitCycleState; static;
    /// <summary>Der Kreis, den die Aufnahme in ASection schlösse.</summary>
    class function CyclePath(const ACycle: TAtlasUseUnitCycle; ASection: TAtlasUseUnitSection): string; static;
    /// <summary>Die Unit, über die der Kreis zur aktiven Unit zurückführt (die letzte vor ihr im Weg).</summary>
    class function CycleVia(const ACycle: TAtlasUseUnitCycle; ASection: TAtlasUseUnitSection): string; static;
    /// <summary>AEntries ohne Units, die schon in uses stehen, ohne die aktive Unit und ohne Include-Dateien.</summary>
    class function Addable(const AInfo: TAtlasUseUnitInfo; const AEntries: TArray<TAtlasUnitEntry>):
      TArray<TAtlasUnitEntry>; static;
    /// <summary>[uri, [Namen], {"section"}] für atlas.server.addUses.</summary>
    class function AddUsesArguments(const AUri: string; const ANames: TArray<string>;
      ASection: TAtlasUseUnitSection): string; static;
    class function SectionText(ASection: TAtlasUseUnitSection): string; static;
    /// <summary>Formulare, Frames und Datenmodule.</summary>
    class function FormKinds: TAtlasUnitKinds; static;
  end;

implementation

const
  Arrow = ' → ';

{ TAtlasUseUnit }

class function TAtlasUseUnit.Arguments(const AUri: string): string;
var
  Items: TJSONArray;
begin
  Items := TJSONArray.Create;
  try
    Items.Add(AUri);
    Result := Items.ToJSON;
  finally
    Items.Free;
  end;
end;

function TextOf(AObject: TJSONObject; const AName: string): string;
begin
  Result := '';
  if AObject.GetValue(AName) is TJSONString then
    Result := AObject.GetValue(AName).Value;
end;

class function TAtlasUseUnit.Parse(const AJson: string; out AInfo: TAtlasUseUnitInfo): Boolean;
var
  Value, Item: TJSONValue;
  Root: TJSONObject;
  Cycle: TAtlasUseUnitCycle;
begin
  AInfo := Default(TAtlasUseUnitInfo);
  Result := False;
  if Trim(AJson) = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONObject) then
      Exit;
    Root := TJSONObject(Value);
    if not (Root.GetValue('found') is TJSONBool) then
      Exit;
    AInfo.Found := TJSONBool(Root.GetValue('found')).AsBoolean;
    AInfo.UnitName := TextOf(Root, 'unit');
    AInfo.FileName := TextOf(Root, 'file');
    if Root.GetValue('inUses') is TJSONArray then
      for Item in TJSONArray(Root.GetValue('inUses')) do
        if Item is TJSONString then
          AInfo.InUses := AInfo.InUses + [Item.Value];
    if Root.GetValue('cycles') is TJSONArray then
      for Item in TJSONArray(Root.GetValue('cycles')) do
      begin
        if not (Item is TJSONObject) then
          Continue;
        Cycle := Default(TAtlasUseUnitCycle);
        Cycle.Name := TextOf(TJSONObject(Item), 'name');
        Cycle.FileName := TextOf(TJSONObject(Item), 'file');
        Cycle.InterfacePath := TextOf(TJSONObject(Item), 'interfacePath');
        Cycle.Path := TextOf(TJSONObject(Item), 'path');
        if (Cycle.Name <> '') and (Cycle.Path <> '') then
          AInfo.Cycles := AInfo.Cycles + [Cycle];
      end;
    if Root.GetValue('generation') is TJSONNumber then
      AInfo.Generation := TJSONNumber(Root.GetValue('generation')).AsInt64;
    Result := True;
  finally
    Value.Free;
  end;
end;

/// <summary>Steht AWritten in uses für die Unit AName? Gleich oder kurz geschrieben ohne Namensraum
/// (SysUtils für System.SysUtils, über die Namensräume des Projekts aufgelöst).</summary>
function Matches(const AWritten, AName: string): Boolean;
begin
  Result := SameText(AWritten, AName) or ((Pos('.', AWritten) = 0) and
    AName.ToUpper.EndsWith('.' + AWritten.ToUpper));
end;

class function TAtlasUseUnit.InUses(const AInfo: TAtlasUseUnitInfo; const AName: string): Boolean;
var
  Written: string;
begin
  Result := SameText(AName, AInfo.UnitName);
  if Result then
    Exit;
  for Written in AInfo.InUses do
    if Matches(Written, AName) then
      Exit(True);
end;

class function TAtlasUseUnit.Marks(const AInfo: TAtlasUseUnitInfo;
  const AEntries: TAtlasUnitEntries): TArray<TAtlasUseUnitMark>;
var
  Cycles: TDictionary<string, Integer>;
  Index, Cycle: Integer;
begin
  SetLength(Result, Length(AEntries));
  // Tausende Zeilen, wenige Kreise: einmal nach Datei (sonst Name) ablegen.
  Cycles := TDictionary<string, Integer>.Create;
  try
    for Index := 0 to High(AInfo.Cycles) do
    begin
      if AInfo.Cycles[Index].FileName <> '' then
        Cycles.AddOrSetValue(LowerCase(AInfo.Cycles[Index].FileName), Index);
      Cycles.AddOrSetValue('#' + LowerCase(AInfo.Cycles[Index].Name), Index);
    end;
    for Index := 0 to High(AEntries) do
    begin
      Result[Index].InUses := InUses(AInfo, AEntries[Index].Name);
      if not Cycles.TryGetValue(LowerCase(AEntries[Index].FileName), Cycle) and
        not Cycles.TryGetValue('#' + LowerCase(AEntries[Index].Name), Cycle) then
        Cycle := -1;
      Result[Index].Cycle := Cycle;
    end;
  finally
    Cycles.Free;
  end;
end;

class function TAtlasUseUnit.CycleState(const ACycle: TAtlasUseUnitCycle;
  ASection: TAtlasUseUnitSection): TAtlasUseUnitCycleState;
begin
  if (ASection = TAtlasUseUnitSection.Interface_) and (ACycle.InterfacePath <> '') then
    Result := TAtlasUseUnitCycleState.Warning
  else if ACycle.Path <> '' then
    Result := TAtlasUseUnitCycleState.Hint
  else
    Result := TAtlasUseUnitCycleState.None;
end;

class function TAtlasUseUnit.CyclePath(const ACycle: TAtlasUseUnitCycle; ASection: TAtlasUseUnitSection): string;
begin
  if CycleState(ACycle, ASection) = TAtlasUseUnitCycleState.Warning then
    Result := ACycle.InterfacePath
  else
    Result := ACycle.Path;
end;

class function TAtlasUseUnit.CycleVia(const ACycle: TAtlasUseUnitCycle; ASection: TAtlasUseUnitSection): string;
var
  Parts: TArray<string>;
begin
  Result := ACycle.Name;
  // "Ziel → Kandidat → … → Via → Ziel": vorletzter Teil.
  Parts := CyclePath(ACycle, ASection).Split([Arrow]);
  if Length(Parts) >= 3 then
    Result := Parts[High(Parts) - 1];
end;

class function TAtlasUseUnit.Addable(const AInfo: TAtlasUseUnitInfo;
  const AEntries: TArray<TAtlasUnitEntry>): TArray<TAtlasUnitEntry>;
var
  Entry: TAtlasUnitEntry;
  Seen: TDictionary<string, Boolean>;
begin
  Result := nil;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Entry in AEntries do
    begin
      if (Entry.Kind = TAtlasUnitKind.Include) or InUses(AInfo, Entry.Name) or
        Seen.ContainsKey(LowerCase(Entry.Name)) then
        Continue;
      Seen.Add(LowerCase(Entry.Name), True);
      Result := Result + [Entry];
    end;
  finally
    Seen.Free;
  end;
end;

class function TAtlasUseUnit.AddUsesArguments(const AUri: string; const ANames: TArray<string>;
  ASection: TAtlasUseUnitSection): string;
var
  Items, Names: TJSONArray;
  Options: TJSONObject;
  Name: string;
begin
  Items := TJSONArray.Create;
  try
    Items.Add(AUri);
    Names := TJSONArray.Create;
    for Name in ANames do
      Names.Add(Name);
    Items.AddElement(Names);
    Options := TJSONObject.Create;
    Options.AddPair('section', SectionText(ASection));
    Items.AddElement(Options);
    Result := Items.ToJSON;
  finally
    Items.Free;
  end;
end;

class function TAtlasUseUnit.SectionText(ASection: TAtlasUseUnitSection): string;
begin
  if ASection = TAtlasUseUnitSection.Interface_ then
    Result := 'interface'
  else
    Result := 'implementation';
end;

class function TAtlasUseUnit.FormKinds: TAtlasUnitKinds;
begin
  Result := [TAtlasUnitKind.Form, TAtlasUnitKind.Frame, TAtlasUnitKind.DataModule];
end;

end.
