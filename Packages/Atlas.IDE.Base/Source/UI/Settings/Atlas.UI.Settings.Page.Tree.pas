unit Atlas.UI.Settings.Page.Tree;

// Baum links auf der Optionsseite „Atlas“ (#890; vorher eine Liste): Bereiche und Unterpunkte, gewählte Seite und
// aufgeklappte Bereiche bis zum nächsten Öffnen. Dazu die Sperren durch Hauptschalter: Grund am Rahmen, Hinweis oben
// auf der Seite, Spiegel in der Übersicht und graue Knoten.

interface

uses
  Vcl.Controls,
  Vcl.ComCtrls,
  Atlas.Core.Settings.Groups,
  Atlas.UI.Settings.Group,
  Atlas.UI.Settings.Page.Nodes;

type
  TAtlasSettingsPageTree = class(TAtlasSettingsPageNodes)
  protected
    /// <summary>Bereiche und ihre Unterpunkte als Baum links (#890; vorher eine Liste).</summary>
    FTree: TTreeView;
    /// <summary>Baum links und rechts daneben die Reiter der Knoten.</summary>
    procedure AddNavigation;
    procedure FillTree;
    function ActiveNode: Integer;
    function LockOfName(const AName: string): TAtlasSettingsLock;
  private
    FFillingTree: Boolean;
    // Gewählte Seite und aufgeklappte Bereiche bis zum nächsten Öffnen (ohne verwaltete Typen: Leckmonitor).
    class var FLastPage: Integer;
    class var FExpandedAreas: set of Byte;
    class var FStateKnown: Boolean;
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure TreeExpanded(Sender: TObject; Node: TTreeNode);
    procedure TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    function PageShown(AIndex: Integer): Boolean;
    procedure RefreshTree;
    /// <summary>Knoten der gezeigten Seiten; liefert den Knoten der Seite ASelected, sonst den ersten.</summary>
    function AddTreeNodes(ASelected: Integer): TTreeNode;
    procedure ExpandAreas;
    procedure ShowWanted(AWanted: TTreeNode);
    function IsOn(const AName: string): Boolean;
    function LockText(const ALock: TAtlasSettingsLock): string;
    procedure ApplyLocks(AContainer: TWinControl; ALocked: Boolean; var AOutside: TArray<string>);
    procedure ApplyFrameLocks(AFrame: TAtlasSettingsGroup; ALocked: Boolean; var AOutside: TArray<string>);
    /// <summary>Gesperrt durch einen Hauptschalter, der nicht im selben Rahmen steht; dessen Grund nach AOutside.
    /// </summary>
    function RowLocked(AControl: TControl; var AOutside: TArray<string>): Boolean;
    function PageGray(AIndex: Integer): Boolean;
    /// <summary>Beim Zeigen eines Reiters: die Seite Versionsverwaltung fragt einmal „Aktuelles Projekt“ ab.
    /// </summary>
    procedure SheetShown(ASheet: TTabSheet);
  public
    procedure SelectPage(AIndex: Integer); override;
    /// <summary>Sperren, Grund, Spiegel und graue Knoten nach den aktuellen Werten (#890).</summary>
    procedure UpdateLocks;
    function SheetGray(ASheet: TTabSheet): Boolean;
    /// <summary>Gemerkte Auswahl und aufgeklappte Bereiche vergessen (Tests).</summary>
    class procedure ForgetTreeState; static;
    /// <summary>Baum der Bereiche und Unterpunkte links; schaltet Pages um (#890).</summary>
    property Navigation: TTreeView read FTree;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.StdCtrls,
  Vcl.Forms,
  Vcl.Graphics,
  Atlas.UI.Strings,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Marks,
  Atlas.UI.Settings.Page.Host,
  Atlas.UI.Settings.Page.General;

procedure AddUnique(var AList: TArray<string>; const AText: string);
var
  Item: string;
begin
  for Item in AList do
  begin
    if Item = AText then
    begin
      Exit;
    end;
  end;
  AList := AList + [AText];
