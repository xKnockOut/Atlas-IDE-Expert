unit Atlas.UI.Welcome.Board;

// Alle Atlas-Bereiche in einem Frame (#753): oben der Kopf (abschaltbar),
// darunter die Bereiche in Spalten nach TAtlasWelcomeLayout.Cells. Im
// Atlas-Layout steht dieser Frame als ein Bereich „Atlas“ oben auf der
// Willkommensseite, im Fenster „Atlas-Start“ mit derselben Anordnung, die
// bei schmalem Fenster Spalten untereinander faltet (AutoFold). Der Inhalt
// scrollt, wenn er höher ist als der Platz. Rebuild legt die Bereichs-Frames
// über TAtlasWelcomeViews an und behält vorhandene, solange ihr Bereich
// sichtbar bleibt.
// Frei anordnen (#767), mit Source und welcomePage.customLayout:
// - Leiste unter dem Kopf: Stift „Seite anpassen“/„Fertig“ und
//   Layout-Umschalter; im Bearbeitungsmodus dazu Spalten, „Bereich
//   hinzufügen“ und „Zurücksetzen“.
// - Im Bearbeitungsmodus je Bereich Griff (Ziehen, Strg+Pfeiltasten), Breite
//   und Auge; eine Einfügelinie zeigt das Ziel (ohne Ziehen: Ende der Spalte
//   mit dem meisten Platz, ein Klick auf freie Fläche setzt sie); unten die
//   Leiste „Ausgeblendet“ zum Einblenden per Klick oder Ziehen.
// - Rechtsklick auf einen Bereich: „Ausblenden“ (wie #628, mit
//   „Rückgängig“), „Einstellungen dazu …“ und „Seite anpassen“.
// Zweispaltige Bereiche und die Reihenfolge rechnet TAtlasWelcomeFlow.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Layout,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Header,
  Atlas.UI.Welcome.Arrange;

