unit Atlas.IDE.Vcs.WorkingCopies;

// „Arbeitskopien …“ in der IDE (#1292): Tabelle der Wurzel einer Gruppe und
// ihrer svn:externals bzw. Git-Submodule (TAtlasWorkingCopiesDialog, modal,
// Thema der IDE).
// - Alles im Hintergrund über TAtlasIdeVcs.Run: erst Collect (ohne Server),
//   dann je Zeile nacheinander die Revision (svnversion) bzw. bei Git die
//   Änderungen des Submoduls; die Tabelle füllt sich zeilenweise. Ein spätes
//   Ergebnis nach dem Schließen bzw. nach einem neuen Collect verfällt.
// - „Server prüfen“ fragt je Zeile svn log nach neuen Commits (nur auf
//   Klick, nie von selbst).
// - Aktualisieren: Wurzel bzw. die Arbeitskopie der Zeile, mit Externals oder
//   ohne (--ignore-externals), wie die Schnellaktion Pull: vorher frisch auf
//   lokale Änderungen geprüft. Danach liest Atlas die Tabelle neu und meldet
//   ADone (Bereich „Projekte“). Den Index der geholten Ordner frischt die
//   Dateiüberwachung auf (#395, didChangeWatchedFiles für die Projektordner).
// - „Revision festschreiben …“ fragt mit der neuen Zeile nach, schreibt
//   svn:externals im definierenden Ordner (propset) und committet nicht.
// - Doppelklick bzw. „Ordner öffnen“: Explorer.
// Protokoll anonym: nur Art und Ergebnis, nie Pfad oder Name.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.WorkingCopies,
  Atlas.UI.Vcs.WorkingCopies;

type
  TAtlasIdeWorkingCopies = class(TInterfacedObject)
  public const
    /// <summary>Zeitlimit je lokalem Aufruf (svnversion, status); vcs.timeoutSeconds, wenn größer.</summary>
    LocalTimeoutMs = 10000;
    /// <summary>Zeitlimit je Serveraufruf (svn log) und für Aktualisieren.</summary>
    ServerTimeoutMs = 120000;
  private
    FFolder: string;
    FName: string;
    FDialog: TAtlasWorkingCopiesDialog;
    FList: TAtlasVcsWorkingCopyList;
    FOpen: Boolean;
    /// <summary>Zählt jedes Collect; Ergebnisse eines älteren verfallen.</summary>
    FGeneration: Integer;
    FDone: TProc;
    procedure Collect;
    procedure FillNext(AIndex: Integer);
    procedure CheckNext(AIndex: Integer);
    procedure CheckServer(Sender: TObject);
    procedure Update(Sender: TObject; AIndex: Integer; AIgnoreExternals: Boolean);
    procedure Pin(Sender: TObject; AIndex: Integer);
    procedure OpenFolder(Sender: TObject; AIndex: Integer);
    function Current(AGeneration: Integer): Boolean;
    function RowName(AIndex: Integer): string;
  public
    /// <summary>Tabelle für AProject (.dproj bzw. .groupproj) zeigen (Hauptthread, modal); ADone im Hauptthread
    /// nach jedem Aktualisieren bzw. Festschreiben (z. B. „Projekte“ neu abfragen).</summary>
    class procedure ShowFor(const AProject: string; const ADone: TProc); static;
    /// <summary>Text für „Revision festschreiben …“: Zeile vorher und nachher.</summary>
    class function PinQuestion(const AList: TAtlasVcsWorkingCopyList; AIndex: Integer; const AName: string;
      out AText: string): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.UITypes,
  Vcl.Controls,
  Vcl.Dialogs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Welcome.QuickActions,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.DockWindow,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Vcs.Service;

class procedure TAtlasIdeWorkingCopies.ShowFor(const AProject: string; const ADone: TProc);
var
  mSession: TAtlasIdeWorkingCopies;
  mKeep: IInterface;
  mFile: string;
