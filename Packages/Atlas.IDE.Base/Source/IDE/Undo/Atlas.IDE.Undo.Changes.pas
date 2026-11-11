unit Atlas.IDE.Undo.Changes;

// Dateiübergreifendes Zurücknehmen von Atlas-Änderungen in der IDE (#721):
// hält das Änderungsprotokoll (TAtlasUndoJournal) mit dem Ziel der IDE
// (TAtlasIdeUndoTarget) und führt die Befehle aus.
// - Add: TAtlasIdeWorkspaceEdit meldet jede Änderung mehrerer Dateien.
// - UndoLast/RedoLast: „Letzte Atlas-Änderung zurücknehmen“ (Strg+Alt+Z) und
//   „… wiederherstellen“ (Strg+Alt+Umschalt+Z) aus Tastatur, Menü und Palette.
// - ShowList: Liste „Atlas-Änderungen“ im Ergebnisfenster (#400); dort
//   Unterschied, Zurücknehmen und Wiederherstellen auch älterer Sätze.
// - Ergebnis und Konflikte als Zeilen in der Meldungsansicht (OnMessage), nie
//   als Dialog; ins Plugin-Protokoll (OnLog) nur Kennung und Anzahlen.
// Einstellungen undo.multiFile* (ApplySettings): aus = nichts protokollieren;
// Sicherung in %LOCALAPPDATA%\Atlas\undo mit Größenbegrenzung; ohne
// Sicherung werden gesicherte Sätze gelöscht. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Undo.Contract,
  Atlas.Core.Undo.Journal;

type
  TAtlasIdeUndo = class
  private class var
    FJournal: TAtlasUndoJournal;
    FFolder: string;
    FPersist: Boolean;
    FMaxSizeMb: Integer;
    FOnMessage: TProc<string>;
    FOnLog: TProc<string>;
    FStoreFactory: TAtlasUndoStoreFactory;
  private
    class procedure Say(const ALines: TArray<string>); static;
    class procedure Report(const AReport: TAtlasUndoReport); static;
    class procedure Refresh; static;
  public
    /// <summary>Protokoll anlegen, Einstellungen übernehmen und gesicherte Sätze laden.</summary>
    class procedure Start(const AMessage, ALog: TProc<string>); static;
    /// <summary>Beim Entladen: Protokoll freigeben (gesicherte Sätze bleiben).</summary>
    class procedure Stop; static;
    /// <summary>undo.multiFile* aus den Einstellungen des Plugins übernehmen.</summary>
    class procedure ApplySettings; static;
    /// <summary>Aktion protokollieren (nur mit laufendem Protokoll); Kennung oder 0.</summary>
    class function Add(const AAction: string; const AFiles: TArray<TAtlasFileChange>): Integer; static;
    class procedure UndoLast; static;
    class procedure RedoLast; static;
    class procedure Undo(AId: Integer); static;
    class procedure Redo(AId: Integer); static;
    /// <summary>Liste „Atlas-Änderungen“ im Ergebnisfenster.</summary>
    class procedure ShowList; static;
    /// <summary>Unterschied eines Satzes (AFileName = '' für alle Dateien).</summary>
    class procedure ShowDiff(AId: Integer; const AFileName: string); static;
    /// <summary>%LOCALAPPDATA%\Atlas\undo.</summary>
    class function DefaultFolder: string; static;
    class property Journal: TAtlasUndoJournal read FJournal;
    /// <summary>Legt die Sicherung an; setzt die Kompositionswurzel (TAtlasUndoFileStore).</summary>
    class property StoreFactory: TAtlasUndoStoreFactory read FStoreFactory write FStoreFactory;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Undo.Names,
  Atlas.UI.Undo.Strings,
  Atlas.UI.Undo.Messages,
  Atlas.UI.Undo.DiffView,
  Atlas.UI.Results.Frame,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Undo.Target;

const
  cBytesPerMb = 1024 * 1024;

class function TAtlasIdeUndo.DefaultFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'undo');
end;

class procedure TAtlasIdeUndo.Start(const AMessage, ALog: TProc<string>);
begin
  if FJournal <> nil then
  begin
    Exit;
  end;
  FOnMessage := AMessage;
  FOnLog := ALog;
  FFolder := DefaultFolder;
  FJournal := TAtlasUndoJournal.Create(TAtlasIdeUndoTarget.Create);
  FJournal.OnLog :=
    procedure(AText: string)
    begin
      if Assigned(FOnLog) then
      begin
        FOnLog(AText);
      end;
    end;
  FJournal.OnChanged :=
    procedure
    begin
      Refresh;
    end;
  FPersist := False;
  ApplySettings;
  try
    FJournal.Load;
  except
    on E: Exception do
      if Assigned(FOnLog) then
      begin
        FOnLog('Atlas-Änderungsprotokoll nicht geladen: ' + E.ClassName);
      end;
  end;
end;

class procedure TAtlasIdeUndo.Stop;
begin
  FreeAndNil(FJournal);
  FOnMessage := nil;
  FOnLog := nil;
  TAtlasIdeResultsWindow.OnChangeUndo := nil;
  TAtlasIdeResultsWindow.OnChangeRedo := nil;
  TAtlasIdeResultsWindow.OnChangeDiff := nil;
end;

/// <summary>Gesicherte Änderungen im Profil löschen; ein Fehler steht nur im Protokoll.</summary>
procedure ClearStore(const AFactory: TAtlasUndoStoreFactory; const AFolder: string; const ALog: TProc<string>);
var
  mCleaner: IAtlasUndoStore;
begin
  if not Assigned(AFactory) then
  begin
    Exit;
  end;
  try
    mCleaner := AFactory(AFolder, 0);
    mCleaner.Clear;
  except
    on E: Exception do
      if Assigned(ALog) then
      begin
        ALog('Atlas-Änderungsprotokoll nicht gelöscht: ' + E.ClassName);
      end;
  end;
