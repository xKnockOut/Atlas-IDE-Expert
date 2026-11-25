unit Atlas.IDE.Assistants.LogWindow;

// Andockbares Fenster „Atlas-KI-Protokoll“ (#2049): verankerbar über TAtlasIdeDockWindow, Inhalt
// TAtlasAssistantsLogFrame, IDE-Thema, Atlas-Symbol im Titel. Das Protokoll (TAtlasAssistantsLog) gehört der
// Composition; TAtlasIdeAssistantsLogView verdrahtet den Frame damit, solange assistants.log an ist:
// - nach jeder Änderung des Protokolls (Version, alle 500 ms geprüft) neu füllen,
// - Doppelklick springt an die erste geänderte Zeile, „Unterschied“ zeigt alt und neu, „Alle dieser Sitzung“ den
//   Unterschied aller Änderungen,
// - „Zurücknehmen“ ersetzt genau den geänderten Block wieder durch den alten Text, als ein Rückgängig-Schritt, nur wenn
//   er dort noch unverändert steht (Plan in TAtlasAssistantsLog.RevertPlan); sonst ist der Knopf gesperrt und sagt
//   warum. War der Puffer vorher gespeichert, wird danach gespeichert (wie der Bearbeitungseingang).
// Prepare meldet das Fenster früh bei der IDE an (Desktop speichert und stellt es wieder her), Release beim Abmelden
// des Moduls: Danach erreicht nichts mehr das Modul (ADR 0017, Regel 3).

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Plugin.Files.Contract,
  Atlas.Core.Assistants.Log,
  Atlas.UI.Assistants.LogFrame;

type
  TAtlasIdeAssistantsLogWindow = class
  public class var
    /// <summary>Ein neuer Frame ist entstanden; setzt TAtlasIdeAssistantsLogView.</summary>
    OnFrame: TProc<TAtlasAssistantsLogFrame>;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Show: TAtlasAssistantsLogFrame; static;
    /// <summary>Frame, falls das Fenster existiert; legt nichts an.</summary>
    class function ExistingFrame: TAtlasAssistantsLogFrame; static;
    class procedure Hide; static;
    class procedure ApplyTheme; static;
    /// <summary>Früh (Register): bei der IDE anmelden, damit der Desktop das Fenster speichert und wiederherstellt.
    /// </summary>
    class procedure Prepare; static;
    class procedure Release; static;
  end;

  TAtlasIdeAssistantsLogView = class
  public const
    cTickMs = 500;
  private
    FLog: TAtlasAssistantsLog;
    FFiles: IAtlasEditorFiles;
    FTimer: TTimer;
    FShownVersion: Integer;
    FOnMessage: TProc<string>;
    procedure Tick(Sender: TObject);
    procedure Wire(AFrame: TAtlasAssistantsLogFrame);
    procedure Fill(AFrame: TAtlasAssistantsLogFrame);
    procedure Open(const AEntry: TAtlasAssistantsLogEntry);
    procedure Diff(const AEntry: TAtlasAssistantsLogEntry);
    procedure Selected(const AEntry: TAtlasAssistantsLogEntry);
    procedure SessionDiff;
    procedure ClearLog;
    function CurrentText(const AFileName: string; out ABuffer: TAtlasEditorFile): Boolean;
  public
    /// <summary>ALog gehört der Composition und lebt länger; AFiles: offene Dateien der IDE; AOnMessage: Zeile für
    /// die Meldungsansicht.</summary>
    constructor Create(ALog: TAtlasAssistantsLog; const AFiles: IAtlasEditorFiles; const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Fenster zeigen und füllen.</summary>
    procedure ShowWindow;
    /// <summary>„Zurücknehmen“ für AEntry; False, wenn es nicht ging (Grund steht dann im Fenster).</summary>
    function Revert(const AEntry: TAtlasAssistantsLogEntry): Boolean;
  end;

implementation

uses
  System.Classes,
  System.IniFiles,
  Vcl.Forms,
  Vcl.ActnList,
  Vcl.ImgList,
  Vcl.Menus,
  Vcl.ComCtrls,
  DesignIntf,
  ToolsAPI,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Assistants.EditPlan,
  Atlas.ToolsApi.Windows.DockWindow,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Assistants.LogEntries,
  Atlas.UI.Undo.DiffView,
  Atlas.UI.Assistants.Strings;

type
  TLogDock = class(TInterfacedObject, INTACustomDockableForm)
  public
    function GetCaption: string;
    function GetIdentifier: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    function GetMenuActionList: TCustomActionList;
    function GetMenuImageList: TCustomImageList;
    procedure CustomizePopupMenu(PopupMenu: TPopupMenu);
    function GetToolbarActionList: TCustomActionList;
    function GetToolbarImageList: TCustomImageList;
    procedure CustomizeToolBar(ToolBar: TToolBar);
    procedure SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
    procedure LoadWindowState(Desktop: TCustomIniFile; const Section: string);
    function GetEditState: TEditState;
    function EditAction(Action: TEditAction): Boolean;
  end;

var
  // Verwaltet Form, Frame und Anmeldung bei der IDE.
  Host: TAtlasIdeDockWindow;

{ TLogDock }

function TLogDock.GetCaption: string;
begin
  Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LogCaption);
