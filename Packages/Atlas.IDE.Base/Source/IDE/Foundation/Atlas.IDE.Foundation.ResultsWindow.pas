unit Atlas.IDE.Foundation.ResultsWindow;

// Andockbares Ergebnisfenster „Atlas-Ergebnisse“ (#400): ein IDE-Fenster
// über INTAServices.CreateDockableForm, das den Frame TAtlasResultsFrame
// enthält. Es entsteht beim ersten Gebrauch, folgt dem IDE-Thema und lässt
// sich wie die Fenster der IDE andocken. Beim Entladen des Packages gibt
// Release es frei. Das Fenster trägt das Atlas-Symbol (#751) zum IDE-Thema;
// ApplyTheme färbt nach einem Themenwechsel um, samt Symbol. Das
// Aufrufdiagramm (#1122) ist nur erlaubt, solange DiagramAllowed True liefert
// (callHierarchy.diagram); ApplySettings überträgt das nach einer Änderung.
// ShowDataFlow zeigt den Baum des Datenflusses (#690); OnFlowExpand und OnFlowFilter holen die nächste Ebene
// bzw. die erste neu. ShowIssues zeigt Issues zu einer Methode (#1275); OnIssueOpen und OnIssueCommit setzt, wer
// die Liste zeigt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.Core.Results.Model,
  Atlas.Core.Undo.Contract,
  Atlas.Core.SymbolPath.Model,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.DataFlow,
  Atlas.UI.Results.View,
  Atlas.UI.Results.Hierarchy,
  Atlas.UI.Results.Changes,
  Atlas.UI.Results.Items,
  Atlas.UI.Results.SymbolPath,
  Atlas.UI.Results.Impact,
  Atlas.UI.Results.DataFlow,
  Atlas.UI.Results.Issues,
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
    /// <summary>Aufrufdiagramm erlaubt (#1122, callHierarchy.diagram); nil = nein. Setzt die Composition.</summary>
    DiagramAllowed: TFunc<Boolean>;
    /// <summary>Datei gehört zu einem Projekt der Gruppe („Nur Projekt-Units“ im Diagramm); nil = alle.</summary>
    IsProjectFile: TFunc<string, Boolean>;
    /// <summary>„In Architekturkarte zeigen“ eines Wegs zwischen Symbolen (#1117).</summary>
    OnShowRoute: TAtlasShowRoute;
    /// <summary>Auswirkungsanalyse (#1120): andere Tiefe, betroffene Tests ausführen.</summary>
    OnImpactDepth: TAtlasImpactDepthChange;
    OnImpactRunTests: TAtlasImpactRunTests;
    /// <summary>Datenfluss (#690): nächste Ebene bzw. Filter geändert.</summary>
    OnFlowExpand: TAtlasDataFlowExpand;
    OnFlowFilter: TAtlasDataFlowFilter;
    /// <summary>Issues zu einer Methode (#1275): Issue öffnen bzw. Commit zeigen.</summary>
    OnIssueOpen: TAtlasResultsIssueAction;
    OnIssueCommit: TAtlasResultsIssueAction;
  public
    /// <summary>Fenster zeigen (bei Bedarf anlegen); nil, wenn die IDE keine andockbaren Fenster anbietet.</summary>
    class function Frame: TAtlasResultsFrame; static;
    class procedure ShowEntries(const ATitle: string; const AEntries: TArray<TAtlasResultEntry>); static;
    /// <summary>Verwendungen getrennt nach Treffersicherheit (#1119): „Sicher“ und „Erschlossen“.</summary>
    class procedure ShowReferences(const ATitle: string; const AEntries: TArray<TAtlasResultEntry>); static;
    /// <summary>Aufrufhierarchie zeigen; AAsDiagram: gleich als Aufrufdiagramm (#1122), sofern erlaubt.</summary>
    class procedure ShowHierarchy(const ATitle: string; ADirection: TAtlasHierarchyDirection;
      const ARoots: TArray<TAtlasHierarchyItem>; AAsDiagram: Boolean); static;
    /// <summary>Nach geänderten Einstellungen: Diagramm erlauben oder abschalten (#1122).</summary>
    class procedure ApplySettings; static;
    /// <summary>Liste „Atlas-Änderungen“ (#721), neueste Sätze zuerst.</summary>
    class procedure ShowChanges(const ATitle: string; const ASets: TArray<TAtlasChangeSet>); static;
    /// <summary>Liste mit Kennungen eines Moduls (#1455, etwa die Notizen #545); die Aktionen kommen mit der
    /// Liste.</summary>
    class procedure ShowItems(const AList: TAtlasResultsItemList); static;
    /// <summary>Aktionen der Liste von AOwner vergessen (Modul stoppt, Regel 3).</summary>
    class procedure ReleaseItems(const AOwner: string); static;
    /// <summary>Weg zwischen Symbolen (#1117) als gezeichnete Kette.</summary>
    class procedure ShowSymbolPath(const ATitle: string; const AAnswer: TAtlasSymbolPathAnswer;
      AMapAvailable: Boolean); static;
    /// <summary>Hinweis statt einer Kette (Suche läuft, Fehler).</summary>
    class procedure ShowSymbolPathMessage(const ATitle, AText: string); static;
    /// <summary>Auswirkungen einer Änderung am Symbol (#1120): direkt, indirekt, Tests.</summary>
    class procedure ShowImpact(const ATitle: string; const AImpact: TAtlasImpact); static;
    /// <summary>Baum des Datenflusses (#690) mit Tiefengrenze und den Filtern der Anfrage.</summary>
    class procedure ShowDataFlow(const ATitle: string; ADirection: TAtlasDataFlowDirection;
      const AResult: TAtlasDataFlowResult; AMaxDepth: Integer; AOnlyProject, AExcludeTests: Boolean); static;
    /// <summary>Issues zu einer Methode bzw. Unit (#1275); AList kennzeichnet die Liste.</summary>
    class procedure ShowIssues(const ATitle: string; AList: Integer; const AIssues: TArray<TAtlasResultIssue>); static;
    /// <summary>Text eines Issues nachtragen, solange die Liste AList gezeigt wird; holt nichts nach vorn.</summary>
    class procedure SetIssueText(AList, AId: Integer; const AText: string); static;
    /// <summary>Frame, falls das Fenster schon existiert; legt nichts an und holt nichts nach vorn.</summary>
    class function ExistingFrame: TAtlasResultsFrame; static;
    /// <summary>Fenstersymbol (#751) zum aktiven IDE-Thema.</summary>
    class procedure UpdateIcon; static;
    /// <summary>Nach einem Themenwechsel: Inhalt im Thema der IDE, Symbol dazu.</summary>
    class procedure ApplyTheme; static;
    /// <summary>Früh (Register): bei der IDE anmelden, damit der Desktop das Fenster speichert und wiederherstellt
    /// (#879).</summary>
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

