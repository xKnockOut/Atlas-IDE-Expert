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
  System.Math,
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
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
    FTimer.Free;
  end;
  FChanges.Free;
  inherited;
end;

class function TAtlasFileReloader.DiskStamp(const AFileName: string; out AStamp: Int64): Boolean;
var
  mData: TWin32FileAttributeData;
begin
  AStamp := 0;
  Result := GetFileAttributesEx(PChar(AFileName), GetFileExInfoStandard, @mData);
  if Result then
  begin
    AStamp := Int64(mData.ftLastWriteTime.dwHighDateTime) shl 32 or mData.ftLastWriteTime.dwLowDateTime;
  end;
end;

class function TAtlasFileReloader.SourceEditorOf(const AModule: IOTAModule): IOTASourceEditor;
var
  mIndex: Integer;
  mEditor: IOTAEditor;
  mFirst: IOTASourceEditor;
begin
  Result := nil;
  mFirst := nil;
  for mIndex := 0 to AModule.ModuleFileCount - 1 do
  begin
    mEditor := AModule.ModuleFileEditors[mIndex];
    if Supports(mEditor, IOTASourceEditor, Result) then
    begin
      if SameText(mEditor.FileName, AModule.FileName) then
      begin
        Exit;
      end;
      if mFirst = nil then
      begin
        mFirst := Result;
      end;
    end;
    Result := nil;
  end;
  // Projekte (.dproj): ihr Quelltext ist die .dpr bzw. .dpk.
  if Supports(AModule, IOTAProject) then
  begin
    Result := mFirst;
  end;
end;

class function TAtlasFileReloader.FindModule(const AFileName: string): IOTAModule;
var
  mServices: IOTAModuleServices;
  mIndex: Integer;
  mEditor: IOTASourceEditor;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  // Über den Quelltexteditor: Die .dpr gehört zum Projektmodul (.dproj).
  for mIndex := 0 to mServices.ModuleCount - 1 do
  begin
    mEditor := SourceEditorOf(mServices.Modules[mIndex]);
    if (mEditor <> nil) and SameText(mEditor.FileName, AFileName) then
    begin
      Exit(mServices.Modules[mIndex]);
    end;
  end;
end;

function TAtlasFileReloader.OpenFiles: TArray<TAtlasObservedFile>;
var
  mServices: IOTAModuleServices;
  mIndex: Integer;
  mModule: IOTAModule;
  mEditor: IOTASourceEditor;
  mStamp: Int64;
  mExists: Boolean;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ModuleCount - 1 do
  begin
    mModule := mServices.Modules[mIndex];
    // Nur Quelltexte im Editor; Projekte und Gruppen verwaltet die IDE selbst.
    mEditor := SourceEditorOf(mModule);
    if mEditor = nil then
    begin
      Continue;
    end;
    mExists := DiskStamp(mEditor.FileName, mStamp);
    Result := Result + [TAtlasObservedFile.Create(mEditor.FileName, mExists, mStamp, mEditor.Modified)];
  end;
end;

procedure TAtlasFileReloader.Tick(Sender: TObject);
begin
  // Beobachtet wird immer (Speichern erkennen, #548); neu geladen nur mit der Einstellung.
  if FBusy then
  begin
    Exit;
  end;
  FBusy := True;
  try
    try
      FChanges.Observe(OpenFiles, NowMs);
      if FChanges.Due(NowMs) then
      begin
        Process(FChanges.TakeBatch);
      end;
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
  mBuffer: IOTAEditBuffer;
  mCurrent, mDisk: string;
