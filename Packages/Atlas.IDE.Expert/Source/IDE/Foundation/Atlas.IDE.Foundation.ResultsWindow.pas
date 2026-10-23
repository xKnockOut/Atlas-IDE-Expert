unit Atlas.IDE.Foundation.ResultsWindow;

// Andockbares Ergebnisfenster „Atlas-Ergebnisse“ (#400): ein IDE-Fenster
// über INTAServices.CreateDockableForm, das den Frame TAtlasResultsFrame
// enthält. Es entsteht beim ersten Gebrauch, folgt dem IDE-Thema und lässt
// sich wie die Fenster der IDE andocken. Beim Entladen des Packages gibt
// Release es frei. Das Fenster trägt das Atlas-Symbol (#751) zum IDE-Thema;
// ApplyTheme färbt nach einem Themenwechsel um, samt Symbol.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.Core.Results.Model,
  Atlas.Core.Undo.Contract,
  Atlas.Core.Notes.Store,
  Atlas.UI.Results.Frame;

type
  TAtlasIdeResultsWindow = class
  public class var
    /// <summary>Sprung zu einer Stelle (Doppelklick, Enter); setzt die Composition.</summary>
    OnOpen: TAtlasResultsOpen;
    /// <summary>Nächste Ebene einer Hierarchie; setzt die Composition.</summary>
    OnExpand: TAtlasHierarchyExpand;
    /// <summary>Liste „Atlas-Änderungen“ (#721): zurücknehmen, wiederherstellen, Unterschied.</summary>
    OnChangeUndo: TAtlasChangeSetAction;
    OnChangeRedo: TAtlasChangeSetAction;
    OnChangeDiff: TAtlasChangeDiff;
    /// <summary>Liste der Notizen (#545): bearbeiten, löschen.</summary>
    OnNoteEdit: TAtlasNoteAction;
    OnNoteDelete: TAtlasNoteAction;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Frame: TAtlasResultsFrame; static;
    class procedure ShowEntries(const ATitle: string; const AEntries: TArray<TAtlasResultEntry>); static;
    class procedure ShowHierarchy(const ATitle: string; ADirection: TAtlasHierarchyDirection;
      const ARoots: TArray<TAtlasHierarchyItem>); static;
    /// <summary>Liste „Atlas-Änderungen“ (#721), neueste Sätze zuerst.</summary>
    class procedure ShowChanges(const ATitle: string; const ASets: TArray<TAtlasChangeSet>); static;
    /// <summary>Notizen des Projekts (#545); ASelectId: diese Notiz wählen.</summary>
    class procedure ShowNotes(const ATitle: string; const AGroups: TArray<TAtlasNoteGroup>;
      const ASelectId: string); static;
    /// <summary>Frame, falls das Fenster schon existiert; legt nichts an und holt nichts nach vorn.</summary>
    class function ExistingFrame: TAtlasResultsFrame; static;
    /// <summary>Fenstersymbol (#751) zum aktiven IDE-Thema.</summary>
    class procedure UpdateIcon; static;
    /// <summary>Nach einem Themenwechsel: Inhalt im Thema der IDE, Symbol dazu.</summary>
    class procedure ApplyTheme; static;
    /// <summary>Früh (Register): bei der IDE anmelden, damit der Desktop das Fenster speichert und wiederherstellt (#879).</summary>
    class procedure Prepare; static;
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
  Vcl.Graphics,
  Atlas.UI.Strings,
  Atlas.UI.Style.Symbol,
  Atlas.IDE.Foundation.Symbol,
  Atlas.IDE.Foundation.DockWindow;

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

var
  // Verwaltet Form, Frame und Anmeldung bei der IDE (#879).
  Host: TAtlasIdeDockWindow;

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
  ResultsFrame: TAtlasResultsFrame;
