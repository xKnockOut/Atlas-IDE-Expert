unit Atlas.IDE.Designer.TabOrder;

// Knopf „Tab-Reihenfolge“ der Designer-Leiste (#1442, #603) in der IDE:
// - Klick auf das Symbol blendet die Marken ein und aus
//   (TAtlasTabOrderOverlay); mit designer.tabOrderOverlay gehen sie für jedes
//   Formular beim ersten Zeigen von selbst an. Auffällige Marken (Rücksprung
//   gegen die Lesereihenfolge, Lücke, Doppelte; TAtlasTabOrder.Issues) in
//   Fehlerfarbe mit Hinweis, Steuerelemente ohne TabStop grau mit „–“,
//   verschachtelte als Pfad „2.1“ mit designer.tabOrderPaths, in Farben je
//   Container mit Rahmen mit designer.tabOrderColors (nicht im Modus
//   „Reihenfolge klicken“). Der Hinweis an einer verschachtelten Marke nennt
//   den Weg mit Namen. Nur sichtbare Steuerelemente bekommen eine Marke,
//   nicht die auf verborgenen Registerseiten. Leserichtung rechts nach
//   links, wenn das Formular BiDiMode bdRightToLeft hat.
// - Menü am Pfeil: Zeigen, „Reihenfolge klicken“, „Nach Lesereihenfolge
//   sortieren“ und „Tab-Reihenfolge rückgängig“; die ändernden Befehle nur mit
//   editor.designerBar.tabOrderClick.
// - Modus „Reihenfolge klicken“: Klicks auf die Marken vergeben je
//   Elternelement 0, 1, 2 …, nicht geklickte rücken dahinter (Setter der
//   VCL). Enter oder ein Klick auf das Symbol übernimmt, Esc stellt den
//   alten Stand her. Andere Datei oder Designer weg: übernehmen.
// - Rückgängig: Stand vor dem letzten Sortieren bzw. Klicken; solange die
//   Marken zu sehen sind und der Designer den Fokus hat, auch mit Strg+Z.
// Tasten über TAtlasKeyHook, angemeldet nur, solange sie etwas tun. Nur im
// Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Menus,
  Atlas.Core.Designer.TabOrder,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar,
  Atlas.UI.Designer.TabOverlay,
  Atlas.IDE.Foundation.KeyHook;

