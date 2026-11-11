unit Atlas.Core.Architecture.RoleUnit;

// Assistent „Unit nach Architekturrolle“ in Datei › Neu › Weitere (#1821),
// ohne VCL und Open Tools API. Units heißen Ausgabeartefakt.Feature.Rolle.Sache
// (docs/Architektur.md, Benennung): Root ohne Rollenbezeichner, die Sache darf
// fehlen und Punkte enthalten. Rollenbezeichner sind reserviert und stehen
// weder als Feature noch in der Sache.
// - Check prüft die Angaben und nennt den ersten Fehler.
// - Imports nennt, was die Rolle laut Importregeln (Platform-Features) darf.
// - UnitText baut das Gerüst: Kopfkommentar mit Rolle und Importregel, uses mit
//   dem Contract des eigenen Features, wenn es ihn gibt und die Rolle ihn darf
//   (alle Rollen; nicht die Contract-Unit selbst).
// - Prefixes liest die Ausgabeartefakte aus "rules" der Projektdatei
//   (architecture-role-import.prefixes), PrefixOf wählt das längste passende
//   für die Unit im Editor, FolderFor den Ordner der neuen Unit: neben einer
//   Unit gleicher Rolle im Feature, sonst neben einer Unit des Features, sonst
//   AFallback.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Rollen eines Platform-Features (Importregeln in docs/Architektur.md).</summary>
  TAtlasArchitectureRole = (Root, Contract, Internals, Providers, Adapters, Composition, Hosting);
  /// <summary>Erster Fehler der Angaben; None = in Ordnung.</summary>
  TAtlasRoleUnitProblem = (None, NoPrefix, BadPrefix, NoFeature, BadFeature, ReservedFeature, BadThing,
    ReservedThing);
{$SCOPEDENUMS OFF}

  /// <summary>Angaben des Assistenten.</summary>
  TAtlasRoleUnitInput = record
    Prefix: string;
    Feature: string;
    Role: TAtlasArchitectureRole;
    Thing: string;
  end;

  TAtlasRoleUnit = class
  public
    /// <summary>Bezeichner der Rolle im Unitnamen; '' für Root.</summary>
    class function RoleName(ARole: TAtlasArchitectureRole): string; static;
    /// <summary>Name der Unit; Teile werden getrimmt.</summary>
    class function UnitName(const AInput: TAtlasRoleUnitInput): string; static;
    /// <summary>Erster Fehler der Angaben.</summary>
    class function Check(const AInput: TAtlasRoleUnitInput): TAtlasRoleUnitProblem; static;
    /// <summary>Rollen, die ARole importieren darf: im eigenen Feature (AOwn) und in fremden Features (AForeign).
    /// </summary>
    class procedure Imports(ARole: TAtlasArchitectureRole; out AOwn, AForeign: TArray<TAtlasArchitectureRole>);
      static;
    /// <summary>Contract-Unit des Features (Prefix.Feature.Contract).</summary>
    class function ContractUnit(const AInput: TAtlasRoleUnitInput): string; static;
    /// <summary>Text der Unit. AContractExists: Die Contract-Unit des Features gibt es im Projekt. AOwnText und
    /// AForeignText: Zeilen des Kopfkommentars für die erlaubten Importe (Sprache der IDE).</summary>
    class function UnitText(const AInput: TAtlasRoleUnitInput; AContractExists: Boolean; const AOwnText,
      AForeignText, ALineBreak: string): string; static;
    /// <summary>Rollennamen durch Komma getrennt; Root heißt ARootName.</summary>
    class function RoleList(const ARoles: TArray<TAtlasArchitectureRole>; const ARootName: string): string; static;
    /// <summary>"prefixes" von architecture-role-import aus dem JSON-Text von "rules"; leer ohne.</summary>
    class function Prefixes(const ARulesJson: string): TArray<string>; static;
    /// <summary>Längstes Präfix aus APrefixes, mit dem AUnitName beginnt; '' ohne.</summary>
    class function PrefixOf(const AUnitName: string; const APrefixes: TArray<string>): string; static;
    /// <summary>Ordner der neuen Unit (mit Trennzeichen am Ende) aus den Dateien des Projekts.</summary>
    class function FolderFor(const AInput: TAtlasRoleUnitInput; const AFiles: TArray<string>;
      const AFallback: string): string; static;
  end;

implementation

uses
  System.JSON;

const
  cRoleNames: array[TAtlasArchitectureRole] of string = ('', 'Contract', 'Internals', 'Providers', 'Adapters',
    'Composition', 'Hosting');
  /// <summary>Rollenbezeichner von Features und Host (docs/Architektur.md, reserviert).</summary>
  cReserved: array[0..9] of string = ('Contract', 'Providers', 'Adapters', 'Internals', 'Hosting', 'Composition',
    'Foundation', 'Core', 'Shell', 'Platform');

function IsReserved(const AName: string): Boolean;
var
  mName: string;