type
  /// <summary>Name abfragen (Neues Layout, Umbenennen); False = abgebrochen.</summary>
  TAtlasWelcomeAskName = reference to function(const APrompt: string; var AName: string): Boolean;
  /// <summary>Rückfrage bzw. Hinweis; True = ja.</summary>
  TAtlasWelcomeConfirm = reference to function(const AText: string; AQuestion: Boolean): Boolean;

  TAtlasWelcomeBoardFrame = class(TAtlasWelcomeFrame)
  public const
    Gap = 12;
    /// <summary>Mindestbreite einer Spalte beim Verteilen.</summary>
    MinColumnWidth = 120;
    /// <summary>Mit AutoFold: schmaler als das faltet eine Spalte unter die vorige.</summary>
    FoldWidth = 280;
  private
    FHeader: TAtlasWelcomeHeaderFrame;
    FBar: TAtlasArrangeStrip;
    FScroll: TScrollBox;
    FHiddenBar: TAtlasArrangeStrip;
    FInsertLine: TPanel;
    FViews: TObjectDictionary<string, TAtlasWelcomeSectionFrame>;
    FColumns: TArray<TArray<string>>;
    FCells: TAtlasWelcomeCells;
    FPlaced: TArray<TAtlasWelcomePlaced>;
    FSections: TArray<TAtlasWelcomeSection>;
    FLayout: TAtlasWelcomeLayout;
    FWanted: Integer;
    FAutoFold: Boolean;
    FPlacing: Boolean;
    FSource: IAtlasWelcomeArrangeSource;
    FCanCustomize: Boolean;
    FEditing: Boolean;
    FCatalog: TArray<TAtlasWelcomeCatalogEntry>;
    FLayoutNames: TArray<string>;
    FActiveLayout: string;
    FTargetColumn: Integer;
    FTargetBefore: string;
    FDragId: string;
    FDragHidden: Boolean;
    FDropValid: Boolean;
    FSectionMenu: TPopupMenu;
    FMenuId: string;
    FBarMenu: TPopupMenu;
    FOnAskName: TAtlasWelcomeAskName;
    FOnConfirm: TAtlasWelcomeConfirm;
    procedure ScrollResize(Sender: TObject);
    procedure ScrollMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ViewHeightChanged(Sender: TObject);
    procedure Place;
    procedure ReadSource;
    procedure ApplyEditing;
    procedure UpdateBars;
    procedure UpdateInsertLine;
    function ViewSections: TArray<TAtlasWelcomeSection>;
    function CatalogIndex(const AId: string): Integer;
    procedure Later(const AProc: TProc<IAtlasWelcomeArrangeSource>);
    procedure Rearranged(const ALayout: TAtlasWelcomeLayout);
    procedure BarClick(const APart: TAtlasArrangePart);
    procedure HiddenClick(const APart: TAtlasArrangePart);
    procedure DragStart(const AId: string; AHidden: Boolean);
    procedure DragMove(const AScreen: TPoint);
    procedure DragEnd(ADrop: Boolean);
    function GripMove(const AId: string; ADirection: TAtlasWelcomeMove): Boolean;
    procedure ToolClick(const AId: string; ATool: TAtlasWelcomeTool);
    procedure SectionMenuPopup(Sender: TObject);
    procedure SectionMenuHide(Sender: TObject);
    procedure SectionMenuSettings(Sender: TObject);
    procedure SectionMenuCustomize(Sender: TObject);
    procedure LayoutMenuSwitch(Sender: TObject);
    procedure LayoutMenuNew(Sender: TObject);
    procedure LayoutMenuRename(Sender: TObject);
    procedure LayoutMenuDelete(Sender: TObject);
    procedure AddMenuClick(Sender: TObject);
    function AskName(const APrompt: string; var AName: string): Boolean;
    function Confirm(const AText: string; AQuestion: Boolean): Boolean;
    function NameTaken(const AName: string): Boolean;
    function SectionIdOf(AComponent: TComponent): string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Bereiche neu verteilen: ASections (sichtbare, mit Titel) nach ALayout in AColumns Spalten
    /// (mit AutoFold höchstens so viele, wie nebeneinander passen).</summary>
    procedure Rebuild(const ASections: TArray<TAtlasWelcomeSection>; const ALayout: TAtlasWelcomeLayout;
      AColumns: Integer);
    /// <summary>Inhalt eines Bereichs nachführen; '' = alle.</summary>
    procedure UpdateSection(const AId: string);
    procedure UpdateContent; override;
    function View(const AId: string): TAtlasWelcomeSectionFrame;
    /// <summary>Griff bzw. Werkzeuge eines Bereichs im Bearbeitungsmodus; nil ohne.</summary>
    function GripOf(const AId: string): TAtlasWelcomeGrip;
    function ToolsOf(const AId: string): TAtlasWelcomeSectionTools;
    /// <summary>Menü „Layout“ bzw. „Bereich hinzufügen“ füllen, ohne es zu zeigen (auch für Tests).</summary>
    procedure BuildLayoutMenu;
    procedure BuildAddMenu;
    /// <summary>Kontextmenü für den Bereich AId vorbereiten (auch für Tests).</summary>
    procedure PrepareSectionMenu(const AId: string);
    /// <summary>Einfügelinie setzen: Spalte und Bereich, vor dem eingefügt wird ('' = ans Ende); -1 = Vorgabe
    /// (Ende der Spalte mit dem meisten Platz).</summary>
    procedure SetTarget(AColumn: Integer; const ABefore: string);
    /// <summary>Ziel der Einfügelinie.</summary>
    procedure Target(out AColumn: Integer; out ABefore: string);
    /// <summary>Kennungen je Spalte, wie zuletzt verteilt.</summary>
    property Columns: TArray<TArray<string>> read FColumns;
    property Header: TAtlasWelcomeHeaderFrame read FHeader;
    /// <summary>Layout, wie zuletzt gesetzt bzw. lokal bearbeitet.</summary>
    property Layout: TAtlasWelcomeLayout read FLayout;
    property Placed: TArray<TAtlasWelcomePlaced> read FPlaced;
    /// <summary>Fenster „Atlas-Start“: Spalten falten, wenn sie schmaler als FoldWidth würden.</summary>
    property AutoFold: Boolean read FAutoFold write FAutoFold;
    /// <summary>„Seite anpassen“ (#767); nil = ohne Leiste und Bearbeitungsmodus. Vor Rebuild setzen.</summary>
    property Source: IAtlasWelcomeArrangeSource read FSource write FSource;
    property Editing: Boolean read FEditing;
    property Bar: TAtlasArrangeStrip read FBar;
    property HiddenBar: TAtlasArrangeStrip read FHiddenBar;
    property InsertLine: TPanel read FInsertLine;
    property SectionMenu: TPopupMenu read FSectionMenu;
    property BarMenu: TPopupMenu read FBarMenu;
    property OnAskName: TAtlasWelcomeAskName read FOnAskName write FOnAskName;
    property OnConfirm: TAtlasWelcomeConfirm read FOnConfirm write FOnConfirm;
  end;

implementation

uses
  Winapi.Windows,
  System.UITypes,
  Vcl.Graphics,
  Vcl.Dialogs,
  Vcl.Themes,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.UI.Strings;

const
  // Tag der Einträge im Kontextmenü eines Bereichs.
  TagHide = 1;
  TagSettings = 2;
  TagCustomize = 3;

/// <summary>AValue logische Pixel in der Auflösung von AControl.</summary>
function Scaled(AControl: TControl; AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, AControl.CurrentPPI, 96);
end;

{ TAtlasWelcomeBoardFrame }

constructor TAtlasWelcomeBoardFrame.Create(AOwner: TComponent);
var
  Item: TMenuItem;
