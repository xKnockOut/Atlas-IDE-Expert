unit Atlas.IDE.Editor.RegionFolds;

// Regionen ({$REGION} … {$ENDREGION}) beim Öffnen auf- oder zuklappen (#1814, editor.regionFolds) und die Befehle
// „Alle Regionen zuklappen“ / „Alle Regionen aufklappen“. Welche Regionen in welcher Reihenfolge, rechnet
// Atlas.Core.Editor.RegionFolds; hier bleiben Notifier, Zeitgeber und die Open Tools API.
// - Die ToolsAPI kennt nur „nächsten Block zu-/aufklappen“ an der Schreibmarke (IOTAElideActions an der
//   Editoransicht). Atlas setzt die Marke deshalb nacheinander auf die Kopfzeile jeder Region, klappt dort und
//   stellt Marke und sichtbaren Ausschnitt danach wieder her.
// - Beim Öffnen: Ein IDE-Notifier merkt sich jede frisch geöffnete Pascal-Datei (ofnFileOpened, auch beim Laden
//   des Desktops). Wird sie zum ersten Mal die aktive Ansicht, klappt Atlas nach einer kurzen Pause (die IDE
//   kennt die Faltbereiche erst nach dem Aufbau der Ansicht) nach editor.regionFolds. Die Region mit der
//   Schreibmarke bleibt offen. Spätere Wechsel zwischen Reitern lassen die Faltung, wie sie ist.
// - editor.regionFolds = off oder Atlas aus: nichts beim Öffnen, Befehle ausgeblendet und ohne Wirkung.
// Gesichert über TAtlasFeature.RegionFolds (#493). Nur im Hauptthread.

interface

uses
  System.Generics.Collections,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Editor.RegionFolds;

type
  TAtlasIdeRegionFolds = class
  private const
    /// <summary>Pause nach dem Wechsel der Ansicht, bis die IDE die Faltbereiche kennt.</summary>
    DelayMs = 400;
  private type
    TIdeNotifier = class(TNotifierObject, IOTAIDENotifier)
    private
      FOwner: TAtlasIdeRegionFolds;
    public
      procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
      procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
      procedure AfterCompile(Succeeded: Boolean); overload;
    end;
  private class var
    FInstance: TAtlasIdeRegionFolds;
  private
    FNotifier: TIdeNotifier;
    FNotifierRef: IOTAIDENotifier;
    FNotifierIndex: Integer;
    /// <summary>Geöffnete Dateien (klein geschrieben), deren erste Anzeige noch aussteht.</summary>
    FPending: TDictionary<string, Boolean>;
    FTimer: TTimer;
    procedure Opened(const AFileName: string);
    procedure TimerTick(Sender: TObject);
    procedure ApplyPending;
    class function Mode: TAtlasRegionFoldMode; static;
    /// <summary>Klappt in AView nach AMode; AKeepCursor: Regionen um die Marke bleiben offen (beim Öffnen),
    /// sonst wandert die Marke auf die Kopfzeile der äußersten zugeklappten Region um sie.</summary>
    class procedure Apply(const AView: IOTAEditView; AMode: TAtlasRegionFoldMode; AKeepCursor: Boolean); static;
    class procedure RunCommand(AMode: TAtlasRegionFoldMode); static;
  public
    constructor Create;
    destructor Destroy; override;
    class procedure Install; static;
    class procedure Uninstall; static;
    /// <summary>editor.regionFolds nicht off und Atlas an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Aus EditorViewActivated: eine frisch geöffnete Datei nach der Pause klappen.</summary>
    class procedure ViewActivated; static;
    /// <summary>Befehl Atlas.CollapseRegions.</summary>
    class procedure CollapseAll; static;
    /// <summary>Befehl Atlas.ExpandRegions.</summary>
    class procedure ExpandAll; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer;

{ TAtlasIdeRegionFolds.TIdeNotifier }

procedure TAtlasIdeRegionFolds.TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
var
  mOwner: TAtlasIdeRegionFolds;
  mName: string;
begin
  mOwner := FOwner;
  if (mOwner = nil) or (NotifyCode <> ofnFileOpened) or not TAtlasRegionFolds.IsPascal(FileName) then
  begin
    Exit;
  end;
  mName := FileName;
  // Keine Exception an die IDE (#493).
  TAtlasGuard.Run(TAtlasFeature.RegionFolds,
    procedure
    begin
      mOwner.Opened(mName);
    end);
end;

procedure TAtlasIdeRegionFolds.TIdeNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TAtlasIdeRegionFolds.TIdeNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

{ TAtlasIdeRegionFolds }

constructor TAtlasIdeRegionFolds.Create;
var
  mServices: IOTAServices;