begin
  for mName in cReserved do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Punktgetrennte Bezeichner ohne leere Teile.</summary>
function IsDottedName(const AName: string): Boolean;
var
  mPart: string;
begin
  if AName = '' then
  begin
    Exit(False);
  end;
  for mPart in AName.Split(['.']) do
  begin
    if not IsValidIdent(mPart) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function HasReservedPart(const AName: string): Boolean;
var
  mPart: string;
begin
  for mPart in AName.Split(['.']) do
  begin
    if IsReserved(mPart) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function Trimmed(const AInput: TAtlasRoleUnitInput): TAtlasRoleUnitInput;
begin
  Result := AInput;
  Result.Prefix := Trim(AInput.Prefix);
  Result.Feature := Trim(AInput.Feature);
  Result.Thing := Trim(AInput.Thing);
end;

class function TAtlasRoleUnit.RoleName(ARole: TAtlasArchitectureRole): string;
begin
  Result := cRoleNames[ARole];
end;

class function TAtlasRoleUnit.UnitName(const AInput: TAtlasRoleUnitInput): string;
var
  mInput: TAtlasRoleUnitInput;
begin
  mInput := Trimmed(AInput);
  Result := mInput.Prefix + '.' + mInput.Feature;
  if mInput.Role <> TAtlasArchitectureRole.Root then
  begin
    Result := Result + '.' + RoleName(mInput.Role);
  end;
  if mInput.Thing <> '' then
  begin
    Result := Result + '.' + mInput.Thing;
  end;
end;

class function TAtlasRoleUnit.Check(const AInput: TAtlasRoleUnitInput): TAtlasRoleUnitProblem;
var
  mInput: TAtlasRoleUnitInput;
begin
  // Die erste Verletzung in Eingabereihenfolge zählt.
  mInput := Trimmed(AInput);
  if mInput.Prefix = '' then
  begin
    Result := TAtlasRoleUnitProblem.NoPrefix;
  end
  else if not IsDottedName(mInput.Prefix) then
  begin
    Result := TAtlasRoleUnitProblem.BadPrefix;
  end
  else if mInput.Feature = '' then
  begin
    Result := TAtlasRoleUnitProblem.NoFeature;
  end
  else if not IsValidIdent(mInput.Feature) then
  begin
    Result := TAtlasRoleUnitProblem.BadFeature;
  end
  else if IsReserved(mInput.Feature) then
  begin
    Result := TAtlasRoleUnitProblem.ReservedFeature;
  end
  else if (mInput.Thing <> '') and not IsDottedName(mInput.Thing) then
  begin
    Result := TAtlasRoleUnitProblem.BadThing;
  end
  else if HasReservedPart(mInput.Thing) then
  begin
    Result := TAtlasRoleUnitProblem.ReservedThing;
  end
  else
  begin
    Result := TAtlasRoleUnitProblem.None;
  end;
end;

class procedure TAtlasRoleUnit.Imports(ARole: TAtlasArchitectureRole;
  out AOwn, AForeign: TArray<TAtlasArchitectureRole>);
begin
  // Fremd immer Contract, außer für Contract auch Root.
  AForeign := [TAtlasArchitectureRole.Contract, TAtlasArchitectureRole.Root];
  case ARole of
    TAtlasArchitectureRole.Contract:
      begin
        AOwn := [TAtlasArchitectureRole.Contract];
        AForeign := [TAtlasArchitectureRole.Contract];
      end;
    TAtlasArchitectureRole.Internals:
      AOwn := [TAtlasArchitectureRole.Contract, TAtlasArchitectureRole.Internals];
    TAtlasArchitectureRole.Root, TAtlasArchitectureRole.Providers, TAtlasArchitectureRole.Adapters:
      AOwn := [TAtlasArchitectureRole.Contract, TAtlasArchitectureRole.Internals, TAtlasArchitectureRole.Root];
    TAtlasArchitectureRole.Composition:
      AOwn := [TAtlasArchitectureRole.Contract, TAtlasArchitectureRole.Providers, TAtlasArchitectureRole.Adapters,
        TAtlasArchitectureRole.Root, TAtlasArchitectureRole.Composition];
    TAtlasArchitectureRole.Hosting:
      AOwn := [TAtlasArchitectureRole.Contract, TAtlasArchitectureRole.Providers, TAtlasArchitectureRole.Adapters,
        TAtlasArchitectureRole.Root, TAtlasArchitectureRole.Composition, TAtlasArchitectureRole.Hosting];
  end;
end;

class function TAtlasRoleUnit.ContractUnit(const AInput: TAtlasRoleUnitInput): string;
var
  mInput: TAtlasRoleUnitInput;
begin
  mInput := Trimmed(AInput);
  Result := mInput.Prefix + '.' + mInput.Feature + '.' + RoleName(TAtlasArchitectureRole.Contract);
end;

