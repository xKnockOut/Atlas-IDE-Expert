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
  end;

implementation

uses
  System.IOUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Undo.Adapters.FileStore,
  Atlas.UI.Strings,
  Atlas.UI.Undo.Messages,
  Atlas.UI.Undo.DiffView,
  Atlas.UI.Results.Frame,
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Results.Window,
  Atlas.IDE.Undo.Target;

const
  BytesPerMb = 1024 * 1024;

class function TAtlasIdeUndo.DefaultFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'undo');
end;

class procedure TAtlasIdeUndo.Start(const AMessage, ALog: TProc<string>);
begin
  if FJournal <> nil then
    Exit;
  FOnMessage := AMessage;
  FOnLog := ALog;
  FFolder := DefaultFolder;
  FJournal := TAtlasUndoJournal.Create(TAtlasIdeUndoTarget.Create);
  FJournal.OnLog :=
    procedure(AText: string)
    begin
      if Assigned(FOnLog) then
        FOnLog(AText);
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
        FOnLog('Atlas-Änderungsprotokoll nicht geladen: ' + E.ClassName);
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

class procedure TAtlasIdeUndo.ApplySettings;
var
  Settings: TAtlasPluginSettings;
  Options: TAtlasUndoOptions;
  Persist: Boolean;
  Cleaner: IAtlasUndoStore;
begin
  if FJournal = nil then
    Exit;
  Settings := TAtlasIdeSettings.Current;
  Options.Enabled := Settings.UndoMultiFile;
  Options.Depth := Settings.UndoMultiFileDepth;
  Options.OnConflict := TAtlasUndoNames.ParseConflictMode(Settings.UndoMultiFileOnConflict);
  Options.NewFiles := TAtlasUndoNames.ParseNewFiles(Settings.UndoMultiFileNewFiles);
  Persist := Settings.UndoMultiFile and Settings.UndoMultiFilePersist;
  if (Persist <> FPersist) or (Settings.UndoMultiFileMaxSizeMb <> FMaxSizeMb) then
  begin
    FPersist := Persist;
    FMaxSizeMb := Settings.UndoMultiFileMaxSizeMb;
    if Persist then
      FJournal.Store := TAtlasUndoFileStore.Create(FFolder, Int64(FMaxSizeMb) * BytesPerMb)
    else
    begin
      // Ohne Sicherung bleibt kein Quelltext im Profil liegen.
      try
        Cleaner := TAtlasUndoFileStore.Create(FFolder, 0);
        Cleaner.Clear;
      except
        on E: Exception do
          if Assigned(FOnLog) then
            FOnLog('Atlas-Änderungsprotokoll nicht gelöscht: ' + E.ClassName);
      end;
      FJournal.Store := nil;
    end;
  end;
  FJournal.Options := Options;
  // Aus: Das Protokoll ist leer, die Aktionen schreiben wie bisher.
  if not Settings.UndoMultiFile and (FJournal.Count > 0) then
    FJournal.Clear;
end;

class function TAtlasIdeUndo.Add(const AAction: string; const AFiles: TArray<TAtlasFileChange>): Integer;
begin
  Result := 0;
  if FJournal = nil then
    Exit;
  try
    Result := FJournal.Add(AAction, AFiles);
  except
    // Eine nicht schreibbare Sicherung darf die Aktion nicht scheitern lassen.
    on E: Exception do
      if Assigned(FOnLog) then
        FOnLog('Atlas-Änderung nicht gesichert: ' + E.ClassName);
  end;
end;

class procedure TAtlasIdeUndo.Say(const ALines: TArray<string>);
var
  Line: string;
begin
  if Assigned(FOnMessage) then
    for Line in ALines do
      FOnMessage(Line);
end;

class procedure TAtlasIdeUndo.Report(const AReport: TAtlasUndoReport);
begin
  Say(TAtlasUndoMessages.Report(AReport));
end;

class procedure TAtlasIdeUndo.UndoLast;
begin
  if FJournal = nil then
    Exit;
  Report(FJournal.Undo);
end;

class procedure TAtlasIdeUndo.RedoLast;
begin
  if FJournal = nil then
    Exit;
  Report(FJournal.Redo);
end;

class procedure TAtlasIdeUndo.Undo(AId: Integer);
begin
  if FJournal = nil then
    Exit;
  Report(FJournal.Undo(AId));
end;

class procedure TAtlasIdeUndo.Redo(AId: Integer);
begin
  if FJournal = nil then
    Exit;
  Report(FJournal.Redo(AId));
end;

class procedure TAtlasIdeUndo.Refresh;
var
  Frame: TAtlasResultsFrame;
begin
  // Nur eine schon sichtbare Liste aktualisieren; nie das Fenster deswegen öffnen.
  Frame := TAtlasIdeResultsWindow.ExistingFrame;
  if (FJournal <> nil) and (Frame <> nil) and Frame.ShowsChanges then
    Frame.ShowChanges(TAtlasStrings.Fmt(TAtlasTextId.UndoListTitle, [FJournal.Count]), FJournal.Sets, Now, True);
end;

class procedure TAtlasIdeUndo.ShowList;
begin
  if FJournal = nil then
    Exit;
  if not FJournal.Options.Enabled then
  begin
    Say([TAtlasStrings.Text(TAtlasTextId.UndoDisabled)]);
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
  TAtlasIdeResultsWindow.ShowChanges(TAtlasStrings.Fmt(TAtlasTextId.UndoListTitle, [FJournal.Count]),
    FJournal.Sets);
end;

class procedure TAtlasIdeUndo.ShowDiff(AId: Integer; const AFileName: string);
var
  ChangeSet: TAtlasChangeSet;
begin
  if (FJournal = nil) or not FJournal.Find(AId, ChangeSet) then
    Exit;
  TAtlasUndoDiffView.Execute(TAtlasStrings.Fmt(TAtlasTextId.UndoDiffTitle, [ChangeSet.Action]),
    TAtlasUndoMessages.DiffLines(ChangeSet, AFileName));
end;

end.