end;

function TLogDock.GetIdentifier: string;
begin
  Result := 'AtlasAssistantsLog';
end;

function TLogDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasAssistantsLogFrame;
end;

procedure TLogDock.FrameCreated(AFrame: TCustomFrame);
begin
  if not (AFrame is TAtlasAssistantsLogFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
  TAtlasIdeDockWindow.ApplyIdeTheme(AFrame);
  if Assigned(TAtlasIdeAssistantsLogWindow.OnFrame) then
  begin
    TAtlasIdeAssistantsLogWindow.OnFrame(TAtlasAssistantsLogFrame(AFrame));
  end;
end;

function TLogDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TLogDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TLogDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TLogDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TLogDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TLogDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TLogDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TLogDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TLogDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TLogDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure EnsureHost;
begin
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TLogDock.Create, True);
  end;
end;

{ TAtlasIdeAssistantsLogWindow }

class function TAtlasIdeAssistantsLogWindow.Show: TAtlasAssistantsLogFrame;
begin
  EnsureHost;
  Host.Present;
  Result := ExistingFrame;
end;

class function TAtlasIdeAssistantsLogWindow.ExistingFrame: TAtlasAssistantsLogFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasAssistantsLogFrame) then
  begin
    Result := TAtlasAssistantsLogFrame(Host.Frame);
  end;
end;

class procedure TAtlasIdeAssistantsLogWindow.Hide;
begin
  TAtlasIdeDockWindow.HideIfAny(Host);
end;

class procedure TAtlasIdeAssistantsLogWindow.ApplyTheme;
var
  mFrame: TAtlasAssistantsLogFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    TAtlasIdeDockWindow.ApplyIdeTheme(mFrame);
  end;
  TAtlasIdeDockWindow.UpdateIcon(Host);
end;

class procedure TAtlasIdeAssistantsLogWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeAssistantsLogWindow.Release;
begin
  OnFrame := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

{ TAtlasIdeAssistantsLogView }

constructor TAtlasIdeAssistantsLogView.Create(ALog: TAtlasAssistantsLog; const AFiles: IAtlasEditorFiles;
  const AOnMessage: TProc<string>);
var
  mFrame: TAtlasAssistantsLogFrame;
begin
  inherited Create;
  FLog := ALog;
  FFiles := AFiles;
  FOnMessage := AOnMessage;
  FShownVersion := -1;
  TAtlasIdeAssistantsLogWindow.OnFrame :=
    procedure(AFrame: TAtlasAssistantsLogFrame)
    begin
      Wire(AFrame);
      Fill(AFrame);
    end;
  // Vom Desktop wiederhergestellt: gleich verdrahten.
  mFrame := TAtlasIdeAssistantsLogWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    Wire(mFrame);
    Fill(mFrame);
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeAssistantsLogView.Destroy;
var
  mFrame: TAtlasAssistantsLogFrame;
begin
  FTimer.Free;
  TAtlasIdeAssistantsLogWindow.OnFrame := nil;
  // Regel 3: Der Frame hält Rückrufe in dieses Objekt; sie gehen mit ihm, das Fenster schließt.
  mFrame := TAtlasIdeAssistantsLogWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    mFrame.OnOpen := nil;
    mFrame.OnDiff := nil;
    mFrame.OnRevert := nil;
    mFrame.OnSelect := nil;
    mFrame.OnSession := nil;
    mFrame.OnClear := nil;
    mFrame.SetEntries(nil, Default(TAtlasAssistantsLogCounts), 0);
  end;
  TAtlasIdeAssistantsLogWindow.Hide;
  inherited Destroy;
end;

procedure TAtlasIdeAssistantsLogView.Wire(AFrame: TAtlasAssistantsLogFrame);
begin
  AFrame.OnOpen := Open;
  AFrame.OnDiff := Diff;
  AFrame.OnSelect := Selected;
  AFrame.OnRevert :=
    procedure(const AEntry: TAtlasAssistantsLogEntry)
    begin
      Revert(AEntry);
    end;
  AFrame.OnSession := SessionDiff;
  AFrame.OnClear := ClearLog;
end;

procedure TAtlasIdeAssistantsLogView.Fill(AFrame: TAtlasAssistantsLogFrame);
begin
  FShownVersion := FLog.Version;
  AFrame.SetEntries(FLog.Entries, FLog.Counts, FLog.Since);
end;

procedure TAtlasIdeAssistantsLogView.Tick(Sender: TObject);
var
  mFrame: TAtlasAssistantsLogFrame;
begin
  if FLog.Version = FShownVersion then
  begin
    Exit;
  end;
  mFrame := TAtlasIdeAssistantsLogWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    Fill(mFrame);
  end;
end;