begin
  inherited Create(AOwner);
  FViews := TObjectDictionary<string, TAtlasWelcomeSectionFrame>.Create([doOwnsValues]);
  FTargetColumn := -1;
  FWanted := 2;
  FLayout := TAtlasWelcomeLayout.Atlas;
  FHeader := TAtlasWelcomeHeaderFrame.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := alTop;
  FBar := TAtlasArrangeStrip.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.Top := FHeader.Top + FHeader.Height;
  FBar.Visible := False;
  FBar.OnPartClick :=
    procedure(const APart: TAtlasArrangePart)
    begin
      BarClick(APart);
    end;
  FHiddenBar := TAtlasArrangeStrip.Create(Self);
  FHiddenBar.Parent := Self;
  FHiddenBar.Align := alBottom;
  FHiddenBar.Visible := False;
  FHiddenBar.OnPartClick :=
    procedure(const APart: TAtlasArrangePart)
    begin
      HiddenClick(APart);
    end;
  FHiddenBar.OnDragStart :=
    procedure(const APart: TAtlasArrangePart)
    begin
      DragStart(APart.Value, True);
    end;
  FHiddenBar.OnDragMove :=
    procedure(APoint: TPoint)
    begin
      DragMove(APoint);
    end;
  FHiddenBar.OnDragEnd :=
    procedure(ADrop: Boolean)
    begin
      DragEnd(ADrop);
    end;
  FScroll := TScrollBox.Create(Self);
  FScroll.Parent := Self;
  FScroll.Align := alClient;
  FScroll.BorderStyle := bsNone;
  FScroll.ParentBackground := True;
  FScroll.VertScrollBar.Tracking := True;
  FScroll.OnResize := ScrollResize;
  FScroll.OnMouseDown := ScrollMouseDown;
  FInsertLine := TPanel.Create(Self);
  FInsertLine.Parent := FScroll;
  FInsertLine.BevelOuter := bvNone;
  FInsertLine.ParentBackground := False;
  FInsertLine.StyleElements := [];
  FInsertLine.Color := clHighlight;
  FInsertLine.Height := 3;
  FInsertLine.Visible := False;
  FSectionMenu := TPopupMenu.Create(Self);
  FSectionMenu.OnPopup := SectionMenuPopup;
  Item := TMenuItem.Create(FSectionMenu);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeHide);
  Item.Tag := TagHide;
  Item.OnClick := SectionMenuHide;
  FSectionMenu.Items.Add(Item);
  Item := TMenuItem.Create(FSectionMenu);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeSettings);
  Item.Tag := TagSettings;
  Item.OnClick := SectionMenuSettings;
  FSectionMenu.Items.Add(Item);
  Item := TMenuItem.Create(FSectionMenu);
  Item.Caption := '-';
  FSectionMenu.Items.Add(Item);
  Item := TMenuItem.Create(FSectionMenu);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeCustomize);
  Item.Tag := TagCustomize;
  Item.OnClick := SectionMenuCustomize;
  FSectionMenu.Items.Add(Item);
  FBarMenu := TPopupMenu.Create(Self);
end;

destructor TAtlasWelcomeBoardFrame.Destroy;
begin
  // Die Bereichs-Frames gehören dem Wörterbuch, nicht dem Frame.
  FreeAndNil(FViews);
  FSource := nil;
  inherited;
end;

function TAtlasWelcomeBoardFrame.View(const AId: string): TAtlasWelcomeSectionFrame;
begin
  if (FViews = nil) or not FViews.TryGetValue(LowerCase(AId), Result) then
    Result := nil;
end;

function TAtlasWelcomeBoardFrame.GripOf(const AId: string): TAtlasWelcomeGrip;
var
  Frame: TAtlasWelcomeSectionFrame;
  Index: Integer;
begin
  Result := nil;
  Frame := View(AId);
  if Frame = nil then
    Exit;
  for Index := 0 to Frame.TitleBar.ControlCount - 1 do
    if Frame.TitleBar.Controls[Index] is TAtlasWelcomeGrip then
      Exit(TAtlasWelcomeGrip(Frame.TitleBar.Controls[Index]));
end;

function TAtlasWelcomeBoardFrame.ToolsOf(const AId: string): TAtlasWelcomeSectionTools;
var
  Frame: TAtlasWelcomeSectionFrame;
  Index: Integer;
begin
  Result := nil;
  Frame := View(AId);
  if Frame = nil then
    Exit;
  for Index := 0 to Frame.TitleBar.ControlCount - 1 do
    if Frame.TitleBar.Controls[Index] is TAtlasWelcomeSectionTools then
      Exit(TAtlasWelcomeSectionTools(Frame.TitleBar.Controls[Index]));
end;

procedure TAtlasWelcomeBoardFrame.ReadSource;
begin
  FCanCustomize := False;
  FEditing := False;
  FCatalog := nil;
  FLayoutNames := nil;
  FActiveLayout := '';
  if FSource = nil then
    Exit;
  FCanCustomize := FSource.CanCustomize;
  FEditing := FCanCustomize and FSource.Editing;
  FCatalog := FSource.Catalog;
  FLayoutNames := FSource.LayoutNames;
  FActiveLayout := FSource.ActiveLayout;
end;

procedure TAtlasWelcomeBoardFrame.Rebuild(const ASections: TArray<TAtlasWelcomeSection>;
  const ALayout: TAtlasWelcomeLayout; AColumns: Integer);
var
  Wanted: TDictionary<string, Boolean>;
  Section: TAtlasWelcomeSection;
  Key: string;
  Frame: TAtlasWelcomeSectionFrame;
