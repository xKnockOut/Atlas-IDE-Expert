unit Atlas.IDE.Architecture.RoleUnit;

// Assistent „Unit nach Architekturrolle“ in Datei › Neu › Weitere (#1821):
// liest die Ausgabeartefakte aus "rules" der Projektdatei
// (architecture-role-import.prefixes), schlägt Ausgabeartefakt und Feature
// der Unit im Editor vor, zeigt den Dialog und legt die Unit über
// TAtlasIdeNewFile.CreateUnit im aktiven Projekt an: neben Units derselben
// Rolle bzw. desselben Features, sonst im Ordner des Projekts; mit dem
// Contract des Features in uses, wenn es ihn in der Projektgruppe gibt
// (Atlas.Core.Architecture.RoleUnit). Ohne Projekt eine Zeile in der
// Meldungsansicht. Hauptthread.

interface

type
  TAtlasIdeRoleUnit = class
  public
    class procedure Execute; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  ToolsAPI,
  Atlas.Core.Architecture.RoleUnit,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Problems.Files,
  Atlas.IDE.Generate.NewFile,
  Atlas.UI.Strings,
  Atlas.UI.Analysis.Strings,
  Atlas.UI.Architecture.RoleUnitDialog;

/// <summary>Ausgabeartefakte aus atlas.json des aktiven Projekts.</summary>
function ProjectPrefixes: TArray<string>;
var
  mRoot: TJSONObject;
  mRules: TJSONValue;
begin
  Result := nil;
  mRoot := TAtlasProjectSettings.ReadProject;
  try
    if mRoot <> nil then
    begin
      mRules := mRoot.GetValue('rules');
      if mRules <> nil then
      begin
        Result := TAtlasRoleUnit.Prefixes(mRules.ToJSON);
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

/// <summary>Unitname der Datei im Editor; '' ohne.</summary>
function ActiveUnitName: string;
var
  mView: IOTAEditView;
begin
  Result := '';
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView <> nil) and (mView.Buffer <> nil) and SameText(ExtractFileExt(mView.Buffer.FileName), '.pas') then
  begin
    Result := ChangeFileExt(ExtractFileName(mView.Buffer.FileName), '');
  end;
end;

/// <summary>Vorschlag: Ausgabeartefakt und Feature der Unit im Editor, sonst das erste Ausgabeartefakt.</summary>
function Proposal(const APrefixes: TArray<string>): TAtlasRoleUnitInput;
var
  mUnit: string;
  mParts: TArray<string>;
begin
  Result := Default(TAtlasRoleUnitInput);
  mUnit := ActiveUnitName;
  Result.Prefix := TAtlasRoleUnit.PrefixOf(mUnit, APrefixes);
  if Result.Prefix <> '' then
  begin
    mParts := Copy(mUnit, Length(Result.Prefix) + 2, MaxInt).Split(['.']);
    if Length(mParts) > 1 then
    begin
      Result.Feature := mParts[0];
    end;
  end
  else if Length(APrefixes) > 0 then
  begin
    Result.Prefix := APrefixes[0];
  end;
end;

function HasUnit(const AFiles: TArray<string>; const AUnitName: string): Boolean;
var
  mFile: string;
begin
  for mFile in AFiles do
  begin
    if SameText(ChangeFileExt(ExtractFileName(mFile), ''), AUnitName) and
      SameText(ExtractFileExt(mFile), '.pas') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class procedure TAtlasIdeRoleUnit.Execute;
var
  mProject: IOTAProject;
  mPrefixes, mFiles: TArray<string>;
  mInput: TAtlasRoleUnitInput;
  mKey, mOwn, mForeign, mText, mFileName, mError: string;
begin
  mProject := GetActiveProject;
  if mProject = nil then
  begin
    TAtlasIdeHost.Message(TAtlasStrings.Text(TAtlasTextId.WelcomeSetupNewNoProject));
    Exit;
  end;
  mPrefixes := ProjectPrefixes;
  mInput := Proposal(mPrefixes);
  if not TAtlasRoleUnitDialog.Execute(mPrefixes, mInput) then
  begin
    Exit;
  end;
  mFiles := TAtlasIdeProblemFiles.GroupFiles(mKey);
  TAtlasRoleUnitDialog.ImportTexts(mInput.Role, mOwn, mForeign);
  mText := TAtlasRoleUnit.UnitText(mInput, HasUnit(mFiles, TAtlasRoleUnit.ContractUnit(mInput)), mOwn, mForeign,
    sLineBreak);
  mFileName := TAtlasRoleUnit.FolderFor(mInput, mFiles, ExtractFilePath(mProject.FileName)) +
    TAtlasRoleUnit.UnitName(mInput) + '.pas';
  if not TAtlasIdeNewFile.CreateUnit(mFileName, mText, mError) then
  begin
    TAtlasIdeHost.Message(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.RoleUnitFailed, [mError]));
  end;
end;

end.
