unit Atlas.UI.Debug.VariablesFrame;

// Inhalt des Fensters „Variablen“ (#853), reine VCL: oben die Reiter Autos,
// Lokal und Überwachung, darunter die Suchleiste (TAtlasVariablesSearchBar),
// im Reiter Überwachung das Eingabefeld für neue Ausdrücke. In der Mitte der
// Baum der gewählten TAtlasEvalList wie im Fenster „Auswerten“
// (TAtlasEvalTreeView): seit dem letzten Schritt geänderte Werte in der
// Warnfarbe, bei einer Suche nur Treffer, ihre Pfade und ihre Unterelemente,
// Treffer fett. Kontextmenü und Tasten je Zeile: TAtlasVariablesRowActions;
// Strg+F springt ins Suchfeld. Unten Anzahl bzw. Treffer und die Tastenhilfe.
// Im Reiter Überwachung neben dem Eingabefeld „3 weitere ausgeblendet – zeigen“,
// solange beim Halt gebundene Ausdrücke anderer Klassen fehlen (#2550); hinter
// jeder gebundenen Zeile steht, wofür sie gilt.
// Die DFM ist leer, weil TCustomFrame.Create für abgeleitete Frames eine
// Ressource verlangt; aufgebaut wird im Code.

interface

uses
  System.Classes,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Buttons,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.Variables,
  Atlas.UI.Debug.EvaluateTreeView,
  Atlas.UI.Debug.VariablesParts,
  Atlas.UI.Foundation.WrapLabel;

type
  TAtlasDebugVariablesFrame = class(TFrame)
  private
    FHooks: TAtlasVariablesFrameHooks;
    FTabButtons: array[TAtlasVariablesTab] of TSpeedButton;
    FSearchBar: TAtlasVariablesSearchBar;
    FWatchBar: TPanel;
    FWatchEdit: TEdit;
    FHiddenCheck: TCheckBox;
    FHiddenCount: Integer;
    /// <summary>SetHidden stellt den Haken: Das ist keine Eingabe.</summary>
    FSettingHidden: Boolean;
    FView: TAtlasEvalTreeView;
    FRows: TAtlasVariablesRowActions;
    FStatus: TAtlasWrapLabel;
    FSearch: TAtlasVariableSearch;
    FTab: TAtlasVariablesTab;
    procedure BuildTabs;
    procedure BuildWatch;
    procedure BuildTree;
    procedure TabClick(Sender: TObject);
    procedure WatchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HiddenClick(Sender: TObject);
    procedure UpdateHidden;
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    function GetTree: TTreeView;
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Liste des Reiters und Suche, die der Baum zeigt; beide gehören der IDE-Schicht (nil: leer).
    /// </summary>
    procedure SetList(AList: TAtlasEvalList; ASearch: TAtlasVariableSearch);
    /// <summary>Nach jeder Änderung der Liste oder der Suche.</summary>
    procedure Refresh;
    /// <summary>Text unten (Anzahl, Treffer, Hinweis).</summary>
    procedure SetStatus(const AText: string);
    procedure SetTab(ATab: TAtlasVariablesTab);
    /// <summary>Im Reiter Überwachung: ACount ausgeblendete Ausdrücke, AShown: sie stehen trotzdem da (#2550).
    /// </summary>
    procedure SetHidden(ACount: Integer; AShown: Boolean);
    procedure FocusSearch;
    /// <summary>Gewählter Knoten; nil ohne Auswahl.</summary>
    function Selected: TAtlasEvalNode;
    procedure Select(const AKey: string);
    /// <summary>Meldungen an die IDE-Schicht.</summary>
    property Hooks: TAtlasVariablesFrameHooks read FHooks;
    property Tab: TAtlasVariablesTab read FTab;
    property Tree: TTreeView read GetTree;
    property WatchBar: TPanel read FWatchBar;
    property WatchEdit: TEdit read FWatchEdit;
    property HiddenCheck: TCheckBox read FHiddenCheck;
    property Status: TAtlasWrapLabel read FStatus;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.UI.Debug.VariablesStrings;

{$R *.dfm}

const
  cButtonHeight = 24;
  cBarHeight = 30;
  cTabWidth = 96;
  cHiddenWidth = 300;
  /// <summary>Abstand der Lage vor dem Ausrichten: Sie bestimmt die Reihenfolge gleich ausgerichteter Teile.
  /// </summary>
  cOrderStep = 1000;
  cTabTexts: array[TAtlasVariablesTab] of TAtlasVariablesTextId = (TAtlasVariablesTextId.VariablesTabAutos,
    TAtlasVariablesTextId.VariablesTabLocals, TAtlasVariablesTextId.VariablesTabWatch);

{ Aufbau }

function Px(AFrame: TControl; AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, AFrame.CurrentPPI, 96);
end;