end;

function PageIndexOf(ANode: TTreeNode): Integer;
begin
  Result := -1;
  if ANode <> nil then
  begin
    Result := Integer(NativeInt(ANode.Data));
  end;
end;

{ TAtlasSettingsPageTree }

procedure TAtlasSettingsPageTree.AddNavigation;
begin
  // Reiter je Bereich (#227); jeder stapelt seine Elemente neu von oben. Viele Reiter: in Zeilen.
  // Bereiche und Unterpunkte als Baum links (#890); die Reiter selbst bleiben unsichtbar, der Baum schaltet sie um.
  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.Align := alLeft;
  FTree.AlignWithMargins := True;
  FTree.Width := 170;
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.OnChange := TreeChange;
  FTree.OnExpanded := TreeExpanded;
  FTree.OnCollapsed := TreeExpanded;
  FTree.OnCustomDrawItem := TreeCustomDrawItem;
  AddPages;
end;

procedure TAtlasSettingsPageTree.SheetShown(ASheet: TTabSheet);
var
  mPart: TAtlasSettingsPagePart;
begin
  for mPart in FParts do
  begin
    mPart.SheetShown(ASheet);
  end;
end;

function TAtlasSettingsPageTree.ActiveNode: Integer;
var
  Index: Integer;
begin
  Result := -1;
  if FPages.ActivePage = nil then
  begin
    Exit;
  end;
  for Index := 0 to High(FNodePages) do
  begin
    if FNodePages[Index].Sheet = FPages.ActivePage then
    begin
      Exit(Index);
    end;
  end;
end;

procedure TAtlasSettingsPageTree.SelectPage(AIndex: Integer);
var
  Index: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FNodePages)) then
  begin
    Exit;
  end;
  FPages.ActivePage := FNodePages[AIndex].Sheet;
  SheetShown(FNodePages[AIndex].Sheet);
  if not ListReady(FTree) then
  begin
    Exit;
  end;
  for Index := 0 to FTree.Items.Count - 1 do
  begin
    if PageIndexOf(FTree.Items[Index]) = AIndex then
    begin
      FTree.Selected := FTree.Items[Index];
      Break;
    end;
  end;
end;

function TAtlasSettingsPageTree.PageShown(AIndex: Integer): Boolean;
var
  Index: Integer;
begin
  // Der Filter blendet Unterpunkte ohne Treffer aus; ein Bereich bleibt, solange einer seiner Punkte trifft.
  if (FMarks.Filter = sfAll) or FMarks.HasMatch(FNodePages[AIndex].Box) then
  begin
    Exit(True);
  end;
  if FNodePages[AIndex].Node = '' then
  begin
    for Index := 0 to High(FNodePages) do
    begin
      if (Index <> AIndex) and (FNodePages[Index].Area = FNodePages[AIndex].Area) and
        FMarks.HasMatch(FNodePages[Index].Box) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TAtlasSettingsPageTree.AddTreeNodes(ASelected: Integer): TTreeNode;
var
  mIndex, mArea: Integer;
  mAreaNodes: TArray<TTreeNode>;
  mNode: TTreeNode;
begin
  Result := nil;
  SetLength(mAreaNodes, Length(Sheets));
  for mIndex := 0 to High(FNodePages) do
  begin
    if not PageShown(mIndex) then
    begin
      Continue;
    end;
    mArea := FNodePages[mIndex].Area;
    if FNodePages[mIndex].Node = '' then
    begin
      mNode := FTree.Items.AddObject(nil, FNodePages[mIndex].Caption, Pointer(NativeInt(mIndex)));
      mAreaNodes[mArea] := mNode;
    end
    else
    begin
      mNode := FTree.Items.AddChildObject(mAreaNodes[mArea], FNodePages[mIndex].Caption, Pointer(NativeInt(mIndex)));
    end;
    if mIndex = ASelected then
    begin
      Result := mNode;
    end;
  end;
  if (Result = nil) and (FTree.Items.Count > 0) then
  begin
    Result := FTree.Items[0];
  end;
