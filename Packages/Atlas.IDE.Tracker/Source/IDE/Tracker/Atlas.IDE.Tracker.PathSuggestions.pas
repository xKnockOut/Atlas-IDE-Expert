unit Atlas.IDE.Tracker.PathSuggestions;

// Arbeitskopien einer Zeile von issues.projects prüfen (#1926, „Prüfen“) und
// vorschlagen (#1929, „Vorschlagen …“) in der IDE.
// - Check: je Ordner Art und Branch im Hintergrund (TAtlasIdeVcs.Run).
// - Suggest: Dialog TAtlasTrackerSuggestDialog; gesucht wird im Hintergrund
//   nur dort, wo Atlas schon war: Arbeitskopie aus „Gilt für“ mit ihren
//   svn:externals bzw. Submodulen, die Projekte der .groupproj und, wenn das
//   Tracker-Projekt "owner/repo" ist, die zuletzt geöffneten Projekte der IDE
//   (Registry <Basis>\Closed Projects, im Hauptthread gelesen), deren
//   .git/config origin auf github.com/owner/repo zeigt; ein Ordner mit einer
//   Datei .git ist ein Worktree. Kein Durchsuchen ganzer Laufwerke.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Projects;

type
  TAtlasIdeTrackerPathSuggestions = class
  public const
    /// <summary>Zeitlimit je Abfrage der Versionsverwaltung.</summary>
    cVcsTimeoutMs = 5000;
    /// <summary>Höchstens so viele zuletzt geöffnete Projekte prüfen.</summary>
    cMaxRecent = 30;
  public
    /// <summary>„Prüfen“: ADone (Hauptthread) bekommt je Ordner eine Zeile „Ordner: Art, Branch“.</summary>
    class procedure Check(const AFolders: TArray<string>; const ADone: TProc<TArray<string>>); static;
    /// <summary>„Vorschlagen …“ für AMapping; Ergebnis wie TAtlasTrackerPathsSuggestEvent.</summary>
    class function Suggest(const AMapping: TAtlasTrackerProjectMapping; out APaths: TArray<string>): Boolean;
      static;
    /// <summary>URL von origin der Git-Arbeitskopie, in der AFolder liegt (#2138); '' ohne. Liest nur .git/config.
    /// </summary>
    class function OriginOfFolder(const AFolder: string): string; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Win.Registry,
  Winapi.Windows,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.WorkingCopies,
  Atlas.Core.Tracker.PathSuggestions,
  Atlas.IDE.Contracts.VersionControl,
  Atlas.UI.Tracker.Settings.Strings,
  Atlas.UI.Tracker.SuggestDialog;

const
  cGitEntry = '.git';
  cGitConfig = 'config';
  cClosedProjects = '\Closed Projects';
  cGroupExtension = '.groupproj';
  cKindNames: array[TAtlasVcsKind] of string = ('', 'git', 'svn');

type
  TFound = TArray<TAtlasTrackerPathSuggestion>;

/// <summary>Arbeitskopie zu AFolder; nil ohne (nur im Hintergrund).</summary>
function VcsOf(const AFolder: string): IAtlasVersionControl;
begin
  Result := nil;
  if (AFolder <> '') and DirectoryExists(AFolder) then
  begin
    Result := TAtlasIdeVcs.ForFolder(AFolder, TAtlasIdeTrackerPathSuggestions.cVcsTimeoutMs);
  end;
  if (Result <> nil) and ((Result.Kind = TAtlasVcsKind.None) or (Result.WorkingCopy.Root = '')) then
  begin
    Result := nil;
  end;
end;

/// <summary>Zeile „Ordner: Art, Branch“ für „Prüfen“ (nur im Hintergrund).</summary>
function CheckLine(const AFolder: string): string;
var
  mVcs: IAtlasVersionControl;
  mHead: TAtlasVcsHead;
  mBranch: string;
begin
  mVcs := VcsOf(AFolder);
  if mVcs = nil then
  begin
    Exit(TAtlasOptionsStrings.Fmt(TAtlasOptionsTextId.SettingsIssuesPathsNone, [AFolder]));
  end;
  mBranch := '';
  if mVcs.Head(mHead) = TAtlasVcsOutcome.Ok then
  begin
    mBranch := mHead.Branch;
    if mHead.Detached then
    begin
      mBranch := mHead.ShortRevision(mVcs.Kind);
    end;
  end;
  Result := TAtlasOptionsStrings.Fmt(TAtlasOptionsTextId.SettingsIssuesPathsFound,
    [AFolder, AtlasVcsKindName(mVcs.Kind), mBranch]);
end;

/// <summary>Arbeitskopie von AFolder mit Grund AReason, bei der Arbeitskopie der Zeile auch ihre Externals bzw.
/// Submodule.</summary>
procedure AddWorkingCopy(var AList: TFound; const AFolder: string; AReason: TAtlasTrackerPathReason;
  const ADetail: string; const AKnown: TArray<string>; AWithNested: Boolean);
