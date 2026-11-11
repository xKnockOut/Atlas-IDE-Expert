unit Atlas.IDE.Designer.Arrange;

// Knopf „Anordnen“ der Designer-Leiste (#730 ff.) in der IDE: Menü mit den
// Befehlen, die Größe und Lage der markierten Steuerelemente ändern. Jeder
// Befehl hat eine eigene Einstellung; ist keiner an, fehlt der Knopf.
// - Breite nach Text (#730, designer.fitToText, TAtlasIdeFitText).
// - Knopfleiste anordnen (#732, designer.buttonBar, TAtlasIdeButtonBar).
// - In Reihe duplizieren … und dessen Rückgängig (#736, designer.duplicateRow,
//   TAtlasIdeDuplicateRow).
// - Platz einfügen …, Platz entfernen … und dessen Rückgängig (#740,
//   designer.insertSpace, TAtlasIdeInsertSpace).
// - An Inhalt anpassen (Untermenü: beide, nur Breite, nur Höhe, alle auf
//   dieselbe Breite) und dessen Rückgängig (#742, designer.fitContainer,
//   TAtlasIdeFitContainer).
// - Fast bündige Kanten (Untermenü: anzeigen, alle angleichen, Auswahl als
//   gewollt markieren, deren Ausnahmen entfernen) und Angleichen rückgängig
//   (#746, designer.nearAlignment, TAtlasIdeNearAlign).
// - Standardgröße (Untermenü: setzen, Tabelle aus Formular übernehmen,
//   Abweichungen anzeigen) und Standardgröße rückgängig (#747,
//   designer.defaultSizes, TAtlasIdeDefaultSizes).
// - Ebene (Untermenü: eine Ebene nach vorn/hinten, ganz nach vorn/hinten,
//   Stapel unter dem markierten Steuerelement zum Auswählen) und Ebene
//   rückgängig (#749, designer.zOrder, TAtlasIdeDesignerLayers).
// - Eigenschaften übertragen (Untermenü: aufnehmen …, auf Auswahl
//   übertragen) und Übertragen rückgängig (#726, designer.propertyPainter,
//   TAtlasIdePropertyPainter).
// - Anchors vorschlagen … und Anchors rückgängig (#727,
//   designer.suggestAnchors, TAtlasIdeAnchors).
// - Texte des Formulars … und Text rückgängig (#728, designer.textTable,
//   TAtlasIdeFormTexts).
// - Label und Feld (Untermenü: Labels an Feldern ausrichten, Label erzeugen,
//   Paar lösen, Paar verbinden) und Label rückgängig (#729,
//   designer.labelPairs, TAtlasIdeLabelPairs).
// - Als Formularraster anordnen … und Raster rückgängig (#731,
//   designer.arrangeForm, TAtlasIdeFormGrid).
// - Einpacken in (Untermenü der Containerklassen, Vorgabe fett), Container
//   auflösen und Einpacken rückgängig (#733, designer.wrapInContainer,
//   TAtlasIdeWrap).
// - Schriften und Farben … und Schriften rückgängig (#741,
//   designer.fontsColors, TAtlasIdeFontsColors).
// - Gruppieren, Gruppe auflösen und Gruppen rückgängig (#744,
//   designer.groups, TAtlasIdeDesignerGroups).
// - Beschriftung bearbeiten (F2) und Beschriftung rückgängig (#748,
//   designer.inlineCaption, TAtlasIdeInlineCaption).
// Gesperrt sind Einträge, für die die Auswahl nicht passt. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.Menus,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Designer.DuplicateRow,
  Atlas.IDE.Designer.InsertSpace,
  Atlas.IDE.Designer.FitContainer,
  Atlas.IDE.Designer.NearAlign,
  Atlas.IDE.Designer.DefaultSizes,
  Atlas.IDE.Designer.Layers,
  Atlas.IDE.Designer.PropertyPainter,
  Atlas.IDE.Designer.Anchors,
  Atlas.IDE.Designer.FormTexts,
  Atlas.IDE.Designer.LabelPairs,
  Atlas.IDE.Designer.FormGrid,
  Atlas.IDE.Designer.Wrap,
  Atlas.IDE.Designer.FontsColors,
  Atlas.IDE.Designer.Groups,
  Atlas.IDE.Designer.InlineCaption;

