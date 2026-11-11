unit Atlas.IDE.Designer.EventMap;

// Ereignis-Karte (#612, designer.eventMap): Knopf der Designer-Leiste öffnet
// bzw. schließt ein andockbares Fenster mit TAtlasEventFrame für das Formular
// im aktiven Designer.
// - Daten: Formulartext (TAtlasDesignerAccess.FormText) und aktueller Text der
//   Unit (Puffer), gerechnet von TAtlasEventMap. Jede Sekunde neu gelesen;
//   die Liste wird nur bei geändertem Text neu gefüllt, damit Auswahl und
//   Bildlauf bleiben. Ohne aktiven Designer bleibt das letzte Formular stehen.
// - Doppelklick springt zum Handler (TAtlasIdeNavigation), ein zweiter wählt
//   die Komponente im Designer aus.
// - „Handler umbenennen“: IDesigner.RenameMethod (Deklaration, Rumpf und alle
//   Zuweisungen); Aufrufe im Code ändert die IDE dabei nicht.
// - „Leeren Handler entfernen“ (leer oder ohne Zuweisung): Zuweisungen im
//   Designer auf nil, dann Deklaration und Rumpf als Atlas-Änderung
//   (TAtlasIdeWorkspaceEdit, ein Schritt im Änderungsprotokoll).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Designer.EventMap,
  Atlas.UI.Designer.Bar,
  Atlas.UI.Designer.EventFrame;

type
  TAtlasIdeEventMap = class
  public const
    cId = 'eventMap';
  private
    FOnMessage: TProc<string>;
    FTimer: TTimer;
    FShown: Boolean;
    FFormFile: string;
    FFormClass: string;
    FRootName: string;
    FText: string;
    FRows: TArray<TAtlasEventRow>;
    procedure Tick(Sender: TObject);
    procedure Reload(AForce: Boolean);
    procedure FillList;
    function Frame: TAtlasEventFrame;
    procedure Wire(AFrame: TAtlasEventFrame);
    procedure Jump(const ARow: TAtlasEventRow);
    procedure ShowComponent(const ARow: TAtlasEventRow);
    procedure Rename(const ARow: TAtlasEventRow);
    procedure Remove(const ARow: TAtlasEventRow);
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    function Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
    /// <summary>Klick: Fenster öffnen bzw. schließen.</summary>
    procedure Toggle;
    procedure ApplyTheme;
    /// <summary>Text des Befunds für die Liste.</summary>
    class function FindingText(const ARow: TAtlasEventRow): string; static;
  end;

implementation

uses
  System.IniFiles,
  System.TypInfo,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.Menus,
  Vcl.ActnList,
  Vcl.ImgList,
  Vcl.ComCtrls,
  Vcl.Dialogs,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.Designer.FormModel,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.UI.Designer.ViewStrings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.DockWindow,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation;

const
  cTick = 1000;

type
  TEventDock = class(TInterfacedObject, INTACustomDockableForm)
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
  // Fenster der Karte; nicht im Desktop gespeichert, es öffnet der Knopf.
  Host: TAtlasIdeDockWindow;

{ TEventDock }

function TEventDock.GetCaption: string;
begin
  Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmCaption);
end;

function TEventDock.GetIdentifier: string;
begin
  Result := 'AtlasEventMap';
end;

function TEventDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasEventFrame;
end;

procedure TEventDock.FrameCreated(AFrame: TCustomFrame);
begin
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  TAtlasIdeDockWindow.ApplyIdeTheme(AFrame);
end;

function TEventDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TEventDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TEventDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TEventDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TEventDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TEventDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TEventDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TEventDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TEventDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TEventDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

{ Hilfen }

/// <summary>Komponente AName im Formular ARoot, auch das Formular selbst.</summary>
function ComponentOf(ARoot: TComponent; const AName: string): TComponent;
begin
  Result := nil;
  if AName = '' then
  begin
    Exit;
  end;
  if SameText(ARoot.Name, AName) then
  begin
    Result := ARoot;
  end
  else
  begin
    Result := ARoot.FindComponent(AName);
  end;
end;

/// <summary>Zeilen [AFirst, ALast] als Löschung (bis zum Anfang der Zeile danach).</summary>
function DeleteLines(AFirst, ALast: Integer): TLspTextEdit;
begin
  Result := Default(TLspTextEdit);
  Result.StartPos := TLspTextPosition.Create(AFirst, 0);
  Result.EndPos := TLspTextPosition.Create(ALast + 1, 0);
  Result.NewText := '';
