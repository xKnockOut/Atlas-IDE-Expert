unit Atlas.UI.Settings.Page.Nodes;

// Knoten der Optionsseite „Atlas“ (#890): verteilt die Zeilen jedes Bereichs auf Unterpunkte (x-nodes) und Rahmen
// der Hauptschalter, baut die Übersicht der Hauptknoten und hält die Seiten der Knoten mit ihren Reitern.

interface

uses
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Core.Settings.Groups,
  Atlas.UI.Settings.Group,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Seite eines Knotens im Baum (#890): der Bereich selbst (Node leer) oder ein Unterpunkt.</summary>
  TAtlasSettingsNodePage = record
    Sheet: TTabSheet;
    Box: TScrollBox;
    /// <summary>Index des Bereichs in FSheets.</summary>
    Area: Integer;
    /// <summary>Id aus x-nodes; leer = Hauptknoten des Bereichs.</summary>
    Node: string;
    Caption: string;
    /// <summary>Grund einer Sperre durch einen Hauptschalter auf einer anderen Seite.</summary>
    Banner: TLabel;
    /// <summary>Im Baum grau: nichts auf der Seite wirkt (aus oder gesperrt).</summary>
    Gray: Boolean;
  end;

  TAtlasSettingsPageNodes = class(TAtlasSettingsPageHost)
  protected
    FPages: TPageControl;
    FGroups: TAtlasSettingsGroups;
    FNodePages: TArray<TAtlasSettingsNodePage>;
    /// <summary>Spiegel der Hauptschalter in der Übersicht und ihr Original, gleicher Index.</summary>
    FMirrors: TArray<TCheckBox>;
    FMirrored: TArray<TCheckBox>;
    FSyncing: Boolean;
    /// <summary>Zeilen der Übersichten und der Rahmen, auf den jede zeigt, gleicher Index (#1903).</summary>
    FOverviewRows: TArray<TControl>;
    FOverviewFrames: TArray<TAtlasSettingsGroup>;
    /// <summary>Rahmen „Funktionen in diesem Bereich“ auf den Hauptknoten.</summary>
    FOverviews: TArray<TAtlasSettingsGroup>;
    /// <summary>Reiter der Knoten rechts vom Baum.</summary>
    procedure AddPages;
    /// <summary>Verteilt die Zeilen aller Bereiche auf Knoten und Rahmen (aus dem Schema).</summary>
    procedure BuildNodes;
    function IsOverview(AFrame: TAtlasSettingsGroup): Boolean;
  private
    FFrames: TArray<TAtlasSettingsGroup>;
    FPlaceTop: Integer;
    /// <summary>Seite des Knotens ANode im Bereich AArea; legt sie bei Bedarf an.</summary>
    function AddNodePage(AArea: Integer; const ANode: string): Integer;
    function AddNodePageCaption(AArea: Integer; const ANode, ACaption: string): Integer;
    procedure Place(AControl: TControl; AHolder: TWinControl);
    procedure BuildArea(AArea: Integer);
    procedure AddOverview(AArea: Integer);
    /// <summary>Rahmen „Funktionen in diesem Bereich“ oben auf der Seite AMain.</summary>
    function NewOverview(AMain: Integer): TAtlasSettingsGroup;
    /// <summary>Zeile der Übersicht zum Rahmen AFrame: Spiegel des Hauptschalters und „Details“ zur Seite APage.
    /// </summary>
    procedure AddOverviewRow(AOverview, AFrame: TAtlasSettingsGroup; APage: Integer);
    procedure MirrorClick(Sender: TObject);
    procedure DetailsClick(Sender: TObject);
  public
    destructor Destroy; override;
    function PageOf(AControl: TControl): Integer; override;
    function NodeBox(AArea: Integer; const ANode, ACaption: string): TScrollBox; override;
    /// <summary>Zum Testen: Rahmen des Hauptschalters AName (Registry-Name); nil ohne Rahmen.</summary>
    function FrameOf(const AName: string): TAtlasSettingsGroup;
    /// <summary>Zum Testen: Reiter des Unterpunkts ANode (Id aus x-nodes).</summary>
    function NodeSheet(const ANode: string): TTabSheet;
    /// <summary>Zum Testen: Spiegel des Hauptschalters AName in der Übersicht seines Bereichs.</summary>
    function OverviewMirror(const AName: string): TCheckBox;
    /// <summary>Id des Unterpunkts zu ASheet; leer beim Hauptknoten.</summary>
    function NodeOfSheet(ASheet: TTabSheet): string;
    /// <summary>Reiter der Seite, einer je Bereich (#227).</summary>
    property Pages: TPageControl read FPages;
    property Groups: TAtlasSettingsGroups read FGroups;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Vcl.Graphics,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Page.Sheets;

type
  /// <summary>Art einer Zeile beim Aufteilen eines Bereichs: mit Einstellung, angehängt, Beschriftung, sonst.
  /// </summary>
  TAtlasRowKind = (rkBound, rkAttached, rkLabel, rkOther);

/// <summary>Liegt AControl in AParent (oder ist es selbst)?</summary>
function Inside(AControl, AParent: TControl): Boolean;
var
  mParent: TControl;
begin
  mParent := AControl;
  while (mParent <> nil) and (mParent <> AParent) do
  begin
    mParent := mParent.Parent;
  end;
  Result := mParent <> nil;
end;

/// <summary>Zeilen von ABox in der Reihenfolge von oben nach unten.</summary>
function SortedRows(ABox: TWinControl): TArray<TControl>;
var
  mIndex, mPosition: Integer;
  mControl: TControl;
begin
  Result := nil;
  for mIndex := 0 to ABox.ControlCount - 1 do
  begin
    mControl := ABox.Controls[mIndex];
    mPosition := Length(Result);
    while (mPosition > 0) and (Result[mPosition - 1].Top > mControl.Top) do
    begin
      Dec(mPosition);
    end;
    Insert(mControl, Result, mPosition);
  end;
end;

/// <summary>Zeile nur mit einer Beschriftung (Überschrift, Hinweis, Beschriftung über einem Textfeld).</summary>
function IsLabelRow(AControl: TControl): Boolean;
begin
  Result := (AControl is TAtlasSettingsRow) and (TWinControl(AControl).ControlCount = 1) and
    (TWinControl(AControl).Controls[0] is TLabel);
end;

type
  /// <summary>Verteilt die Zeilen eines Bereichs auf die Seiten seiner Knoten und ihre Behälter (Seite oder Rahmen
  /// des Hauptschalters). Gleicher Index in allen Feldern: eine Zeile des Bereichs von oben nach unten.</summary>
  TAtlasSettingsAreaLayout = class
  private
    FPage: TAtlasSettingsPageNodes;
    FArea: Integer;
    FMain: Integer;
    FRows: TArray<TControl>;
    FKinds: TArray<TAtlasRowKind>;
    FNames: TArray<string>;
    FRowPages: TArray<Integer>;
    FHolders: TArray<TWinControl>;
    FFrames: TArray<TAtlasSettingsGroup>;
    FResolved: TArray<Boolean>;
    /// <summary>Erster Name der Zeile, den der Katalog kennt; '' ohne Einstellung.</summary>
    function KnownName(AControl: TControl): string;
    /// <summary>Hängt eine Zeile an einem Element in AControl (Liste und Knöpfe einer Funktion)?</summary>
    function HasAttached(AControl: TControl): Boolean;
    function RowOfAnchor(AAnchor: TControl): Integer;
    /// <summary>Rahmen des Hauptschalters AName, wenn er auf der Seite APage steht; sonst nil.</summary>
    function FrameFor(const AName: string; APage: Integer): TAtlasSettingsGroup;
    function KindOf(AIndex: Integer): TAtlasRowKind;
    /// <summary>Gleiche Seite und gleicher Behälter wie die Zeile AOther.</summary>
    procedure Follow(AIndex, AOther: Integer);
    procedure Classify;
    procedure AddFrames;
    procedure PlaceBound;
    procedure PlaceAttached;
    procedure PlaceOthers;
    procedure PlaceLabels;
    procedure PlaceRows;
  public
    constructor Create(APage: TAtlasSettingsPageNodes; AArea: Integer);
    procedure Run;
  end;

{ TAtlasSettingsAreaLayout }

constructor TAtlasSettingsAreaLayout.Create(APage: TAtlasSettingsPageNodes; AArea: Integer);
begin
  inherited Create;
  FPage := APage;
  FArea := AArea;
end;

function TAtlasSettingsAreaLayout.KnownName(AControl: TControl): string;
var
  mCandidate: string;
begin
  Result := '';
  for mCandidate in FPage.Marks.NamesWithin(AControl) do
  begin
    if FPage.FGroups.Contains(mCandidate) then
    begin
      Exit(mCandidate);
    end;
  end;
end;

function TAtlasSettingsAreaLayout.HasAttached(AControl: TControl): Boolean;
var
  mItem: TPair<TControl, TControl>;
begin
  for mItem in FPage.FAttached do
  begin
    if Inside(mItem.Value, AControl) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasSettingsAreaLayout.RowOfAnchor(AAnchor: TControl): Integer;
var
  mCandidate: Integer;
begin
  for mCandidate := 0 to High(FRows) do
  begin
    if Inside(AAnchor, FRows[mCandidate]) then
    begin
      Exit(mCandidate);
    end;
  end;
  Result := -1;
end;

function TAtlasSettingsAreaLayout.FrameFor(const AName: string; APage: Integer): TAtlasSettingsGroup;
var
  mCandidate: Integer;
begin
  Result := nil;
  if AName = '' then
  begin
    Exit;
  end;
  for mCandidate := 0 to High(FRows) do
  begin
    if (FFrames[mCandidate] <> nil) and (FRowPages[mCandidate] = APage) and SameText(FNames[mCandidate], AName) then
    begin
      Exit(FFrames[mCandidate]);
    end;
  end;
end;

function TAtlasSettingsAreaLayout.KindOf(AIndex: Integer): TAtlasRowKind;
begin
  Result := rkOther;
  if FNames[AIndex] <> '' then
  begin
    Result := rkBound;
  end
  else if FPage.FAttached.ContainsKey(FRows[AIndex]) then
  begin
    Result := rkAttached;
  end
  else if IsLabelRow(FRows[AIndex]) then
  begin
    Result := rkLabel;
  end;
end;

procedure TAtlasSettingsAreaLayout.Follow(AIndex, AOther: Integer);
begin
  FRowPages[AIndex] := FRowPages[AOther];
  FHolders[AIndex] := FHolders[AOther];
  FResolved[AIndex] := True;
end;

procedure TAtlasSettingsAreaLayout.Classify;
var
  mIndex: Integer;
begin
  FRows := SortedRows(FPage.Boxes[FArea]);
  FMain := FPage.AddNodePage(FArea, '');
  SetLength(FKinds, Length(FRows));
  SetLength(FNames, Length(FRows));
  SetLength(FRowPages, Length(FRows));
  SetLength(FHolders, Length(FRows));
  SetLength(FFrames, Length(FRows));
  SetLength(FResolved, Length(FRows));
  for mIndex := 0 to High(FRows) do
  begin
    FNames[mIndex] := KnownName(FRows[mIndex]);
    FRowPages[mIndex] := FMain;
    FHolders[mIndex] := FPage.FNodePages[FMain].Box;
    FFrames[mIndex] := nil;
    FResolved[mIndex] := False;
    FKinds[mIndex] := KindOf(mIndex);
  end;
end;

procedure TAtlasSettingsAreaLayout.AddFrames;
var
  mIndex: Integer;
begin
  // Unterpunkt jeder Einstellung; Hauptschalter (auch Kontrollkästchen mit angehängter Liste) bekommen einen Rahmen.
  for mIndex := 0 to High(FRows) do
  begin
    if FKinds[mIndex] <> rkBound then
    begin
      Continue;
    end;
    FRowPages[mIndex] := FPage.AddNodePage(FArea, FPage.FGroups.NodeOf(FNames[mIndex]));
    if FPage.FGroups.IsMaster(FNames[mIndex]) or ((FRows[mIndex] is TCheckBox) and HasAttached(FRows[mIndex])) then
    begin
      FFrames[mIndex] := TAtlasSettingsGroup.Create(FPage);
      FPage.FFrames := FPage.FFrames + [FFrames[mIndex]];
    end;
  end;
end;

procedure TAtlasSettingsAreaLayout.PlaceBound;
var
  mIndex: Integer;
  mFrame: TAtlasSettingsGroup;
begin
  // Behälter: der Rahmen des Hauptschalters auf derselben Seite, sonst die Seite selbst.
  for mIndex := 0 to High(FRows) do
  begin
    if FKinds[mIndex] = rkBound then
    begin
      FHolders[mIndex] := FPage.FNodePages[FRowPages[mIndex]].Box;
      mFrame := FrameFor(FPage.FGroups.ParentOf(FNames[mIndex]), FRowPages[mIndex]);
      if mFrame <> nil then
      begin
        FHolders[mIndex] := mFrame;
      end;
      FResolved[mIndex] := True;
    end;
  end;
end;

procedure TAtlasSettingsAreaLayout.PlaceAttached;
var
  mIndex, mOther: Integer;
begin
  // Zeilen ohne eigene Einstellung, die zu einer gehören (Liste, Knöpfe): in deren Rahmen.
  for mIndex := 0 to High(FRows) do
  begin
    if FKinds[mIndex] <> rkAttached then
    begin
      Continue;
    end;
    mOther := RowOfAnchor(FPage.FAttached[FRows[mIndex]]);
    if (mOther >= 0) and FResolved[mOther] then
    begin
      Follow(mIndex, mOther);
      if FFrames[mOther] <> nil then
      begin
        FHolders[mIndex] := FFrames[mOther];
      end;
    end;
  end;
end;

procedure TAtlasSettingsAreaLayout.PlaceOthers;
var
  mIndex, mPage: Integer;
begin
  // Übrige Zeilen (Serverpfad, Knöpfe des Bereichs): oben auf der Seite der Zeile davor.
  mPage := FMain;
  for mIndex := 0 to High(FRows) do
  begin
    if FResolved[mIndex] then
    begin
      mPage := FRowPages[mIndex];
    end
    else if FKinds[mIndex] <> rkLabel then
    begin
      FRowPages[mIndex] := mPage;
      FHolders[mIndex] := FPage.FNodePages[mPage].Box;
      FResolved[mIndex] := True;
    end;
  end;
end;

procedure TAtlasSettingsAreaLayout.PlaceLabels;
var
  mIndex: Integer;
begin
  // Überschriften und Beschriftungen gehören zur Zeile darunter, am Ende des Bereichs zur Zeile darüber.
  for mIndex := High(FRows) downto 0 do
  begin
    if not FResolved[mIndex] and (mIndex < High(FRows)) and FResolved[mIndex + 1] then
    begin
      Follow(mIndex, mIndex + 1);
    end;
  end;
  for mIndex := 1 to High(FRows) do
  begin
    if not FResolved[mIndex] then
    begin
      Follow(mIndex, mIndex - 1);
    end;
  end;
end;

procedure TAtlasSettingsAreaLayout.PlaceRows;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FRows) do
  begin
    if FFrames[mIndex] = nil then
    begin
      FPage.Place(FRows[mIndex], FHolders[mIndex]);
      Continue;
    end;
    FPage.Place(FFrames[mIndex], FHolders[mIndex]);
    FFrames[mIndex].SetMaster(FRows[mIndex], FNames[mIndex]);
    // Rahmen, Hauptschalter und Grund der Sperre bleiben beim Filtern stehen.
    FPage.Marks.Pin(FFrames[mIndex]);
    FPage.Marks.Pin(FRows[mIndex]);
    FPage.Marks.Pin(FFrames[mIndex].Reason);
  end;