type
  TAtlasIdeDesignerTabOrder = class;

  /// <summary>Esc und Enter im Modus „Reihenfolge klicken“, Strg+Z für „Tab-Reihenfolge rückgängig“.</summary>
  TAtlasDesignerTabKeys = class(TAtlasKeyClient)
  private
    FOwner: TAtlasIdeDesignerTabOrder;
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  end;

  TAtlasIdeDesignerTabOrder = class
  public const
    cId = 'tabOrder';
  private
    FOnMessage: TProc<string>;
    FOverlay: TAtlasTabOrderOverlay;
    FMenu: TPopupMenu;
    FKeys: TAtlasDesignerTabKeys;
    FShown: Boolean;
    /// <summary>Datei des Formulars, für das die Marken zuletzt galten.</summary>
    FFile: string;
    /// <summary>Formulare, für die designer.tabOrderOverlay schon gegriffen hat.</summary>
    FAutoShown: TStringList;
    FClicks: TAtlasTabClicks;
    FUndo: TArray<TAtlasTabAssignment>;
    FUndoFile: string;
    /// <summary>Pfade für diese Sitzung umgeschaltet (Menü); Vorgabe aus designer.tabOrderPaths.</summary>
    FPathsToggled: Boolean;
    /// <summary>Farben für diese Sitzung umgeschaltet (Menü); Vorgabe aus designer.tabOrderColors.</summary>
    FColorsToggled: Boolean;
    function PathsWanted: Boolean;
    function ColorsWanted: Boolean;
    procedure Say(const AText: string);
    procedure EnsureOverlay;
    procedure ItemClick(Sender: TObject);
    function AddItem(const ACaption: string; ATag: Integer; AEnabled, AChecked: Boolean): TMenuItem;
    procedure Apply(ARoot: TComponent; const AList: TArray<TAtlasTabAssignment>);
    procedure BadgeClicked(const AName: string);
    procedure FormChanged(const AFileName: string);
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Knopf der Leiste: Symbol blendet ein und aus, Pfeil öffnet das Menü.</summary>
    function Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
    /// <summary>Klick auf das Symbol: im Modus übernehmen, sonst ein- und ausblenden.</summary>
    procedure Toggle;
    /// <summary>Menü an APoint (Bildschirm).</summary>
    procedure Popup(const APoint: TPoint);
    /// <summary>Takt der Leiste: Marken nachführen, Hinweis unter der Maus.</summary>
    procedure Update;
    /// <summary>Marken ausblenden (Leiste aus, Sicherung ausgelöst); ein laufender Modus wird übernommen.</summary>
    procedure Hide;
    /// <summary>Modus „Reihenfolge klicken“ beginnen.</summary>
    procedure StartClicks;
    /// <summary>Modus beenden; AKeep = False stellt den alten Stand her.</summary>
    procedure FinishClicks(AKeep: Boolean);
    /// <summary>Nach Lesereihenfolge sortieren.</summary>
    procedure SortByReading;
    function CanUndo: Boolean;
    procedure Undo;
    /// <summary>Tasten an- oder abmelden (Designer gezeigt).</summary>
    procedure UpdateKeys(AWanted: Boolean);
    procedure ApplyTheme;
    property Shown: Boolean read FShown;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

const
  cKeyPriority = 60;
  cShow = 1;
  cClicks = 2;
  cSort = 3;
  cUndo = 4;
  cPaths = 5;
  cColors = 6;

/// <summary>Formular des Designers für die Marken: aktiv, mit sichtbarem Fenster.</summary>
function OverlayForm(out AEditor: IOTAFormEditor; out AForm: TWinControl): Boolean;
var
  mRoot: TComponent;
begin
  AForm := nil;
  Result := Application.Active and TAtlasDesignerAccess.Current(AEditor, mRoot) and (mRoot is TWinControl);
  if Result then
  begin
    AForm := TWinControl(mRoot);
    Result := AForm.HandleAllocated and IsWindowVisible(AForm.Handle);
  end;
end;

/// <summary>Steuerelemente mit TabOrder (TWinControl mit Namen und Elternelement) des Formulars.</summary>
function TabStopsOf(ARoot: TComponent): TArray<TAtlasTabStop>;
var
  mIndex: Integer;
  mComponent: TComponent;
  mControl: TWinControl;
  mStop: TAtlasTabStop;
begin
  Result := nil;
  if not (ARoot is TWinControl) then
  begin
    Exit;
  end;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    mComponent := ARoot.Components[mIndex];
    if not (mComponent is TWinControl) or (mComponent.Name = '') or (TWinControl(mComponent).Parent = nil) then
    begin
      Continue;
    end;
    mControl := TWinControl(mComponent);
    mStop := TAtlasTabStop.Create(mControl.Name, TAtlasDesignerAccess.ParentNameOf(mControl, ARoot),
      mControl.TabOrder, TAtlasDesignerAccess.BoundsInRoot(mControl, TWinControl(ARoot)));
    mStop.Focusable := mControl.TabStop;
    mStop.Container := csAcceptsControls in mControl.ControlStyle;
    // Showing: auch Elternelemente sichtbar; falsch auf verborgenen Registerseiten.
    mStop.Shown := mControl.Showing;
    Result := Result + [mStop];
  end;
end;

function RightToLeft(AForm: TWinControl): Boolean;
begin
  Result := AForm.BiDiMode = bdRightToLeft;
end;