type
  /// <summary>Befehle hinter RunExtra: Schriften und Farben (#741), Gruppen (#744), Beschriftung (#748).</summary>
  TAtlasArrangeExtras = record
    Fonts: TAtlasIdeFontsColors;
    Groups: TAtlasIdeDesignerGroups;
    Caption: TAtlasIdeInlineCaption;
  end;

type
  TAtlasIdeDesignerArrange = class
  private
    FMenu: TPopupMenu;
    FOnMessage: TProc<string>;
    FDuplicate: TAtlasIdeDuplicateRow;
    FSpace: TAtlasIdeInsertSpace;
    FFit: TAtlasIdeFitContainer;
    FNear: TAtlasIdeNearAlign;
    FSizes: TAtlasIdeDefaultSizes;
    FLayers: TAtlasIdeDesignerLayers;
    FPainter: TAtlasIdePropertyPainter;
    FAnchors: TAtlasIdeAnchors;
    FTexts: TAtlasIdeFormTexts;
    FPairs: TAtlasIdeLabelPairs;
    FGrid: TAtlasIdeFormGrid;
    FWrap: TAtlasIdeWrap;
    FExtra: TAtlasArrangeExtras;
    /// <summary>Containerklassen im zuletzt gezeigten Menü.</summary>
    FWrapClasses: TArray<string>;
    /// <summary>Namen der Stapel-Einträge im zuletzt gezeigten Menü.</summary>
    FStackNames: TArray<string>;
    function AddItem(AParent: TMenuItem; const ACaption: string; ATag: Integer; AEnabled: Boolean): TMenuItem;
    procedure AddFitItems(AEnabled, AMany: Boolean);
    procedure AddNearItems(ASelection: Boolean);
    procedure AddSizeItems(const ASettings: TAtlasPluginSettings);
    procedure AddLayerItems;
    procedure AddPaintItems;
    procedure AddPairItems;
    procedure AddWrapItems(const ASettings: TAtlasPluginSettings);
    /// <summary>Einpacken (#733): 0 auflösen, 1 rückgängig, ab 2 Klasse aus FWrapClasses.</summary>
    procedure RunWrap(ACommand: Integer);
    procedure AddExtraItems(const ASettings: TAtlasPluginSettings; ASelection: Boolean);
    /// <summary>TAtlasArrangeExtras: ACommand ist cFontsOpen … cCaptionUndo.</summary>
    procedure RunExtra(ACommand: Integer);
    /// <summary>Untermenüs ab „Fast bündige Kanten“ (#746 ff.).</summary>
    procedure AddFormItems(const ASettings: TAtlasPluginSettings; ASelection: Boolean);
    procedure ItemClick(Sender: TObject);
    /// <summary>Befehl zum Menü-Tag ATag ausführen.</summary>
    procedure Run(ATag: Integer);
    procedure RunArrange(ATag: Integer);
    /// <summary>Anchors (#727), Texte des Formulars (#728) und Formularraster (#731).</summary>
    procedure RunTools(ATag: Integer);
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Ist mindestens ein Befehl eingeschaltet?</summary>
    class function Available(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Menü für die Auswahl im aktiven Designer an APoint (Bildschirm).</summary>
    procedure Popup(const APoint: TPoint);
    procedure ApplyTheme;
    /// <summary>Tasten an- oder abmelden (Designer gezeigt).</summary>
    procedure UpdateKeys(AWanted: Boolean);
  end;

implementation

uses
  System.Classes,
  ToolsAPI,
  Atlas.Core.Designer.FitContainer,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.FitText,
  Atlas.IDE.Designer.ButtonBar,
  Atlas.IDE.Foundation.Settings;

const
  cFitToText = 1;
  cButtonBar = 2;
  cDuplicate = 3;
  cDuplicateUndo = 4;
  cSpaceInsert = 5;
  cSpaceRemove = 6;
  cSpaceUndo = 7;
  cFitBoth = 8;
  cFitWidth = 9;
  cFitHeight = 10;
  cFitSame = 11;
  cFitUndo = 12;
  cAnchors = 13;
  cAnchorsUndo = 14;
  cTexts = 15;
  cTextsUndo = 16;
  cGrid = 17;
  cGridUndo = 18;
  /// <summary>Ab hier TAtlasNearCommand: cNearFirst + Ord(Befehl).</summary>
  cNearFirst = 20;
  /// <summary>Ab hier TAtlasSizesCommand: cSizesFirst + Ord(Befehl).</summary>
  cSizesFirst = 30;
  /// <summary>Ab hier TAtlasLayersCommand: cLayersFirst + Ord(Befehl).</summary>
  cLayersFirst = 40;
  /// <summary>Ab hier TAtlasPaintCommand: cPaintFirst + Ord(Befehl).</summary>
  cPaintFirst = 50;
  cPairsFirst = 60;
  /// <summary>Ab hier Einpacken: cWrapFirst + RunWrap-Befehl.</summary>
  cWrapFirst = 70;
  cWrapUnwrap = 0;
  cWrapUndo = 1;
  cWrapClasses = 2;
  /// <summary>Ab hier RunExtra: Schriften und Farben (#741), Gruppen (#744), Beschriftung (#748).</summary>
  cFontsFirst = 90;
  cFontsOpen = 0;
  cFontsUndo = 1;
  cGroupsGroup = 2;
  cGroupsUngroup = 3;
  cGroupsUndo = 4;
  cCaptionEdit = 5;
  cCaptionUndo = 6;
  /// <summary>Ab hier Einträge des Stapels: cStackFirst + Index in FStackNames.</summary>
  cStackFirst = 100;

{ TAtlasIdeDesignerArrange }

constructor TAtlasIdeDesignerArrange.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FMenu := TPopupMenu.Create(nil);
  FDuplicate := TAtlasIdeDuplicateRow.Create(AOnMessage);
  FSpace := TAtlasIdeInsertSpace.Create(AOnMessage);
  FFit := TAtlasIdeFitContainer.Create(AOnMessage);
  FNear := TAtlasIdeNearAlign.Create(AOnMessage);
  FSizes := TAtlasIdeDefaultSizes.Create(AOnMessage);
  FLayers := TAtlasIdeDesignerLayers.Create(AOnMessage);
  FPainter := TAtlasIdePropertyPainter.Create(AOnMessage);
  FAnchors := TAtlasIdeAnchors.Create(AOnMessage);
  FTexts := TAtlasIdeFormTexts.Create(AOnMessage);
  FPairs := TAtlasIdeLabelPairs.Create(AOnMessage);
  FGrid := TAtlasIdeFormGrid.Create(AOnMessage);
  FWrap := TAtlasIdeWrap.Create(AOnMessage);
  FExtra.Fonts := TAtlasIdeFontsColors.Create(AOnMessage);
  FExtra.Groups := TAtlasIdeDesignerGroups.Create(AOnMessage);
  FExtra.Caption := TAtlasIdeInlineCaption.Create(AOnMessage);
end;

destructor TAtlasIdeDesignerArrange.Destroy;
begin
  FExtra.Caption.Free;
  FExtra.Groups.Free;
  FExtra.Fonts.Free;
  FWrap.Free;
  FGrid.Free;
  FPairs.Free;
  FTexts.Free;
  FAnchors.Free;
  FPainter.Free;
  FLayers.Free;
  FSizes.Free;
  FNear.Free;
  FFit.Free;
  FSpace.Free;
  FDuplicate.Free;
  FMenu.Free;
  inherited Destroy;
end;

class function TAtlasIdeDesignerArrange.Available(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.DesignerFitToText or ASettings.DesignerButtonBar or ASettings.DesignerDuplicateRow or
    ASettings.DesignerInsertSpace or ASettings.DesignerFitContainer or ASettings.DesignerNearAlignment or
    ASettings.DesignerDefaultSizes or ASettings.DesignerZOrder or
    ASettings.DesignerPropertyPainter or ASettings.DesignerSuggestAnchors or
    ASettings.DesignerTextTable or ASettings.DesignerLabelPairs or
    ASettings.DesignerArrangeForm or ASettings.DesignerWrapInContainer or ASettings.DesignerFontsColors or
    ASettings.DesignerGroups or ASettings.DesignerInlineCaption;
end;

function TAtlasIdeDesignerArrange.AddItem(AParent: TMenuItem; const ACaption: string; ATag: Integer;
  AEnabled: Boolean): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.Enabled := AEnabled;
  if ATag > 0 then
  begin
    Result.OnClick := ItemClick;
  end;
  AParent.Add(Result);
end;

procedure TAtlasIdeDesignerArrange.AddFitItems(AEnabled, AMany: Boolean);
var
  mSub: TMenuItem;
begin
  mSub := AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerFitContainerCmd), 0, AEnabled);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerFitContainerBoth), cFitBoth, True);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerFitContainerWidth), cFitWidth, True);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerFitContainerHeight), cFitHeight, True);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerFitContainerSame), cFitSame, AMany);
  AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerFitContainerUndoCmd), cFitUndo,
    FFit.CanUndo);