end;

procedure TAtlasSettingsAreaLayout.Run;
begin
  Classify;
  AddFrames;
  PlaceBound;
  PlaceAttached;
  PlaceOthers;
  PlaceLabels;
  PlaceRows;
end;

{ TAtlasSettingsPageNodes }

destructor TAtlasSettingsPageNodes.Destroy;
begin
  // Elemente melden beim Abbau nichts mehr (csDestroying); danach fragt keine Sperre mehr die Gruppen.
  Destroying;
  FreeAndNil(FGroups);
  inherited Destroy;
end;

procedure TAtlasSettingsPageNodes.AddPages;
begin
  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.AlignWithMargins := True;
  FPages.Top := FPages.ScaleValue(100);
end;

function TAtlasSettingsPageNodes.AddNodePage(AArea: Integer; const ANode: string): Integer;
begin
  if ANode = '' then
  begin
    Result := AddNodePageCaption(AArea, ANode, '');
  end
  else
  begin
    Result := AddNodePageCaption(AArea, ANode,
      FGroups.NodeCaption(ANode, TAtlasStrings.Language = TAtlasLanguage.English));
  end;
end;

function TAtlasSettingsPageNodes.NodeBox(AArea: Integer; const ANode, ACaption: string): TScrollBox;
begin
  Result := FNodePages[AddNodePageCaption(AArea, ANode, ACaption)].Box;