end;

procedure TAtlasSettingsPageTree.ExpandAreas;
var
  mIndex, mArea: Integer;
  mNode: TTreeNode;
begin
  // Aufgeklappt wie beim letzten Mal; beim ersten Öffnen der Bereich der gewählten Seite.
  for mIndex := 0 to FTree.Items.Count - 1 do
  begin
    mNode := FTree.Items[mIndex];
    if (mNode.Level = 0) and mNode.HasChildren then
    begin
      mArea := FNodePages[PageIndexOf(mNode)].Area;
      mNode.Expanded := FStateKnown and (mArea <= High(Byte)) and (Byte(mArea) in FExpandedAreas);
    end;
  end;
end;

procedure TAtlasSettingsPageTree.ShowWanted(AWanted: TTreeNode);
begin
  if AWanted = nil then
  begin
    Exit;
  end;
  if AWanted.Parent <> nil then
  begin
    AWanted.Parent.Expanded := True;
  end
  else if not FStateKnown and AWanted.HasChildren then
  begin
    AWanted.Expanded := True;
  end;
  FTree.Selected := AWanted;
  FPages.ActivePage := FNodePages[PageIndexOf(AWanted)].Sheet;
end;

procedure TAtlasSettingsPageTree.FillTree;
var
  mSelected: Integer;
  mWanted: TTreeNode;
begin
  mSelected := ActiveNode;
  if (mSelected < 0) and FStateKnown then
  begin
    mSelected := FLastPage;
  end;
  FFillingTree := True;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    mWanted := AddTreeNodes(mSelected);
    ExpandAreas;
    ShowWanted(mWanted);
  finally
    FTree.Items.EndUpdate;
    FFillingTree := False;
  end;
  RefreshTree;
end;

procedure TAtlasSettingsPageTree.RefreshTree;
var
  Index, Page: Integer;
  Node: TTreeNode;
  mText: string;
begin
  if not ListReady(FTree) then
  begin
    Exit;
  end;
  for Index := 0 to FTree.Items.Count - 1 do
  begin
    Node := FTree.Items[Index];
    Page := PageIndexOf(Node);
    if (Page < 0) or (Page > High(FNodePages)) then
    begin
      Continue;
    end;
    // Punkt wie an den Einstellungen: Auf dieser Seite ist etwas geändert.
    mText := FNodePages[Page].Caption;
    if FMarks.HasMarked(FNodePages[Page].Box) then
    begin
      mText := TAtlasSettingsMarks.Dot + mText;
    end;
    if Node.Text <> mText then
    begin
      Node.Text := mText;
    end;
  end;
  FTree.Invalidate;
end;

procedure TAtlasSettingsPageTree.TreeChange(Sender: TObject; Node: TTreeNode);
var
  Index: Integer;
begin
  Index := PageIndexOf(Node);
  if (Index < 0) or (Index > High(FNodePages)) or (csDestroying in ComponentState) then
  begin
    Exit;
  end;
  FPages.ActivePage := FNodePages[Index].Sheet;
  SheetShown(FNodePages[Index].Sheet);
  // Beim Neuaufbau des Baums wählt er selbst; gemerkt wird nur die Wahl des Nutzers.
  if FFillingTree then
  begin
    Exit;
  end;
  FLastPage := Index;
  FStateKnown := True;
end;

procedure TAtlasSettingsPageTree.TreeExpanded(Sender: TObject; Node: TTreeNode);
var
  Index, Area: Integer;
begin
  Index := PageIndexOf(Node);
  if FFillingTree or (csDestroying in ComponentState) or (Index < 0) or (Index > High(FNodePages)) then
  begin
    Exit;
  end;
  Area := FNodePages[Index].Area;
  if (Area < 0) or (Area > High(Byte)) then
  begin
    Exit;
  end;
  if Node.Expanded then
  begin
    Include(FExpandedAreas, Byte(Area));
  end
  else
  begin
    Exclude(FExpandedAreas, Byte(Area));
  end;
  FStateKnown := True;