begin
  Result := False;
  if not Supports(AEditor, IOTAEditBuffer, mBuffer) then
  begin
    Exit;
  end;
  mCurrent := TAtlasEditorBuffer.Text(mBuffer).Replace(#13, '');
  try
    mDisk := DiskText(AFileName).Replace(#13, '');
  except
    Exit;
  end;
  Result := mCurrent = mDisk;
end;

type
  /// <summary>Stand einer Editoransicht vor dem Neuladen.</summary>
  TViewState = record
    Cursor: TOTAEditPos;
    TopRow: Integer;
    LeftColumn: Integer;
  end;

function SaveViews(const AEditor: IOTASourceEditor): TArray<TViewState>;
var
  mView: IOTAEditView;
  mIndex: Integer;
begin
  SetLength(Result, AEditor.EditViewCount);
  for mIndex := 0 to High(Result) do
  begin
    mView := AEditor.EditViews[mIndex];
    Result[mIndex].Cursor := mView.CursorPos;
    Result[mIndex].TopRow := mView.TopRow;
    Result[mIndex].LeftColumn := mView.LeftColumn;
  end;
end;

procedure RestoreViews(const AEditor: IOTASourceEditor; const AStates: TArray<TViewState>);
var
  mView: IOTAEditView;
  mIndex: Integer;
begin
  if AEditor = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to Min(AEditor.EditViewCount - 1, High(AStates)) do
  begin
    mView := AEditor.EditViews[mIndex];
    mView.SetTopLeft(AStates[mIndex].TopRow, AStates[mIndex].LeftColumn);
    mView.CursorPos := AStates[mIndex].Cursor;
    mView.Paint;
  end;
end;

function TAtlasFileReloader.Reload(const AFileName: string): Boolean;
var
  mModule: IOTAModule;
  mEditor: IOTASourceEditor;
  mStates: TArray<TViewState>;
begin
  Result := False;
  mModule := FindModule(AFileName);
  if mModule = nil then
  begin
    Exit;
  end;
  mEditor := SourceEditorOf(mModule);
  if (mEditor = nil) or mEditor.Modified then
  begin
    Exit;
  end;
  // Nur der Zeitstempel (eigenes Speichern, Touch): nichts neu laden, Rückgängig bleibt.
  if SameAsDisk(mEditor, AFileName) then
  begin
    if Assigned(FOnSaved) then
    begin
      FOnSaved(AFileName);
    end;
    Exit;
  end;
  if not TAtlasIdeSettings.Current.ReloadExternal then
  begin
    Exit;
  end;
  mStates := SaveViews(mEditor);
  mModule.Refresh(True);
  // Neu geladen ohne Editorereignis: gemeinsamen Pufferstand verwerfen (P-04).
  TAtlasEditorSnapshots.Invalidate(AFileName);
  RestoreViews(SourceEditorOf(mModule), mStates);
  Result := True;
end;

class procedure TAtlasFileReloader.ShowDiff(const AFileName: string; AShow: Boolean);
const
  cMaxDiffLines = 40;
var
  mModule: IOTAModule;
  mEditor: IOTASourceEditor;
  mBuffer: IOTAEditBuffer;
  mDisk: string;
  mLines: TArray<string>;
  mIndex: Integer;
  mMessages: IOTAMessageServices;
begin
  // Die Rückfrage der IDE lässt sich nicht unterdrücken (sie hat „Alle Ja/Alle Nein“); der
  // Unterschied steht im Meldungsfenster, damit man nachsehen kann.
  mModule := FindModule(AFileName);
  mEditor := nil;
  if mModule <> nil then
  begin
    mEditor := SourceEditorOf(mModule);
  end;
  if not Supports(mEditor, IOTAEditBuffer, mBuffer) then
  begin
    Exit;
  end;
  try
    mDisk := DiskText(AFileName);
  except
    on Exception do
      Exit;
  end;
  mLines := TAtlasTextDiff.Lines(TAtlasEditorBuffer.Text(mBuffer), mDisk);
  if Length(mLines) = 0 then
  begin
    Exit;
  end;
  AddMessage(TAtlasStrings.Fmt(TAtlasTextId.ReloadDiffTitle, [ExtractFileName(AFileName)]));
  for mIndex := 0 to High(mLines) do
  begin
    if mIndex < cMaxDiffLines then
    begin
      AddMessage('    ' + mLines[mIndex]);
    end;
  end;
  if Length(mLines) > cMaxDiffLines then
  begin
    AddMessage('    …');
  end;
  if AShow and Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    mMessages.ShowMessageView(mMessages.GetGroup('Atlas'));
  end;
end;

class procedure TAtlasFileReloader.AddMessage(const AText: string);
var
  mMessages: IOTAMessageServices;
  mGroup: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mGroup := mMessages.GetGroup('Atlas');
  if mGroup = nil then
  begin
    mGroup := mMessages.AddMessageGroup('Atlas');
  end;
  mMessages.AddTitleMessage(AText, mGroup);
end;

class function TAtlasFileReloader.CompareAction(const AFileName: string): TAtlasNotificationAction;
begin
  Result := TAtlasNotificationCenter.Action(TAtlasStrings.Text(TAtlasTextId.NotificationsCompare),
    procedure
    begin
      ShowDiff(AFileName, True);
    end);
end;

/// <summary>Eigene Änderungen behalten: Hinweis mit „Vergleichen“, bei „einblenden“ der Unterschied (#536).</summary>
procedure NotifyKept(const ACenter: IAtlasNotificationCenter; const AFileName: string);
var
  mName: string;
begin
  mName := ExtractFileName(AFileName);
  if ACenter.Notify(TAtlasNotificationSources.cReload, TAtlasNotificationSeverity.Warning,
    TAtlasStrings.Fmt(TAtlasTextId.NotificationsReloadKept, [mName]),
    TAtlasStrings.Fmt(TAtlasTextId.NotificationsReloadKeptText, [mName]),
    [TAtlasFileReloader.CompareAction(AFileName)]) = TAtlasNotificationMode.Show then
  begin
    TAtlasFileReloader.AddMessage(TAtlasStrings.Fmt(TAtlasTextId.ReloadKeptModified, [mName]));
    TAtlasFileReloader.ShowDiff(AFileName, False);
  end;
end;

procedure NotifyDeleted(const ACenter: IAtlasNotificationCenter; const AFileName: string);
var
  mName: string;
begin
  mName := ExtractFileName(AFileName);
  if ACenter.Notify(TAtlasNotificationSources.cReload, TAtlasNotificationSeverity.Warning,
    TAtlasStrings.Fmt(TAtlasTextId.NotificationsReloadDeleted, [mName]), AFileName) =
    TAtlasNotificationMode.Show then
  begin
    TAtlasFileReloader.AddMessage(TAtlasStrings.Fmt(TAtlasTextId.ReloadDeleted, [mName]));
  end;
end;

/// <summary>Ein Hinweis für alle neu geladenen Dateien; bei „einblenden“ auch im Meldungsfenster.</summary>
procedure NotifyReloaded(const ACenter: IAtlasNotificationCenter; const AReloaded: TArray<string>);
var
  mName, mNames: string;
begin
  mNames := '';
  for mName in AReloaded do
  begin
    if mNames <> '' then
    begin
      mNames := mNames + ', ';
    end;
    mNames := mNames + ExtractFileName(mName);
  end;
  if ACenter.Notify(TAtlasNotificationSources.cReload, TAtlasNotificationSeverity.Info,
    TAtlasStrings.Fmt(TAtlasTextId.NotificationsReloaded, [Length(AReloaded)]), mNames) =
    TAtlasNotificationMode.Show then
  begin
    TAtlasFileReloader.AddMessage(TAtlasStrings.Fmt(TAtlasTextId.ReloadDone, [Length(AReloaded)]));
    for mName in AReloaded do
    begin
      TAtlasFileReloader.AddMessage('    ' + mName);
    end;
  end;
end;

procedure TAtlasFileReloader.Process(const ADecisions: TArray<TAtlasReloadDecision>);
var
  mDecision: TAtlasReloadDecision;
  mReloaded: TArray<string>;
  mActivity: IInterface;
  mCenter: IAtlasNotificationCenter;
  mActive: Boolean;
begin
  mActivity := TAtlasActivity.Scope('Dateien neu laden');
  mCenter := TAtlasNotificationCenter.Default;
  mReloaded := nil;
  mActive := TAtlasIdeSettings.Current.ReloadExternal;
  for mDecision in ADecisions do
  begin
    if Assigned(FReport) and mActive then
    begin
      FReport(Format('Extern geändert: %s (%s)', [mDecision.FileName,
        TAtlasExternalChanges.ActionText(mDecision.Action)]));
    end;
  end;
  for mDecision in ADecisions do
  begin
    if mDecision.Action = TAtlasReloadAction.Reload then
    begin
      if Reload(mDecision.FileName) then
      begin
        mReloaded := mReloaded + [mDecision.FileName];
      end;
    end
    else if mActive and (mDecision.Action = TAtlasReloadAction.KeepModified) then
    begin
      NotifyKept(mCenter, mDecision.FileName);
    end
    else if mActive and (mDecision.Action = TAtlasReloadAction.Deleted) then
    begin
      NotifyDeleted(mCenter, mDecision.FileName);
    end;
  end;
  if Length(mReloaded) > 0 then
  begin
    NotifyReloaded(mCenter, mReloaded);
  end;
end;

end.