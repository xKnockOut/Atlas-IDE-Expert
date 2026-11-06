unit Atlas.Core.Modules.KnownPackages;

// Module unter „Known Packages“ der IDE (ADR 0017, Meldung vom 05.11.2026:
// nach einem Morgen standen dort nur noch Base, die 11 Module fehlten), ohne
// VCL und Open Tools API:
// - Modul-BPL: Atlas.IDE.<Name><Endung>.bpl im Ordner von Base mit derselben
//   Versionsendung wie Base. Base selbst, die aufgelösten Verträge
//   (Atlas.IDE.Contracts) und das Plugin aus 1.x (Atlas.IDE.Expert) zählen
//   nicht.
// - Fehlend: weder unter „Known Packages“ noch unter „Disabled Packages“.
//   Abgeschaltete Module und Module, die aus einem anderen Ordner eingetragen
//   sind, meldet Check getrennt; beide fehlen nicht.
// - Compare: Atlas-Einträge, die zwischen zwei Ständen der Liste wegfallen
//   oder dazukommen (Beobachtung während der Sitzung).
// Die Werte heißen wie der Pfad der BPL, ihr Inhalt ist die Beschreibung (wie
// TUpdateKnownPackages im Updater). Makros wie $(BDSCOMMONDIR) löst der
// Aufrufer vorher auf.

interface

uses
  System.SysUtils;

type
  TAtlasKnownPackagesInput = record
    /// <summary>Pfad der BPL von Base.</summary>
    BaseFile: string;
    /// <summary>BPL-Dateien im Ordner von Base (Pfade).</summary>
    Files: TArray<string>;
    /// <summary>Wertnamen unter „Known Packages“ (bzw. „Known Packages x64“), Makros aufgelöst.</summary>
    Known: TArray<string>;
    /// <summary>Wertnamen unter „Disabled Packages“, Makros aufgelöst.</summary>
    Disabled: TArray<string>;
  end;

  TAtlasKnownPackagesState = record
    /// <summary>Modul-BPLs im Ordner von Base.</summary>
    Modules: TArray<string>;
    /// <summary>Weder eingetragen noch abgeschaltet.</summary>
    Missing: TArray<string>;
    /// <summary>Unter „Disabled Packages“.</summary>
    Disabled: TArray<string>;
    /// <summary>Gleiches Modul aus einem anderen Ordner eingetragen.</summary>
    Elsewhere: TArray<string>;
    function IsComplete: Boolean;
  end;

  TAtlasKnownPackagesChange = record
    Removed: TArray<string>;
    Added: TArray<string>;
    function IsEmpty: Boolean;
  end;

  TAtlasKnownPackages = class
  private
    class function SamePath(const A, B: string): Boolean; static;
    class function FileNameOf(const APath: string): string; static;
    class function FolderOf(const APath: string): string; static;
    class function Contains(const AList: TArray<string>; const AFile: string): Boolean; static;
    class function NamedElsewhere(const AList: TArray<string>; const AFile: string): Boolean; static;
    class function AtlasEntries(const AValues: TArray<string>): TArray<string>; static;
    class function Without(const AList, AOther: TArray<string>): TArray<string>; static;
  public
    /// <summary>Name ohne Ordner, Vorsilbe, Versionsendung und .bpl: „Debugger“.</summary>
    class function ModuleName(const AFile: string): string; static;
    /// <summary>Versionsendung des Dateinamens, z. B. „370“; '' ohne.</summary>
    class function Suffix(const AFile: string): string; static;
    /// <summary>Ein Package von Atlas (Vorsilbe Atlas.IDE., Endung .bpl), auch Base.</summary>
    class function IsAtlasPackage(const AFile: string): Boolean; static;
    /// <summary>Modul-BPL zu Base ABaseFile: gleicher Ordner, gleiche Versionsendung, weder Base noch Verträge
    /// noch das Plugin aus 1.x.</summary>
    class function IsModuleFile(const AFile, ABaseFile: string): Boolean; static;
    class function Check(const AInput: TAtlasKnownPackagesInput): TAtlasKnownPackagesState; static;
    /// <summary>Atlas-Einträge, die von ABefore zu AAfter wegfallen bzw. dazukommen.</summary>
    class function Compare(const ABefore, AAfter: TArray<string>): TAtlasKnownPackagesChange; static;
    /// <summary>Beschreibung eines wieder eingetragenen Moduls: „Atlas Debugger“.</summary>
    class function Description(const AFile: string): string; static;
    /// <summary>Modulnamen, mit „, “ getrennt; '-' ohne.</summary>
    class function Names(const AFiles: TArray<string>): string; static;
    /// <summary>Protokollzeile zu AState (nur Modulnamen, keine Pfade).</summary>
    class function Report(const AState: TAtlasKnownPackagesState): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Updates;

const
  cLegacyPackage = 'Atlas.IDE.Expert';

{ TAtlasKnownPackagesState }

function TAtlasKnownPackagesState.IsComplete: Boolean;
begin
  Result := Length(Missing) = 0;
end;

{ TAtlasKnownPackagesChange }

function TAtlasKnownPackagesChange.IsEmpty: Boolean;
begin
  Result := (Length(Removed) = 0) and (Length(Added) = 0);
end;