begin
  if ExtractFileDir(AProject) = '' then
    Exit;
  mSession := TAtlasIdeWorkingCopies.Create;
  mKeep := mSession;
  mSession.FFolder := ExtractFileDir(AProject);
  mFile := TAtlasIdeFiles.GroupOfProject(AProject);
  if mFile = '' then
    mFile := AProject;
  mSession.FName := ChangeFileExt(ExtractFileName(mFile), '');
  mSession.FDone := ADone;
  mSession.FList := TAtlasVcsWorkingCopyList.Empty;
  mSession.FDialog := TAtlasWorkingCopiesDialog.CreateDialog(nil, mSession.FName);
  try
    TAtlasIdeDockWindow.ApplyIdeTheme(mSession.FDialog);
    mSession.FDialog.OnCheckServer := mSession.CheckServer;
    mSession.FDialog.OnUpdate := mSession.Update;
    mSession.FDialog.OnPin := mSession.Pin;
    mSession.FDialog.OnOpenFolder := mSession.OpenFolder;
    mSession.FOpen := True;
    mSession.Collect;
    mSession.FDialog.ShowModal;
  finally
    // Späte Ergebnisse gehen danach nicht mehr an den Dialog; die Sitzung lebt, bis der letzte Lauf endet.
    mSession.FOpen := False;
    mSession.FDialog.Free;
    mSession.FDialog := nil;
  end;
end;

function TAtlasIdeWorkingCopies.Current(AGeneration: Integer): Boolean;
begin
  Result := FOpen and (FDialog <> nil) and (AGeneration = FGeneration);
end;

function TAtlasIdeWorkingCopies.RowName(AIndex: Integer): string;
begin
  Result := FName;
  if (AIndex >= 0) and (AIndex <= High(FList.Rows)) then
    Result := FList.Rows[AIndex].Caption(FName);
end;

procedure TAtlasIdeWorkingCopies.Collect;
var
  mKeep: IInterface;
  mFolder: string;
  mList: TAtlasVcsWorkingCopyList;
  mGeneration: Integer;
begin
  Inc(FGeneration);
  mGeneration := FGeneration;
  mKeep := Self;
  mFolder := FFolder;
  mList := TAtlasVcsWorkingCopyList.Empty;
  // Arbeit und Ergebnis teilen sich mList; das Ergebnis kommt erst nach der Arbeit.
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      mList := TAtlasVcsWorkingCopies.Collect(TAtlasIdeVcs.ForFolder(mFolder, TAtlasIdeVcs.AtLeast(LocalTimeoutMs)));
    end,
    procedure
    begin
      if (mKeep = nil) or not Current(mGeneration) then
        Exit;
      TAtlasGuard.Log(Format('Arbeitskopien: %s, %d Zeilen, %s', [AtlasVcsKindName(mList.Kind),
        Length(mList.Rows), AtlasVcsOutcomeName(mList.Outcome)]));
      if (mList.Kind <> TAtlasVcsKind.Git) and (mList.Kind <> TAtlasVcsKind.Svn) then
        TAtlasIdeVcs.Report(TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesNoVcs));
      FList := mList;
      FDialog.SetList(FList);
      FillNext(0);
    end) then
    TAtlasIdeVcs.Report(TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesNoVcs));
end;

procedure TAtlasIdeWorkingCopies.FillNext(AIndex: Integer);
var
  mKeep: IInterface;
  mIndex, mGeneration: Integer;
  mWork: TAtlasVcsWorkingCopyList;
  mRoot, mFolder: string;
begin
  // Nächste Zeile ohne Revision (SVN) bzw. ohne Änderungen (Git: Wurzel und Submodule je für sich).
  mIndex := AIndex;
  while (mIndex <= High(FList.Rows)) and FList.Rows[mIndex].Loaded and
    not ((FList.Kind = TAtlasVcsKind.Git) and (FList.Rows[mIndex].Changed < 0)) do
    Inc(mIndex);
  if mIndex > High(FList.Rows) then
    Exit;
  mGeneration := FGeneration;
  mKeep := Self;
  // Eigene Kopie für den Hintergrund: Die Tabelle liest FList weiter.
  mWork := FList;
  mWork.Rows := Copy(FList.Rows);
  mRoot := FList.Root;
  mFolder := FList.Rows[mIndex].Folder;
  if not TAtlasIdeVcs.Run(
    procedure
    var
      mSvn: IAtlasVcsSvnWorkingCopy;
    begin
      if mWork.Kind = TAtlasVcsKind.Git then
        TAtlasVcsWorkingCopies.FillChanges(mWork, mIndex, TAtlasIdeVcs.ForFolder(mFolder,
          TAtlasIdeVcs.AtLeast(LocalTimeoutMs)))
      else
      begin
        if not Supports(TAtlasIdeVcs.ForFolder(mRoot, TAtlasIdeVcs.AtLeast(LocalTimeoutMs)), IAtlasVcsSvnWorkingCopy,
          mSvn) then
          mSvn := nil;
        TAtlasVcsWorkingCopies.FillRevision(mWork, mIndex, mSvn);
      end;
    end,
    procedure
    begin
      if (mKeep = nil) or not Current(mGeneration) then
        Exit;
      FList.Rows[mIndex] := mWork.Rows[mIndex];
      FDialog.SetRow(mIndex, FList.Rows[mIndex]);
      FillNext(mIndex + 1);
    end) then
    Exit;
