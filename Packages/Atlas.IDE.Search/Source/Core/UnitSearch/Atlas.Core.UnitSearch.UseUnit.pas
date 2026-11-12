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
// - Formulare suchen setzt den Filter cFormsFilter (Tippsyntax) bzw. die Arten
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
    cCommand = 'atlas.useUnitInfo';
    cFormsFilter = 't:form|frame|dm';
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

uses
  Atlas.Text.Json;

const
  cArrow = ' → ';

{ TAtlasUseUnit }

class function TAtlasUseUnit.Arguments(const AUri: string): string;
var
  mItems: TJSONArray;
begin
  mItems := TJSONArray.Create;
  try
    mItems.Add(AUri);
    Result := mItems.ToJSON;
  finally
    mItems.Free;
  end;
end;

/// <summary>Texte des Arrays AName; andere Einträge zählen nicht.</summary>
function TextsOf(AObject: TJSONObject; const AName: string): TArray<string>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if AObject.GetValue(AName) is TJSONArray then
  begin
    for mItem in TJSONArray(AObject.GetValue(AName)) do
    begin
      if mItem is TJSONString then
      begin
        Result := Result + [mItem.Value];
      end;
    end;
  end;
end;

/// <summary>Zyklen aus "cycles"; nur Einträge mit Name und Pfad.</summary>
function CyclesOf(AObject: TJSONObject): TArray<TAtlasUseUnitCycle>;
var
  mItem: TJSONValue;
  mCycle: TAtlasUseUnitCycle;
begin
  Result := nil;
  if not (AObject.GetValue('cycles') is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AObject.GetValue('cycles')) do
  begin
    if mItem is TJSONObject then
    begin
      mCycle := Default(TAtlasUseUnitCycle);
      mCycle.Name := TJsonRead.Text(TJSONObject(mItem), 'name');
      mCycle.FileName := TJsonRead.Text(TJSONObject(mItem), 'file');
      mCycle.InterfacePath := TJsonRead.Text(TJSONObject(mItem), 'interfacePath');
      mCycle.Path := TJsonRead.Text(TJSONObject(mItem), 'path');
      if (mCycle.Name <> '') and (mCycle.Path <> '') then
      begin
        Result := Result + [mCycle];
      end;
    end;
  end;
end;

class function TAtlasUseUnit.Parse(const AJson: string; out AInfo: TAtlasUseUnitInfo): Boolean;
var
  mValue: TJSONValue;
  mRoot: TJSONObject;
begin
  AInfo := Default(TAtlasUseUnitInfo);
  Result := False;
  if Trim(AJson) = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) or not (TJSONObject(mValue).GetValue('found') is TJSONBool) then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    AInfo.Found := TJSONBool(mRoot.GetValue('found')).AsBoolean;
    AInfo.UnitName := TJsonRead.Text(mRoot, 'unit');
    AInfo.FileName := TJsonRead.Text(mRoot, 'file');
    AInfo.InUses := TextsOf(mRoot, 'inUses');
    AInfo.Cycles := CyclesOf(mRoot);
    if mRoot.GetValue('generation') is TJSONNumber then
    begin
      AInfo.Generation := TJSONNumber(mRoot.GetValue('generation')).AsInt64;
    end;
    Result := True;
  finally
    mValue.Free;
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
  mWritten: string;
begin
  Result := SameText(AName, AInfo.UnitName);
  if Result then
  begin
    Exit;
  end;
  for mWritten in AInfo.InUses do
  begin
    if Matches(mWritten, AName) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasUseUnit.Marks(const AInfo: TAtlasUseUnitInfo;
  const AEntries: TAtlasUnitEntries): TArray<TAtlasUseUnitMark>;
var
  mCycles: TDictionary<string, Integer>;
  mIndex, mCycle: Integer;