/// <summary>Client des Formulars auf dem Bildschirm (AScreen) und der sichtbare Teil davon (AVisible): Der
/// Designer kann es abschneiden oder scrollen. False, wenn nichts sichtbar ist.</summary>
function VisibleArea(AForm: TWinControl; out AScreen, AVisible: TRect): Boolean;
var
  mOrigin: TPoint;
  mHost: HWND;
begin
  mOrigin := AForm.ClientToScreen(Point(0, 0));
  AScreen := Rect(mOrigin.X, mOrigin.Y, mOrigin.X + AForm.ClientWidth, mOrigin.Y + AForm.ClientHeight);
  mHost := GetParent(AForm.Handle);
  AVisible := AScreen;
  if (mHost <> 0) and GetWindowRect(mHost, AVisible) then
  begin
    AVisible.Intersect(AScreen);
  end
  else
  begin
    AVisible := AScreen;
  end;
  Result := not AVisible.IsEmpty;
end;

function IssueText(AIssue: TAtlasTabIssue): string;
begin
  case AIssue of
    TAtlasTabIssue.Jump:
      Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTabJump);
    TAtlasTabIssue.Gap:
      Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTabGap);
    TAtlasTabIssue.Duplicate:
      Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTabDuplicate);
  else
    Result := '';
  end;
end;

/// <summary>Verschiebung vom Client des Formulars (AScreen) in den Client des Fensters (AVisible).</summary>
function OffsetOf(const AScreen, AVisible: TRect): TPoint;
begin
  Result := Point(AScreen.Left - AVisible.Left, AScreen.Top - AVisible.Top);
end;

/// <summary>Stil und Hinweis der Marke nach Zustand: ohne TabStop, geklickt, auffällig. APath: Weg mit Namen.
/// </summary>
procedure MarkBadge(var ABadge: TAtlasTabBadge; const AStop: TAtlasTabStop; AIssue: TAtlasTabIssue;
  APicked: TFunc<string, Boolean>; const APath: string);
begin
  if not AStop.Reached then
  begin
    ABadge.Text := '–';
    ABadge.Style := TAtlasTabBadgeStyle.Muted;
    ABadge.Hint := APath + ': ' + TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTabNoStop);
  end
  else if APicked(AStop.Name) then
  begin
    ABadge.Style := TAtlasTabBadgeStyle.Picked;
  end
  else if AIssue <> TAtlasTabIssue.None then
  begin
    ABadge.Style := TAtlasTabBadgeStyle.Warn;
    ABadge.Hint := APath + ': ' + IssueText(AIssue);
  end;
end;

/// <summary>Marken der sichtbaren Steuerelemente oben rechts; AOffset aus OffsetOf. AGroups: Farbgruppen aus
/// TAtlasTabOrder.Groups, nil = ohne Farben.</summary>
function BadgesOf(const AStops: TArray<TAtlasTabStop>; ARightToLeft, APaths: Boolean;
  const AGroups: TArray<Integer>; const AOffset: TPoint; APicked: TFunc<string, Boolean>): TArray<TAtlasTabBadge>;
var
  mIssues: TArray<TAtlasTabIssue>;
  mPaths: TArray<string>;
  mIndex: Integer;
  mBadge: TAtlasTabBadge;
  mPath: string;