end;

procedure TAtlasIdeDesignerArrange.AddNearItems(ASelection: Boolean);
var
  mSub: TMenuItem;
begin
  mSub := AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerNearCmd), 0, True);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerNearShow),
    cNearFirst + Ord(TAtlasNearCommand.Show), True);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerNearFixAll),
    cNearFirst + Ord(TAtlasNearCommand.FixAll), True);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerNearExcept),
    cNearFirst + Ord(TAtlasNearCommand.MarkSelection), ASelection);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerNearRemoveExcept),
    cNearFirst + Ord(TAtlasNearCommand.RemoveSelection), ASelection);
  AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerNearUndoCmd),
    cNearFirst + Ord(TAtlasNearCommand.Undo), FNear.CanUndo);
end;

procedure TAtlasIdeDesignerArrange.AddSizeItems(const ASettings: TAtlasPluginSettings);
var
  mSub: TMenuItem;
begin
  mSub := AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSizesCmd), 0, True);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSizesApply),
    cSizesFirst + Ord(TAtlasSizesCommand.Apply), Trim(ASettings.DesignerDefaultSizesTable) <> '');
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSizesLearn),
    cSizesFirst + Ord(TAtlasSizesCommand.Learn), True);
  if ASettings.DesignerDefaultSizesMarkDeviations then
  begin
    AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSizesShow),
      cSizesFirst + Ord(TAtlasSizesCommand.Show), Trim(ASettings.DesignerDefaultSizesTable) <> '');
  end;
  AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSizesUndoCmd),
    cSizesFirst + Ord(TAtlasSizesCommand.Undo), FSizes.CanUndo);
