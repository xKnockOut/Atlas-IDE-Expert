unit Atlas.IDE.Tests.ApprovalFiles;

// Befehl „Liegengebliebene .received-Dateien löschen“ (#1881,
// tests.approvalFiles): Ordner der Vergleichsdateien des Testprojekts
// (Atlas.Core.Tests.Approval.FolderOf, tests.approvalFolder aus atlas.json),
// nach Rückfrage alle received-Dateien darin löschen. Fehlt in der nächsten
// .gitignore eine Zeile für sie, fragt Atlas, ob es *.received.* eintragen
// soll. Ergebnis als Zeile in der Meldungsansicht.

interface

uses
  Atlas.IDE.Tests.Runner;

type
  TAtlasIdeApprovalFiles = class
  private
    /// <summary>*.received.* in die .gitignore ab AFolder eintragen, wenn sie fehlt und der Benutzer zustimmt.
    /// </summary>
    class procedure SuggestIgnore(const AFolder: string); static;
  public
    /// <summary>received-Dateien des Testprojekts AProject löschen ('' = aktives Projekt).</summary>
    class procedure Clean(ATests: TAtlasIdeTests; const AProject: string); static;
    /// <summary>Aktives Projekt der IDE; '' ohne.</summary>
    class function ActiveProject: string; static;
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,
  System.IOUtils,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Tests.Approval,
  Atlas.UI.Tests.Strings;

{ TAtlasIdeApprovalFiles }

class function TAtlasIdeApprovalFiles.ActiveProject: string;
var
  mServices: IOTAModuleServices;
  mProject: IOTAProject;
begin
  Result := '';
  mProject := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    mProject := mServices.GetActiveProject;
  end;
  if mProject <> nil then
  begin
    Result := mProject.FileName;
  end;
end;

class procedure TAtlasIdeApprovalFiles.Clean(ATests: TAtlasIdeTests; const AProject: string);
var
  mProject, mFolder, mFile: string;
  mFiles: TArray<string>;
  mDeleted: Integer;
begin
  mProject := AProject;
  if mProject = '' then
  begin
    mProject := ActiveProject;
  end;
  if mProject = '' then
  begin
    ATests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsApprovalNoProject));
    Exit;
  end;
  mFolder := TAtlasTestApproval.FolderOf(mProject);
  mFiles := TAtlasTestApproval.Leftovers(mFolder);
  if Length(mFiles) = 0 then
  begin
    ATests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsApprovalCleanNone, [mFolder]));
    SuggestIgnore(ExtractFileDir(mProject));
    Exit;
  end;
  if MessageDlg(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsApprovalCleanAsk, [Length(mFiles), mFolder]),
    TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0) <> mrYes then
  begin
    Exit;
  end;
  mDeleted := 0;
  for mFile in mFiles do
  begin
    if DeleteFile(mFile) then
    begin
      Inc(mDeleted);
    end;
  end;
  ATests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsApprovalCleaned, [mDeleted, Length(mFiles)]));
  SuggestIgnore(ExtractFileDir(mProject));
end;

class procedure TAtlasIdeApprovalFiles.SuggestIgnore(const AFolder: string);
var
  mIgnore, mText: string;
begin
  mIgnore := TAtlasTestApproval.IgnoreFileFrom(AFolder);
  if mIgnore = '' then
  begin
    Exit;
  end;
  mText := TFile.ReadAllText(mIgnore, TEncoding.UTF8);
  if TAtlasTestApproval.HasIgnoreEntry(mText) or (MessageDlg(TAtlasTestsStrings.Fmt(
    TAtlasTestsTextId.TestsApprovalIgnoreAsk, [TAtlasTestApproval.cIgnorePattern, mIgnore]),
    TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0) <> mrYes) then
  begin
    Exit;
  end;
  if (mText <> '') and not mText.EndsWith(#10) then
  begin
    mText := mText + sLineBreak;
  end;
  // Ohne BOM: git läse sie als Teil des ersten Musters.
  TFile.WriteAllBytes(mIgnore, TEncoding.UTF8.GetBytes(mText + TAtlasTestApproval.cIgnorePattern + sLineBreak));
end;

end.