end;

procedure TAtlasIdeWorkingCopies.CheckServer(Sender: TObject);
begin
  if FList.Kind <> TAtlasVcsKind.Svn then
    Exit;
  FDialog.SetBusy(True);
  CheckNext(0);
end;

procedure TAtlasIdeWorkingCopies.CheckNext(AIndex: Integer);
var
  mKeep: IInterface;
  mIndex, mGeneration: Integer;
  mWork: TAtlasVcsWorkingCopyList;
  mRoot: string;
begin
  // Nur Zeilen mit Pfad im selben Repository; je Zeile ein svn log, nacheinander.
  mIndex := AIndex;
  while (mIndex <= High(FList.Rows)) and (FList.Rows[mIndex].RepositoryPath = '') do
    Inc(mIndex);
  if mIndex > High(FList.Rows) then
  begin
    FDialog.SetBusy(False);
    Exit;
  end;
  mGeneration := FGeneration;
  mKeep := Self;
  mWork := FList;
  mWork.Rows := Copy(FList.Rows);
  mRoot := FList.Root;
  FDialog.SetChecking(mIndex, True);
  if not TAtlasIdeVcs.Run(
    procedure
    var
      mExternals: IAtlasVcsSvnExternals;
    begin
      if not Supports(TAtlasIdeVcs.ForFolder(mRoot, TAtlasIdeVcs.AtLeast(ServerTimeoutMs)), IAtlasVcsSvnExternals,
        mExternals) then
        mExternals := nil;
      TAtlasVcsWorkingCopies.CheckServer(mWork, mIndex, mExternals);
    end,
    procedure
    begin
      if (mKeep = nil) or not Current(mGeneration) then
        Exit;
      FList.Rows[mIndex] := mWork.Rows[mIndex];
      FDialog.SetChecking(mIndex, False);
      FDialog.SetRow(mIndex, FList.Rows[mIndex]);
      CheckNext(mIndex + 1);
    end) then
    FDialog.SetBusy(False);
end;

procedure TAtlasIdeWorkingCopies.Update(Sender: TObject; AIndex: Integer; AIgnoreExternals: Boolean);
var
  mKeep: IInterface;
  mFolder, mName: string;
  mIgnore: Boolean;
  mOutcome: TAtlasPullOutcome;
  mReason: TAtlasVcsOutcome;
begin
  if (AIndex < 0) or (AIndex > High(FList.Rows)) then
    Exit;
  mKeep := Self;
  // Wurzel bzw. die eigene Arbeitskopie des Externals (der Ordner hat ein eigenes .svn).
  mFolder := FList.Rows[AIndex].Folder;
  mName := RowName(AIndex);
  mIgnore := AIgnoreExternals;
  mOutcome := TAtlasPullOutcome.Failed;
  mReason := TAtlasVcsOutcome.Failed;
  FDialog.SetBusy(True);
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      mOutcome := TAtlasWelcomeQuickActions.Pull(TAtlasIdeVcs.ForFolder(mFolder,
        TAtlasIdeVcs.AtLeast(ServerTimeoutMs)), mIgnore, mReason);
    end,
    procedure
    begin
      if mKeep = nil then
        Exit;
      TAtlasGuard.Log(Format('Arbeitskopien: aktualisiert (ohne Externals %s), %s',
        [BoolToStr(mIgnore, True), AtlasVcsOutcomeName(mReason)]));
      case mOutcome of
        TAtlasPullOutcome.Updated:
          TAtlasIdeVcs.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsWorkingCopiesUpdated, [mName]));
        TAtlasPullOutcome.UpToDate:
          TAtlasIdeVcs.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsWorkingCopiesUpToDate, [mName]));
        TAtlasPullOutcome.Blocked:
          TAtlasIdeVcs.Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgPullBlocked, [mName]));
      else
        if mReason = TAtlasVcsOutcome.LoginNeeded then
          TAtlasIdeVcs.Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgPullLogin, [mName]))
        else
          TAtlasIdeVcs.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsWorkingCopiesUpdateFailed, [mName,
            AtlasVcsOutcomeName(mReason)]));
      end;
      if Assigned(FDone) then
        FDone();
      if not FOpen or (FDialog = nil) then
        Exit;
      FDialog.SetBusy(False);
      // Neue Revisionen, ggf. neue Externals: neu lesen.
      Collect;
    end) then
    FDialog.SetBusy(False);