end;

function TAtlasSettingsPageNodes.AddNodePageCaption(AArea: Integer; const ANode, ACaption: string): Integer;
var
  mPage: TAtlasSettingsNodePage;
  mIndex: Integer;
begin
  for mIndex := 0 to High(FNodePages) do
  begin
    if (FNodePages[mIndex].Area = AArea) and SameText(FNodePages[mIndex].Node, ANode) then
    begin
      Exit(mIndex);
    end;
  end;
  mPage := Default(TAtlasSettingsNodePage);
  mPage.Area := AArea;
  mPage.Node := ANode;
  if ANode = '' then
  begin
    mPage.Sheet := FSheets[AArea];
    mPage.Box := FBoxes[AArea];
    mPage.Caption := FSheets[AArea].Caption;
  end
  else
  begin
    mPage.Caption := ACaption;
    mPage.Sheet := TTabSheet.Create(Self);
    mPage.Sheet.Caption := mPage.Caption;
    mPage.Box := TScrollBox.Create(Self);
    mPage.Box.Parent := mPage.Sheet;
    mPage.Box.Align := alClient;
    mPage.Box.BorderStyle := bsNone;
    mPage.Box.ParentBackground := True;
    mPage.Box.VertScrollBar.Tracking := True;
    mPage.Box.HorzScrollBar.Visible := False;
  end;
  // Hinweis auf eine Sperre durch einen Hauptschalter auf einer anderen Seite, immer ganz oben.
  mPage.Banner := TLabel.Create(Self);
  mPage.Banner.Parent := mPage.Box;
  mPage.Banner.Align := alTop;
  mPage.Banner.AlignWithMargins := True;
  mPage.Banner.Top := 0;
  mPage.Banner.WordWrap := True;
  mPage.Banner.ShowAccelChar := False;
  mPage.Banner.Font.Style := [fsItalic];
  mPage.Banner.Visible := False;
  FMarks.Pin(mPage.Banner);
  FNodePages := FNodePages + [mPage];
  Result := High(FNodePages);