begin
  mIssues := TAtlasTabOrder.Issues(AStops, ARightToLeft);
  mPaths := TAtlasTabOrder.Paths(AStops);
  Result := nil;
  for mIndex := 0 to High(AStops) do
  begin
    if not AStops[mIndex].Shown then
    begin
      Continue;
    end;
    mBadge := TAtlasTabBadge.Create(AStops[mIndex].Name, IntToStr(AStops[mIndex].TabOrder),
      TAtlasTabBadgeStyle.Normal, Point(AStops[mIndex].Bounds.Right + AOffset.X,
      AStops[mIndex].Bounds.Top + AOffset.Y));
    if APaths then
    begin
      mBadge.Text := mPaths[mIndex];
    end;
    mPath := TAtlasTabOrder.NamedPath(AStops, mIndex);
    if AGroups <> nil then
    begin
      mBadge.Group := TAtlasTabOrder.GroupOf(AStops, AGroups, mIndex);
    end;
    if TAtlasTabOrder.IndexOf(AStops, AStops[mIndex].ParentName) >= 0 then
    begin
      // Verschachtelt: Der Hinweis nennt den ganzen Weg, die Marke nur die eigene Nummer.
      mBadge.Hint := mPath;
    end;
    MarkBadge(mBadge, AStops[mIndex], mIssues[mIndex], APicked, mPath);
    Result := Result + [mBadge];
  end;
end;

/// <summary>Gestrichelte Rahmen der sichtbaren Container mit Farbgruppe.</summary>
function FramesOf(const AStops: TArray<TAtlasTabStop>; const AGroups: TArray<Integer>;
  const AOffset: TPoint): TArray<TAtlasTabFrame>;
var
  mIndex: Integer;
  mBounds: TRect;
begin
  Result := nil;
  for mIndex := 0 to High(AGroups) do
  begin
    if AStops[mIndex].Shown and (AGroups[mIndex] >= 0) then
    begin
      mBounds := AStops[mIndex].Bounds;
      mBounds.Offset(AOffset);
      Result := Result + [TAtlasTabFrame.Create(mBounds, AGroups[mIndex])];
    end;
  end;
end;

{ TAtlasDesignerTabKeys }

function TAtlasDesignerTabKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  if not TAtlasDesignerAccess.Focused then
  begin
    Exit(False);
  end;
  if FOwner.FClicks.Active then
  begin
    Result := (AShift = []) and ((AKey = VK_ESCAPE) or (AKey = VK_RETURN));
  end
  else
  begin
    Result := FOwner.FShown and (AShift = [ssCtrl]) and (AKey = Ord('Z')) and FOwner.CanUndo;
  end;
end;

procedure TAtlasDesignerTabKeys.HandleKey(AKey: Word; AShift: TShiftState);
var
  mOwner: TAtlasIdeDesignerTabOrder;
  mKey: Word;
begin
  mOwner := FOwner;
  mKey := AKey;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      if mKey = VK_ESCAPE then
      begin
        mOwner.FinishClicks(False);
      end
      else if mKey = VK_RETURN then
      begin
        mOwner.FinishClicks(True);
      end
      else
      begin
        mOwner.Undo;
      end;
    end);
end;

{ TAtlasIdeDesignerTabOrder }

constructor TAtlasIdeDesignerTabOrder.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FMenu := TPopupMenu.Create(nil);
  FClicks := TAtlasTabClicks.Create;
  FAutoShown := TStringList.Create;
  FAutoShown.CaseSensitive := False;
  FKeys := TAtlasDesignerTabKeys.Create(cKeyPriority);
  FKeys.FOwner := Self;
end;

destructor TAtlasIdeDesignerTabOrder.Destroy;
begin
  TAtlasKeyHook.Remove(FKeys);
  FKeys.Free;
  FOverlay.Free;
  FAutoShown.Free;
  FClicks.Free;
  FMenu.Free;
  inherited Destroy;
end;

function TAtlasIdeDesignerTabOrder.PathsWanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DesignerTabOrderPaths <> FPathsToggled;
end;

function TAtlasIdeDesignerTabOrder.ColorsWanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DesignerTabOrderColors <> FColorsToggled;
end;

procedure TAtlasIdeDesignerTabOrder.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

function TAtlasIdeDesignerTabOrder.Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
var
  mHint: string;
begin
  if FClicks.Active then
  begin
    mHint := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTabModeHint);
  end
  else if ASettings.DesignerTabOrderClick then
  begin
    mHint := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarTabOrderClickHint);
  end
  else
  begin
    mHint := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarTabOrderHint);
  end;
  Result := TAtlasDesignerButton.Create(cId, TAtlasToolbarIcon.TabOrder, mHint);
  Result.Pressed := FShown;
  Result.Menu := True;