end;

procedure TAtlasSettingsPageTree.TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
  var DefaultDraw: Boolean);
var
  Index: Integer;
begin
  DefaultDraw := True;
  // Abgeschaltete oder gesperrte Unterpunkte grau.
  Index := PageIndexOf(Node);
  if (Index >= 0) and (Index <= High(FNodePages)) and FNodePages[Index].Gray and not (cdsSelected in State) then
  begin
    Sender.Canvas.Font.Color := clGrayText;
  end;
end;

function TAtlasSettingsPageTree.IsOn(const AName: string): Boolean;
var
  Control: TControl;
begin
  // Kontrollkästchen: angehakt; Auswahl (etwa „Beim Öffnen bauen“): ein Eintrag außer dem ersten („nicht …“).
  Control := FMarks.ControlOfName(AName);
  if Control is TCheckBox then
  begin
    Result := TCheckBox(Control).Checked;
  end
  else if Control is TAtlasChoiceBox then
  begin
    Result := TAtlasChoiceBox(Control).Choice > 0;
  end
  else
  begin
    Result := True;
  end;
end;

function TAtlasSettingsPageTree.LockOfName(const AName: string): TAtlasSettingsLock;
begin
  Result := FGroups.LockOf(AName, IsOn, Part<TAtlasSettingsGeneralPart>.ExperimentalEnabled.Checked);
end;

function TAtlasSettingsPageTree.LockText(const ALock: TAtlasSettingsLock): string;
var
  Page, Entry: Integer;
  Where, mCaption: string;
begin
  Result := '';
  case ALock.Reason of
    lrExperimental:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsLockedExperimental);
    lrMasterOff:
      begin
        mCaption := FMarks.TextOfName(ALock.Master);
        if mCaption = '' then
        begin
          mCaption := FGroups.KeyOf(ALock.Master);
        end;
        Where := '';
        Page := PageOf(FMarks.ControlOfName(ALock.Master));
        if Page >= 0 then
        begin
          Where := FSheets[FNodePages[Page].Area].Caption;
          if FNodePages[Page].Node <> '' then
          begin
            Where := Where + ' › ' + FNodePages[Page].Caption;
          end;
        end
        else
        begin
          Entry := Catalog.IndexOfName(ALock.Master);
          if Entry >= 0 then
          begin
            Where := Catalog.Entries[Entry].Page;
          end;
        end;
        Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsLockedMaster, [mCaption, Where]);
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TAtlasSettingsPageTree.ApplyFrameLocks(AFrame: TAtlasSettingsGroup; ALocked: Boolean;
  var AOutside: TArray<string>);
var
  mLock: TAtlasSettingsLock;
  mMasterLocked: Boolean;
begin
  // Der Hauptschalter selbst: gesperrt durch einen Rahmen darüber, einen Schalter woanders oder experimentell.
  mLock := LockOfName(AFrame.MasterName);
  mMasterLocked := ALocked or mLock.Locked;
  SetLocked(AFrame.Master, mMasterLocked);
  if mLock.Locked and not ALocked then
  begin
    AFrame.ShowReason(LockText(mLock));
  end
  else
  begin
    AFrame.ShowReason('');
  end;
  ApplyLocks(AFrame, mMasterLocked or not IsOn(AFrame.MasterName), AOutside);
end;

function TAtlasSettingsPageTree.RowLocked(AControl: TControl; var AOutside: TArray<string>): Boolean;
var
  mAnchor: TControl;
  mLock: TAtlasSettingsLock;
  mSetting: string;
  mNames: TArray<string>;
begin
  // Zeile ohne Rahmen: ihr Hauptschalter steht auf einer anderen Seite (Grund oben auf der Seite).
  Result := False;
  mNames := FMarks.NamesWithin(AControl);
  if (Length(mNames) = 0) and FAttached.TryGetValue(AControl, mAnchor) then
  begin
    mNames := FMarks.NamesWithin(mAnchor);
  end;
  for mSetting in mNames do
  begin
    mLock := LockOfName(mSetting);
    if not mLock.Locked then
    begin
      Continue;
    end;
    Result := True;
    if mLock.Reason = lrMasterOff then
    begin
      AddUnique(AOutside, LockText(mLock));
    end;
  end;
