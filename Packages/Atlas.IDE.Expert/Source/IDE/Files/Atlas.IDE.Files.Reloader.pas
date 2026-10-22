unit Atlas.IDE.Files.Reloader;

// Extern geänderte Dateien ohne Rückfrage neu laden (#536).
// Ein Timer (500 ms, läuft auch, wenn die IDE im Hintergrund ist) meldet die
// offenen Quelltexte an TAtlasExternalChanges. Ist ein Vorgang fertig, lädt
// Atlas Dateien ohne ungespeicherte Änderungen über IOTAModule.Refresh neu,
// bevor die IDE beim Zurückwechseln selbst vergleicht; Cursor und sichtbarer
// Bereich bleiben. Puffer mit eigenen Änderungen fasst Atlas nie an: Für sie
// bleibt die Rückfrage der IDE (mit „Alle Ja/Alle Nein“; sie lässt sich nicht
// unterdrücken); den Unterschied Editor/Platte schreibt Atlas vorher ins
// Meldungsfenster. Gelöschte Dateien meldet Atlas nur. Hat sich nur der Zeitstempel geändert
// (z. B. eigenes Speichern), bleibt der Puffer unberührt.
// Ergebnis im Meldungsfenster, Gruppe „Atlas“.
// Benachrichtigungszentrale (#601, Quelle reload): Jedes Ergebnis ist auch ein
// Eintrag („Dateien neu geladen: 3“, „Eigene Änderungen behalten: X“ mit
// „Vergleichen“, „Datei gelöscht: X“). Die Zeilen im Meldungsfenster samt
// Unterschied erscheinen nur bei „einblenden“; „Vergleichen“ schreibt den
// Unterschied auf Abruf dorthin und zeigt das Fenster.
// Die Platte liest TAtlasTextFile wie beim Speichern (Kodierung mit der
// Vorgabe aus atlas.json, Lesen teilt Löschen, Bericht M5): Ein gleichzeitiges
// atomares Ersetzen scheitert nicht an diesem Vergleich.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Files.ExternalChanges,
  Atlas.Core.Notifications.Contract;

type
  TAtlasFileReloader = class
  private
    FTimer: TTimer;
    FChanges: TAtlasExternalChanges;
    FBusy: Boolean;
    FReport: TProc<string>;
    FOnSaved: TProc<string>;
    procedure Tick(Sender: TObject);
    function OpenFiles: TArray<TAtlasObservedFile>;
    procedure Process(const ADecisions: TArray<TAtlasReloadDecision>);
    function Reload(const AFileName: string): Boolean;
    /// <summary>Unterschied Editor/Platte von AFileName ins Meldungsfenster; AShow zeigt das Fenster.</summary>
    class procedure ShowDiff(const AFileName: string; AShow: Boolean); static;
    /// <summary>Aktion „Vergleichen“ für AFileName (eigene Variable je Datei für die anonyme Methode).</summary>
    class function CompareAction(const AFileName: string): TAtlasNotificationAction; static;
    class function SourceEditorOf(const AModule: IOTAModule): IOTASourceEditor; static;
    class function FindModule(const AFileName: string): IOTAModule; static;
    class function DiskStamp(const AFileName: string; out AStamp: Int64): Boolean; static;
    class function SameAsDisk(const AEditor: IOTASourceEditor; const AFileName: string): Boolean; static;
    class procedure AddMessage(const AText: string); static;
  public
    /// <summary>AReport erhält je Vorgang eine Zeile fürs Protokoll (was neu geladen bzw. behalten wurde).</summary>
    constructor Create(const AReport: TProc<string>);
    destructor Destroy; override;
    /// <summary>Datei wurde gespeichert (neuer Zeitstempel, Inhalt wie im Puffer), z. B. für #548.</summary>
    property OnSaved: TProc<string> read FOnSaved write FOnSaved;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Winapi.Windows,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.Core.Files.TextDiff,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Files.EncodingDefault,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources;