/// <summary>Öffnen, Änderungen (Rückgängig, Wiederholen, Unterschied) und Wege an die Ereignisse des Fensters.
/// </summary>
procedure WireNavigation(AFrame: TAtlasResultsFrame);
begin
  AFrame.OnOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      if Assigned(TAtlasIdeResultsWindow.OnOpen) then
      begin
        TAtlasIdeResultsWindow.OnOpen(AFileName, ALine, ACharacter);
      end;
    end;
  AFrame.Changes.OnUndo :=
    procedure(ASetId: Integer)
    begin
      if Assigned(TAtlasIdeResultsWindow.OnChangeUndo) then
      begin
        TAtlasIdeResultsWindow.OnChangeUndo(ASetId);
      end;
    end;
  AFrame.Changes.OnRedo :=
    procedure(ASetId: Integer)
    begin
      if Assigned(TAtlasIdeResultsWindow.OnChangeRedo) then
      begin
        TAtlasIdeResultsWindow.OnChangeRedo(ASetId);
      end;
    end;
  AFrame.Changes.OnDiff :=
    procedure(ASetId: Integer; const AFileName: string)
    begin
      if Assigned(TAtlasIdeResultsWindow.OnChangeDiff) then
      begin
        TAtlasIdeResultsWindow.OnChangeDiff(ASetId, AFileName);
      end;
    end;
  AFrame.Path.OnShowRoute :=
    procedure(const AUnits: TArray<string>)
    begin
      if Assigned(TAtlasIdeResultsWindow.OnShowRoute) then
      begin
        TAtlasIdeResultsWindow.OnShowRoute(AUnits);
      end;
    end;
end;

