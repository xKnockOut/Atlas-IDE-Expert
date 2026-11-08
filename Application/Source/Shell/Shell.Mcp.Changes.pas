unit Shell.Mcp.Changes;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Units und Änderungen für die Prompts (#1357): Auflösung von
// Unit-Namen und Pfaden (#99) und die geänderten Dateien samt Befunden für prepare_commit.

interface

uses
  System.SysUtils,
  Atlas.Common.Mcp.Paths,
  Atlas.Common.Mcp.Prompts,
  Atlas.Common.Index.Contract,
  Shell.WorkspaceGroup;

/// <summary>Unit-Name oder Pfad → Datei, geprüft wie Pfadparameter (#99): Units außerhalb des Arbeitsbereichs
/// und seiner Bibliothekspfade ergeben einen Fehler mit Begründung (#1357).</summary>
function UnitFileOf(const AIndex: ISymbolIndex; AGroup: TShellWorkspaceGroup; AGuard: TMcpPathGuard):
  TFunc<string, string>;
/// <summary>Änderungen laut Git oder SVN für prepare_commit (#1357): geänderte Dateien unter ARoot und ihre Befunde
/// in geänderten Zeilen wie --changed-lines, dazu der Commit-Präfix, den das Plugin für das aktuelle Issue in
/// &lt;gitdir&gt;/atlas-commit-prefix schreibt (#765).</summary>
function ChangesOf(AGroup: TShellWorkspaceGroup; const ARoot: string): TMcpChangesFunc;

implementation

uses
  Atlas.Common.Mcp.Server,
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.ChangedFiles,
  Atlas.Core.VersionControl.Providers.Git,
  Atlas.Core.Tracker.CommitHook,
  Shell.VersionControlChanges,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Rules.Builtin,
  Shell.Platform,
  Shell.Bootstrap,
  Shell.Mcp.Context,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TMcpChangesText = (NotInIndex);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpChangesText] of TAtlasText = (
    (De: 'Unit "%s" ist nicht im Index'; En: 'Unit "%s" is not in the index'));

/// <summary>Unit-Name oder Pfad → Datei, geprüft wie Pfadparameter (#99): Units außerhalb des Arbeitsbereichs
/// und seiner Bibliothekspfade ergeben einen Fehler mit Begründung (#1357).</summary>
function UnitFileOf(const AIndex: ISymbolIndex; AGroup: TShellWorkspaceGroup; AGuard: TMcpPathGuard):
  TFunc<string, string>;