end;

procedure TAtlasIdeDesignerArrange.AddLayerItems;
var
  mSub: TMenuItem;
  mOne: Boolean;
  mEntry: TAtlasStackEntry;
begin
  mOne := TAtlasIdeDesignerLayers.HasTarget;
  mSub := AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerLayerCmd), 0, mOne);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerLayerForward),
    cLayersFirst + Ord(TAtlasLayersCommand.Forward), True);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerLayerBackward),
    cLayersFirst + Ord(TAtlasLayersCommand.Backward), True);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerLayerFront),
    cLayersFirst + Ord(TAtlasLayersCommand.Front), True);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerLayerBack),
    cLayersFirst + Ord(TAtlasLayersCommand.Back), True);
  FStackNames := nil;
  AddItem(mSub, '-', 0, True);
  for mEntry in TAtlasIdeDesignerLayers.Stack do
  begin
    if mEntry.BreakBefore then
    begin
      AddItem(mSub, '-', 0, True);
    end;
    AddItem(mSub, mEntry.Caption, cStackFirst + Length(FStackNames), True).Checked := mEntry.Selected;
    FStackNames := FStackNames + [mEntry.Name];
  end;
  AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerLayerUndoCmd),
    cLayersFirst + Ord(TAtlasLayersCommand.Undo), FLayers.CanUndo);