end;

procedure TAtlasSettingsPageNodes.Place(AControl: TControl; AHolder: TWinControl);
begin
  if AHolder is TAtlasSettingsGroup then
  begin
    TAtlasSettingsGroup(AHolder).AddRow(AControl);
  end
  else
  begin
    AControl.Parent := AHolder;
    AControl.Align := alTop;
    AControl.AlignWithMargins := True;
    // alTop ordnet nach Top: jede Zeile unter die vorige.
    AControl.Top := FPlaceTop;
    Inc(FPlaceTop, 100);
  end;
end;

procedure TAtlasSettingsPageNodes.BuildNodes;
var
  mArea: Integer;
  mFrame: TAtlasSettingsGroup;
  mPart: TAtlasSettingsPagePart;
begin
  FGroups := TAtlasSettingsGroups.Create(Catalog);
  for mArea := 0 to High(FSheets) do
  begin
    BuildArea(mArea);
  end;
  for mPart in FParts do
  begin
    mPart.AddNodePages;
  end;
  for mFrame in FFrames do
  begin
    if not (mFrame.Parent is TAtlasSettingsGroup) then
    begin
      mFrame.AdjustHeight;
    end;
  end;
  for mArea := 0 to High(FSheets) do
  begin
    AddOverview(mArea);
  end;
