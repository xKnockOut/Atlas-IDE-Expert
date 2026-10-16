unit Atlas.IDE.Foundation.EditorSnapshot;

// Gemeinsamer Stand des Editorpuffers für Probleme und Inlay-Hints (P-04):
// Beide Zeitgeber fragten bisher je Takt den ganzen Puffer ab und verglichen
// den ganzen Text. Jetzt liest Get nur, wenn ein Ereignis (EditorViewModified,
// Wechsel des Editors, eigene Schreibvorgänge, Neuladen) den Stand als veraltet
// markiert hat, Zeilenzahl oder Änderungsstatus abweichen oder das
// Sicherheitsnetz (TAtlasSnapshotPolicy.SafetyMs) abgelaufen ist. Version
// steigt nur, wenn der neu gelesene Text abweicht; Verbraucher vergleichen
// die Version statt des Textes.

interface

uses
  ToolsAPI;

type
  TAtlasEditorSnapshot = record
    FileName: string;
    Text: string;
    /// <summary>Steigt bei jedem neu gelesenen, abweichenden Text (über alle Dateien eindeutig).</summary>
    Version: Cardinal;
  end;

  TAtlasEditorSnapshots = class
  public
    /// <summary>Stand der Datei von AView; liest den Puffer nur, wenn er als veraltet gilt.</summary>
    class function Get(const AView: IOTAEditView): TAtlasEditorSnapshot; static;
    /// <summary>Markiert AFileName als veraltet.</summary>
    class procedure Invalidate(const AFileName: string); overload; static;
    /// <summary>Markiert alle Dateien als veraltet.</summary>
    class procedure Invalidate; overload; static;
    /// <summary>Meldet den Beobachter der Editorereignisse an.</summary>
    class procedure Install; static;
    /// <summary>Meldet ab und gibt die gemerkten Stände frei.</summary>
    class procedure Uninstall; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DockForm,
  Atlas.Core.Editor.SnapshotPolicy,
  Atlas.IDE.Foundation.EditorBuffer;

type
  TEntry = record
    State: TAtlasSnapshotState;
    Text: string;
    Version: Cardinal;
  end;

  TSnapshotNotifier = class(TNotifierObject, INTAEditServicesNotifier)
  public
    procedure WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
    procedure WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
    procedure WindowActivated(const EditWindow: INTAEditWindow);
    procedure WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer; var Handled: Boolean);
    procedure EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
    procedure EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
    procedure DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    procedure DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    procedure DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
  end;

var
  // Nur im Hauptthread benutzt (Zeitgeber, Editorereignisse).
  Entries: TDictionary<string, TEntry>;
  NextVersion: Cardinal;
  NotifierIndex: Integer = -1;

function KeyOf(const AFileName: string): string;
begin
  Result := AnsiUpperCase(AFileName);
end;

function EnsureEntries: TDictionary<string, TEntry>;
begin
  if Entries = nil then
    Entries := TDictionary<string, TEntry>.Create;
  Result := Entries;
end;

procedure InvalidateView(const AView: IOTAEditView);
begin
  if (AView <> nil) and (AView.Buffer <> nil) then
    TAtlasEditorSnapshots.Invalidate(AView.Buffer.FileName);
end;

{ TSnapshotNotifier }

procedure TSnapshotNotifier.WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
begin
end;

procedure TSnapshotNotifier.WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
begin
end;

procedure TSnapshotNotifier.WindowActivated(const EditWindow: INTAEditWindow);
begin
  // Unbekannt, welche Datei: alle neu prüfen.
  TAtlasEditorSnapshots.Invalidate;
end;

procedure TSnapshotNotifier.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer;
  var Handled: Boolean);
begin
end;

procedure TSnapshotNotifier.EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  InvalidateView(EditView);
end;

procedure TSnapshotNotifier.EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  InvalidateView(EditView);
end;

procedure TSnapshotNotifier.DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TSnapshotNotifier.DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TSnapshotNotifier.DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

{ TAtlasEditorSnapshots }

class function TAtlasEditorSnapshots.Get(const AView: IOTAEditView): TAtlasEditorSnapshot;
var
  Buffer: IOTAEditBuffer;
  Key, Text: string;
  Entry: TEntry;
  Lines: Integer;
  Modified: Boolean;
  Stamp: Cardinal;
begin
  Buffer := AView.Buffer;
  Result.FileName := Buffer.FileName;
  Key := KeyOf(Result.FileName);
  if not EnsureEntries.TryGetValue(Key, Entry) then
    Entry := Default(TEntry);
  Lines := Buffer.GetLinesInBuffer;
  Modified := Buffer.GetModified;
  Stamp := GetTickCount;
  if TAtlasSnapshotPolicy.MustRead(Entry.State, Lines, Modified, Stamp) then
  begin
    Text := TAtlasEditorBuffer.Text(Buffer);
    if not Entry.State.Known or (Text <> Entry.Text) then
    begin
      Entry.Text := Text;
      Inc(NextVersion);
      Entry.Version := NextVersion;
    end;
    Entry.State.Known := True;
    Entry.State.Dirty := False;
    Entry.State.Lines := Lines;
    Entry.State.Modified := Modified;
    Entry.State.ReadAt := Stamp;
    Entries.AddOrSetValue(Key, Entry);
  end;
  Result.Text := Entry.Text;
  Result.Version := Entry.Version;
end;

class procedure TAtlasEditorSnapshots.Invalidate(const AFileName: string);
var
  Key: string;
  Entry: TEntry;
begin
  if Entries = nil then
    Exit;
  Key := KeyOf(AFileName);
  if Entries.TryGetValue(Key, Entry) then
  begin
    Entry.State.Dirty := True;
    Entries[Key] := Entry;
  end;
end;

class procedure TAtlasEditorSnapshots.Invalidate;
var
  Keys: TArray<string>;
  Key: string;
  Entry: TEntry;
begin
  if Entries = nil then
    Exit;
  Keys := Entries.Keys.ToArray;
  for Key in Keys do
  begin
    Entry := Entries[Key];
    Entry.State.Dirty := True;
    Entries[Key] := Entry;
  end;
end;

class procedure TAtlasEditorSnapshots.Install;
var
  Editors: IOTAEditorServices;
begin
  if NotifierIndex >= 0 then
    Exit;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    NotifierIndex := Editors.AddNotifier(TSnapshotNotifier.Create);
end;

class procedure TAtlasEditorSnapshots.Uninstall;
var
  Editors: IOTAEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (NotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Editors.RemoveNotifier(NotifierIndex);
  NotifierIndex := -1;
  FreeAndNil(Entries);
end;

end.