class function TAtlasRoleUnit.RoleList(const ARoles: TArray<TAtlasArchitectureRole>; const ARootName: string):
  string;
var
  mRole: TAtlasArchitectureRole;
  mName: string;
begin
  Result := '';
  for mRole in ARoles do
  begin
    mName := RoleName(mRole);
    if mRole = TAtlasArchitectureRole.Root then
    begin
      mName := ARootName;
    end;
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + mName;
  end;
end;

class function TAtlasRoleUnit.UnitText(const AInput: TAtlasRoleUnitInput; AContractExists: Boolean;
  const AOwnText, AForeignText, ALineBreak: string): string;
var
  mName, mContract: string;
begin
  mName := UnitName(AInput);
  mContract := ContractUnit(AInput);
  Result := 'unit ' + mName + ';' + ALineBreak + ALineBreak;
  if AOwnText <> '' then
  begin
    Result := Result + '// ' + AOwnText + ALineBreak;
  end;
  if AForeignText <> '' then
  begin
    Result := Result + '// ' + AForeignText + ALineBreak;
  end;
  if (AOwnText <> '') or (AForeignText <> '') then
  begin
    Result := Result + ALineBreak;
  end;
  Result := Result + 'interface' + ALineBreak + ALineBreak;
  if AContractExists and not SameText(mName, mContract) then
  begin
    Result := Result + 'uses' + ALineBreak + '  ' + mContract + ';' + ALineBreak + ALineBreak;
  end;
  Result := Result + 'implementation' + ALineBreak + ALineBreak + 'end.' + ALineBreak;
end;

class function TAtlasRoleUnit.Prefixes(const ARulesJson: string): TArray<string>;
var
  mRules, mRule, mList: TJSONValue;
  mItem: TJSONValue;
begin
  Result := nil;
  if Trim(ARulesJson) = '' then
  begin
    Exit;
  end;
  mRules := TJSONObject.ParseJSONValue(ARulesJson);
  try
    if not (mRules is TJSONObject) then
    begin
      Exit;
    end;
    mRule := TJSONObject(mRules).GetValue('architecture-role-import');
    if not (mRule is TJSONObject) then
    begin
      Exit;
    end;
    mList := TJSONObject(mRule).GetValue('prefixes');
    if not (mList is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mList) do
    begin
      // TJSONNumber erbt von TJSONString.
      if (mItem is TJSONString) and not (mItem is TJSONNumber) and (Trim(mItem.Value) <> '') then
      begin
        Result := Result + [Trim(mItem.Value)];
      end;
    end;
  finally
    mRules.Free;
  end;
end;

class function TAtlasRoleUnit.PrefixOf(const AUnitName: string; const APrefixes: TArray<string>): string;
var
  mPrefix: string;
begin
  Result := '';
  for mPrefix in APrefixes do
  begin
    if (Length(mPrefix) > Length(Result)) and AUnitName.StartsWith(mPrefix + '.', True) then
    begin
      Result := mPrefix;
    end;
  end;
end;

/// <summary>Unitname einer Datei: ohne Ordner (beide Trennzeichen) und Endung.</summary>
function UnitNameOfFile(const AFileName: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(StringReplace(AFileName, '\', '/', [rfReplaceAll])), '');
  Result := Copy(Result, LastDelimiter('/', Result) + 1, MaxInt);
end;

/// <summary>Ordner von AFileName mit Trennzeichen am Ende, wie die Datei es schreibt.</summary>
function FolderOf(const AFileName: string): string;
begin
  Result := Copy(AFileName, 1, LastDelimiter('\/', AFileName));
end;

class function TAtlasRoleUnit.FolderFor(const AInput: TAtlasRoleUnitInput; const AFiles: TArray<string>;
  const AFallback: string): string;
var
  mInput: TAtlasRoleUnitInput;
  mFeature, mRoleUnit, mName, mFile, mFeatureFolder: string;
begin
  mInput := Trimmed(AInput);
  mFeature := mInput.Prefix + '.' + mInput.Feature + '.';
  mRoleUnit := mFeature + RoleName(mInput.Role) + '.';
  mFeatureFolder := '';
  for mFile in AFiles do
  begin
    if not SameText(ExtractFileExt(mFile), '.pas') then
    begin
      Continue;
    end;
    mName := UnitNameOfFile(mFile) + '.';
    if (mInput.Role <> TAtlasArchitectureRole.Root) and mName.StartsWith(mRoleUnit, True) then
    begin
      Exit(FolderOf(mFile));
    end;
    if (mFeatureFolder = '') and mName.StartsWith(mFeature, True) then
    begin
      mFeatureFolder := FolderOf(mFile);
    end;
  end;
  Result := mFeatureFolder;
  if Result = '' then
  begin
    Result := AFallback;
    if (Result <> '') and not CharInSet(Result[Length(Result)], ['\', '/']) then
    begin
      Result := Result + PathDelim;
    end;
  end;
end;

end.