end;

procedure TAtlasSettingsPageNodes.BuildArea(AArea: Integer);
var
  mLayout: TAtlasSettingsAreaLayout;
begin
  FPlaceTop := 1000;
  mLayout := TAtlasSettingsAreaLayout.Create(Self, AArea);
  try
    mLayout.Run;
  finally
    mLayout.Free;
  end;
end;

function TAtlasSettingsPageNodes.NewOverview(AMain: Integer): TAtlasSettingsGroup;
var
  mCaption: TLabel;
begin
  Result := TAtlasSettingsGroup.Create(Self);
  FPlaceTop := 100000;
  Place(Result, FNodePages[AMain].Box);
  mCaption := TLabel.Create(Self);
  mCaption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsOverviewTitle);
  mCaption.Font.Style := [fsBold];
  Result.SetMaster(mCaption, '');
  FOverviews := FOverviews + [Result];
  FMarks.Pin(Result);
end;

procedure TAtlasSettingsPageNodes.AddOverviewRow(AOverview, AFrame: TAtlasSettingsGroup; APage: Integer);
var
  mRow: TWinControl;
  mDetails, mCaption: TLabel;
  mMirror: TCheckBox;
begin
  mRow := TAtlasSettingsRow.Create(Self);
  mRow.Height := mRow.ScaleValue(24);
  AOverview.AddRow(mRow);
  FOverviewRows := FOverviewRows + [mRow];
  FOverviewFrames := FOverviewFrames + [AFrame];
  mDetails := TLabel.Create(Self);
  mDetails.Parent := mRow;
  mDetails.Align := alRight;
  mDetails.AlignWithMargins := True;
  mDetails.Layout := tlCenter;
  mDetails.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsOverviewDetails);
  mDetails.Font.Style := [fsUnderline];
  mDetails.Font.Color := clHotLight;
  mDetails.Cursor := crHandPoint;
  mDetails.Tag := APage;
  mDetails.OnClick := DetailsClick;
  if AFrame.Master is TCheckBox then
  begin
    mMirror := TCheckBox.Create(Self);
    mMirror.Parent := mRow;
    mMirror.Align := alClient;
    mMirror.Caption := FMarks.TextOfName(AFrame.MasterName);
    mMirror.Tag := Length(FMirrors);
    mMirror.OnClick := MirrorClick;
    FMirrors := FMirrors + [mMirror];
    FMirrored := FMirrored + [TCheckBox(AFrame.Master)];
  end
  else
  begin
    mCaption := TLabel.Create(Self);
    mCaption.Parent := mRow;
    mCaption.Align := alClient;
    mCaption.Layout := tlCenter;
    mCaption.Caption := FMarks.TextOfName(AFrame.MasterName);
  end;