begin
  FSections := ASections;
  FLayout := ALayout;
  FWanted := AColumns;
  ReadSource;
  Wanted := TDictionary<string, Boolean>.Create;
  try
    for Section in ASections do
    begin
      Key := LowerCase(Section.Id);
      Wanted.AddOrSetValue(Key, True);
      if not FViews.TryGetValue(Key, Frame) then
      begin
        // Ohne Besitzer: Das Wörterbuch gibt die Frames frei.
        Frame := TAtlasWelcomeViews.CreateView(Section.Id, nil);
        if Frame = nil then
          Continue;
        Frame.Parent := FScroll;
        Frame.OnHeightChanged := ViewHeightChanged;
        FViews.Add(Key, Frame);
        Frame.UpdateContent;
      end;
      Frame.ShowTitle := True;
      Frame.Title := Section.Title;
    end;
    for Key in FViews.Keys.ToArray do
      if not Wanted.ContainsKey(Key) then
        FViews.Remove(Key);
  finally
    Wanted.Free;
  end;
  // Ein Ziel, dessen Bereich verschwunden ist, gilt nicht mehr.
  if (FTargetBefore <> '') and (View(FTargetBefore) = nil) then
    FTargetColumn := -1;
  ApplyEditing;
  UpdateBars;
  Place;
end;

function TAtlasWelcomeBoardFrame.ViewSections: TArray<TAtlasWelcomeSection>;
var
  Section: TAtlasWelcomeSection;
begin
  Result := nil;
  for Section in FSections do
    if View(Section.Id) <> nil then
      Result := Result + [Section];
end;

function TAtlasWelcomeBoardFrame.CatalogIndex(const AId: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(FCatalog) do
    if SameText(FCatalog[Index].Id, AId) then
      Exit(Index);
  Result := -1;
end;

procedure TAtlasWelcomeBoardFrame.ApplyEditing;
var
  Pair: TPair<string, TAtlasWelcomeSectionFrame>;
  Frame: TAtlasWelcomeSectionFrame;
  Grip: TAtlasWelcomeGrip;
  Tools: TAtlasWelcomeSectionTools;
begin
  for Pair in FViews do
  begin
    Frame := Pair.Value;
    Grip := GripOf(Frame.SectionId);
    Tools := ToolsOf(Frame.SectionId);
    if FEditing then
    begin
      if Grip = nil then
      begin
        Grip := TAtlasWelcomeGrip.Create(Frame);
        Grip.Parent := Frame.TitleBar;
        Grip.Align := alLeft;
        Grip.Width := Scaled(Frame, TAtlasWelcomeGrip.GripWidth);
        Grip.SectionId := Frame.SectionId;
        Grip.OnMove := GripMove;
        Grip.OnDragStart :=
          procedure(AId: string)
          begin
            DragStart(AId, False);
          end;
        Grip.OnDragMove :=
          procedure(APoint: TPoint)
          begin
            DragMove(APoint);
          end;
        Grip.OnDragEnd :=
          procedure(ADrop: Boolean)
          begin
            DragEnd(ADrop);
          end;
      end;
      if Tools = nil then
      begin
        Tools := TAtlasWelcomeSectionTools.Create(Frame);
        Tools.Parent := Frame.TitleBar;
        Tools.Align := alRight;
        Tools.Width := Scaled(Frame, 2 * TAtlasWelcomeSectionTools.ToolWidth);
        Tools.SectionId := Frame.SectionId;
        Tools.OnTool :=
          procedure(AId: string; ATool: TAtlasWelcomeTool)
          begin
            ToolClick(AId, ATool);
          end;
      end;
      Tools.Wide := FLayout.WidthOf(Frame.SectionId) > 1;
      Tools.Invalidate;
      Frame.TitleLabel.Left := Grip.Width + Scaled(Frame, 4);
    end
    else
    begin
      Grip.Free;
      Tools.Free;
      Frame.TitleLabel.Left := 2;
    end;
    // Rechtsklick „Ausblenden“ (#628-Weg) an Titel und Fläche des Bereichs.
    if FSource <> nil then
    begin
      Frame.TitleBar.PopupMenu := FSectionMenu;
      if Frame.PopupMenu = nil then
        Frame.PopupMenu := FSectionMenu;
    end
    else
    begin
      if Frame.TitleBar.PopupMenu = FSectionMenu then
        Frame.TitleBar.PopupMenu := nil;
      if Frame.PopupMenu = FSectionMenu then
        Frame.PopupMenu := nil;
    end;
  end;
end;

procedure TAtlasWelcomeBoardFrame.UpdateBars;
var
  Parts: TArray<TAtlasArrangePart>;
  Entry: TAtlasWelcomeCatalogEntry;
  Count: Integer;
  Any: Boolean;
begin
  Parts := nil;
  if FCanCustomize then
  begin
    if FEditing then
      Parts := Parts + [TAtlasArrangePart.Create(TAtlasArrangePartKind.Edit, '',
        TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeDone), '', True)]
    else
      Parts := Parts + [TAtlasArrangePart.Create(TAtlasArrangePartKind.Edit, '',
        '✎ ' + TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeCustomize),
        TAtlasStrings.Text(TAtlasTextId.CommandWelcomeCustomize), False)];
    // Umschalter im Kopf: mit mehreren Layouts immer, sonst nur beim Bearbeiten (dort Neu/Umbenennen).
    if FEditing or (Length(FLayoutNames) > 1) then
      Parts := Parts + [TAtlasArrangePart.Create(TAtlasArrangePartKind.Layout, '',
        TAtlasStrings.Fmt(TAtlasTextId.WelcomeArrangeLayout, [FActiveLayout]) + ' ▾', '', False)];
    if FEditing then
    begin
      Parts := Parts + [TAtlasArrangePart.Create(TAtlasArrangePartKind.Text, '',
        TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeColumns), '', False)];
      for Count := TAtlasWelcomeLayout.MinColumns to TAtlasWelcomeLayout.MaxColumns do
        Parts := Parts + [TAtlasArrangePart.Create(TAtlasArrangePartKind.Column, IntToStr(Count), IntToStr(Count),
          '', FLayout.Columns = Count)];
      Parts := Parts + [TAtlasArrangePart.Create(TAtlasArrangePartKind.Add, '',
        TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeAdd) + ' ▾', '', False),
        TAtlasArrangePart.Create(TAtlasArrangePartKind.Reset, '', TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeReset),
        TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeResetHint), False)];
    end;
  end;
  FBar.SetParts(Parts);
  FBar.Visible := Length(Parts) > 0;
  // Ausgeblendet: angemeldete Bereiche, deren Einstellung aus ist.
  Parts := [TAtlasArrangePart.Create(TAtlasArrangePartKind.Text, '',
    TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeHidden), '', False)];
  Any := False;
  for Entry in FCatalog do
    if not Entry.Shown then
    begin
      Parts := Parts + [TAtlasArrangePart.Create(TAtlasArrangePartKind.Hidden, Entry.Id, Entry.Title + ' +',
        TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeShowHint), False)];
      Any := True;
    end;
  if not Any then
    Parts := Parts + [TAtlasArrangePart.Create(TAtlasArrangePartKind.Text, '',
      TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeHiddenNone), '', False)];
  FHiddenBar.SetParts(Parts);
  FHiddenBar.Visible := FEditing;
  FInsertLine.Visible := FEditing;