var
  mVcs: IAtlasVersionControl;
  mRow: TAtlasVcsWorkingCopyRow;
  mReason: TAtlasTrackerPathReason;
  mRoot: string;
begin
  mVcs := VcsOf(AFolder);
  if mVcs = nil then
  begin
    Exit;
  end;
  mRoot := mVcs.WorkingCopy.Root;
  TAtlasTrackerPathSuggestions.Add(AList, TAtlasTrackerPathSuggestion.Create(mRoot, cKindNames[mVcs.Kind], AReason,
    ADetail), AKnown);
  if not AWithNested then
  begin
    Exit;
  end;
  for mRow in TAtlasVcsWorkingCopies.Folders(mVcs) do
  begin
    // Main ist mRoot selbst und steht schon in der Liste.
    if mRow.Kind = TAtlasVcsWorkingCopyKind.Main then
    begin
      Continue;
    end;
    mReason := TAtlasTrackerPathReason.External;
    if mRow.Kind = TAtlasVcsWorkingCopyKind.Submodule then
    begin
      mReason := TAtlasTrackerPathReason.Submodule;
    end;
    TAtlasTrackerPathSuggestions.Add(AList, TAtlasTrackerPathSuggestion.Create(mRow.Folder, cKindNames[mVcs.Kind],
      mReason, mRoot), AKnown);
  end;
end;

/// <summary>Projekte der .groupproj AGroupFile mit ihren Arbeitskopien.</summary>
procedure AddGroup(var AList: TFound; const AGroupFile: string; const AKnown: TArray<string>);
var
  mProject: string;
begin
  if not SameText(ExtractFileExt(AGroupFile), cGroupExtension) or not FileExists(AGroupFile) then
  begin
    Exit;
  end;
  for mProject in TAtlasTrackerPathSuggestions.GroupProjects(AGroupFile,
    TFile.ReadAllText(AGroupFile, TEncoding.UTF8)) do
  begin
    AddWorkingCopy(AList, ExtractFileDir(mProject), TAtlasTrackerPathReason.Group, ExtractFileName(AGroupFile),
      AKnown, False);
  end;
end;

/// <summary>Ordner mit .git oberhalb von AFolder (AFolder eingeschlossen); '' ohne.</summary>
function GitRootOf(const AFolder: string): string;
var
  mFolder, mParent: string;
begin
  mFolder := ExcludeTrailingPathDelimiter(AFolder);
  while mFolder <> '' do
  begin
    if DirectoryExists(TPath.Combine(mFolder, cGitEntry)) or FileExists(TPath.Combine(mFolder, cGitEntry)) then
    begin
      Exit(mFolder);
    end;
    mParent := ExtractFileDir(mFolder);
    if SameText(mParent, mFolder) then
    begin
      Break;
    end;
    mFolder := mParent;
  end;
  Result := '';
end;

/// <summary>origin der Arbeitskopie AFolder (mit .git); AWorktree: .git ist eine Datei.</summary>
function OriginOf(const AFolder: string; out AWorktree: Boolean): string;
var
  mEntry, mGitDir, mConfig: string;
begin
  Result := '';
  mEntry := TPath.Combine(AFolder, cGitEntry);
  AWorktree := FileExists(mEntry);
  mGitDir := mEntry;
  if AWorktree then
  begin
    mGitDir := TAtlasTrackerPathSuggestions.CommonGitDir(TAtlasTrackerPathSuggestions.WorktreeGitDir(AFolder,
      TFile.ReadAllText(mEntry, TEncoding.UTF8)));
  end;
  mConfig := TPath.Combine(mGitDir, cGitConfig);
  if (mGitDir <> '') and FileExists(mConfig) then
  begin
    Result := TAtlasTrackerPathSuggestions.OriginUrl(TFile.ReadAllText(mConfig, TEncoding.UTF8));
  end;
end;

/// <summary>Zuletzt geöffnete Projekte, deren origin auf AOwnerRepo zeigt.</summary>
procedure AddRecent(var AList: TFound; const AOwnerRepo: string; const ARecent, AKnown: TArray<string>);
var
  mProject, mRoot, mUrl: string;
  mWorktree: Boolean;
  mReason: TAtlasTrackerPathReason;
begin
  for mProject in ARecent do
  begin
    mRoot := GitRootOf(ExtractFileDir(mProject));
    if mRoot = '' then
    begin
      Continue;
    end;
    mUrl := OriginOf(mRoot, mWorktree);
    if not SameText(TAtlasTrackerPathSuggestions.OwnerRepo(mUrl), AOwnerRepo) then
    begin
      Continue;
    end;
    mReason := TAtlasTrackerPathReason.Remote;
    if mWorktree then
    begin
      mReason := TAtlasTrackerPathReason.Worktree;
    end;
    TAtlasTrackerPathSuggestions.Add(AList, TAtlasTrackerPathSuggestion.Create(mRoot, cKindNames[TAtlasVcsKind.Git],
      mReason, mUrl), AKnown);
  end;