end;

procedure TAtlasIdeDesignerTabOrder.Toggle;
begin
  if FClicks.Active then
  begin
    FinishClicks(True);
    Exit;
  end;
  FShown := not FShown;
  Update;
end;

function TAtlasIdeDesignerTabOrder.AddItem(const ACaption: string; ATag: Integer;
  AEnabled, AChecked: Boolean): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.Enabled := AEnabled;
  Result.Checked := AChecked;
  if ATag > 0 then
  begin
    Result.OnClick := ItemClick;
  end;
  FMenu.Items.Add(Result);
end;

procedure TAtlasIdeDesignerTabOrder.Popup(const APoint: TPoint);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mForm, mChange: Boolean;
begin
  mForm := TAtlasDesignerAccess.Current(mEditor, mRoot) and (mRoot is TWinControl);
  mChange := mForm and TAtlasIdeSettings.Current.DesignerTabOrderClick;
  FMenu.Items.Clear;
  AddItem(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarTabOrderHint), cShow, mForm, FShown);
  AddItem(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTabPaths), cPaths, mForm, PathsWanted);
  AddItem(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTabColors), cColors, mForm, ColorsWanted);
  AddItem('-', 0, True, False);
  AddItem(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTabClickMode), cClicks, mChange, FClicks.Active);
  AddItem(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTabSort), cSort, mChange and not FClicks.Active,
    False);
  AddItem(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTabUndo), cUndo,
    mChange and not FClicks.Active and CanUndo, False);
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeDesignerTabOrder.ItemClick(Sender: TObject);
var
  mTag: Integer;
  mOwner: TAtlasIdeDesignerTabOrder;
begin
  mTag := TMenuItem(Sender).Tag;
  mOwner := Self;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      case mTag of
        cShow:
          mOwner.Toggle;
        cPaths:
          begin
            // Wahl für die Sitzung; dauerhaft über designer.tabOrderPaths.
            mOwner.FPathsToggled := not mOwner.FPathsToggled;
            mOwner.Update;
          end;
        cColors:
          begin
            // Wahl für die Sitzung; dauerhaft über designer.tabOrderColors.
            mOwner.FColorsToggled := not mOwner.FColorsToggled;
            mOwner.Update;
          end;
        cClicks:
          if mOwner.FClicks.Active then
          begin
            mOwner.FinishClicks(True);
          end
          else
          begin
            mOwner.StartClicks;
          end;
        cSort:
          mOwner.SortByReading;
        cUndo:
          mOwner.Undo;
      end;
    end);
end;

procedure TAtlasIdeDesignerTabOrder.EnsureOverlay;
begin
  if FOverlay <> nil then
  begin
    Exit;
  end;
  FOverlay := TAtlasTabOrderOverlay.CreateOverlay(nil, Application.MainFormHandle, TAtlasIdeStyle.Colors);
  FOverlay.OnBadgeClick :=
    procedure(AName: string)
    var
      mName: string;
    begin
      mName := AName;
      TAtlasGuard.Run(TAtlasFeature.DesignerBar,
        procedure
        begin
          BadgeClicked(mName);
        end);
    end;
end;

procedure TAtlasIdeDesignerTabOrder.FormChanged(const AFileName: string);
begin
  // Anderes Formular: ein laufender Modus gilt als übernommen.
  if FClicks.Active then
  begin
    FClicks.Reset;
  end;
  FFile := AFileName;
  if TAtlasIdeSettings.Current.DesignerTabOrderOverlay and (FAutoShown.IndexOf(AFileName) < 0) then
  begin
    FAutoShown.Add(AFileName);
    FShown := True;
  end;
end;