end;

procedure TAtlasWelcomeBoardFrame.ScrollResize(Sender: TObject);
begin
  Place;
end;

procedure TAtlasWelcomeBoardFrame.ViewHeightChanged(Sender: TObject);
begin
  Place;
end;

procedure TAtlasWelcomeBoardFrame.Place;
var
  Count, Position: Integer;
  Item: TAtlasWelcomePlaced;
  Frame: TAtlasWelcomeSectionFrame;
  Column: Integer;
  Cell: TAtlasWelcomeCell;
begin
  if FPlacing or (FViews = nil) then
    Exit;
  FPlacing := True;
  try
    if FBar.Visible then
      FBar.Height := FBar.PreferredHeight;
    if FHiddenBar.Visible then
      FHiddenBar.Height := FHiddenBar.PreferredHeight;
    Count := FWanted;
    if FAutoFold and (FScroll.ClientWidth > 0) then
      Count := TAtlasWelcomeFlow.FitColumns(FWanted, FScroll.ClientWidth, Gap, FoldWidth);
    FCells := FLayout.Cells(ViewSections, Count);
    FColumns := nil;
    SetLength(FColumns, Length(FCells));
    for Column := 0 to High(FCells) do
      for Cell in FCells[Column] do
        FColumns[Column] := FColumns[Column] + [Cell.Id];
    // Breite zuerst: Bereiche mit umbrechendem Text (#756) berechnen ihre Höhe danach.
    FPlaced := TAtlasWelcomeFlow.Place(FCells, FScroll.ClientWidth, Gap, MinColumnWidth,
      function(const AId: string; AWidth: Integer): Integer
      var
        View_: TAtlasWelcomeSectionFrame;
      begin
        Result := 0;
        View_ := View(AId);
        if View_ = nil then
          Exit;
        View_.Width := AWidth;
        Result := View_.PreferredHeight;
      end);
    Position := FScroll.VertScrollBar.Position;
    for Item in FPlaced do
    begin
      Frame := View(Item.Id);
      if Frame <> nil then
        Frame.SetBounds(Item.Left, Item.Top - Position, Item.Width, Item.Height);
    end;
    UpdateInsertLine;
  finally
    FPlacing := False;
  end;
end;

procedure TAtlasWelcomeBoardFrame.Target(out AColumn: Integer; out ABefore: string);
begin
  AColumn := FTargetColumn;
  ABefore := FTargetBefore;
  if (AColumn < 0) or (AColumn > High(FCells)) then
  begin
    // Vorgabe: Ende der Spalte mit dem meisten Platz.
    AColumn := TAtlasWelcomeFlow.ShortestColumn(FCells, FPlaced, Gap);
    ABefore := '';
  end;
end;

procedure TAtlasWelcomeBoardFrame.SetTarget(AColumn: Integer; const ABefore: string);
begin
  FTargetColumn := AColumn;
  FTargetBefore := ABefore;
  if AColumn < 0 then
    FTargetBefore := '';
  UpdateInsertLine;
end;

procedure TAtlasWelcomeBoardFrame.UpdateInsertLine;
var
  Column, mLeft, mTop, mWidth: Integer;
  Before: string;