{ TAtlasKnownPackages }

class function TAtlasKnownPackages.SamePath(const A, B: string): Boolean;
begin
  Result := SameText(A.Replace('/', '\').Trim, B.Replace('/', '\').Trim);
end;

class function TAtlasKnownPackages.FileNameOf(const APath: string): string;
begin
  Result := APath.Substring(APath.LastDelimiter('\/') + 1);
end;

class function TAtlasKnownPackages.FolderOf(const APath: string): string;
begin
  // Nicht ExtractFileDir: Das trennt unter Windows nur an \ und unter Linux nur an /.
  Result := APath.Substring(0, APath.LastDelimiter('\/'));
end;

class function TAtlasKnownPackages.ModuleName(const AFile: string): string;
begin
  Result := TUpdateVersions.PackageName(AFile);
  if StartsText(TUpdateVersions.PackagePrefix, Result) then
  begin
    Result := Result.Substring(Length(TUpdateVersions.PackagePrefix));
  end;
end;

class function TAtlasKnownPackages.Suffix(const AFile: string): string;
var
  mName: string;
begin
  mName := FileNameOf(AFile);
  if EndsText('.bpl', mName) then
  begin
    mName := mName.Substring(0, Length(mName) - 4);
  end;
  Result := mName.Substring(Length(TUpdateVersions.PackageName(AFile)));
end;

class function TAtlasKnownPackages.IsAtlasPackage(const AFile: string): Boolean;
var
  mName: string;
begin
  mName := FileNameOf(AFile);
  Result := StartsText(TUpdateVersions.PackagePrefix, mName) and EndsText('.bpl', mName);
end;

class function TAtlasKnownPackages.IsModuleFile(const AFile, ABaseFile: string): Boolean;
var
  mName: string;
begin
  if not IsAtlasPackage(AFile) or not SamePath(FolderOf(AFile), FolderOf(ABaseFile)) or
    not SameText(Suffix(AFile), Suffix(ABaseFile)) then
  begin
    Exit(False);
  end;
  mName := TUpdateVersions.PackageName(AFile);
  Result := not TUpdateVersions.IsRequiredPackage(mName) and not SameText(mName, cLegacyPackage);
end;

class function TAtlasKnownPackages.Contains(const AList: TArray<string>; const AFile: string): Boolean;
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if SamePath(mItem, AFile) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasKnownPackages.NamedElsewhere(const AList: TArray<string>; const AFile: string): Boolean;
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if IsAtlasPackage(mItem) and SameText(TUpdateVersions.PackageName(mItem), TUpdateVersions.PackageName(AFile))
      and not SamePath(mItem, AFile) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasKnownPackages.Check(const AInput: TAtlasKnownPackagesInput): TAtlasKnownPackagesState;
var
  mFile: string;
begin
  Result := Default(TAtlasKnownPackagesState);
  for mFile in AInput.Files do
  begin
    if not IsModuleFile(mFile, AInput.BaseFile) then
    begin
      Continue;
    end;
    Result.Modules := Result.Modules + [mFile];
    if Contains(AInput.Known, mFile) then
    begin
      Continue;
    end;
    if Contains(AInput.Disabled, mFile) then
    begin
      Result.Disabled := Result.Disabled + [mFile];
    end
    else if NamedElsewhere(AInput.Known, mFile) then
    begin
      Result.Elsewhere := Result.Elsewhere + [mFile];
    end
    else
    begin
      Result.Missing := Result.Missing + [mFile];
    end;
  end;
end;

class function TAtlasKnownPackages.AtlasEntries(const AValues: TArray<string>): TArray<string>;
var
  mValue: string;
begin
  Result := nil;
  for mValue in AValues do
  begin
    if IsAtlasPackage(mValue) then
    begin
      Result := Result + [mValue];
    end;
  end;
end;

class function TAtlasKnownPackages.Without(const AList, AOther: TArray<string>): TArray<string>;
var
  mItem: string;
begin
  Result := nil;
  for mItem in AList do
  begin
    if not Contains(AOther, mItem) then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

class function TAtlasKnownPackages.Compare(const ABefore, AAfter: TArray<string>): TAtlasKnownPackagesChange;
var
  mBefore, mAfter: TArray<string>;
begin
  mBefore := AtlasEntries(ABefore);
  mAfter := AtlasEntries(AAfter);
  Result.Removed := Without(mBefore, mAfter);
  Result.Added := Without(mAfter, mBefore);
end;

class function TAtlasKnownPackages.Description(const AFile: string): string;
begin
  Result := 'Atlas ' + ModuleName(AFile);
end;

class function TAtlasKnownPackages.Names(const AFiles: TArray<string>): string;
var
  mFile: string;
begin
  Result := '';
  for mFile in AFiles do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + ModuleName(mFile);
  end;
  if Result = '' then
  begin
    Result := '-';
  end;
end;

class function TAtlasKnownPackages.Report(const AState: TAtlasKnownPackagesState): string;
begin
  Result := Format('Known Packages: %d Module im Ordner von Base, fehlend: %s; abgeschaltet: %s; ' +
    'aus anderem Ordner: %s', [Length(AState.Modules), Names(AState.Missing), Names(AState.Disabled),
    Names(AState.Elsewhere)]);
end;

end.