function AddBar(AFrame: TWinControl; AOrder: Integer): TPanel;
begin
  Result := TPanel.Create(AFrame);
  // Erst Lage und Höhe, dann ausrichten: Sonst kann die VCL die Reihenfolge der Leisten vertauschen.
  Result.Top := AOrder * cOrderStep;
  Result.Height := Px(AFrame, cBarHeight);
  Result.Align := alTop;
  Result.BevelOuter := bvNone;
  Result.ShowCaption := False;
  Result.ParentBackground := True;
  Result.Parent := AFrame;
end;

function AddFooter(AFrame: TWinControl; AOrder: Integer; const AText: string): TAtlasWrapLabel;
begin
  Result := TAtlasWrapLabel.Create(AFrame);
  // Unten ausgerichtet: Die größere Lage steht weiter unten.
  Result.Top := AOrder * cOrderStep;
  Result.Align := alBottom;
  Result.AlignWithMargins := True;
  Result.Font.Color := clGrayText;
  Result.Caption := AText;
  Result.Parent := AFrame;
end;

{ TAtlasDebugVariablesFrame }

constructor TAtlasDebugVariablesFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Name := '';
  FHooks := TAtlasVariablesFrameHooks.Create;
  FTab := TAtlasVariablesTab.Autos;
  BuildTabs;
  FSearchBar := TAtlasVariablesSearchBar.CreateIn(Self, FHooks, cOrderStep, Px(Self, cBarHeight));
  BuildWatch;
  AddFooter(Self, 2, TAtlasVariablesStrings.Text(TAtlasVariablesTextId.VariablesKeys));
  FStatus := AddFooter(Self, 1, '');
  BuildTree;
end;

destructor TAtlasDebugVariablesFrame.Destroy;
begin
  // Der Baum vergeht erst im inherited: Beim Löschen seiner Knoten darf er nicht mehr nach FView fragen.
  FreeAndNil(FView);
  FreeAndNil(FRows);
  FSearch := nil;
  // Suchleiste und Zeilenaktionen melden beim Freigeben nichts mehr.
  FreeAndNil(FHooks);
  inherited Destroy;
end;

procedure TAtlasDebugVariablesFrame.BuildTabs;
var
  mBar: TPanel;
  mTab: TAtlasVariablesTab;
  mButton: TSpeedButton;
begin
  mBar := AddBar(Self, 0);
  for mTab := Low(TAtlasVariablesTab) to High(TAtlasVariablesTab) do
  begin
    mButton := TSpeedButton.Create(Self);
    // Lage vor dem Ausrichten: Sie bestimmt die Reihenfolge am linken Rand.
    mButton.Left := cOrderStep * Ord(mTab);
    mButton.Parent := mBar;
    mButton.Align := alLeft;
    mButton.AlignWithMargins := True;
    mButton.Width := Px(Self, cTabWidth);
    mButton.Height := Px(Self, cButtonHeight);
    mButton.GroupIndex := 1;
    mButton.AllowAllUp := False;
    mButton.Caption := TAtlasVariablesStrings.Text(cTabTexts[mTab]);
    mButton.Tag := Ord(mTab);
    mButton.Down := mTab = FTab;
    mButton.OnClick := TabClick;
    FTabButtons[mTab] := mButton;
  end;
end;

procedure TAtlasDebugVariablesFrame.BuildWatch;
begin
  FWatchBar := AddBar(Self, 2);
  FWatchBar.Visible := False;
  FHiddenCheck := TCheckBox.Create(Self);
  FHiddenCheck.Parent := FWatchBar;
  FHiddenCheck.Align := alRight;
  FHiddenCheck.AlignWithMargins := True;
  FHiddenCheck.Width := Px(Self, cHiddenWidth);
  FHiddenCheck.Visible := False;
  FHiddenCheck.OnClick := HiddenClick;
  FWatchEdit := TEdit.Create(Self);
  FWatchEdit.Parent := FWatchBar;
  FWatchEdit.Align := alClient;
  FWatchEdit.AlignWithMargins := True;
  FWatchEdit.TextHint := TAtlasVariablesStrings.Text(TAtlasVariablesTextId.VariablesWatchHint);
  FWatchEdit.OnKeyDown := WatchKeyDown;
end;

/// <summary>Baum mit Kontextmenü. Sichtbar und Treffer kommen aus der Suche der IDE-Schicht, solange der Frame sie
/// kennt.</summary>
procedure TAtlasDebugVariablesFrame.BuildTree;
var
  mTree: TTreeView;
