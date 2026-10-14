unit Atlas.IDE.Results.Window;

// Andockbares Ergebnisfenster „Atlas-Ergebnisse“ (#400): ein IDE-Fenster
// über INTAServices.CreateDockableForm, das den Frame TAtlasResultsFrame
// enthält. Es entsteht beim ersten Gebrauch, folgt dem IDE-Thema und lässt
// sich wie die Fenster der IDE andocken. Beim Entladen des Packages gibt
// Release es frei.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.Core.Results.Model,
  Atlas.UI.Results.Frame;

type
  TAtlasIdeResultsWindow = class
  public class var
    /// <summary>Sprung zu einer Stelle (Doppelklick, Enter); setzt die Composition.</summary>
    OnOpen: TAtlasResultsOpen;
    /// <summary>Nächste Ebene einer Hierarchie; setzt die Composition.</summary>
    OnExpand: TAtlasHierarchyExpand;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Frame: TAtlasResultsFrame; static;
    class procedure ShowEntries(const ATitle: string; const AEntries: TArray<TAtlasResultEntry>); static;
    class procedure ShowHierarchy(const ATitle: string; ADirection: TAtlasHierarchyDirection;
      const ARoots: TArray<TAtlasHierarchyItem>); static;
    /// <summary>Beim Entladen: Fenster schließen und freigeben.</summary>
    class procedure Release; static;
  end;

implementation

uses
  System.IniFiles,
  Vcl.ActnList,
  Vcl.ImgList,
  Vcl.Menus,
  Vcl.ComCtrls,
  DesignIntf,
  ToolsAPI,
  Atlas.UI.Strings;

type
  TResultsDock = class(TInterfacedObject, INTACustomDockableForm)
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

  /// <summary>Meldet, wenn die IDE Fenster oder Frame selbst freigibt (z. B. beim Beenden).</summary>
  TWatch = class(TComponent)
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

var
  Dock: INTACustomDockableForm;
  Form: TCustomForm;
  ResultsFrame: TAtlasResultsFrame;
  Watch: TWatch;

{ TResultsDock }

function TResultsDock.GetCaption: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.ResultsCaption);
end;

function TResultsDock.GetIdentifier: string;
begin
  Result := 'AtlasResults';
end;

function TResultsDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasResultsFrame;
end;

procedure TResultsDock.FrameCreated(AFrame: TCustomFrame);
var
  Theming: IOTAIDEThemingServices;
begin
  if not (AFrame is TAtlasResultsFrame) then
    Exit;
  ResultsFrame := TAtlasResultsFrame(AFrame);
  ResultsFrame.FreeNotification(Watch);
  ResultsFrame.OnOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      if Assigned(TAtlasIdeResultsWindow.OnOpen) then
        TAtlasIdeResultsWindow.OnOpen(AFileName, ALine, ACharacter);
    end;
  ResultsFrame.OnExpand :=
    function(ADirection: TAtlasHierarchyDirection; const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>
    begin
      Result := nil;
      if Assigned(TAtlasIdeResultsWindow.OnExpand) then
        Result := TAtlasIdeResultsWindow.OnExpand(ADirection, AItem);
    end;
  if Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) and Theming.IDEThemingEnabled then
    Theming.ApplyTheme(AFrame);
end;

function TResultsDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TResultsDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TResultsDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TResultsDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TResultsDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TResultsDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TResultsDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TResultsDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TResultsDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TResultsDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

{ TWatch }

procedure TWatch.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation <> opRemove then
    Exit;
  if AComponent = ResultsFrame then
    ResultsFrame := nil;
  if AComponent = Form then
  begin
    Form := nil;
    ResultsFrame := nil;
  end;
end;

{ TAtlasIdeResultsWindow }

class function TAtlasIdeResultsWindow.Frame: TAtlasResultsFrame;
var
  Services: INTAServices;
begin
  if Form = nil then
  begin
    if not Supports(BorlandIDEServices, INTAServices, Services) then
      Exit(nil);
    if Watch = nil then
      Watch := TWatch.Create(nil);
    Dock := TResultsDock.Create;
    Form := Services.CreateDockableForm(Dock);
    if Form <> nil then
      Form.FreeNotification(Watch);
  end;
  if Form <> nil then
  begin
    Form.Show;
    Form.BringToFront;
  end;
  Result := ResultsFrame;
end;

class procedure TAtlasIdeResultsWindow.ShowEntries(const ATitle: string; const AEntries: TArray<TAtlasResultEntry>);
var
  Target: TAtlasResultsFrame;
begin
  Target := Frame;
  if Target <> nil then
    Target.ShowEntries(ATitle, TAtlasResults.Group(AEntries));
end;

class procedure TAtlasIdeResultsWindow.ShowHierarchy(const ATitle: string; ADirection: TAtlasHierarchyDirection;
  const ARoots: TArray<TAtlasHierarchyItem>);
var
  Target: TAtlasResultsFrame;
begin
  Target := Frame;
  if Target <> nil then
    Target.ShowHierarchy(ATitle, ADirection, ARoots);
end;

class procedure TAtlasIdeResultsWindow.Release;
begin
  OnOpen := nil;
  OnExpand := nil;
  ResultsFrame := nil;
  FreeAndNil(Form);
  Dock := nil;
  FreeAndNil(Watch);
end;

end.