procedure TAtlasIdeDesignerTabOrder.Update;
var
  mEditor: IOTAFormEditor;
  mForm: TWinControl;
  mScreen, mVisible: TRect;
  mClicks: TAtlasTabClicks;
  mStops: TArray<TAtlasTabStop>;
  mGroups: TArray<Integer>;
begin
  if not OverlayForm(mEditor, mForm) then
  begin
    if FOverlay <> nil then
    begin
      FOverlay.HideOverlay;
    end;
    Exit;
  end;
  if not SameText(mEditor.FileName, FFile) then
  begin
    FormChanged(mEditor.FileName);
  end;
  if not (FShown or FClicks.Active) or not VisibleArea(mForm, mScreen, mVisible) then
  begin
    if FOverlay <> nil then
    begin
      FOverlay.HideOverlay;
    end;
    Exit;
  end;
  EnsureOverlay;
  mClicks := FClicks;
  FOverlay.Clickable := FClicks.Active;
  mStops := TabStopsOf(mForm);
  mGroups := nil;
  // Beim Klicken ruhen die Farben: Grün heißt dort „schon geklickt“.
  if ColorsWanted and not FClicks.Active then
  begin
    mGroups := TAtlasTabOrder.Groups(mStops, TAtlasTabOrderOverlay.GroupCount);
  end;
  FOverlay.SetFrames(FramesOf(mStops, mGroups, OffsetOf(mScreen, mVisible)));
  FOverlay.SetBadges(BadgesOf(mStops, RightToLeft(mForm), PathsWanted, mGroups, OffsetOf(mScreen, mVisible),
    function(AName: string): Boolean
    begin
      Result := mClicks.Active and mClicks.Clicked(AName);
    end));
  if not FOverlay.Shown or (FOverlay.BoundsRect <> mVisible) then
  begin
    FOverlay.ShowAt(mVisible);
  end;
  FOverlay.UpdateHint(Mouse.CursorPos);
end;

procedure TAtlasIdeDesignerTabOrder.Hide;
begin
  if FClicks.Active then
  begin
    FClicks.Reset;
  end;
  if FOverlay <> nil then
  begin
    FOverlay.HideOverlay;
  end;
end;

procedure TAtlasIdeDesignerTabOrder.Apply(ARoot: TComponent; const AList: TArray<TAtlasTabAssignment>);
var
  mAssignment: TAtlasTabAssignment;
  mComponent: TComponent;
begin
  for mAssignment in AList do
  begin
    mComponent := ARoot.FindComponent(mAssignment.Name);
    if (mComponent is TWinControl) and (TWinControl(mComponent).TabOrder <> mAssignment.Order) then
    begin
      TWinControl(mComponent).TabOrder := mAssignment.Order;
    end;
  end;
end;

procedure TAtlasIdeDesignerTabOrder.StartClicks;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mStops: TArray<TAtlasTabStop>;
begin
  if not TAtlasIdeSettings.Current.DesignerTabOrderClick or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mStops := TabStopsOf(mRoot);
  FClicks.Start(mStops);
  FFile := mEditor.FileName;
  Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTabClickStarted));
  Update;
end;

procedure TAtlasIdeDesignerTabOrder.FinishClicks(AKeep: Boolean);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mDesigner: IDesigner;
  mRestore: TArray<TAtlasTabAssignment>;
  mCount: Integer;
begin
  if not FClicks.Active then
  begin
    Exit;
  end;
  mRestore := FClicks.Restore;
  mCount := FClicks.Count;
  FClicks.Reset;
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) or not SameText(mEditor.FileName, FFile) then
  begin
    Update;
    Exit;
  end;
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  if AKeep then
  begin
    if mCount > 0 then
    begin
      FUndo := mRestore;
      FUndoFile := FFile;
    end;
    Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerTabClickDone, [mCount]));
  end
  else
  begin
    Apply(mRoot, mRestore);
    if (mDesigner <> nil) and (mCount > 0) then
    begin
      mDesigner.Modified;
    end;
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTabClickCanceled));
  end;
  Update;