end;

{ TAtlasIdeEventMap }

class function TAtlasIdeEventMap.FindingText(const ARow: TAtlasEventRow): string;
begin
  case ARow.Finding of
    TAtlasEventFinding.Empty:
      Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmEmpty);
    TAtlasEventFinding.Unassigned:
      Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmUnassigned);
    TAtlasEventFinding.Missing:
      Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmMissing);
  else
    Result := '';
  end;
end;

constructor TAtlasIdeEventMap.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cTick;
  FTimer.OnTimer := Tick;
end;

destructor TAtlasIdeEventMap.Destroy;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FreeAndNil(Host);
  FTimer.Free;
  inherited Destroy;
end;

function TAtlasIdeEventMap.Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
begin
  if not ASettings.DesignerEventMap then
  begin
    Exit(Default(TAtlasDesignerButton));
  end;
  Result := TAtlasDesignerButton.Create(cId, TAtlasToolbarIcon.EventMap,
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmHint));
  Result.Pressed := FShown;
end;

function TAtlasIdeEventMap.Frame: TAtlasEventFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasEventFrame) then
  begin
    Result := TAtlasEventFrame(Host.Frame);
  end;
end;

procedure TAtlasIdeEventMap.Toggle;
var
  mCreated: Boolean;
begin
  if FShown and (Host <> nil) and Host.Shown then
  begin
    Host.Hide;
    FShown := False;
    FTimer.Enabled := False;
    Exit;
  end;
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TEventDock.Create, False);
  end;
  FShown := Host.Show(mCreated) and (Frame <> nil);
  if FShown then
  begin
    Wire(Frame);
    ApplyTheme;
    Reload(True);
  end;
  FTimer.Enabled := FShown;
end;

procedure TAtlasIdeEventMap.Wire(AFrame: TAtlasEventFrame);
begin
  AFrame.OnJump :=
    procedure(ARow: TAtlasEventRow)
    begin
      Jump(ARow);
    end;
  AFrame.OnShow :=
    procedure(ARow: TAtlasEventRow)
    begin
      ShowComponent(ARow);
    end;
  AFrame.OnRename :=
    procedure(ARow: TAtlasEventRow)
    begin
      Rename(ARow);
    end;
  AFrame.OnRemove :=
    procedure(ARow: TAtlasEventRow)
    begin
      Remove(ARow);
    end;
  AFrame.OnOptions :=
    procedure
    begin
      FillList;
    end;
end;

procedure TAtlasIdeEventMap.Tick(Sender: TObject);
begin
  if (Host = nil) or not Host.Shown then
  begin
    // Fenster mit dem X geschlossen.
    FShown := False;
    FTimer.Enabled := False;
    Exit;
  end;
  Reload(False);
end;

procedure TAtlasIdeEventMap.Reload(AForce: Boolean);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mDfm, mUnit, mFile: string;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mFile := ChangeFileExt(mEditor.FileName, '.pas');
  mDfm := TAtlasDesignerAccess.FormText(mRoot, TAtlasDesignerAccess.DesignerOf(mEditor));
  mUnit := TAtlasIdeWorkspaceEdit.CurrentText(mFile);
  if not AForce and SameText(mFile, FFormFile) and (mDfm + #0 + mUnit = FText) then
  begin
    Exit;
  end;
  FFormFile := mFile;
  // Im Designer trägt das Formular den Namen seiner Klasse (TfrmKunden).
  FFormClass := mRoot.ClassName;
  FRootName := mRoot.Name;
  FText := mDfm + #0 + mUnit;
  FRows := TAtlasEventMap.Rows(TAtlasFormModel.Parse(mDfm), TAtlasEventMap.Handlers(mUnit, FFormClass));
  FillList;
end;

procedure TAtlasIdeEventMap.FillList;
var
  mFrame: TAtlasEventFrame;
begin
  mFrame := Frame;
  if (mFrame = nil) or not FShown then
  begin
    Exit;
  end;
  mFrame.ShowRows(TAtlasEventMap.Sorted(TAtlasEventMap.Filter(FRows, mFrame.FilterText, mFrame.EventFilter,
    mFrame.OnlyFindings), mFrame.Group), TAtlasEventMap.Events(FRows),
    function(ARow: TAtlasEventRow): string
    begin
      Result := FindingText(ARow);
    end);
end;

procedure TAtlasIdeEventMap.Jump(const ARow: TAtlasEventRow);
begin
  if ARow.Line < 0 then
  begin
    FOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EmNoBody, [ARow.Handler]));
    Exit;
  end;
  TAtlasIdeNavigation.GoToLocation(FFormFile, ARow.Line, 0);
