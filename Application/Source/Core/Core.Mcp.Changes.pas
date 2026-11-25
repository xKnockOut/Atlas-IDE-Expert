unit Core.Mcp.Changes;

// Host-Rolle Core: MCP-Modus (--mcp, #48), Units und Änderungen für die Prompts (#1357): Auflösung von
// Unit-Namen und Pfaden (#99) und die geänderten Dateien samt Befunden für prepare_commit.

interface

uses
  System.SysUtils,
  Atlas.Common.Mcp.Paths,
  Atlas.Common.Mcp.Prompts,
  Atlas.Common.Index.Contract,
  Atlas.Common.Mcp.Contract.Workspace,
  Core.Mcp.Context;

/// <summary>Unit-Name oder Pfad → Datei, geprüft wie Pfadparameter (#99): Units außerhalb des Arbeitsbereichs
/// und seiner Bibliothekspfade ergeben einen Fehler mit Begründung (#1357).</summary>
function UnitFileOf(const AIndex: ISymbolIndex; const AWorkspace: IMcpWorkspace; AGuard: TMcpPathGuard):
  TFunc<string, string>;
/// <summary>Änderungen laut Git oder SVN für prepare_commit (#1357): geänderte Dateien unter ARoot und ihre Befunde
/// in geänderten Zeilen wie --changed-lines, dazu der Commit-Präfix, den das Plugin für das aktuelle Issue in
/// &lt;gitdir&gt;/atlas-commit-prefix schreibt (#765).</summary>
function ChangesOf(const AAdapters: TMcpHostAdapters; const AWorkspace: IMcpWorkspace; const ARoot: string):
  TMcpChangesFunc;

implementation

uses
  Atlas.Common.Mcp.Server,
  System.StrUtils,
  Atlas.Core.Tracker.CommitHook,
  Core.Mcp.IssueTools,
  Atlas.Common.Mcp.Contract.Vcs,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Mcp.Contract.TextChecks,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TMcpChangesText = (NotInIndex);
{$SCOPEDENUMS OFF}

const
  /// <summary>Längster Commit-Präfix, den prepare_commit übernimmt.</summary>
  cMaxPrefixBytes = 1024;
  cTexts: array[TMcpChangesText] of TAtlasText = (
    (De: 'Unit "%s" ist nicht im Index'; En: 'Unit "%s" is not in the index'));

/// <summary>Unit-Name oder Pfad → Datei, geprüft wie Pfadparameter (#99): Units außerhalb des Arbeitsbereichs
/// und seiner Bibliothekspfade ergeben einen Fehler mit Begründung (#1357).</summary>
function UnitFileOf(const AIndex: ISymbolIndex; const AWorkspace: IMcpWorkspace; AGuard: TMcpPathGuard):
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
      AWorkspace.EnsureUnit(AUnit);
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

/// <summary>Geänderte Datei relativ zu ARoot mit ihren Befunden in geänderten Zeilen (wie --changed-lines); ohne
/// AChecks ohne Befunde.</summary>
function ChangedFileOf(const AWorkspace: IMcpWorkspace; const AVcs: IMcpVcsChanges; const ARoot, AFile: string;
  const AChecks: IMcpTextChecks): TMcpChangedFile;
var
  mText: string;
  mFinding: TRuleFinding;
begin
  Result := Default(TMcpChangedFile);
  Result.Path := ExtractRelativePath(IncludeTrailingPathDelimiter(ARoot), AFile);
  Result.Findings := nil;
  if (AChecks = nil) or not (MatchText(ExtractFileExt(AFile), ['.pas', '.dpr', '.dpk']) and
    ReadSourceText(AFile, mText)) then
  begin
    Exit;
  end;
  for mFinding in AChecks.Check(AFile, Result.Path, mText, AWorkspace.Settings) do
  begin
    if AVcs.LineChanged(AFile, mFinding.Range.StartPos.Line) then
    begin
      Result.Findings := Result.Findings + [mFinding];
    end;
  end;
end;

/// <summary>Änderungen unter ARoot gegenüber ABase samt Befunden und Commit-Präfix.</summary>
function ChangeSetOf(const AAdapters: TMcpHostAdapters; const AWorkspace: IMcpWorkspace; const ARoot, ABase: string):
  TMcpChangeSet;
var
  mVcs: IMcpVcsChanges;
  mFile: string;
begin
  Result := Default(TMcpChangeSet);
  Result.Files := nil;
  Result.Base := BaseOrHead(ABase);
  if not AAdapters.Vcs.Changes(ARoot, ABase, AWorkspace.Settings, mVcs, Result.Error) then
  begin
    Exit;
  end;
  Result.Vcs := mVcs.Name;
  for mFile in mVcs.Files do
  begin
    if TMcpPathGuard.IsInside(ARoot, mFile) then
    begin
      Result.Files := Result.Files + [ChangedFileOf(AWorkspace, mVcs, ARoot, mFile, AAdapters.TextChecks)];
    end;
  end;
  if mVcs.Git then
  begin
    // Direkt gelesen: Der Dateizugriff des Tracker-Moduls (TAtlasTrackerFiles) ist im Server nicht angemeldet.
    Result.CommitPrefix := ReadGitDirFile(AAdapters.GitDir(mVcs.RepoRoot), TAtlasCommitHook.cPrefixFile,
      cMaxPrefixBytes);
  end;
end;

/// <summary>Änderungen laut Git oder SVN für prepare_commit (#1357): geänderte Dateien unter ARoot und ihre Befunde
/// in geänderten Zeilen wie --changed-lines, dazu der Commit-Präfix, den das Plugin für das aktuelle Issue in
/// &lt;gitdir&gt;/atlas-commit-prefix schreibt (#765).</summary>
function ChangesOf(const AAdapters: TMcpHostAdapters; const AWorkspace: IMcpWorkspace; const ARoot: string):
  TMcpChangesFunc;
var
  mRoot: string;
  mAdapters: TMcpHostAdapters;
begin
  mRoot := ARoot;
  mAdapters := AAdapters;
  Result :=
    function(const ABase: string): TMcpChangeSet
    begin
      Result := ChangeSetOf(mAdapters, AWorkspace, mRoot, ABase);
    end;
end;

initialization
  TAtlasTextTables.Add('Core.Mcp.Changes', cTexts);

end.