/// <summary>Text der Datei auf der Platte in ihrer Kodierung; Ausnahme, wenn sie nicht lesbar ist.</summary>
function DiskText(const AFileName: string): string;
begin
  Result := TAtlasTextFile.Load(AFileName, TAtlasEncodingDefault.CodePageFor(AFileName)).Text;
end;

function NowMs: Int64;
begin
  Result := GetTickCount64;
end;

{ TAtlasFileReloader }

constructor TAtlasFileReloader.Create(const AReport: TProc<string>);
begin
  inherited Create;
  FReport := AReport;
  FChanges := TAtlasExternalChanges.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 500;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasFileReloader.Destroy;
begin
  FTimer.Enabled := False;
  FTimer.Free;
  FChanges.Free;
  inherited;
end;

class function TAtlasFileReloader.DiskStamp(const AFileName: string; out AStamp: Int64): Boolean;
var
  Data: TWin32FileAttributeData;
begin
  AStamp := 0;
  Result := GetFileAttributesEx(PChar(AFileName), GetFileExInfoStandard, @Data);
  if Result then
    AStamp := Int64(Data.ftLastWriteTime.dwHighDateTime) shl 32 or Data.ftLastWriteTime.dwLowDateTime;
end;

class function TAtlasFileReloader.SourceEditorOf(const AModule: IOTAModule): IOTASourceEditor;
var
  Index: Integer;
  Editor: IOTAEditor;
  First: IOTASourceEditor;
begin
  Result := nil;
  First := nil;
  for Index := 0 to AModule.ModuleFileCount - 1 do
  begin
    Editor := AModule.ModuleFileEditors[Index];
    if Supports(Editor, IOTASourceEditor, Result) then
    begin
      if SameText(Editor.FileName, AModule.FileName) then
        Exit;
      if First = nil then
        First := Result;
    end;
    Result := nil;
  end;
  // Projekte (.dproj): ihr Quelltext ist die .dpr bzw. .dpk.
  if Supports(AModule, IOTAProject) then
    Result := First;
end;

class function TAtlasFileReloader.FindModule(const AFileName: string): IOTAModule;
var
  Services: IOTAModuleServices;
  Index: Integer;
  Editor: IOTASourceEditor;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  // Über den Quelltexteditor: Die .dpr gehört zum Projektmodul (.dproj).
  for Index := 0 to Services.ModuleCount - 1 do
  begin
    Editor := SourceEditorOf(Services.Modules[Index]);
    if (Editor <> nil) and SameText(Editor.FileName, AFileName) then
      Exit(Services.Modules[Index]);
  end;
end;

function TAtlasFileReloader.OpenFiles: TArray<TAtlasObservedFile>;
var
  Services: IOTAModuleServices;
  Index: Integer;
  Module: IOTAModule;
  Editor: IOTASourceEditor;
  Stamp: Int64;
  Exists: Boolean;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  for Index := 0 to Services.ModuleCount - 1 do
  begin
    Module := Services.Modules[Index];
    // Nur Quelltexte im Editor; Projekte und Gruppen verwaltet die IDE selbst.
    Editor := SourceEditorOf(Module);
    if Editor = nil then
      Continue;
    Exists := DiskStamp(Editor.FileName, Stamp);
    Result := Result + [TAtlasObservedFile.Create(Editor.FileName, Exists, Stamp, Editor.Modified)];
  end;
end;

procedure TAtlasFileReloader.Tick(Sender: TObject);
begin
  // Beobachtet wird immer (Speichern erkennen, #548); neu geladen nur mit der Einstellung.
  if FBusy then
    Exit;
  FBusy := True;
  try
    try
      FChanges.Observe(OpenFiles, NowMs);
      if FChanges.Due(NowMs) then
        Process(FChanges.TakeBatch);
    except
      // Keine Exception an die IDE (#493); im nächsten Takt neu versuchen.
      on E: Exception do
        TAtlasGuard.Report(TAtlasFeature.Reloader, E);
    end;
  finally
    FBusy := False;
  end;