end;

procedure TAtlasIdeDesignerArrange.AddPaintItems;
var
  mSub: TMenuItem;
begin
  mSub := AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerPaintCmd), 0, True);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerPaintPickUp),
    cPaintFirst + Ord(TAtlasPaintCommand.PickUp), True);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerPaintApply),
    cPaintFirst + Ord(TAtlasPaintCommand.Apply), FPainter.CanApply);
  AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerPaintUndoCmd),
    cPaintFirst + Ord(TAtlasPaintCommand.Undo), FPainter.CanUndo);
end;

procedure TAtlasIdeDesignerArrange.Popup(const APoint: TPoint);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSelected: TArray<TComponent>;
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  if not Available(mSettings) or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mSelected := TAtlasDesignerAccess.Selection(mEditor, mRoot);
  FMenu.Items.Clear;
  if mSettings.DesignerFitToText then
  begin
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerFitToText), cFitToText,
      Length(TAtlasIdeFitText.Candidates(mSelected)) > 0);
  end;
  if mSettings.DesignerButtonBar then
  begin
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerButtonBarCmd), cButtonBar,
      Length(TAtlasIdeButtonBar.Candidates(mSelected)) > 0);
  end;
  if mSettings.DesignerDuplicateRow then
  begin
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateCmd), cDuplicate,
      Length(TAtlasIdeDuplicateRow.Candidates(mSelected)) > 0);
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateUndoCmd), cDuplicateUndo,
      FDuplicate.CanUndo);
  end;
  if mSettings.DesignerInsertSpace then
  begin
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSpaceInsertCmd), cSpaceInsert,
      Length(TAtlasIdeInsertSpace.Candidates(mSelected)) > 0);
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSpaceRemoveCmd), cSpaceRemove,
      Length(TAtlasIdeInsertSpace.Candidates(mSelected)) > 0);
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSpaceUndoCmd), cSpaceUndo,
      FSpace.CanUndo);
  end;
  if mSettings.DesignerFitContainer then
  begin
    AddFitItems(Length(TAtlasIdeFitContainer.Candidates(mSelected, mRoot)) > 0,
      Length(TAtlasIdeFitContainer.Candidates(mSelected, mRoot)) > 1);
  end;
  AddFormItems(mSettings, Length(mSelected) > 0);
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeDesignerArrange.AddPairItems;
var
  mSub: TMenuItem;
begin
  mSub := TMenuItem.Create(FMenu);
  mSub.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerPairsMenu);
  FMenu.Items.Add(mSub);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerPairsAlignCmd),
    cPairsFirst + Ord(TAtlasPairsCommand.AlignLabels), True);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerPairsCreateCmd),
    cPairsFirst + Ord(TAtlasPairsCommand.CreateLabels), FPairs.CanCreate);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerPairsReleaseCmd),
    cPairsFirst + Ord(TAtlasPairsCommand.Release), True);
  AddItem(mSub, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerPairsJoinCmd),
    cPairsFirst + Ord(TAtlasPairsCommand.Join), True);
  AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerPairsUndoCmd),
    cPairsFirst + Ord(TAtlasPairsCommand.Undo), FPairs.CanUndo);
end;

procedure TAtlasIdeDesignerArrange.AddWrapItems(const ASettings: TAtlasPluginSettings);
var
  mSub: TMenuItem;
  mIndex: Integer;