begin
  if not FEditing then
  begin
    FInsertLine.Visible := False;
    Exit;
  end;
  Target(Column, Before);
  TAtlasWelcomeFlow.InsertLine(FCells, FPlaced, FScroll.ClientWidth, Gap, MinColumnWidth, Column, Before, mLeft,
    mTop, mWidth);
  FInsertLine.SetBounds(mLeft, mTop - 1 - FScroll.VertScrollBar.Position, mWidth, 3);
  FInsertLine.Color := StyleServices(Self).GetSystemColor(clHighlight);
  FInsertLine.Visible := True;
  FInsertLine.BringToFront;
end;

procedure TAtlasWelcomeBoardFrame.ScrollMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Column: Integer;
  Before: string;
begin
  // Klick auf freie Fläche setzt die Einfügelinie für „Bereich hinzufügen“ und „Ausgeblendet“.
  if not FEditing or (Button <> mbLeft) then
    Exit;
  TAtlasWelcomeFlow.DropTarget(FCells, FPlaced, FScroll.ClientWidth, Gap, MinColumnWidth, X,
    Y + FScroll.VertScrollBar.Position, '', Column, Before);
  SetTarget(Column, Before);
end;

procedure TAtlasWelcomeBoardFrame.Later(const AProc: TProc<IAtlasWelcomeArrangeSource>);
var
  Source_: IAtlasWelcomeArrangeSource;
begin
  Source_ := FSource;
  if Source_ = nil then
    Exit;
  // Über die Nachrichtenschleife: Der Aufruf baut die Tafel neu auf und gäbe sonst das klickende Element frei.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.WelcomePage,
        procedure
        begin
          AProc(Source_);
        end);
    end);
end;

procedure TAtlasWelcomeBoardFrame.Rearranged(const ALayout: TAtlasWelcomeLayout);
var
  Layout_: TAtlasWelcomeLayout;
begin
  if TAtlasWelcomeLayout.Same(ALayout, FLayout) then
    Exit;
  // Sofort zeigen (mehrere Strg+Pfeiltasten hintereinander), gespeichert wird über die Quelle. Eine andere
  // Spaltenzahl gilt gleich mit: Place verteilt auf FWanted, das sonst erst der nächste Rebuild setzt.
  if ALayout.Columns <> FLayout.Columns then
    FWanted := ALayout.Columns;
  FLayout := ALayout;
  Layout_ := ALayout;
  ApplyEditing;
  UpdateBars;
  Place;
  Later(
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.Arrange(Layout_);
    end);
end;

function TAtlasWelcomeBoardFrame.GripMove(const AId: string; ADirection: TAtlasWelcomeMove): Boolean;
var
  Moved: TAtlasWelcomeLayout;
  Grip: TAtlasWelcomeGrip;
begin
  Result := FEditing and FLayout.MovedBy(AId, ADirection, ViewSections, Moved);
  if not Result then
    Exit;
  Rearranged(Moved);
  // Der Fokus bleibt am Griff des verschobenen Bereichs.
  Grip := GripOf(AId);
  // Nur mit sichtbarer Form: CanFocus allein lässt eine verborgene durch („kann den Fokus nicht erhalten“).
  if (Grip <> nil) and Grip.CanFocus and not Grip.Focused and (GetParentForm(Grip) <> nil) and GetParentForm(Grip).Visible then
    Grip.SetFocus;
end;

procedure TAtlasWelcomeBoardFrame.ToolClick(const AId: string; ATool: TAtlasWelcomeTool);
var
  Id: string;
begin
  case ATool of
    TAtlasWelcomeTool.Width:
      Rearranged(FLayout.WithWidth(AId, 3 - FLayout.WidthOf(AId)));
    TAtlasWelcomeTool.Eye:
      begin
        Id := AId;
        Later(
          procedure(ASource: IAtlasWelcomeArrangeSource)
          begin
            ASource.HideSection(Id);
          end);
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TAtlasWelcomeBoardFrame.DragStart(const AId: string; AHidden: Boolean);
begin
  if not FEditing then
    Exit;
  FDragId := AId;
  FDragHidden := AHidden;
  FDropValid := False;
end;

procedure TAtlasWelcomeBoardFrame.DragMove(const AScreen: TPoint);
var
  Local: TPoint;
  Column: Integer;
  Before: string;
begin
  if FDragId = '' then
    Exit;
  Local := FScroll.ScreenToClient(AScreen);
  FDropValid := PtInRect(FScroll.ClientRect, Local);
  if not FDropValid then
    Exit;
  TAtlasWelcomeFlow.DropTarget(FCells, FPlaced, FScroll.ClientWidth, Gap, MinColumnWidth, Local.X,
    Local.Y + FScroll.VertScrollBar.Position, FDragId, Column, Before);
  SetTarget(Column, Before);
end;

procedure TAtlasWelcomeBoardFrame.DragEnd(ADrop: Boolean);
var
  Id, Before: string;
  Column: Integer;
begin
  Id := FDragId;
  FDragId := '';
  if (Id = '') or not ADrop or not FDropValid then
  begin
    SetTarget(-1, '');
    Exit;
  end;
  Target(Column, Before);
  // Danach wieder die Vorgabe: Ende der Spalte mit dem meisten Platz.
  SetTarget(-1, '');
  if FDragHidden then
    Later(
      procedure(ASource: IAtlasWelcomeArrangeSource)
      begin
        ASource.ShowSection(Id, Column, Before);
      end)
  else
    Rearranged(FLayout.MovedTo(Id, Column, Before));