end;

procedure TAtlasSettingsPageNodes.AddOverview(AArea: Integer);
var
  mOverview, mFrame: TAtlasSettingsGroup;
  mMain, mIndex, mChild: Integer;
  mBox: TScrollBox;
begin
  // Hauptknoten: je Hauptschalter der Unterpunkte eine Zeile mit Spiegel und „Details“.
  mMain := AddNodePage(AArea, '');
  mOverview := nil;
  for mIndex := 0 to High(FNodePages) do
  begin
    if (FNodePages[mIndex].Area <> AArea) or (FNodePages[mIndex].Node = '') then
    begin
      Continue;
    end;
    mBox := FNodePages[mIndex].Box;
    for mChild := 0 to mBox.ControlCount - 1 do
    begin
      if not (mBox.Controls[mChild] is TAtlasSettingsGroup) or
        (TAtlasSettingsGroup(mBox.Controls[mChild]).Master = nil) then
      begin
        Continue;
      end;
      mFrame := TAtlasSettingsGroup(mBox.Controls[mChild]);
      if mOverview = nil then
      begin
        mOverview := NewOverview(mMain);
      end;
      AddOverviewRow(mOverview, mFrame, mIndex);
    end;
  end;
  if mOverview <> nil then
  begin
    mOverview.AdjustHeight;
  end;