begin
  FRows := TAtlasVariablesRowActions.Create(Self, FHooks, Selected);
  mTree := TTreeView.Create(Self);
  mTree.Parent := Self;
  mTree.Align := alClient;
  mTree.AlignWithMargins := True;
  mTree.ReadOnly := True;
  mTree.HideSelection := False;
  mTree.PopupMenu := FRows.Menu;
  mTree.OnKeyDown := TreeKeyDown;
  FView := TAtlasEvalTreeView.Create(mTree);
  FView.OnExpand :=
    procedure(ANode: TAtlasEvalNode)
    begin
      if Assigned(FHooks.Expand) then
      begin
        FHooks.Expand(ANode);
      end;
    end;
  FView.Sync.Visible :=
    function(ANode: TAtlasEvalNode): Boolean
    begin
      Result := (FSearch = nil) or FSearch.IsShown(ANode);
    end;
  FView.Sync.Emphasis :=
    function(ANode: TAtlasEvalNode): Boolean
    begin
      Result := (FSearch <> nil) and FSearch.IsHit(ANode);
    end;
  FView.Sync.Suffix :=
    function(ANode: TAtlasEvalNode): string
    begin
      Result := '';
      if (FTab = TAtlasVariablesTab.Watch) and Assigned(FHooks.ScopeText) then
      begin
        Result := FHooks.ScopeText(ANode);
      end;
    end;
end;

function TAtlasDebugVariablesFrame.GetTree: TTreeView;
begin
  Result := FView.Tree;
end;

procedure TAtlasDebugVariablesFrame.CreateWnd;
begin
  inherited CreateWnd;
  // TTreeView.Items braucht ein Fenster.
  Refresh;
end;

procedure TAtlasDebugVariablesFrame.TabClick(Sender: TObject);
begin
  if not (Sender is TSpeedButton) then
  begin
    Exit;
  end;
  SetTab(TAtlasVariablesTab(TSpeedButton(Sender).Tag));
  if Assigned(FHooks.Tab) then
  begin
    FHooks.Tab(FTab);
  end;
end;

procedure TAtlasDebugVariablesFrame.WatchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  mText: string;
begin
  if (Key <> VK_RETURN) or (Shift <> []) then
  begin
    Exit;
  end;
  Key := 0;
  mText := Trim(FWatchEdit.Text);
  if (mText <> '') and Assigned(FHooks.AddWatch) then
  begin
    FWatchEdit.Text := '';
    FHooks.AddWatch(mText);
  end;
end;

procedure TAtlasDebugVariablesFrame.HiddenClick(Sender: TObject);
begin
  if not FSettingHidden and Assigned(FHooks.ShowHidden) then
  begin
    FHooks.ShowHidden(FHiddenCheck.Checked);
  end;
end;

procedure TAtlasDebugVariablesFrame.SetHidden(ACount: Integer; AShown: Boolean);
begin
  FHiddenCount := ACount;
  FSettingHidden := True;
  try
    if FHiddenCheck.Checked <> AShown then
    begin
      FHiddenCheck.Checked := AShown;
    end;
  finally
    FSettingHidden := False;
  end;
  UpdateHidden;
end;

procedure TAtlasDebugVariablesFrame.UpdateHidden;
var
  mCaption: string;
begin
  mCaption := TAtlasVariablesStrings.Fmt(TAtlasVariablesTextId.VariablesScopeHidden, [FHiddenCount]);
  if FHiddenCheck.Caption <> mCaption then
  begin
    FHiddenCheck.Caption := mCaption;
  end;
  FHiddenCheck.Visible := FHiddenCount > 0;
end;

procedure TAtlasDebugVariablesFrame.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = Ord('F')) and (Shift = [ssCtrl]) then
  begin
    Key := 0;
    FocusSearch;
  end
  else if FRows.KeyDown(Key, Shift) then
  begin
    Key := 0;
  end;
end;

procedure TAtlasDebugVariablesFrame.SetList(AList: TAtlasEvalList; ASearch: TAtlasVariableSearch);
begin
  FView.List := AList;
  FSearch := ASearch;
  Refresh;
end;

procedure TAtlasDebugVariablesFrame.Refresh;
begin
  if HandleAllocated then
  begin
    FView.Refresh;
  end;
end;

procedure TAtlasDebugVariablesFrame.SetStatus(const AText: string);
begin
  if FStatus.Caption <> AText then
  begin
    FStatus.Caption := AText;
  end;
end;

procedure TAtlasDebugVariablesFrame.SetTab(ATab: TAtlasVariablesTab);
begin
  FTab := ATab;
  FTabButtons[ATab].Down := True;
  FWatchBar.Visible := ATab = TAtlasVariablesTab.Watch;
  FRows.Watches := ATab = TAtlasVariablesTab.Watch;
end;

procedure TAtlasDebugVariablesFrame.FocusSearch;
begin
  FSearchBar.FocusSearch;
end;

function TAtlasDebugVariablesFrame.Selected: TAtlasEvalNode;
begin
  Result := FView.SelectedNode;
end;

procedure TAtlasDebugVariablesFrame.Select(const AKey: string);
begin
  if HandleAllocated then
  begin
    FView.Select(AKey);
  end;
end;

end.
