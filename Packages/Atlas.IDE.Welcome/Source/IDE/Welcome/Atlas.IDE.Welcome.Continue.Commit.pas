unit Atlas.IDE.Welcome.Continue.Commit;

// Klick auf einen eingehenden Commit im Bereich „Weiterarbeiten“ (#571):
// listet seine Dateien im Fenster „Atlas-Ergebnisse“ (#400), die eigenen
// zuerst. Ohne Dateiliste (etwa bei einem Merge) fragt es den Anbieter der
// Versionsverwaltung im Ordner des Projekts im Hintergrund (TAtlasIdeVcs.Run)
// und meldet einen Fehler in der Meldungsansicht.

interface

uses
  System.SysUtils,
  Atlas.Core.Welcome.Continue,
  Atlas.Core.Notifications.MessageSink;

type
  TAtlasIdeContinueCommit = record
  public
    /// <summary>Dateien von ACommit im Ergebnisfenster zeigen; ohne Dateiliste beim Anbieter im Ordner von
    /// AProject nachfragen. AAlive: Ist der Bereich noch da, wenn die Antwort kommt (sonst geschieht nichts)?
    /// AMessage: Zeile in die Meldungsansicht, wenn die Abfrage scheitert.</summary>
    class procedure Show(const AProject: string; const ACommit: TAtlasContinueCommit; const AAlive: TFunc<Boolean>;
      const AMessage: TAtlasMessageSink); static;
  end;

implementation

uses
  Atlas.Core.Results.Model,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Welcome.Strings,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Contracts.VersionControl;

/// <summary>Einträge für „Atlas-Ergebnisse“: die Dateien des Commits, die eigenen zuerst.</summary>
function CommitEntries(const ACommit: TAtlasContinueCommit; const AFiles: TArray<string>): TArray<TAtlasResultEntry>;
var
  mFileName: string;
  mEntry: TAtlasResultEntry;
begin
  Result := nil;
  for mFileName in TAtlasContinueSession.OwnFirst(ACommit.Files, AFiles) do
  begin
    mEntry := TAtlasResultEntry.Create(mFileName, 0, 0);
    mEntry.Text := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueCommitFile,
      [ACommit.Commit.ShortHash]);
    Result := Result + [mEntry];
  end;
end;

procedure ShowEntries(const ACommit: TAtlasContinueCommit; const AFiles: TArray<string>);
var
  mCommit: TAtlasContinueCommit;
  mEntries: TArray<TAtlasResultEntry>;
begin
  mCommit := ACommit;
  mEntries := CommitEntries(ACommit, AFiles);
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      TAtlasIdeResultsWindow.ShowEntries(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueCommitTitle,
        [mCommit.Commit.ShortHash, mCommit.Commit.Summary, mCommit.Commit.Author, Length(mEntries)]), mEntries);
    end);
end;

/// <summary>Im Hintergrund: Dateien des Commits AHash beim Anbieter im Ordner ADir.</summary>
function CommitFiles(const ADir, AHash: string; out AFiles: TArray<string>): TAtlasVcsOutcome;
var
  mLocal: IAtlasVcsLocalWork;
  mChanges: TArray<TAtlasVcsChange>;
  mChange: TAtlasVcsChange;
begin
  AFiles := nil;
  Result := TAtlasVcsOutcome.Failed;
  if not Supports(TAtlasIdeVcs.ForFolder(ADir, TAtlasWelcomeContinue.cFetchTimeoutMs), IAtlasVcsLocalWork,
    mLocal) then
  begin
    Exit;
  end;
  Result := mLocal.ChangesIn(AHash, mChanges);
  for mChange in mChanges do
  begin
    AFiles := AFiles + [mChange.Path];
  end;
end;

{ TAtlasIdeContinueCommit }

class procedure TAtlasIdeContinueCommit.Show(const AProject: string; const ACommit: TAtlasContinueCommit;
  const AAlive: TFunc<Boolean>; const AMessage: TAtlasMessageSink);
var
  mCommit: TAtlasContinueCommit;
  mAlive: TFunc<Boolean>;
  mMessage: TAtlasMessageSink;
  mDir: string;
  mFiles: TArray<string>;
  mOutcome: TAtlasVcsOutcome;
begin
  if Length(ACommit.Commit.Files) > 0 then
  begin
    ShowEntries(ACommit, ACommit.Commit.Files);
    Exit;
  end;
  mCommit := ACommit;
  mAlive := AAlive;
  mMessage := AMessage;
  mDir := ExtractFileDir(AProject);
  mFiles := nil;
  mOutcome := TAtlasVcsOutcome.Failed;
  TAtlasIdeVcs.Run(
    procedure
    begin
      mOutcome := CommitFiles(mDir, mCommit.Commit.Hash, mFiles);
    end,
    procedure
    begin
      if not mAlive() then
      begin
        Exit;
      end;
      if mOutcome <> TAtlasVcsOutcome.Ok then
      begin
        mMessage.Say(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueCommitFailed,
          [mCommit.Commit.ShortHash, AtlasVcsOutcomeName(mOutcome)]));
        Exit;
      end;
      ShowEntries(mCommit, mFiles);
    end);
end;

end.