end;

procedure TAtlasSettingsPageNodes.MirrorClick(Sender: TObject);
var
  mIndex: Integer;
begin
  if FSyncing or not (Sender is TCheckBox) then
  begin
    Exit;
  end;
  mIndex := TCheckBox(Sender).Tag;
  if (mIndex >= 0) and (mIndex <= High(FMirrored)) then
  begin
    FMirrored[mIndex].Checked := TCheckBox(Sender).Checked;
  end;
end;

procedure TAtlasSettingsPageNodes.DetailsClick(Sender: TObject);
begin
  if Sender is TControl then
  begin
    SelectPage(TControl(Sender).Tag);
  end;
end;

function TAtlasSettingsPageNodes.IsOverview(AFrame: TAtlasSettingsGroup): Boolean;
var
  mOverview: TAtlasSettingsGroup;
begin
  for mOverview in FOverviews do
  begin
    if mOverview = AFrame then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasSettingsPageNodes.PageOf(AControl: TControl): Integer;
var
  mParent: TControl;
  mIndex: Integer;
begin
  Result := -1;
  mParent := AControl;
  while (mParent <> nil) and not (mParent is TTabSheet) do
  begin
    mParent := mParent.Parent;
  end;
  if mParent = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FNodePages) do
  begin
    if FNodePages[mIndex].Sheet = mParent then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TAtlasSettingsPageNodes.FrameOf(const AName: string): TAtlasSettingsGroup;
var
  mFrame: TAtlasSettingsGroup;
begin
  for mFrame in FFrames do
  begin
    if SameText(mFrame.MasterName, AName) then
    begin
      Exit(mFrame);
    end;
  end;
  Result := nil;
end;

function TAtlasSettingsPageNodes.NodeSheet(const ANode: string): TTabSheet;
var
  mPage: TAtlasSettingsNodePage;
begin
  for mPage in FNodePages do
  begin
    if (ANode <> '') and SameText(mPage.Node, ANode) then
    begin
      Exit(mPage.Sheet);
    end;
  end;
  Result := nil;
end;

function TAtlasSettingsPageNodes.OverviewMirror(const AName: string): TCheckBox;
var
  mFrame: TAtlasSettingsGroup;
  mIndex: Integer;
begin
  Result := nil;
  mFrame := FrameOf(AName);
  if mFrame = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FMirrored) do
  begin
    if FMirrored[mIndex] = mFrame.Master then
    begin
      Exit(FMirrors[mIndex]);
    end;
  end;
end;

function TAtlasSettingsPageNodes.NodeOfSheet(ASheet: TTabSheet): string;
var
  mPage: TAtlasSettingsNodePage;
begin
  for mPage in FNodePages do
  begin
    if mPage.Sheet = ASheet then
    begin
      Exit(mPage.Node);
    end;
  end;
  Result := '';
end;

end.