begin
  Result :=
    function(AUnit: string): string
    var
      mUnit: TUnitIndex;
    begin
      if (Pos('\', AUnit) > 0) or (Pos('/', AUnit) > 0) or SameText(ExtractFileExt(AUnit), '.pas') then
      begin
        Exit(AGuard.Resolve(AUnit));
      end;
      // Units anderer Projekte der Gruppe erst bei Bedarf (#1112).
      AGroup.EnsureUnit(AUnit);
      if not AIndex.FindUnit(AUnit, mUnit) then
      begin
        raise EMcpToolError.Create(cTexts[TMcpChangesText.NotInIndex].Fmt([AUnit]));
      end;
      Result := AGuard.Resolve(mUnit.FileName);
    end;
end;

function BaseOrHead(const ABase: string): string;
begin
  Result := ABase;
  if Result = '' then
  begin
    Result := 'HEAD';
  end;
end;

/// <summary>Erkennt Git oder SVN unter ARoot und lädt die Änderungen gegenüber ABase ('' = nicht eingecheckt
/// gegenüber HEAD bzw. BASE); False mit dem Grund in AError.</summary>
function LoadChanges(const AProcess: ICompilerProcess; const ASettings: TServerSettings; const ARoot, ABase: string;
  out AVcs: TVcsChanges; out AError: string): Boolean;
begin
  AError := '';
  AVcs := nil;
  try
    AVcs := TVcsChanges.Detect(AProcess, ARoot, ASettings.VcsProvider, ASettings.VcsGitPath, ASettings.VcsSvnPath,
      ASettings.VcsTimeoutSeconds);
    // Ohne Basis: nicht eingecheckte Änderungen gegenüber HEAD (SVN: BASE); mit Basis seit der Abzweigung.
    AVcs.Load(BaseOrHead(ABase), ABase <> '', ABase = '', True, True);
  except
    on E: EVcsChanges do
    begin
      FreeAndNil(AVcs);
      AError := E.Message;
    end;
  end;
  Result := AVcs <> nil;
end;

/// <summary>Geänderte Datei relativ zu ARoot mit ihren Befunden in geänderten Zeilen (wie --changed-lines).</summary>
function ChangedFileOf(AGroup: TShellWorkspaceGroup; AVcs: TVcsChanges; const ARoot, AFile: string;
  const ACheckProject: TCheckProjectFunc): TMcpChangedFile;
var
  mText: string;
  mLines: TChangedLines;
  mFinding: TRuleFinding;
  mScopes: TFindingScopes;
begin
  Result := Default(TMcpChangedFile);
  Result.Path := ExtractRelativePath(IncludeTrailingPathDelimiter(ARoot), AFile);
  Result.Findings := nil;
  if not (MatchText(ExtractFileExt(AFile), ['.pas', '.dpr', '.dpk']) and ReadSourceText(AFile, mText) and
    TChangedFiles.LinesOf(AVcs.Lines, AVcs.RepoRoot, AFile, mLines)) then
  begin
    Exit;
  end;
  for mFinding in TFileChecker.CheckText(BuiltinRules, AGroup.Main.Configuration.Settings, Result.Path, mText,
    TCheckOrigin.Make(ACheckProject(AFile), AGroup.Main.State.CheckSource(AFile)), mScopes) do
  begin
    if mLines.Contains(mFinding.Range.StartPos.Line) then
    begin
      Result.Findings := Result.Findings + [mFinding];
    end;
  end;
end;

/// <summary>Änderungen unter ARoot gegenüber ABase samt Befunden und Commit-Präfix.</summary>
function ChangeSetOf(AGroup: TShellWorkspaceGroup; const ARoot, ABase: string): TMcpChangeSet;
var
  mProcess: ICompilerProcess;
  mVcs: TVcsChanges;
  mFile: string;
  mCheckProject: TCheckProjectFunc;
begin
  Result := Default(TMcpChangeSet);
  Result.Files := nil;
  Result.Base := BaseOrHead(ABase);
  // Über eine Variable halten: Detect gibt einen Probelauf frei, bevor es den nächsten startet.
  mProcess := TProcessRunner.Create;
  if not LoadChanges(mProcess, AGroup.Main.Configuration.Settings, ARoot, ABase, mVcs, Result.Error) then
  begin
    Exit;
  end;
  try
    Result.Vcs := mVcs.Name;
    mCheckProject := CheckProjectOf(AGroup);
    for mFile in mVcs.Files do
    begin
      if TMcpPathGuard.IsInside(ARoot, mFile) then
      begin
        Result.Files := Result.Files + [ChangedFileOf(AGroup, mVcs, ARoot, mFile, mCheckProject)];
      end;
    end;
    if mVcs is TGitChanges then
    begin
      Result.CommitPrefix := TAtlasCommitHook.ReadPrefix(TAtlasGitVersionControl.GitDir(mVcs.RepoRoot));
    end;
  finally
    mVcs.Free;
  end;
end;

/// <summary>Änderungen laut Git oder SVN für prepare_commit (#1357): geänderte Dateien unter ARoot und ihre Befunde
/// in geänderten Zeilen wie --changed-lines, dazu der Commit-Präfix, den das Plugin für das aktuelle Issue in
/// &lt;gitdir&gt;/atlas-commit-prefix schreibt (#765).</summary>
function ChangesOf(AGroup: TShellWorkspaceGroup; const ARoot: string): TMcpChangesFunc;
var
  mRoot: string;
begin
  mRoot := ARoot;
  Result :=
    function(const ABase: string): TMcpChangeSet
    begin
      Result := ChangeSetOf(AGroup, mRoot, ABase);
    end;
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.Changes', cTexts);

end.