end;

class function TAtlasFileReloader.SameAsDisk(const AEditor: IOTASourceEditor; const AFileName: string): Boolean;
var
  Buffer: IOTAEditBuffer;
  Current, Disk: string;
begin
  Result := False;
  if not Supports(AEditor, IOTAEditBuffer, Buffer) then
    Exit;
  Current := TAtlasEditorBuffer.Text(Buffer).Replace(#13, '');
  try
    Disk := DiskText(AFileName).Replace(#13, '');
  except
    Exit;
  end;
  Result := Current = Disk;
end;

function TAtlasFileReloader.Reload(const AFileName: string): Boolean;
type
  TViewState = record
    Cursor: TOTAEditPos;
    TopRow: Integer;
    LeftColumn: Integer;
  end;
var
  Module: IOTAModule;
  Editor: IOTASourceEditor;
  States: TArray<TViewState>;
  View: IOTAEditView;
  Index: Integer;
begin
  Result := False;
  Module := FindModule(AFileName);
  if Module = nil then
    Exit;
  Editor := SourceEditorOf(Module);
  if (Editor = nil) or Editor.Modified then
    Exit;
  // Nur der Zeitstempel (eigenes Speichern, Touch): nichts neu laden, Rückgängig bleibt.
  if SameAsDisk(Editor, AFileName) then
  begin
    if Assigned(FOnSaved) then
      FOnSaved(AFileName);
    Exit;
  end;
  if not TAtlasIdeSettings.Current.ReloadExternal then
    Exit;
  SetLength(States, Editor.EditViewCount);
  for Index := 0 to High(States) do
  begin
    View := Editor.EditViews[Index];
    States[Index].Cursor := View.CursorPos;
    States[Index].TopRow := View.TopRow;
    States[Index].LeftColumn := View.LeftColumn;
  end;
  Module.Refresh(True);
  // Neu geladen ohne Editorereignis: gemeinsamen Pufferstand verwerfen (P-04).
  TAtlasEditorSnapshots.Invalidate(AFileName);
  Editor := SourceEditorOf(Module);
  if Editor <> nil then
    for Index := 0 to Editor.EditViewCount - 1 do
      if Index <= High(States) then
      begin
        View := Editor.EditViews[Index];
        View.SetTopLeft(States[Index].TopRow, States[Index].LeftColumn);
        View.CursorPos := States[Index].Cursor;
        View.Paint;
      end;
  Result := True;
end;

class procedure TAtlasFileReloader.ShowDiff(const AFileName: string; AShow: Boolean);
const
  MaxDiffLines = 40;
var
  Module: IOTAModule;
  Editor: IOTASourceEditor;
  Buffer: IOTAEditBuffer;
  Disk: string;
  Lines: TArray<string>;
  Index: Integer;
  Messages: IOTAMessageServices;
begin
  // Die Rückfrage der IDE lässt sich nicht unterdrücken (sie hat „Alle Ja/Alle Nein“); der
  // Unterschied steht im Meldungsfenster, damit man nachsehen kann.
  Module := FindModule(AFileName);
  Editor := nil;
  if Module <> nil then
    Editor := SourceEditorOf(Module);
  if not Supports(Editor, IOTAEditBuffer, Buffer) then
    Exit;
  try
    Disk := DiskText(AFileName);
  except
    on Exception do
      Exit;
  end;
  Lines := TAtlasTextDiff.Lines(TAtlasEditorBuffer.Text(Buffer), Disk);
  if Length(Lines) = 0 then
    Exit;
  AddMessage(TAtlasStrings.Fmt(TAtlasTextId.ReloadDiffTitle, [ExtractFileName(AFileName)]));
  for Index := 0 to High(Lines) do
    if Index < MaxDiffLines then
      AddMessage('    ' + Lines[Index]);
  if Length(Lines) > MaxDiffLines then
    AddMessage('    …');
  if AShow and Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Messages.ShowMessageView(Messages.GetGroup('Atlas'));
end;

class procedure TAtlasFileReloader.AddMessage(const AText: string);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Group := Messages.GetGroup('Atlas');
  if Group = nil then
    Group := Messages.AddMessageGroup('Atlas');
  Messages.AddTitleMessage(AText, Group);
end;

class function TAtlasFileReloader.CompareAction(const AFileName: string): TAtlasNotificationAction;
begin
  Result := TAtlasNotificationCenter.Action(TAtlasStrings.Text(TAtlasTextId.NotificationsCompare),
    procedure
    begin
      ShowDiff(AFileName, True);
    end);
end;

procedure TAtlasFileReloader.Process(const ADecisions: TArray<TAtlasReloadDecision>);
var
  Decision: TAtlasReloadDecision;
  Reloaded: TArray<string>;
  Name, FileName, Names: string;
  Activity: IInterface;
  Center: IAtlasNotificationCenter;
  Mode: TAtlasNotificationMode;
begin
  Activity := TAtlasActivity.Scope('Dateien neu laden');
  Center := TAtlasNotificationCenter.Default;
  Reloaded := nil;
  if Assigned(FReport) and TAtlasIdeSettings.Current.ReloadExternal then
    for Decision in ADecisions do
      FReport(Format('Extern geändert: %s (%s)', [Decision.FileName,
        TAtlasExternalChanges.ActionText(Decision.Action)]));
  for Decision in ADecisions do
    case Decision.Action of
      TAtlasReloadAction.Reload:
        if Reload(Decision.FileName) then
          Reloaded := Reloaded + [Decision.FileName];
      TAtlasReloadAction.KeepModified:
        if TAtlasIdeSettings.Current.ReloadExternal then
        begin
          FileName := Decision.FileName;
          Name := ExtractFileName(FileName);
          Mode := Center.Notify(TAtlasNotificationSources.Reload, TAtlasNotificationSeverity.Warning,
            TAtlasStrings.Fmt(TAtlasTextId.NotificationsReloadKept, [Name]),
            TAtlasStrings.Fmt(TAtlasTextId.NotificationsReloadKeptText, [Name]), [CompareAction(FileName)]);
          // Unterschied bei Dateien mit eigenen Änderungen (#536), nur bei „einblenden“.
          if Mode = TAtlasNotificationMode.Show then
          begin
            AddMessage(TAtlasStrings.Fmt(TAtlasTextId.ReloadKeptModified, [Name]));
            ShowDiff(FileName, False);
          end;
        end;
      TAtlasReloadAction.Deleted:
        if TAtlasIdeSettings.Current.ReloadExternal then
        begin
          Name := ExtractFileName(Decision.FileName);
          if Center.Notify(TAtlasNotificationSources.Reload, TAtlasNotificationSeverity.Warning,
            TAtlasStrings.Fmt(TAtlasTextId.NotificationsReloadDeleted, [Name]), Decision.FileName) =
            TAtlasNotificationMode.Show then
            AddMessage(TAtlasStrings.Fmt(TAtlasTextId.ReloadDeleted, [Name]));
        end;
    end;
  if Length(Reloaded) > 0 then
  begin
    Names := '';
    for Name in Reloaded do
    begin
      if Names <> '' then
        Names := Names + ', ';
      Names := Names + ExtractFileName(Name);
    end;
    if Center.Notify(TAtlasNotificationSources.Reload, TAtlasNotificationSeverity.Info,
      TAtlasStrings.Fmt(TAtlasTextId.NotificationsReloaded, [Length(Reloaded)]), Names) =
      TAtlasNotificationMode.Show then
    begin
      AddMessage(TAtlasStrings.Fmt(TAtlasTextId.ReloadDone, [Length(Reloaded)]));
      for Name in Reloaded do
        AddMessage('    ' + Name);
    end;
  end;
end;

end.