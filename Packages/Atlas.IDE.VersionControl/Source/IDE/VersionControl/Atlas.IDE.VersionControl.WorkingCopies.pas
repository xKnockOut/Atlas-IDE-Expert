unit Atlas.IDE.VersionControl.WorkingCopies;

// „Arbeitskopien …“ in der IDE (#1292): Tabelle der Wurzel einer Gruppe und
// ihrer svn:externals bzw. Git-Submodule (TAtlasWorkingCopiesDialog, modal,
// Thema der IDE).
// - Alles im Hintergrund über TAtlasIdeVcsCore.Run: erst Collect (ohne Server),
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
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.WorkingCopies,
  Atlas.UI.VersionControl.WorkingCopies;

type
  TAtlasIdeWorkingCopies = class(TInterfacedObject)
  public const
    /// <summary>Zeitlimit je lokalem Aufruf (svnversion, status); vcs.timeoutSeconds, wenn größer.</summary>
    cLocalTimeoutMs = 10000;
    /// <summary>Zeitlimit je Serveraufruf (svn log) und für Aktualisieren.</summary>
    cServerTimeoutMs = 120000;
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
    /// <summary>Nach Aktualisieren bzw. Festschreiben: FDone melden und die Tabelle neu lesen, solange offen.</summary>
    procedure AfterChange;
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
  Atlas.Core.VersionControl.Pull,
  Atlas.UI.Strings,
  Atlas.UI.VersionControl.Strings,
  Atlas.IDE.Foundation.DockWindow,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.VersionControl.Service;

class procedure TAtlasIdeWorkingCopies.ShowFor(const AProject: string; const ADone: TProc);
var
  mSession: TAtlasIdeWorkingCopies;
  mKeep: IInterface;
  mFile: string;
begin
  if ExtractFileDir(AProject) = '' then
  begin
    Exit;
  end;
  mSession := TAtlasIdeWorkingCopies.Create;
  mKeep := mSession;
  mSession.FFolder := ExtractFileDir(AProject);
  mFile := TAtlasIdeFiles.GroupOfProject(AProject);
  if mFile = '' then
  begin
    mFile := AProject;
  end;
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
  begin
    Result := FList.Rows[AIndex].Caption(FName);
  end;
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
  if not TAtlasIdeVcsCore.Run(
    procedure
    begin
      mList := TAtlasVcsWorkingCopies.Collect(TAtlasIdeVcsCore.ForFolder(mFolder, TAtlasIdeVcsCore.AtLeast(cLocalTimeoutMs)));
    end,
    procedure
    begin
      if (mKeep = nil) or not Current(mGeneration) then
      begin
        Exit;
      end;
      TAtlasGuard.Log(Format('Arbeitskopien: %s, %d Zeilen, %s', [AtlasVcsKindName(mList.Kind),
        Length(mList.Rows), AtlasVcsOutcomeName(mList.Outcome)]));
      if (mList.Kind <> TAtlasVcsKind.Git) and (mList.Kind <> TAtlasVcsKind.Svn) then
      begin
        TAtlasIdeVcsCore.Report(TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsWorkingCopiesNoVcs));
      end;
      FList := mList;
      FDialog.SetList(FList);
      FillNext(0);
    end) then
  begin
    TAtlasIdeVcsCore.Report(TAtlasVcsStrings.Text(TAtlasVcsTextId.VcsWorkingCopiesNoVcs));
  end;
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
  begin
    Inc(mIndex);
  end;
  if mIndex > High(FList.Rows) then
  begin
    Exit;
  end;
  mGeneration := FGeneration;
  mKeep := Self;
  // Eigene Kopie für den Hintergrund: Die Tabelle liest FList weiter.
  mWork := FList;
  mWork.Rows := Copy(FList.Rows);
  mRoot := FList.Root;
  mFolder := FList.Rows[mIndex].Folder;
  if not TAtlasIdeVcsCore.Run(
    procedure
    var
      mSvn: IAtlasVcsSvnWorkingCopy;
    begin
      if mWork.Kind = TAtlasVcsKind.Git then
      begin
        TAtlasVcsWorkingCopies.FillChanges(mWork, mIndex, TAtlasIdeVcsCore.ForFolder(mFolder,
          TAtlasIdeVcsCore.AtLeast(cLocalTimeoutMs)));
      end
      else
      begin
        if not Supports(TAtlasIdeVcsCore.ForFolder(mRoot, TAtlasIdeVcsCore.AtLeast(cLocalTimeoutMs)), IAtlasVcsSvnWorkingCopy,
          mSvn) then
        begin
          mSvn := nil;
        end;
        TAtlasVcsWorkingCopies.FillRevision(mWork, mIndex, mSvn);
      end;
    end,
    procedure
    begin
      if (mKeep = nil) or not Current(mGeneration) then
      begin
        Exit;
      end;
      FList.Rows[mIndex] := mWork.Rows[mIndex];
      FDialog.SetRow(mIndex, FList.Rows[mIndex]);
      FillNext(mIndex + 1);
    end) then
  begin
    Exit;
  end;
