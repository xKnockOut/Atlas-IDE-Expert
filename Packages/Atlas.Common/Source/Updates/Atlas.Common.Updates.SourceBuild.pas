unit Atlas.Common.Updates.SourceBuild;

// Platform-Feature "Updates" (#1519), Root: Plugin-Packages aus dem
// Quelltext bauen, wenn das Release kein Paket für die eigene IDE hat
// (Delphi 12: das Release baut nur für Delphi 13).
// - Reihenfolge wie im Release-Workflow: Kern und Verträge zuerst, dann jedes
//   Modul unter Packages\Atlas.IDE.* (Ordner mit gleichnamigem .dpk/.dproj).
// - Die BPLs landen unter Output\<Plattform>\Release\Bpl des Quelltexts und
//   ersetzen die BPLs des Release-Pakets in files\<Plattform>; deren Map-
//   Dateien gehören zur anderen IDE und fallen weg.

interface

uses
  System.SysUtils,
  Atlas.Common.Updates.Contract;

type
  TUpdateSourceBuild = class
  public
    /// <summary>Projekte (.dproj, relativ zum Quelltext) in Bau-Reihenfolge.</summary>
    class function Projects(const AFiles: TArray<string>): TArray<string>; static;
    class function OutputDir(const ASourceDir, APlatform: string): string; static;
    /// <summary>Baut alles; EUpdateError (build) mit dem Projekt beim ersten Fehler.</summary>
    class procedure Build(const ASystem: TUpdateSystem; const ABdsVersion, APlatform, ASourceDir: string); static;
    /// <summary>Ersetzt BPLs und Maps in AFilesDir\APlatform durch die gebauten BPLs.</summary>
    class procedure Stage(const AFiles: IUpdateFiles; const ASourceDir, APlatform, AFilesDir: string); static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Text.Updates,
  Atlas.Text.UpdateRun,
  Atlas.Common.Localization.Texts;

const
  cBuildingText: array[0..0] of TAtlasText = ((De: 'Baue %s'; En: 'Building %s'));

{ TUpdateSourceBuild }

/// <summary>Packages\X\X.dproj mit X = Atlas.IDE.*; '' sonst.</summary>
function PackageOf(const AFile: string): string;
var
  mParts: TArray<string>;
begin
  Result := '';
  mParts := AFile.Replace('/', '\').Split(['\']);
  if (Length(mParts) = 3) and SameText(mParts[0], 'Packages') and
    mParts[1].StartsWith(TUpdateVersions.cPackagePrefix, True) and SameText(mParts[2], mParts[1] + '.dproj') then
  begin
    Result := mParts[1];
  end;
end;

class function TUpdateSourceBuild.Projects(const AFiles: TArray<string>): TArray<string>;
var
  mFirst, mRest: TList<string>;
  mFile, mName: string;
begin
  mFirst := TList<string>.Create;
  mRest := TList<string>.Create;
  try
    for mFile in AFiles do
    begin
      mName := PackageOf(mFile);
      if SameText(mName, TUpdateVersions.cContractsPackage) or SameText(mName, TUpdateVersions.cBasePackage) then
      begin
        mFirst.Add('Packages\' + mName + '\' + mName + '.dproj');
      end
      else if mName <> '' then
      begin
        mRest.Add('Packages\' + mName + '\' + mName + '.dproj');
      end;
    end;
    // Kern und Verträge (nach Namen) vor den Modulen, die gegen ihre .dcp übersetzen.
    mFirst.Sort;
    mRest.Sort;
    Result := mFirst.ToArray + mRest.ToArray;
  finally
    mRest.Free;
    mFirst.Free;
  end;
end;

class function TUpdateSourceBuild.OutputDir(const ASourceDir, APlatform: string): string;
begin
  Result := TUpdateLayout.Join(ASourceDir, 'Output\' + APlatform + '\Release\Bpl');
end;

class procedure TUpdateSourceBuild.Build(const ASystem: TUpdateSystem; const ABdsVersion, APlatform,
  ASourceDir: string);
var
  mProject: string;
  mLog: TUpdateLog;
begin
  mLog := ASystem.Log;
  for mProject in Projects(ASystem.Files.FilesIn(ASourceDir)) do
  begin
    mLog(cBuildingText[0].Fmt([mProject]));
    if ASystem.Builder.Build(ABdsVersion, APlatform, TUpdateLayout.Join(ASourceDir, mProject),
      procedure(const ALine: string)
      begin
        mLog(ALine);
      end) <> 0 then
    begin
      raise EUpdateError.CreateCode(TUpdateErrors.cBuild, mProject);
    end;
  end;
end;

function IsPluginFile(const AFile, AExtension: string): Boolean;
begin
  Result := (Pos('\', AFile) = 0) and AFile.StartsWith(TUpdateVersions.cPackagePrefix, True) and
    AFile.EndsWith(AExtension, True);
end;

class procedure TUpdateSourceBuild.Stage(const AFiles: IUpdateFiles; const ASourceDir, APlatform,
  AFilesDir: string);
var
  mTarget, mOutput, mFile: string;
begin
  mTarget := TUpdateLayout.Join(AFilesDir, APlatform);
  for mFile in AFiles.FilesIn(mTarget) do
  begin
    if IsPluginFile(mFile, '.bpl') or IsPluginFile(mFile, '.map') then
    begin
      AFiles.DeleteFile(TUpdateLayout.Join(mTarget, mFile));
    end;
  end;
  mOutput := OutputDir(ASourceDir, APlatform);
  for mFile in AFiles.FilesIn(mOutput) do
  begin
    if IsPluginFile(mFile, '.bpl') then
    begin
      AFiles.CopyFile(TUpdateLayout.Join(mOutput, mFile), TUpdateLayout.Join(mTarget, mFile));
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Updates.SourceBuild', cBuildingText);

end.