procedure TAtlasIdeAssistantsLogView.ShowWindow;
var
  mFrame: TAtlasAssistantsLogFrame;
begin
  mFrame := TAtlasIdeAssistantsLogWindow.Show;
  if mFrame <> nil then
  begin
    Wire(mFrame);
    Fill(mFrame);
  end;
end;

procedure TAtlasIdeAssistantsLogView.Open(const AEntry: TAtlasAssistantsLogEntry);
begin
  if AEntry.FileName = '' then
  begin
    Exit;
  end;
  if AEntry.HasChange then
  begin
    TAtlasIdeNavigation.GoToLocation(AEntry.FileName, AEntry.Change.FirstLine - 1, 0);
  end
  else
  begin
    TAtlasIdeNavigation.ShowFile(AEntry.FileName);
  end;
end;

procedure TAtlasIdeAssistantsLogView.Diff(const AEntry: TAtlasAssistantsLogEntry);
begin
  if AEntry.HasChange and AEntry.Change.Kept then
  begin
    TAtlasUndoDiffView.Execute(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LogDiffTitle,
      [ExtractFileName(AEntry.FileName)]), AEntry.Change.DiffLines);
  end;
end;

procedure TAtlasIdeAssistantsLogView.SessionDiff;
begin
  TAtlasUndoDiffView.Execute(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LogSessionTitle),
    FLog.SessionDiffLines);
end;

procedure TAtlasIdeAssistantsLogView.ClearLog;
begin
  FLog.Clear;
end;

function TAtlasIdeAssistantsLogView.CurrentText(const AFileName: string; out ABuffer: TAtlasEditorFile): Boolean;
begin
  ABuffer := FFiles.Buffer(AFileName);
  Result := ABuffer.Open;
end;

procedure TAtlasIdeAssistantsLogView.Selected(const AEntry: TAtlasAssistantsLogEntry);
var
  mBuffer: TAtlasEditorFile;
  mNewText: string;
  mFrame: TAtlasAssistantsLogFrame;
  mBlock: TAtlasLogRevertBlock;
begin
  mFrame := TAtlasIdeAssistantsLogWindow.ExistingFrame;
  if mFrame = nil then
  begin
    Exit;
  end;
  // Nicht offene Dateien öffnet erst „Zurücknehmen“; bis dahin gilt der Plan gegen den Text, den die IDE kennt.
  if CurrentText(AEntry.FileName, mBuffer) then
  begin
    mBlock := FLog.RevertPlan(AEntry.Id, mBuffer.Text, mNewText);
  end
  else
  begin
    mBlock := FLog.RevertPlan(AEntry.Id, '', mNewText);
    if mBlock = TAtlasLogRevertBlock.ChangedSince then
    begin
      mBlock := TAtlasLogRevertBlock.None;
    end;
  end;
  mFrame.SetRevertState(mBlock);
end;

function TAtlasIdeAssistantsLogView.Revert(const AEntry: TAtlasAssistantsLogEntry): Boolean;
var
  mBuffer: TAtlasEditorFile;
  mNewText, mError: string;
  mBlock: TAtlasLogRevertBlock;
  mFrame: TAtlasAssistantsLogFrame;
begin
  Result := False;
  if not CurrentText(AEntry.FileName, mBuffer) then
  begin
    // Zurückgenommen wird im Editorpuffer: erst öffnen.
    TAtlasIdeNavigation.ShowFile(AEntry.FileName);
    if not CurrentText(AEntry.FileName, mBuffer) then
    begin
      Exit;
    end;
  end;
  mBlock := FLog.RevertPlan(AEntry.Id, mBuffer.Text, mNewText);
  mFrame := TAtlasIdeAssistantsLogWindow.ExistingFrame;
  if mBlock <> TAtlasLogRevertBlock.None then
  begin
    if mFrame <> nil then
    begin
      mFrame.SetRevertState(mBlock);
    end;
    Exit;
  end;
  mError := TAtlasIdeWorkspaceEdit.Apply(TAtlasEditInboxPlan.EditOf(AEntry.FileName, mBuffer.Text, mNewText),
    TAtlasUnopenedPolicy.OpenInEditor, TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.UndoActionRevert)).Error;
  if mError <> '' then
  begin
    if Assigned(FOnMessage) then
    begin
      FOnMessage(mError);
    end;
    Exit;
  end;
  // War der Puffer gespeichert, bleibt er es: Der MCP-Server liest über die Platte.
  if not mBuffer.Modified then
  begin
    FFiles.Save(AEntry.FileName);
  end;
  FLog.MarkReverted(AEntry.Id);
  TAtlasIdeLogEntries.AddEdit(FLog, TAtlasAssistantsLogKind.Reverted, AEntry.FileName, AEntry.Client,
    mBuffer.Text, mNewText);
  if Assigned(FOnMessage) then
  begin
    FOnMessage(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LogRevertDone, [ExtractFileName(AEntry.FileName)]));
  end;
  Result := True;
end;

end.