begin
  inherited Create;
  FPending := TDictionary<string, Boolean>.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := DelayMs;
  FTimer.OnTimer := TimerTick;
  FNotifierIndex := -1;
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    FNotifier := TIdeNotifier.Create;
    FNotifier.FOwner := Self;
    FNotifierRef := FNotifier;
    FNotifierIndex := mServices.AddNotifier(FNotifierRef);
  end;
end;

destructor TAtlasIdeRegionFolds.Destroy;
var
  mServices: IOTAServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if FNotifier <> nil then
  begin
    FNotifier.FOwner := nil;
  end;
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    mServices.RemoveNotifier(FNotifierIndex);
  end;
  FNotifierRef := nil;
  FreeAndNil(FTimer);
  FreeAndNil(FPending);
  inherited;
end;

class procedure TAtlasIdeRegionFolds.Install;
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeRegionFolds.Create;
  end;
end;

class procedure TAtlasIdeRegionFolds.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeRegionFolds.Mode: TAtlasRegionFoldMode;
begin
  Result := TAtlasRegionFolds.ModeOf(TAtlasIdeSettings.Current.RegionFolds);
end;

class function TAtlasIdeRegionFolds.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and (TAtlasRegionFolds.ModeOf(mSettings.RegionFolds) <> TAtlasRegionFoldMode.Off);
end;

procedure TAtlasIdeRegionFolds.Opened(const AFileName: string);
begin
  if Enabled and (Mode in [TAtlasRegionFoldMode.Collapse, TAtlasRegionFoldMode.Expand]) then
  begin
    FPending.AddOrSetValue(LowerCase(AFileName), True);
    // Die geöffnete Datei ist meist gleich die aktive Ansicht.
    FTimer.Enabled := False;
    FTimer.Enabled := True;
  end;
end;

class procedure TAtlasIdeRegionFolds.ViewActivated;
begin
  if (FInstance <> nil) and (FInstance.FPending.Count > 0) then
  begin
    FInstance.FTimer.Enabled := False;
    FInstance.FTimer.Enabled := True;
  end;
end;

procedure TAtlasIdeRegionFolds.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  TAtlasGuard.Run(TAtlasFeature.RegionFolds, ApplyPending);
end;

procedure TAtlasIdeRegionFolds.ApplyPending;
var
  mView: IOTAEditView;
  mName: string;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  mName := LowerCase(mView.Buffer.FileName);
  if not FPending.ContainsKey(mName) then
  begin
    Exit;
  end;
  FPending.Remove(mName);
  if Enabled then
  begin
    Apply(mView, Mode, True);
  end;
end;

class procedure TAtlasIdeRegionFolds.Apply(const AView: IOTAEditView; AMode: TAtlasRegionFoldMode;
  AKeepCursor: Boolean);
var
  mElide: IOTAElideActions;
  mRegions: TArray<TAtlasRegion>;
  mCursor, mPos: TOTAEditPos;
  mLine, mKeep: Integer;
begin
  if not Supports(AView, IOTAElideActions, mElide) then
  begin
    Exit;
  end;
  mRegions := TAtlasRegionFolds.Find(TAtlasEditorBuffer.Text(AView.Buffer));
  mCursor := AView.CursorPos;
  mKeep := 0;
  if AKeepCursor then
  begin
    mKeep := mCursor.Line;
  end;
  for mLine in TAtlasRegionFolds.Order(mRegions, AMode, mKeep) do
  begin
    mPos.Col := 1;
    mPos.Line := mLine;
    AView.CursorPos := mPos;
    if AMode = TAtlasRegionFoldMode.Collapse then
    begin
      mElide.ElideNearestBlock;
    end
    else
    begin
      mElide.UnElideNearestBlock;
    end;
  end;
  if (AMode = TAtlasRegionFoldMode.Collapse) and not AKeepCursor then
  begin
    mPos.Col := 1;
    mPos.Line := TAtlasRegionFolds.VisibleLine(mRegions, mCursor.Line);
    if mPos.Line <> mCursor.Line then
    begin
      mCursor := mPos;
    end;
  end;
  AView.CursorPos := mCursor;
  AView.MoveViewToCursor;
end;

class procedure TAtlasIdeRegionFolds.RunCommand(AMode: TAtlasRegionFoldMode);
var
  mView: IOTAEditView;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  if Enabled and (mView <> nil) and (mView.Buffer <> nil) then
  begin
    Apply(mView, AMode, False);
  end;
end;

class procedure TAtlasIdeRegionFolds.CollapseAll;
begin
  RunCommand(TAtlasRegionFoldMode.Collapse);
end;

class procedure TAtlasIdeRegionFolds.ExpandAll;
begin
  RunCommand(TAtlasRegionFoldMode.Expand);
end;

end.