end;

class function TAtlasIdeWorkingCopies.PinQuestion(const AList: TAtlasVcsWorkingCopyList; AIndex: Integer;
  const AName: string; out AText: string): Boolean;
var
  mOwner, mDefinition: string;
begin
  AText := '';
  Result := TAtlasVcsWorkingCopies.PinnedText(AList, AIndex, mOwner, mDefinition);
  if not Result then
    Exit;
  if mOwner = '' then
    mOwner := AName
  else
    mOwner := StringReplace(mOwner, '/', '\', [rfReplaceAll]);
  AText := TAtlasStrings.Fmt(TAtlasTextId.VcsWorkingCopiesPinConfirm, [AList.Rows[AIndex].Caption(AName),
    AList.Rows[AIndex].Revision, mOwner, sLineBreak + sLineBreak]);
end;

procedure TAtlasIdeWorkingCopies.Pin(Sender: TObject; AIndex: Integer);
var
  mKeep: IInterface;
  mQuestion, mRoot, mName, mRevision: string;
  mWork: TAtlasVcsWorkingCopyList;
  mOutcome: TAtlasVcsOutcome;
begin
  if not PinQuestion(FList, AIndex, FName, mQuestion) then
    Exit;
  if MessageDlg(mQuestion, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  mKeep := Self;
  mWork := FList;
  mWork.Rows := Copy(FList.Rows);
  mRoot := FList.Root;
  mName := RowName(AIndex);
  mRevision := FList.Rows[AIndex].Revision;
  mOutcome := TAtlasVcsOutcome.Failed;
  FDialog.SetBusy(True);
  if not TAtlasIdeVcs.Run(
    procedure
    var
      mExternals: IAtlasVcsSvnExternals;
    begin
      if not Supports(TAtlasIdeVcs.ForFolder(mRoot, TAtlasIdeVcs.AtLeast(LocalTimeoutMs)), IAtlasVcsSvnExternals,
        mExternals) then
        mExternals := nil;
      mOutcome := TAtlasVcsWorkingCopies.Pin(mWork, AIndex, mExternals);
    end,
    procedure
    begin
      if mKeep = nil then
        Exit;
      TAtlasGuard.Log('Arbeitskopien: festschreiben, ' + AtlasVcsOutcomeName(mOutcome));
      if mOutcome = TAtlasVcsOutcome.Ok then
        TAtlasIdeVcs.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsWorkingCopiesPinned, [mName, mRevision]))
      else
        TAtlasIdeVcs.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsWorkingCopiesPinFailed, [mName,
          AtlasVcsOutcomeName(mOutcome)]));
      if Assigned(FDone) then
        FDone();
      if not FOpen or (FDialog = nil) then
        Exit;
      FDialog.SetBusy(False);
      Collect;
    end) then
    FDialog.SetBusy(False);
end;

procedure TAtlasIdeWorkingCopies.OpenFolder(Sender: TObject; AIndex: Integer);
var
  mFolder: string;
begin
  if (AIndex < 0) or (AIndex > High(FList.Rows)) then
    Exit;
  mFolder := FList.Rows[AIndex].Folder;
  TAtlasGuard.Run(TAtlasFeature.Files,
    procedure
    begin
      if DirectoryExists(mFolder) then
        ShellExecute(0, 'open', PChar(mFolder), nil, nil, SW_SHOWNORMAL);
    end);
end;

end.