begin
  mSub := AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerWrapMenu), 0,
    TAtlasIdeWrap.CanWrap);
  FWrapClasses := TAtlasIdeWrap.ClassNames;
  if Length(FWrapClasses) > cFontsFirst - cWrapFirst - cWrapClasses then
  begin
    SetLength(FWrapClasses, cFontsFirst - cWrapFirst - cWrapClasses);
  end;
  for mIndex := 0 to High(FWrapClasses) do
  begin
    AddItem(mSub, FWrapClasses[mIndex], cWrapFirst + cWrapClasses + mIndex, True).Default :=
      SameText(FWrapClasses[mIndex], ASettings.DesignerWrapInContainerDefaultClass);
  end;
  AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerWrapUnwrapCmd),
    cWrapFirst + cWrapUnwrap, TAtlasIdeWrap.CanUnwrap);
  AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerWrapUndoCmd), cWrapFirst + cWrapUndo,
    FWrap.CanUndo);
end;

procedure TAtlasIdeDesignerArrange.AddExtraItems(const ASettings: TAtlasPluginSettings; ASelection: Boolean);
begin
  if ASettings.DesignerFontsColors then
  begin
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerFontsCmd), cFontsFirst + cFontsOpen,
      True);
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerFontsUndoCmd),
      cFontsFirst + cFontsUndo, FExtra.Fonts.CanUndo);
  end;
  if ASettings.DesignerGroups then
  begin
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerGroupsCmd),
      cFontsFirst + cGroupsGroup, ASelection);
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerGroupsUngroupCmd),
      cFontsFirst + cGroupsUngroup, FExtra.Groups.HasGroup);
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerGroupsUndoCmd),
      cFontsFirst + cGroupsUndo, FExtra.Groups.CanUndo);
  end;
  if ASettings.DesignerInlineCaption then
  begin
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerCaptionEditCmd),
      cFontsFirst + cCaptionEdit, FExtra.Caption.CanEdit);
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerCaptionUndoCmd),
      cFontsFirst + cCaptionUndo, FExtra.Caption.CanUndo);
  end;
end;

procedure TAtlasIdeDesignerArrange.RunExtra(ACommand: Integer);
begin
  case ACommand of
    cFontsOpen:
      FExtra.Fonts.Execute;
    cFontsUndo:
      FExtra.Fonts.Undo;
    cGroupsGroup:
      FExtra.Groups.Group;
    cGroupsUngroup:
      FExtra.Groups.Ungroup;
    cGroupsUndo:
      FExtra.Groups.Undo;
    cCaptionEdit:
      FExtra.Caption.Edit;
    cCaptionUndo:
      FExtra.Caption.Undo;
  end;
end;

procedure TAtlasIdeDesignerArrange.RunWrap(ACommand: Integer);
begin
  if ACommand = cWrapUnwrap then
  begin
    FWrap.Unwrap;
  end
  else if ACommand = cWrapUndo then
  begin
    FWrap.Undo;
  end
  else if ACommand - cWrapClasses <= High(FWrapClasses) then
  begin
    FWrap.Wrap(FWrapClasses[ACommand - cWrapClasses]);
  end;
end;

procedure TAtlasIdeDesignerArrange.AddFormItems(const ASettings: TAtlasPluginSettings; ASelection: Boolean);
begin
  if ASettings.DesignerNearAlignment then
  begin
    AddNearItems(ASelection);
  end;
  if ASettings.DesignerDefaultSizes then
  begin
    AddSizeItems(ASettings);
  end;
  if ASettings.DesignerZOrder then
  begin
    AddLayerItems;
  end;
  if ASettings.DesignerPropertyPainter then
  begin
    AddPaintItems;
  end;
  if ASettings.DesignerSuggestAnchors then
  begin
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAnchorsCmd), cAnchors, True);
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAnchorsUndoCmd), cAnchorsUndo,
      FAnchors.CanUndo);
  end;
  if ASettings.DesignerLabelPairs then
  begin
    AddPairItems;
  end;
  if ASettings.DesignerArrangeForm then
  begin
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerGridCmd), cGrid,
      TAtlasIdeFormGrid.CanArrange);
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerGridUndoCmd), cGridUndo,
      FGrid.CanUndo);
  end;
  if ASettings.DesignerWrapInContainer then
  begin
    AddWrapItems(ASettings);
  end;
  AddExtraItems(ASettings, ASelection);
  if ASettings.DesignerTextTable then
  begin
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTextsCmd), cTexts, True);
    AddItem(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTextsUndoCmd), cTextsUndo,
      FTexts.CanUndo);
  end;