end;

procedure TAtlasIdeWorkingCopies.CheckServer(Sender: TObject);
begin
  if FList.Kind <> TAtlasVcsKind.Svn then
  begin
    Exit;
  end;
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
  begin
    Inc(mIndex);
  end;
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
  if not TAtlasIdeVcsCore.Run(
    procedure
    var
      mExternals: IAtlasVcsSvnExternals;
    begin
      if not Supports(TAtlasIdeVcsCore.ForFolder(mRoot, TAtlasIdeVcsCore.AtLeast(cServerTimeoutMs)), IAtlasVcsSvnExternals,
        mExternals) then
      begin
        mExternals := nil;
      end;
      TAtlasVcsWorkingCopies.CheckServer(mWork, mIndex, mExternals);
    end,
    procedure
    begin
      if (mKeep = nil) or not Current(mGeneration) then
      begin
        Exit;
      end;
      FList.Rows[mIndex] := mWork.Rows[mIndex];
      FDialog.SetChecking(mIndex, False);
      FDialog.SetRow(mIndex, FList.Rows[mIndex]);
      CheckNext(mIndex + 1);
    end) then
  begin
    FDialog.SetBusy(False);
  end;
end;

procedure TAtlasIdeWorkingCopies.AfterChange;
begin
  if Assigned(FDone) then
  begin
    FDone();
  end;
  if FOpen and (FDialog <> nil) then
  begin
    FDialog.SetBusy(False);
    // Neue Revisionen, ggf. neue Externals: neu lesen.
    Collect;
  end;
end;

/// <summary>Meldung nach dem Aktualisieren von AName.</summary>
function PullMessage(AOutcome: TAtlasPullOutcome; AReason: TAtlasVcsOutcome; const AName: string): string;
begin
  case AOutcome of
    TAtlasPullOutcome.Updated:
      Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsWorkingCopiesUpdated, [AName]);
    TAtlasPullOutcome.UpToDate:
      Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsWorkingCopiesUpToDate, [AName]);
    TAtlasPullOutcome.Blocked:
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgPullBlocked, [AName]);
  else
    if AReason = TAtlasVcsOutcome.LoginNeeded then
    begin
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgPullLogin, [AName]);
    end
    else
    begin
      Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsWorkingCopiesUpdateFailed, [AName, AtlasVcsOutcomeName(AReason)]);
    end;
  end;
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
  begin
    Exit;
  end;
  mKeep := Self;
  // Wurzel bzw. die eigene Arbeitskopie des Externals (der Ordner hat ein eigenes .svn).
  mFolder := FList.Rows[AIndex].Folder;
  mName := RowName(AIndex);
  mIgnore := AIgnoreExternals;
  mOutcome := TAtlasPullOutcome.Failed;
  mReason := TAtlasVcsOutcome.Failed;
  FDialog.SetBusy(True);
  if not TAtlasIdeVcsCore.Run(
    procedure
    begin
      mOutcome := TAtlasVcsPull.Pull(TAtlasIdeVcsCore.ForFolder(mFolder,
        TAtlasIdeVcsCore.AtLeast(cServerTimeoutMs)), mIgnore, mReason);
    end,
    procedure
    begin
      if mKeep = nil then
      begin
        Exit;
      end;
      TAtlasGuard.Log(Format('Arbeitskopien: aktualisiert (ohne Externals %s), %s',
        [BoolToStr(mIgnore, True), AtlasVcsOutcomeName(mReason)]));
      TAtlasIdeVcsCore.Report(PullMessage(mOutcome, mReason, mName));
      AfterChange;
    end) then
  begin
    FDialog.SetBusy(False);
  end;
