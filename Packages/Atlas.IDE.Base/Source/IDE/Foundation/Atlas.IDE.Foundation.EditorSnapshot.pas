unit Atlas.IDE.Foundation.EditorSnapshot;

// Gemeinsamer Stand des Editorpuffers für Probleme und Inlay-Hints (P-04):
// Beide Zeitgeber fragten bisher je Takt den ganzen Puffer ab und verglichen
// den ganzen Text. Jetzt liest Get nur, wenn ein Ereignis (EditorViewModified,
// Wechsel des Editors, eigene Schreibvorgänge, Neuladen) den Stand als veraltet
// markiert hat, Zeilenzahl oder Änderungsstatus abweichen oder das
// Sicherheitsnetz (TAtlasSnapshotPolicy.cSafetyMs) abgelaufen ist. Version
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
    /// <summary>Ersetzt in ABuffer (Text AText) ab Zeichen AStart AOldLength Zeichen durch AInsert, ein
    /// Rückgängig-Schritt, und markiert die Datei als veraltet (eigener Schreibvorgang).</summary>
    class procedure ReplaceText(const ABuffer: IOTAEditBuffer; const AText: string; AStart, AOldLength: Integer;
      const AInsert: string); static;
    /// <summary>Meldet den Beobachter der Editorereignisse an.</summary>
    class procedure Install; static;
    /// <summary>Meldet ab und gibt die gemerkten Stände frei.</summary>
    class procedure Uninstall; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DockForm,
  Atlas.Core.Editor.SnapshotPolicy,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.Core.Diagnostics.Deadline;

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
  begin
    Entries := TDictionary<string, TEntry>.Create;
  end;
  Result := Entries;
end;

procedure InvalidateView(const AView: IOTAEditView);
begin
  if (AView <> nil) and (AView.Buffer <> nil) then
  begin
    TAtlasEditorSnapshots.Invalidate(AView.Buffer.FileName);
  end;
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
  mBuffer: IOTAEditBuffer;
  mKey, mText: string;
  mEntry: TEntry;
  mLines: Integer;
  mModified: Boolean;
  mStamp: UInt64;
begin
  mBuffer := AView.Buffer;
  Result.FileName := mBuffer.FileName;
  mKey := KeyOf(Result.FileName);
  if not EnsureEntries.TryGetValue(mKey, mEntry) then
  begin
    mEntry := Default(TEntry);
  end;
  mLines := mBuffer.GetLinesInBuffer;
  mModified := mBuffer.GetModified;
  mStamp := TAtlasTicks.Now;
  if TAtlasSnapshotPolicy.MustRead(mEntry.State, mLines, mModified, mStamp) then
  begin
    mText := TAtlasEditorBuffer.Text(mBuffer);
    if not mEntry.State.Known or (mText <> mEntry.Text) then
    begin
      mEntry.Text := mText;
      Inc(NextVersion);
      mEntry.Version := NextVersion;
    end;
    mEntry.State.Known := True;
    mEntry.State.Dirty := False;
    mEntry.State.Lines := mLines;
    mEntry.State.Modified := mModified;
    mEntry.State.ReadAt := mStamp;
    Entries.AddOrSetValue(mKey, mEntry);
  end;
  Result.Text := mEntry.Text;
  Result.Version := mEntry.Version;
end;

class procedure TAtlasEditorSnapshots.Invalidate(const AFileName: string);
var
  mKey: string;
  mEntry: TEntry;
begin
  if Entries = nil then
  begin
    Exit;
  end;
  mKey := KeyOf(AFileName);
  if Entries.TryGetValue(mKey, mEntry) then
  begin
    mEntry.State.Dirty := True;
    Entries[mKey] := mEntry;
  end;
end;

class procedure TAtlasEditorSnapshots.Invalidate;
var
  mKeys: TArray<string>;
  mKey: string;
  mEntry: TEntry;
begin
  if Entries = nil then
  begin
    Exit;
  end;
  mKeys := Entries.Keys.ToArray;
  for mKey in mKeys do
  begin
    mEntry := Entries[mKey];
    mEntry.State.Dirty := True;
    Entries[mKey] := mEntry;
  end;
end;

class procedure TAtlasEditorSnapshots.ReplaceText(const ABuffer: IOTAEditBuffer; const AText: string; AStart,
  AOldLength: Integer; const AInsert: string);
var
  mWriter: IOTAEditWriter;
begin
  mWriter := ABuffer.CreateUndoableWriter;
  mWriter.CopyTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, AStart)));
  mWriter.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, AStart + AOldLength)));
  if AInsert <> '' then
  begin
    mWriter.Insert(PAnsiChar(UTF8Encode(AInsert)));
  end;
  mWriter := nil;
  Invalidate(ABuffer.FileName);
end;

class procedure TAtlasEditorSnapshots.Install;
var
  mEditors: IOTAEditorServices;
begin
  if NotifierIndex >= 0 then
  begin
    Exit;
  end;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    NotifierIndex := mEditors.AddNotifier(TSnapshotNotifier.Create);
  end;
end;

class procedure TAtlasEditorSnapshots.Uninstall;
var
  mEditors: IOTAEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (NotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mEditors.RemoveNotifier(NotifierIndex);
  end;
  NotifierIndex := -1;
  FreeAndNil(Entries);
end;

end.