end;

class procedure TAtlasIdeUndo.ApplySettings;
var
  mSettings: TAtlasPluginSettings;
  mOptions: TAtlasUndoOptions;
  mPersist: Boolean;
begin
  if FJournal = nil then
  begin
    Exit;
  end;
  mSettings := TAtlasIdeSettings.Current;
  mOptions.Enabled := mSettings.UndoMultiFile;
  mOptions.Depth := mSettings.UndoMultiFileDepth;
  mOptions.OnConflict := TAtlasUndoNames.ParseConflictMode(mSettings.UndoMultiFileOnConflict);
  mOptions.NewFiles := TAtlasUndoNames.ParseNewFiles(mSettings.UndoMultiFileNewFiles);
  mPersist := mSettings.UndoMultiFile and mSettings.UndoMultiFilePersist;
  if (mPersist <> FPersist) or (mSettings.UndoMultiFileMaxSizeMb <> FMaxSizeMb) then
  begin
    FPersist := mPersist;
    FMaxSizeMb := mSettings.UndoMultiFileMaxSizeMb;
    if mPersist and Assigned(FStoreFactory) then
    begin
      FJournal.Store := FStoreFactory(FFolder, Int64(FMaxSizeMb) * cBytesPerMb);
    end
    else
    begin
      // Ohne Sicherung bleibt kein Quelltext im Profil liegen.
      ClearStore(FStoreFactory, FFolder, FOnLog);
      FJournal.Store := nil;
    end;
  end;
  FJournal.Options := mOptions;
  // Aus: Das Protokoll ist leer, die Aktionen schreiben wie bisher.
  if not mSettings.UndoMultiFile and (FJournal.Count > 0) then
  begin
    FJournal.Clear;
  end;
end;

class function TAtlasIdeUndo.Add(const AAction: string; const AFiles: TArray<TAtlasFileChange>): Integer;
begin
  Result := 0;
  if FJournal = nil then
  begin
    Exit;
  end;
  try
    Result := FJournal.Add(AAction, AFiles);
  except
    // Eine nicht schreibbare Sicherung darf die Aktion nicht scheitern lassen.
    on E: Exception do
      if Assigned(FOnLog) then
      begin
        FOnLog('Atlas-Änderung nicht gesichert: ' + E.ClassName);
      end;
  end;
end;

class procedure TAtlasIdeUndo.Say(const ALines: TArray<string>);
var
  mLine: string;
begin
  if Assigned(FOnMessage) then
  begin
    for mLine in ALines do
    begin
      FOnMessage(mLine);
    end;
  end;
end;

class procedure TAtlasIdeUndo.Report(const AReport: TAtlasUndoReport);
begin
  Say(TAtlasUndoMessages.Report(AReport));
end;

class procedure TAtlasIdeUndo.UndoLast;
begin
  if FJournal = nil then
  begin
    Exit;
  end;
  Report(FJournal.Undo);
end;

class procedure TAtlasIdeUndo.RedoLast;
begin
  if FJournal = nil then
  begin
    Exit;
  end;
  Report(FJournal.Redo);
end;

class procedure TAtlasIdeUndo.Undo(AId: Integer);
begin
  if FJournal = nil then
  begin
    Exit;
  end;
  Report(FJournal.Undo(AId));
end;

class procedure TAtlasIdeUndo.Redo(AId: Integer);
begin
  if FJournal = nil then
  begin
    Exit;
  end;
  Report(FJournal.Redo(AId));
end;

class procedure TAtlasIdeUndo.Refresh;
var
  mFrame: TAtlasResultsFrame;
begin
  // Nur eine schon sichtbare Liste aktualisieren; nie das Fenster deswegen öffnen.
  mFrame := TAtlasIdeResultsWindow.ExistingFrame;
  if (FJournal <> nil) and (mFrame <> nil) and mFrame.Changes.Shows then
  begin
    mFrame.Changes.Show(TAtlasUndoStrings.Fmt(TAtlasUndoTextId.UndoListTitle, [FJournal.Count]), FJournal.Sets, Now,
      True);
  end;
end;

class procedure TAtlasIdeUndo.ShowList;
begin
  if FJournal = nil then
  begin
    Exit;
  end;
  if not FJournal.Options.Enabled then
  begin
    Say([TAtlasUndoStrings.Text(TAtlasUndoTextId.UndoDisabled)]);
    Exit;
  end;
  TAtlasIdeResultsWindow.OnChangeUndo :=
    procedure(ASetId: Integer)
    begin
      Undo(ASetId);
    end;
  TAtlasIdeResultsWindow.OnChangeRedo :=
    procedure(ASetId: Integer)
    begin
      Redo(ASetId);
    end;
  TAtlasIdeResultsWindow.OnChangeDiff :=
    procedure(ASetId: Integer; const AFileName: string)
    begin
      ShowDiff(ASetId, AFileName);
    end;
  TAtlasIdeResultsWindow.ShowChanges(TAtlasUndoStrings.Fmt(TAtlasUndoTextId.UndoListTitle, [FJournal.Count]),
    FJournal.Sets);
end;

class procedure TAtlasIdeUndo.ShowDiff(AId: Integer; const AFileName: string);
var
  mChangeSet: TAtlasChangeSet;
begin
  if (FJournal = nil) or not FJournal.Find(AId, mChangeSet) then
  begin
    Exit;
  end;
  TAtlasUndoDiffView.Execute(TAtlasUndoStrings.Fmt(TAtlasUndoTextId.UndoDiffTitle, [mChangeSet.Action]),
    TAtlasUndoMessages.DiffLines(mChangeSet, AFileName));
end;

end.