end;

procedure TAtlasIdeDesignerArrange.RunArrange(ATag: Integer);
begin
  case ATag of
    cFitToText:
      TAtlasIdeFitText.Execute(FOnMessage);
    cButtonBar:
      TAtlasIdeButtonBar.Execute(FOnMessage);
    cDuplicate:
      FDuplicate.Execute;
    cDuplicateUndo:
      FDuplicate.Undo;
    cSpaceInsert:
      FSpace.Execute(False);
    cSpaceRemove:
      FSpace.Execute(True);
    cSpaceUndo:
      FSpace.Undo;
    cFitBoth:
      FFit.Execute(TAtlasFitMode.Both, False);
    cFitWidth:
      FFit.Execute(TAtlasFitMode.Width, False);
    cFitHeight:
      FFit.Execute(TAtlasFitMode.Height, False);
    cFitSame:
      FFit.Execute(TAtlasFitMode.Both, True);
    cFitUndo:
      FFit.Undo;
  else
    RunTools(ATag);
  end;
end;

procedure TAtlasIdeDesignerArrange.RunTools(ATag: Integer);
begin
  case ATag of
    cAnchors:
      FAnchors.Execute;
    cAnchorsUndo:
      FAnchors.Undo;
    cTexts:
      FTexts.Execute;
    cTextsUndo:
      FTexts.Undo;
    cGrid:
      FGrid.Execute;
    cGridUndo:
      FGrid.Undo;
  end;
end;

procedure TAtlasIdeDesignerArrange.Run(ATag: Integer);
begin
  if ATag >= cStackFirst then
  begin
    if ATag - cStackFirst <= High(FStackNames) then
    begin
      TAtlasIdeDesignerLayers.SelectName(FStackNames[ATag - cStackFirst]);
    end;
  end
  else if ATag >= cFontsFirst then
  begin
    RunExtra(ATag - cFontsFirst);
  end
  else if ATag >= cWrapFirst then
  begin
    RunWrap(ATag - cWrapFirst);
  end
  else if ATag >= cPairsFirst then
  begin
    FPairs.Execute(TAtlasPairsCommand(ATag - cPairsFirst));
  end
  else if ATag >= cPaintFirst then
  begin
    FPainter.Execute(TAtlasPaintCommand(ATag - cPaintFirst));
  end
  else if ATag >= cLayersFirst then
  begin
    FLayers.Execute(TAtlasLayersCommand(ATag - cLayersFirst));
  end
  else if ATag >= cSizesFirst then
  begin
    FSizes.Execute(TAtlasSizesCommand(ATag - cSizesFirst));
  end
  else if ATag >= cNearFirst then
  begin
    FNear.Execute(TAtlasNearCommand(ATag - cNearFirst));
  end
  else
  begin
    RunArrange(ATag);
  end;
end;

procedure TAtlasIdeDesignerArrange.ItemClick(Sender: TObject);
var
  mTag: Integer;
  mSelf: TAtlasIdeDesignerArrange;
begin
  mTag := TMenuItem(Sender).Tag;
  mSelf := Self;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      mSelf.Run(mTag);
    end);
end;

procedure TAtlasIdeDesignerArrange.UpdateKeys(AWanted: Boolean);
begin
  FLayers.UpdateKeys(AWanted);
  FPainter.UpdateKeys(AWanted);
  FExtra.Groups.UpdateKeys(AWanted);
  FExtra.Caption.UpdateKeys(AWanted);
end;

procedure TAtlasIdeDesignerArrange.ApplyTheme;
begin
  FDuplicate.ApplyTheme;
  FNear.ApplyTheme;
  FSizes.ApplyTheme;
  FAnchors.ApplyTheme;
  FGrid.ApplyTheme;
  FExtra.Groups.ApplyTheme;
  FExtra.Caption.ApplyTheme;
end;

end.