/// <summary>Auswirkung, Hierarchie und Datenfluss an die Ereignisse des Fensters.</summary>
procedure WireAnalysis(AFrame: TAtlasResultsFrame);
begin
  AFrame.Impact.OnDepth :=
    procedure(ADepth: Integer)
    begin
      if Assigned(TAtlasIdeResultsWindow.OnImpactDepth) then
      begin
        TAtlasIdeResultsWindow.OnImpactDepth(ADepth);
      end;
    end;
  AFrame.Impact.OnRunTests :=
    procedure(const AImpact: TAtlasImpact)
    begin
      if Assigned(TAtlasIdeResultsWindow.OnImpactRunTests) then
      begin
        TAtlasIdeResultsWindow.OnImpactRunTests(AImpact);
      end;
    end;
  AFrame.Hierarchy.OnExpand :=
    function(ADirection: TAtlasHierarchyDirection; const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>
    begin
      Result := nil;
      if Assigned(TAtlasIdeResultsWindow.OnExpand) then
      begin
        Result := TAtlasIdeResultsWindow.OnExpand(ADirection, AItem);
      end;
    end;
  AFrame.Flow.OnExpand :=
    function(ADirection: TAtlasDataFlowDirection; const ASource: TAtlasDataFlowSymbol;
      const APath: TArray<string>): TAtlasDataFlowResult
    begin
      Result := Default(TAtlasDataFlowResult);
      if Assigned(TAtlasIdeResultsWindow.OnFlowExpand) then
      begin
        Result := TAtlasIdeResultsWindow.OnFlowExpand(ADirection, ASource, APath);
      end;
    end;
  AFrame.Flow.OnFilter :=
    procedure(AOnlyProject, AExcludeTests: Boolean)
    begin
      if Assigned(TAtlasIdeResultsWindow.OnFlowFilter) then
      begin
        TAtlasIdeResultsWindow.OnFlowFilter(AOnlyProject, AExcludeTests);
      end;
    end;
end;

/// <summary>Tracker-Einträge an die Ereignisse des Fensters.</summary>
procedure WireIssues(AFrame: TAtlasResultsFrame);
begin
  AFrame.Issues.OnOpen :=
    procedure(AList, AId: Integer)
    begin
      if Assigned(TAtlasIdeResultsWindow.OnIssueOpen) then
      begin
        TAtlasIdeResultsWindow.OnIssueOpen(AList, AId);
      end;
    end;
  AFrame.Issues.OnCommit :=
    procedure(AList, AId: Integer)
    begin
      if Assigned(TAtlasIdeResultsWindow.OnIssueCommit) then
      begin
        TAtlasIdeResultsWindow.OnIssueCommit(AList, AId);
      end;
    end;
end;

procedure TResultsDock.FrameCreated(AFrame: TCustomFrame);
var
  mResultsFrame: TAtlasResultsFrame;
begin
  if not (AFrame is TAtlasResultsFrame) then
  begin
    Exit;
  end;
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  mResultsFrame := TAtlasResultsFrame(AFrame);
  TAtlasIdeResultsWindow.UpdateIcon;
  WireNavigation(mResultsFrame);
  WireAnalysis(mResultsFrame);
  WireIssues(mResultsFrame);
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
  begin
    Host := TAtlasIdeDockWindow.Create(TResultsDock.Create, True);
  end;
end;

{ TAtlasIdeResultsWindow }

class function TAtlasIdeResultsWindow.Frame: TAtlasResultsFrame;
var
  mCreated: Boolean;
begin
  // Lebt die Form noch (X versteckt nur), wird sie samt Gastgebern gezeigt; sonst neu angelegt.
  EnsureHost;
  Host.Show(mCreated);
  if mCreated then
  begin
    UpdateIcon;
  end;
  Result := ExistingFrame;
end;

class procedure TAtlasIdeResultsWindow.ShowEntries(const ATitle: string; const AEntries: TArray<TAtlasResultEntry>);
var
  mTarget: TAtlasResultsFrame;
begin
  mTarget := Frame;
  if mTarget <> nil then
  begin
    mTarget.Entries.Show(ATitle, TAtlasResults.Group(AEntries));
  end;
end;

class procedure TAtlasIdeResultsWindow.ShowReferences(const ATitle: string;
  const AEntries: TArray<TAtlasResultEntry>);
var
  mTarget: TAtlasResultsFrame;
begin
  mTarget := Frame;
  if mTarget <> nil then
  begin
    mTarget.Entries.ShowRated(ATitle, AEntries, TAtlasStrings.Text(TAtlasTextId.ResultsSureGroup),
      TAtlasStrings.Text(TAtlasTextId.ResultsInferredGroup));
  end;
end;

class procedure TAtlasIdeResultsWindow.ShowHierarchy(const ATitle: string; ADirection: TAtlasHierarchyDirection;
  const ARoots: TArray<TAtlasHierarchyItem>; AAsDiagram: Boolean);
var
  mTarget: TAtlasResultsFrame;
begin
  mTarget := Frame;
  if mTarget = nil then
  begin
    Exit;
  end;
  mTarget.Hierarchy.DiagramAllowed := Assigned(DiagramAllowed) and DiagramAllowed();
  mTarget.Hierarchy.IsProjectFile := IsProjectFile;
  mTarget.Hierarchy.Show(ATitle, ADirection, ARoots, AAsDiagram);
end;

class procedure TAtlasIdeResultsWindow.ApplySettings;
var
  mTarget: TAtlasResultsFrame;
begin
  mTarget := ExistingFrame;
  if mTarget <> nil then
  begin
    mTarget.Hierarchy.DiagramAllowed := Assigned(DiagramAllowed) and DiagramAllowed();
  end;
end;

class procedure TAtlasIdeResultsWindow.ShowChanges(const ATitle: string; const ASets: TArray<TAtlasChangeSet>);
var
  mTarget: TAtlasResultsFrame;
begin
  mTarget := Frame;
  if mTarget <> nil then
  begin
    mTarget.Changes.Show(ATitle, ASets, Now, False);
  end;
end;

class procedure TAtlasIdeResultsWindow.ShowItems(const AList: TAtlasResultsItemList);
var
  mTarget: TAtlasResultsFrame;
begin
  mTarget := Frame;
  if mTarget <> nil then
  begin
    mTarget.Items.Show(AList);
  end;
end;

class procedure TAtlasIdeResultsWindow.ReleaseItems(const AOwner: string);
begin
  if ExistingFrame <> nil then
  begin
    ExistingFrame.Items.Release(AOwner);
  end;
end;

class procedure TAtlasIdeResultsWindow.ShowSymbolPath(const ATitle: string; const AAnswer: TAtlasSymbolPathAnswer;
  AMapAvailable: Boolean);
var
  mTarget: TAtlasResultsFrame;
begin
  mTarget := Frame;
  if mTarget <> nil then
  begin
    mTarget.Path.Show(ATitle, AAnswer, AMapAvailable);
  end;
end;

class procedure TAtlasIdeResultsWindow.ShowSymbolPathMessage(const ATitle, AText: string);
var
  mTarget: TAtlasResultsFrame;
begin
  mTarget := Frame;
  if mTarget <> nil then
  begin
    mTarget.Path.ShowText(ATitle, AText);
  end;
end;

class procedure TAtlasIdeResultsWindow.ShowImpact(const ATitle: string; const AImpact: TAtlasImpact);
var
  mTarget: TAtlasResultsFrame;
begin
  mTarget := Frame;
  if mTarget <> nil then
  begin
    mTarget.Impact.Show(ATitle, AImpact);
  end;
end;

class procedure TAtlasIdeResultsWindow.ShowDataFlow(const ATitle: string; ADirection: TAtlasDataFlowDirection;
  const AResult: TAtlasDataFlowResult; AMaxDepth: Integer; AOnlyProject, AExcludeTests: Boolean);
var
  mTarget: TAtlasResultsFrame;
begin
  mTarget := Frame;
  if mTarget <> nil then
  begin
    mTarget.Flow.Show(ATitle, ADirection, AResult, AMaxDepth, AOnlyProject, AExcludeTests);
  end;
end;

class procedure TAtlasIdeResultsWindow.ShowIssues(const ATitle: string; AList: Integer;
  const AIssues: TArray<TAtlasResultIssue>);
var
  mTarget: TAtlasResultsFrame;
begin
  mTarget := Frame;
  if mTarget <> nil then
  begin
    mTarget.Issues.Show(ATitle, AList, AIssues);
  end;
end;

class procedure TAtlasIdeResultsWindow.SetIssueText(AList, AId: Integer; const AText: string);
var
  mTarget: TAtlasResultsFrame;
begin
  mTarget := ExistingFrame;
  if mTarget <> nil then
  begin
    mTarget.Issues.SetText(AList, AId, AText);
  end;
end;

class function TAtlasIdeResultsWindow.ExistingFrame: TAtlasResultsFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasResultsFrame) then
  begin
    Result := TAtlasResultsFrame(Host.Frame);
  end;
end;

class procedure TAtlasIdeResultsWindow.UpdateIcon;
var
  mIcon: TIcon;
begin
  if (Host = nil) or (Host.Form = nil) then
  begin
    Exit;
  end;
  mIcon := TAtlasSymbolImages.Icon(TAtlasIdeSymbol.Current);
  try
    // Icon ist erst in TForm öffentlich.
    TForm(Host.Form).Icon.Assign(mIcon);
  finally
    mIcon.Free;
  end;
end;

class procedure TAtlasIdeResultsWindow.ApplyTheme;
var
  mFrame: TAtlasResultsFrame;
begin
  mFrame := ExistingFrame;
  if mFrame <> nil then
  begin
    TAtlasIdeDockWindow.ApplyIdeTheme(mFrame);
  end;
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
  OnShowRoute := nil;
  OnImpactDepth := nil;
  OnImpactRunTests := nil;
  OnFlowExpand := nil;
  OnFlowFilter := nil;
  OnIssueOpen := nil;
  OnIssueCommit := nil;
  // Meldet ab und gibt die Form nur frei, wenn die IDE sie nicht schon zerstört hat.
  FreeAndNil(Host);
end;

end.