end;

procedure TAtlasWelcomeBoardFrame.HiddenClick(const APart: TAtlasArrangePart);
var
  Id, Before: string;
  Column: Integer;
begin
  if APart.Kind <> TAtlasArrangePartKind.Hidden then
    Exit;
  Id := APart.Value;
  Target(Column, Before);
  SetTarget(-1, '');
  Later(
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.ShowSection(Id, Column, Before);
    end);
end;

procedure TAtlasWelcomeBoardFrame.BarClick(const APart: TAtlasArrangePart);
var
  Editing_: Boolean;
  Count: Integer;
  Where: TPoint;
begin
  case APart.Kind of
    TAtlasArrangePartKind.Edit:
      begin
        Editing_ := not FEditing;
        Later(
          procedure(ASource: IAtlasWelcomeArrangeSource)
          begin
            ASource.SetEditing(Editing_);
          end);
      end;
    TAtlasArrangePartKind.Column:
      begin
        Count := StrToIntDef(APart.Value, FLayout.Columns);
        Rearranged(FLayout.WithColumns(Count));
      end;
    TAtlasArrangePartKind.Reset:
      Later(
        procedure(ASource: IAtlasWelcomeArrangeSource)
        begin
          ASource.ResetLayout;
        end);
    TAtlasArrangePartKind.Layout, TAtlasArrangePartKind.Add:
      begin
        if APart.Kind = TAtlasArrangePartKind.Layout then
          BuildLayoutMenu
        else
          BuildAddMenu;
        Where := FBar.ClientToScreen(Point(APart.Rect.Left, APart.Rect.Bottom));
        FBarMenu.Popup(Where.X, Where.Y);
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TAtlasWelcomeBoardFrame.BuildLayoutMenu;
var
  Item: TMenuItem;
  mName: string;
  Index: Integer;
begin
  FBarMenu.Items.Clear;
  for Index := 0 to High(FLayoutNames) do
  begin
    mName := FLayoutNames[Index];
    Item := TMenuItem.Create(FBarMenu);
    Item.Caption := mName;
    Item.RadioItem := True;
    Item.Checked := SameText(mName, FActiveLayout);
    Item.Tag := Index;
    Item.OnClick := LayoutMenuSwitch;
    FBarMenu.Items.Add(Item);
  end;
  Item := TMenuItem.Create(FBarMenu);
  Item.Caption := '-';
  FBarMenu.Items.Add(Item);
  Item := TMenuItem.Create(FBarMenu);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeNewLayout);
  Item.OnClick := LayoutMenuNew;
  FBarMenu.Items.Add(Item);
  Item := TMenuItem.Create(FBarMenu);
  Item.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeRenameLayout);
  Item.OnClick := LayoutMenuRename;
  FBarMenu.Items.Add(Item);
  Item := TMenuItem.Create(FBarMenu);
  Item.Caption := TAtlasStrings.Fmt(TAtlasTextId.WelcomeArrangeDeleteLayout, [FActiveLayout]);
  Item.Enabled := Length(FLayoutNames) > 1;
  Item.OnClick := LayoutMenuDelete;
  FBarMenu.Items.Add(Item);
end;

procedure TAtlasWelcomeBoardFrame.BuildAddMenu;
var
  Item: TMenuItem;
  Index: Integer;
begin
  FBarMenu.Items.Clear;
  // Alle Atlas-Bereiche mit kurzer Beschreibung; sichtbare sind abgehakt und lassen sich nicht wählen.
  for Index := 0 to High(FCatalog) do
  begin
    Item := TMenuItem.Create(FBarMenu);
    Item.Caption := FCatalog[Index].Title + ' – ' + FCatalog[Index].Description;
    Item.Checked := FCatalog[Index].Shown;
    Item.Enabled := not FCatalog[Index].Shown;
    Item.Tag := Index;
    Item.OnClick := AddMenuClick;
    FBarMenu.Items.Add(Item);
  end;
end;

procedure TAtlasWelcomeBoardFrame.AddMenuClick(Sender: TObject);
var
  Index, Column: Integer;
  Id, Before: string;
begin
  Index := (Sender as TMenuItem).Tag;
  if (Index < 0) or (Index > High(FCatalog)) or FCatalog[Index].Shown then
    Exit;
  Id := FCatalog[Index].Id;
  Target(Column, Before);
  SetTarget(-1, '');
  Later(
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.ShowSection(Id, Column, Before);
    end);
end;

procedure TAtlasWelcomeBoardFrame.LayoutMenuSwitch(Sender: TObject);
var
  Index: Integer;
  mName: string;
begin
  Index := (Sender as TMenuItem).Tag;
  if (Index < 0) or (Index > High(FLayoutNames)) or SameText(FLayoutNames[Index], FActiveLayout) then
    Exit;
  mName := FLayoutNames[Index];
  Later(
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.SwitchLayout(mName);
    end);
end;