end;

procedure TAtlasIdeDesignerTabOrder.BadgeClicked(const AName: string);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mDesigner: IDesigner;
  mOrder: Integer;
begin
  if not FClicks.Active or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mComponent := mRoot.FindComponent(AName);
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  if not (mComponent is TWinControl) or (mDesigner = nil) then
  begin
    Exit;
  end;
  mOrder := FClicks.Next(AName, TAtlasDesignerAccess.ParentNameOf(TWinControl(mComponent), mRoot));
  if mOrder < 0 then
  begin
    Exit;
  end;
  // Der Setter der VCL schiebt die übrigen Geschwister weiter: Der Zähler je Elternelement genügt.
  TWinControl(mComponent).TabOrder := mOrder;
  mDesigner.Modified;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerBarTabOrderSet,
    [AName, TWinControl(mComponent).TabOrder]));
  Update;
end;

procedure TAtlasIdeDesignerTabOrder.SortByReading;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mDesigner: IDesigner;
  mStops: TArray<TAtlasTabStop>;
  mList, mOld: TArray<TAtlasTabAssignment>;
  mOrders: TArray<Integer>;
  mIndex, mChanged: Integer;
begin
  if not TAtlasIdeSettings.Current.DesignerTabOrderClick or not TAtlasDesignerAccess.Current(mEditor, mRoot) or
    not (mRoot is TWinControl) then
  begin
    Exit;
  end;
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  mStops := TabStopsOf(mRoot);
  mOrders := TAtlasTabOrder.ReadingOrder(mStops, RightToLeft(TWinControl(mRoot)));
  mList := TAtlasTabOrder.Assignments(mStops, mOrders);
  if (Length(mList) = 0) or (mDesigner = nil) then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTabSortedNone));
    Exit;
  end;
  mChanged := 0;
  SetLength(mOld, Length(mStops));
  for mIndex := 0 to High(mStops) do
  begin
    mOld[mIndex] := TAtlasTabAssignment.Create(mStops[mIndex].Name, mStops[mIndex].TabOrder);
    if mStops[mIndex].TabOrder <> mOrders[mIndex] then
    begin
      Inc(mChanged);
    end;
  end;
  // Rückgängig: der alte Stand, aufsteigend gesetzt wie beim Sortieren.
  for mIndex := 0 to High(mStops) do
  begin
    mOrders[mIndex] := mStops[mIndex].TabOrder;
    mStops[mIndex].TabOrder := -1;
  end;
  FUndo := TAtlasTabOrder.Assignments(mStops, mOrders);
  FUndoFile := mEditor.FileName;
  Apply(mRoot, mList);
  mDesigner.Modified;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerTabSorted, [mChanged]));
  Update;
end;

function TAtlasIdeDesignerTabOrder.CanUndo: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := (Length(FUndo) > 0) and TAtlasDesignerAccess.Current(mEditor, mRoot) and
    SameText(mEditor.FileName, FUndoFile);
end;

procedure TAtlasIdeDesignerTabOrder.Undo;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mDesigner: IDesigner;
begin
  if not CanUndo or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  Apply(mRoot, FUndo);
  FUndo := nil;
  FUndoFile := '';
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  if mDesigner <> nil then
  begin
    mDesigner.Modified;
  end;
  Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTabUndone));
  Update;
end;

procedure TAtlasIdeDesignerTabOrder.UpdateKeys(AWanted: Boolean);
begin
  if AWanted and (FClicks.Active or (FShown and (Length(FUndo) > 0))) then
  begin
    TAtlasKeyHook.Add(FKeys);
  end
  else
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
end;

procedure TAtlasIdeDesignerTabOrder.ApplyTheme;
begin
  if FOverlay <> nil then
  begin
    FOverlay.ApplyColors(TAtlasIdeStyle.Colors);
  end;
end;

end.