begin
  if not (AFrame is TAtlasResultsFrame) then
    Exit;
  if Host <> nil then
    Host.FrameCreated(AFrame);
  ResultsFrame := TAtlasResultsFrame(AFrame);
  TAtlasIdeResultsWindow.UpdateIcon;
  ResultsFrame.OnOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      if Assigned(TAtlasIdeResultsWindow.OnOpen) then
        TAtlasIdeResultsWindow.OnOpen(AFileName, ALine, ACharacter);
    end;
  ResultsFrame.OnChangeUndo :=
    procedure(ASetId: Integer)
    begin
      if Assigned(TAtlasIdeResultsWindow.OnChangeUndo) then
        TAtlasIdeResultsWindow.OnChangeUndo(ASetId);
    end;
  ResultsFrame.OnChangeRedo :=
    procedure(ASetId: Integer)
    begin
      if Assigned(TAtlasIdeResultsWindow.OnChangeRedo) then
        TAtlasIdeResultsWindow.OnChangeRedo(ASetId);
    end;
  ResultsFrame.OnChangeDiff :=
    procedure(ASetId: Integer; const AFileName: string)
    begin
      if Assigned(TAtlasIdeResultsWindow.OnChangeDiff) then
        TAtlasIdeResultsWindow.OnChangeDiff(ASetId, AFileName);
    end;
  ResultsFrame.OnNoteEdit :=
    procedure(const ANoteId: string)
    begin
      if Assigned(TAtlasIdeResultsWindow.OnNoteEdit) then
        TAtlasIdeResultsWindow.OnNoteEdit(ANoteId);
    end;
  ResultsFrame.OnNoteDelete :=
    procedure(const ANoteId: string)
    begin
      if Assigned(TAtlasIdeResultsWindow.OnNoteDelete) then
        TAtlasIdeResultsWindow.OnNoteDelete(ANoteId);
    end;
  ResultsFrame.OnExpand :=
    function(ADirection: TAtlasHierarchyDirection; const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>
    begin
      Result := nil;
      if Assigned(TAtlasIdeResultsWindow.OnExpand) then
        Result := TAtlasIdeResultsWindow.OnExpand(ADirection, AItem);
    end;
  TAtlasIdeDockWindow.ApplyIdeTheme(AFrame);
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

procedure EnsureHost;
begin
  if Host = nil then
    Host := TAtlasIdeDockWindow.Create(TResultsDock.Create, True);
end;

{ TAtlasIdeResultsWindow }

class function TAtlasIdeResultsWindow.Frame: TAtlasResultsFrame;
var
  Created: Boolean;
begin
  // Lebt die Form noch (X versteckt nur), wird sie samt Gastgebern gezeigt; sonst neu angelegt.
  EnsureHost;
  Host.Show(Created);
  if Created then
    UpdateIcon;
  Result := ExistingFrame;
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

class procedure TAtlasIdeResultsWindow.ShowChanges(const ATitle: string; const ASets: TArray<TAtlasChangeSet>);
var
  Target: TAtlasResultsFrame;
begin
  Target := Frame;
  if Target <> nil then
    Target.ShowChanges(ATitle, ASets, Now, False);
end;

class procedure TAtlasIdeResultsWindow.ShowNotes(const ATitle: string; const AGroups: TArray<TAtlasNoteGroup>;
  const ASelectId: string);
var
  Target: TAtlasResultsFrame;
begin
  Target := Frame;
  if Target <> nil then
    Target.ShowNotes(ATitle, AGroups, ASelectId);
end;

class function TAtlasIdeResultsWindow.ExistingFrame: TAtlasResultsFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasResultsFrame) then
    Result := TAtlasResultsFrame(Host.Frame);
end;

class procedure TAtlasIdeResultsWindow.UpdateIcon;
var
  Icon: TIcon;
begin
  if (Host = nil) or (Host.Form = nil) then
    Exit;
  Icon := TAtlasSymbolImages.Icon(TAtlasIdeSymbol.Current);
  try
    // Icon ist erst in TForm öffentlich.
    TForm(Host.Form).Icon.Assign(Icon);
  finally
    Icon.Free;
  end;
end;

class procedure TAtlasIdeResultsWindow.ApplyTheme;
var
  Frame: TAtlasResultsFrame;
begin
  Frame := ExistingFrame;
  if Frame <> nil then
    TAtlasIdeDockWindow.ApplyIdeTheme(Frame);
  UpdateIcon;
end;

class procedure TAtlasIdeResultsWindow.Prepare;
begin
  EnsureHost;
end;

class procedure TAtlasIdeResultsWindow.Release;
begin
  OnOpen := nil;
  OnExpand := nil;
  OnChangeUndo := nil;
  OnChangeRedo := nil;
  OnChangeDiff := nil;
  OnNoteEdit := nil;
  OnNoteDelete := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