function TAtlasWelcomeBoardFrame.NameTaken(const AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in FLayoutNames do
    Result := Result or SameText(mName, Trim(AName));
end;

procedure TAtlasWelcomeBoardFrame.LayoutMenuNew(Sender: TObject);
var
  mName: string;
begin
  mName := '';
  if not AskName(TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeLayoutName), mName) or (Trim(mName) = '') then
    Exit;
  if NameTaken(mName) then
  begin
    Confirm(TAtlasStrings.Fmt(TAtlasTextId.WelcomeArrangeLayoutTaken, [Trim(mName)]), False);
    Exit;
  end;
  mName := Trim(mName);
  Later(
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.AddLayout(mName);
    end);
end;

procedure TAtlasWelcomeBoardFrame.LayoutMenuRename(Sender: TObject);
var
  mName: string;
begin
  mName := FActiveLayout;
  if not AskName(TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeLayoutName), mName) or (Trim(mName) = '') or
    SameText(Trim(mName), FActiveLayout) then
    Exit;
  if NameTaken(mName) then
  begin
    Confirm(TAtlasStrings.Fmt(TAtlasTextId.WelcomeArrangeLayoutTaken, [Trim(mName)]), False);
    Exit;
  end;
  mName := Trim(mName);
  Later(
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.RenameLayout(mName);
    end);
end;

procedure TAtlasWelcomeBoardFrame.LayoutMenuDelete(Sender: TObject);
begin
  if (Length(FLayoutNames) < 2) or
    not Confirm(TAtlasStrings.Fmt(TAtlasTextId.WelcomeArrangeDeleteConfirm, [FActiveLayout]), True) then
    Exit;
  Later(
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.DeleteLayout;
    end);
end;

function TAtlasWelcomeBoardFrame.AskName(const APrompt: string; var AName: string): Boolean;
begin
  if Assigned(FOnAskName) then
    Exit(FOnAskName(APrompt, AName));
  Result := InputQuery(TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeCustomize), APrompt, AName);
end;

function TAtlasWelcomeBoardFrame.Confirm(const AText: string; AQuestion: Boolean): Boolean;
begin
  if Assigned(FOnConfirm) then
    Exit(FOnConfirm(AText, AQuestion));
  if AQuestion then
    Result := MessageDlg(AText, mtConfirmation, [mbYes, mbNo], 0) = mrYes
  else
  begin
    MessageDlg(AText, mtInformation, [mbOK], 0);
    Result := True;
  end;
end;

function TAtlasWelcomeBoardFrame.SectionIdOf(AComponent: TComponent): string;
var
  Control: TControl;
begin
  Result := '';
  if not (AComponent is TControl) then
    Exit;
  Control := TControl(AComponent);
  while (Control <> nil) and not (Control is TAtlasWelcomeSectionFrame) do
    Control := Control.Parent;
  if Control <> nil then
    Result := TAtlasWelcomeSectionFrame(Control).SectionId;
end;

procedure TAtlasWelcomeBoardFrame.PrepareSectionMenu(const AId: string);
var
  Item: TMenuItem;
  Index: Integer;
begin
  FMenuId := AId;
  for Index := 0 to FSectionMenu.Items.Count - 1 do
  begin
    Item := FSectionMenu.Items[Index];
    case Item.Tag of
      TagHide, TagSettings:
        Item.Enabled := (FSource <> nil) and (CatalogIndex(AId) >= 0);
      TagCustomize:
        begin
          Item.Visible := FCanCustomize;
          Item.Checked := FEditing;
        end;
    end;
  end;
  // Trennstrich nur mit „Seite anpassen“ dahinter.
  FSectionMenu.Items[2].Visible := FCanCustomize;
end;

procedure TAtlasWelcomeBoardFrame.SectionMenuPopup(Sender: TObject);
begin
  PrepareSectionMenu(SectionIdOf(FSectionMenu.PopupComponent));
end;

procedure TAtlasWelcomeBoardFrame.SectionMenuHide(Sender: TObject);
var
  Id: string;
  Where: TPoint;
begin
  Id := FMenuId;
  if Id = '' then
    Exit;
  Where := FSectionMenu.PopupPoint;
  Later(
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.HideSectionAt(Id, Where);
    end);
end;

procedure TAtlasWelcomeBoardFrame.SectionMenuSettings(Sender: TObject);
var
  Id: string;
begin
  Id := FMenuId;
  if Id = '' then
    Exit;
  Later(
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.ShowSectionSettings(Id);
    end);
end;

procedure TAtlasWelcomeBoardFrame.SectionMenuCustomize(Sender: TObject);
var
  Editing_: Boolean;
begin
  Editing_ := not FEditing;
  Later(
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.SetEditing(Editing_);
    end);
end;

procedure TAtlasWelcomeBoardFrame.UpdateSection(const AId: string);
var
  Frame: TAtlasWelcomeSectionFrame;
begin
  if AId = '' then
  begin
    for Frame in FViews.Values do
      Frame.UpdateContent;
    Place;
    Exit;
  end;
  Frame := View(AId);
  if Frame <> nil then
  begin
    Frame.UpdateContent;
    Place;
  end;
end;

procedure TAtlasWelcomeBoardFrame.UpdateContent;
begin
  UpdateSection('');
  inherited;
end;

end.