end;

procedure TAtlasSettingsPageTree.ApplyLocks(AContainer: TWinControl; ALocked: Boolean; var AOutside: TArray<string>);
var
  mIndex: Integer;
  mControl: TControl;
  mFrame: TAtlasSettingsGroup;
begin
  for mIndex := 0 to AContainer.ControlCount - 1 do
  begin
    mControl := AContainer.Controls[mIndex];
    if (AContainer is TAtlasSettingsGroup) and ((mControl = TAtlasSettingsGroup(AContainer).Master) or
      (mControl = TAtlasSettingsGroup(AContainer).Reason)) then
    begin
      Continue;
    end;
    if mControl is TAtlasSettingsGroup then
    begin
      mFrame := TAtlasSettingsGroup(mControl);
      if not IsOverview(mFrame) and (mFrame.Master <> nil) then
      begin
        ApplyFrameLocks(mFrame, ALocked, AOutside);
      end;
    end
    else
    begin
      SetLocked(mControl, ALocked or RowLocked(mControl, AOutside));
    end;
  end;
end;

function TAtlasSettingsPageTree.PageGray(AIndex: Integer): Boolean;
var
  Box: TScrollBox;
  Index: Integer;
  Control: TControl;
  Frame: TAtlasSettingsGroup;
  Any: Boolean;
begin
  // Grau, wenn nichts auf der Seite wirkt: jeder Rahmen aus oder gesperrt, jede übrige Einstellung gesperrt.
  Box := FNodePages[AIndex].Box;
  Any := False;
  for Index := 0 to Box.ControlCount - 1 do
  begin
    Control := Box.Controls[Index];
    if Control is TAtlasSettingsGroup then
    begin
      Frame := TAtlasSettingsGroup(Control);
      if IsOverview(Frame) or (Frame.Master = nil) then
      begin
        Continue;
      end;
      Any := True;
      if Frame.Master.Enabled and IsOn(Frame.MasterName) then
      begin
        Exit(False);
      end;
    end
    else if Length(FMarks.NamesWithin(Control)) > 0 then
    begin
      Any := True;
      if Control.Enabled then
      begin
        Exit(False);
      end;
    end;
  end;
  Result := Any;
end;

procedure TAtlasSettingsPageTree.UpdateLocks;
var
  Index: Integer;
  Outside: TArray<string>;
begin
  if FGroups = nil then
  begin
    Exit;
  end;
  for Index := 0 to High(FNodePages) do
  begin
    Outside := nil;
    ApplyLocks(FNodePages[Index].Box, False, Outside);
    FNodePages[Index].Banner.Caption := string.Join(sLineBreak, Outside);
    FNodePages[Index].Banner.Visible := Length(Outside) > 0;
  end;
  // Spiegel in der Übersicht folgen ihrem Hauptschalter.
  FSyncing := True;
  try
    for Index := 0 to High(FMirrors) do
    begin
      FMirrors[Index].Checked := FMirrored[Index].Checked;
      FMirrors[Index].Enabled := FMirrored[Index].Enabled;
    end;
  finally
    FSyncing := False;
  end;
  for Index := 0 to High(FNodePages) do
  begin
    FNodePages[Index].Gray := PageGray(Index);
  end;
  RefreshTree;
end;

function TAtlasSettingsPageTree.SheetGray(ASheet: TTabSheet): Boolean;
var
  Index: Integer;
begin
  for Index := 0 to High(FNodePages) do
  begin
    if FNodePages[Index].Sheet = ASheet then
    begin
      Exit(FNodePages[Index].Gray);
    end;
  end;
  Result := False;
end;

class procedure TAtlasSettingsPageTree.ForgetTreeState;
begin
  FStateKnown := False;
  FLastPage := 0;
  FExpandedAreas := [];
end;

end.