end;

/// <summary>Liste „Wieder öffnen“ der IDE (Hauptthread), höchstens cMaxRecent.</summary>
function RecentProjects: TArray<string>;
var
  mServices: IOTAServices;
  mRegistry: TRegistry;
  mNames: TStringList;
  mName, mProject: string;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Exit;
  end;
  mRegistry := TRegistry.Create(KEY_READ);
  mNames := TStringList.Create;
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    if not mRegistry.OpenKeyReadOnly(mServices.GetBaseRegistryKey + cClosedProjects) then
    begin
      Exit;
    end;
    mRegistry.GetValueNames(mNames);
    for mName in mNames do
    begin
      mProject := '';
      if mRegistry.GetDataType(mName) in [rdString, rdExpandString] then
      begin
        mProject := TAtlasTrackerPathSuggestions.RecentProjectOf(mRegistry.ReadString(mName));
      end;
      if (mProject <> '') and (Length(Result) < TAtlasIdeTrackerPathSuggestions.cMaxRecent) then
      begin
        Result := Result + [mProject];
      end;
    end;
  finally
    mNames.Free;
    mRegistry.Free;
  end;
end;

/// <summary>Die ganze Suche (nur im Hintergrund).</summary>
function Search(const AMapping: TAtlasTrackerProjectMapping; const ARecent: TArray<string>): TFound;
begin
  Result := nil;
  AddWorkingCopy(Result, AMapping.MatchFolder, TAtlasTrackerPathReason.Project, ExtractFileName(AMapping.Match),
    AMapping.Paths, True);
  AddGroup(Result, AMapping.Match, AMapping.Paths);
  if TAtlasTrackerPathSuggestions.IsOwnerRepo(AMapping.Project) then
  begin
    AddRecent(Result, Trim(AMapping.Project), ARecent, AMapping.Paths);
  end;
end;

{ TAtlasIdeTrackerPathSuggestions }

class procedure TAtlasIdeTrackerPathSuggestions.Check(const AFolders: TArray<string>;
  const ADone: TProc<TArray<string>>);
var
  mFolders, mLines: TArray<string>;
  mMissing: string;
begin
  mFolders := Copy(AFolders);
  mLines := nil;
  if not TAtlasIdeVcs.Run(
    procedure
    var
      mFolder: string;
    begin
      for mFolder in mFolders do
      begin
        mLines := mLines + [CheckLine(mFolder)];
      end;
    end,
    procedure
    begin
      ADone(mLines);
    end) then
  begin
    // Ohne Versionsverwaltung: jeder Ordner ohne Arbeitskopie.
    for mMissing in mFolders do
    begin
      mLines := mLines + [TAtlasOptionsStrings.Fmt(TAtlasOptionsTextId.SettingsIssuesPathsNone, [mMissing])];
    end;
    ADone(mLines);
  end;
end;

class function TAtlasIdeTrackerPathSuggestions.Suggest(const AMapping: TAtlasTrackerProjectMapping;
  out APaths: TArray<string>): Boolean;
var
  mMapping: TAtlasTrackerProjectMapping;
  mRecent: TArray<string>;
  mTitle: string;
begin
  mMapping := AMapping;
  mRecent := nil;
  if TAtlasTrackerPathSuggestions.IsOwnerRepo(AMapping.Project) then
  begin
    mRecent := RecentProjects;
  end;
  mTitle := AMapping.Connection;
  if AMapping.Project <> '' then
  begin
    mTitle := mTitle + ' · ' + AMapping.Project;
  end;
  Result := TAtlasTrackerSuggestDialog.Execute(mTitle,
    procedure(const AFill: TAtlasTrackerSuggestFill)
    var
      mFound: TFound;
    begin
      mFound := nil;
      if not TAtlasIdeVcs.Run(
        procedure
        begin
          try
            mFound := Search(mMapping, mRecent);
          except
            // Unlesbare Datei oder Registry: zeigen, was bis dahin gefunden wurde.
            on E: Exception do
            begin
              TAtlasGuard.Report(TAtlasFeature.Tracker, E);
            end;
          end;
        end,
        procedure
        begin
          AFill(mFound);
        end) then
      begin
        AFill(nil);
      end;
    end, APaths) <> TAtlasTrackerSuggestAnswer.Cancel;
end;

class function TAtlasIdeTrackerPathSuggestions.OriginOfFolder(const AFolder: string): string;
var
  mRoot: string;
  mWorktree: Boolean;
begin
  Result := '';
  mRoot := GitRootOf(AFolder);
  if mRoot <> '' then
  begin
    Result := OriginOf(mRoot, mWorktree);
  end;
end;

end.