end;

procedure TAtlasIdeEventMap.ShowComponent(const ARow: TAtlasEventRow);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mServices: IOTAModuleServices;
  mModule: IOTAModule;
begin
  if Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    mModule := mServices.FindModule(FFormFile);
    if mModule <> nil then
    begin
      mModule.ShowFilename(ChangeFileExt(FFormFile, '.dfm'));
    end;
  end;
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) or not SameText(mRoot.Name, FRootName) then
  begin
    Exit;
  end;
  mComponent := ComponentOf(mRoot, ARow.Component);
  if (mComponent <> nil) and (TAtlasDesignerAccess.DesignerOf(mEditor) <> nil) then
  begin
    TAtlasDesignerAccess.Select(TAtlasDesignerAccess.DesignerOf(mEditor), mRoot, [mComponent]);
  end;
end;

procedure TAtlasIdeEventMap.Rename(const ARow: TAtlasEventRow);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mDesigner: IDesigner;
  mName: string;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) or not SameText(mRoot.Name, FRootName) then
  begin
    FOnMessage(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ToolNoForm));
    Exit;
  end;
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  mName := ARow.Handler;
  if (mDesigner = nil) or not InputQuery(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmRenameTitle),
    TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EmRenamePrompt, [ARow.Handler]), mName) then
  begin
    Exit;
  end;
  mName := Trim(mName);
  if SameText(mName, ARow.Handler) then
  begin
    Exit;
  end;
  if not IsValidIdent(mName) or mDesigner.MethodExists(mName) or not mDesigner.MethodExists(ARow.Handler) then
  begin
    FOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EmRenameFailed, [ARow.Handler, mName]));
    Exit;
  end;
  mDesigner.RenameMethod(ARow.Handler, mName);
  mDesigner.Modified;
  Reload(True);
end;

procedure TAtlasIdeEventMap.Remove(const ARow: TAtlasEventRow);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mDesigner: IDesigner;
  mRow: TAtlasEventRow;
  mCleared, mDecl, mFirst, mLast: Integer;
  mFile: TLspFileEdits;
  mWorkspace: TLspWorkspaceEdit;
  mResult: TAtlasWorkspaceEditResult;
  mText: string;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) or not SameText(mRoot.Name, FRootName) then
  begin
    FOnMessage(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ToolNoForm));
    Exit;
  end;
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  mText := TAtlasIdeWorkspaceEdit.CurrentText(FFormFile);
  if (mDesigner = nil) or not TAtlasEventMap.HandlerRange(mText, FFormClass, ARow.Handler, mDecl, mFirst,
    mLast) then
  begin
    FOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EmNoBody, [ARow.Handler]));
    Exit;
  end;
  // Erst die Zuweisungen, sonst fragt die IDE beim Speichern nach der fehlenden Methode.
  mCleared := 0;
  for mRow in FRows do
  begin
    mComponent := ComponentOf(mRoot, mRow.Component);
    if (mComponent <> nil) and SameText(mRow.Handler, ARow.Handler) and
      (GetPropInfo(mComponent, mRow.Event) <> nil) then
    begin
      SetMethodProp(mComponent, mRow.Event, Default(TMethod));
      Inc(mCleared);
    end;
  end;
  if mCleared > 0 then
  begin
    mDesigner.Modified;
  end;
  mFile := Default(TLspFileEdits);
  mFile.FileName := FFormFile;
  mFile.Edits := [DeleteLines(mFirst, mLast), DeleteLines(mDecl, mDecl)];
  mWorkspace := Default(TLspWorkspaceEdit);
  mWorkspace.Files := [mFile];
  mResult := TAtlasIdeWorkspaceEdit.Apply(mWorkspace, TAtlasUnopenedPolicy.OpenInEditor,
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmAction));
  if mResult.Error <> '' then
  begin
    FOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EmRemoveFailed, [ARow.Handler, mResult.Error]));
    Exit;
  end;
  FOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.EmRemoved, [ARow.Handler, mCleared]));
  Reload(True);
end;

procedure TAtlasIdeEventMap.ApplyTheme;
var
  mFrame: TAtlasEventFrame;
begin
  mFrame := Frame;
  if mFrame <> nil then
  begin
    TAtlasIdeDockWindow.ApplyIdeTheme(mFrame);
    mFrame.ErrorColor := TColor(TAtlasIdeStyle.Colors.Error);
  end;
end;

end.