end;

class function TAtlasIdeWorkingCopies.PinQuestion(const AList: TAtlasVcsWorkingCopyList; AIndex: Integer;
  const AName: string; out AText: string): Boolean;
var
  mOwner, mDefinition: string;
begin
  AText := '';
  Result := TAtlasVcsWorkingCopies.PinnedText(AList, AIndex, mOwner, mDefinition);
  if not Result then
  begin
    Exit;
  end;
  if mOwner = '' then
  begin
    mOwner := AName;
  end
  else
  begin
    mOwner := StringReplace(mOwner, '/', '\', [rfReplaceAll]);
  end;
  AText := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsWorkingCopiesPinConfirm, [AList.Rows[AIndex].Caption(AName),
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
  begin
    Exit;
  end;
  if MessageDlg(mQuestion, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
  begin
    Exit;
  end;
  mKeep := Self;
  mWork := FList;
  mWork.Rows := Copy(FList.Rows);
  mRoot := FList.Root;
  mName := RowName(AIndex);
  mRevision := FList.Rows[AIndex].Revision;
  mOutcome := TAtlasVcsOutcome.Failed;
  FDialog.SetBusy(True);
  if not TAtlasIdeVcsCore.Run(
    procedure
    var
      mExternals: IAtlasVcsSvnExternals;
    begin
      if not Supports(TAtlasIdeVcsCore.ForFolder(mRoot, TAtlasIdeVcsCore.AtLeast(cLocalTimeoutMs)), IAtlasVcsSvnExternals,
        mExternals) then
      begin
        mExternals := nil;
      end;
      mOutcome := TAtlasVcsWorkingCopies.Pin(mWork, AIndex, mExternals);
    end,
    procedure
    begin
      if mKeep = nil then
      begin
        Exit;
      end;
      TAtlasGuard.Log('Arbeitskopien: festschreiben, ' + AtlasVcsOutcomeName(mOutcome));
      if mOutcome = TAtlasVcsOutcome.Ok then
      begin
        TAtlasIdeVcsCore.Report(TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsWorkingCopiesPinned, [mName, mRevision]));
      end
      else
      begin
        TAtlasIdeVcsCore.Report(TAtlasVcsStrings.Fmt(TAtlasVcsTextId.VcsWorkingCopiesPinFailed, [mName,
          AtlasVcsOutcomeName(mOutcome)]));
      end;
      AfterChange;
    end) then
  begin
    FDialog.SetBusy(False);
  end;
end;

procedure TAtlasIdeWorkingCopies.OpenFolder(Sender: TObject; AIndex: Integer);
var
  mFolder: string;
begin
  if (AIndex < 0) or (AIndex > High(FList.Rows)) then
  begin
    Exit;
  end;
  mFolder := FList.Rows[AIndex].Folder;
  TAtlasGuard.Run(TAtlasFeature.Files,
    procedure
    begin
      if DirectoryExists(mFolder) then
      begin
        ShellExecute(0, 'open', PChar(mFolder), nil, nil, SW_SHOWNORMAL);
      end;
    end);
end;

end.