begin
  SetLength(Result, Length(AEntries));
  // Tausende Zeilen, wenige Kreise: einmal nach Datei (sonst Name) ablegen.
  mCycles := TDictionary<string, Integer>.Create;
  try
    for mIndex := 0 to High(AInfo.Cycles) do
    begin
      if AInfo.Cycles[mIndex].FileName <> '' then
      begin
        mCycles.AddOrSetValue(LowerCase(AInfo.Cycles[mIndex].FileName), mIndex);
      end;
      mCycles.AddOrSetValue('#' + LowerCase(AInfo.Cycles[mIndex].Name), mIndex);
    end;
    for mIndex := 0 to High(AEntries) do
    begin
      Result[mIndex].InUses := InUses(AInfo, AEntries[mIndex].Name);
      if not mCycles.TryGetValue(LowerCase(AEntries[mIndex].FileName), mCycle) and
        not mCycles.TryGetValue('#' + LowerCase(AEntries[mIndex].Name), mCycle) then
      begin
        mCycle := -1;
      end;
      Result[mIndex].Cycle := mCycle;
    end;
  finally
    mCycles.Free;
  end;
end;

class function TAtlasUseUnit.CycleState(const ACycle: TAtlasUseUnitCycle;
  ASection: TAtlasUseUnitSection): TAtlasUseUnitCycleState;
begin
  if (ASection = TAtlasUseUnitSection.Interface_) and (ACycle.InterfacePath <> '') then
  begin
    Result := TAtlasUseUnitCycleState.Warning;
  end
  else if ACycle.Path <> '' then
  begin
    Result := TAtlasUseUnitCycleState.Hint;
  end
  else
  begin
    Result := TAtlasUseUnitCycleState.None;
  end;
end;

class function TAtlasUseUnit.CyclePath(const ACycle: TAtlasUseUnitCycle; ASection: TAtlasUseUnitSection): string;
begin
  if CycleState(ACycle, ASection) = TAtlasUseUnitCycleState.Warning then
  begin
    Result := ACycle.InterfacePath;
  end
  else
  begin
    Result := ACycle.Path;
  end;
end;

class function TAtlasUseUnit.CycleVia(const ACycle: TAtlasUseUnitCycle; ASection: TAtlasUseUnitSection): string;
var
  mParts: TArray<string>;
begin
  Result := ACycle.Name;
  // "Ziel → Kandidat → … → Via → Ziel": vorletzter Teil.
  mParts := CyclePath(ACycle, ASection).Split([cArrow]);
  if Length(mParts) >= 3 then
  begin
    Result := mParts[High(mParts) - 1];
  end;
end;

class function TAtlasUseUnit.Addable(const AInfo: TAtlasUseUnitInfo;
  const AEntries: TArray<TAtlasUnitEntry>): TArray<TAtlasUnitEntry>;
var
  mEntry: TAtlasUnitEntry;
  mSeen: TDictionary<string, Boolean>;
begin
  Result := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mEntry in AEntries do
    begin
      if (mEntry.Kind = TAtlasUnitKind.Include) or InUses(AInfo, mEntry.Name) or
        mSeen.ContainsKey(LowerCase(mEntry.Name)) then
      begin
        Continue;
      end;
      mSeen.Add(LowerCase(mEntry.Name), True);
      Result := Result + [mEntry];
    end;
  finally
    mSeen.Free;
  end;
end;

class function TAtlasUseUnit.AddUsesArguments(const AUri: string; const ANames: TArray<string>;
  ASection: TAtlasUseUnitSection): string;
var
  mItems, mNames: TJSONArray;
  mOptions: TJSONObject;
  mName: string;
begin
  mItems := TJSONArray.Create;
  try
    mItems.Add(AUri);
    mNames := TJSONArray.Create;
    for mName in ANames do
    begin
      mNames.Add(mName);
    end;
    mItems.AddElement(mNames);
    mOptions := TJSONObject.Create;
    mOptions.AddPair('section', SectionText(ASection));
    mItems.AddElement(mOptions);
    Result := mItems.ToJSON;
  finally
    mItems.Free;
  end;
end;

class function TAtlasUseUnit.SectionText(ASection: TAtlasUseUnitSection): string;
begin
  if ASection = TAtlasUseUnitSection.Interface_ then
  begin
    Result := 'interface';
  end
  else
  begin
    Result := 'implementation';
  end;
end;

class function TAtlasUseUnit.FormKinds: TAtlasUnitKinds;
begin
  Result := [TAtlasUnitKind.Form, TAtlasUnitKind.Frame, TAtlasUnitKind.DataModule];
end;

end.
