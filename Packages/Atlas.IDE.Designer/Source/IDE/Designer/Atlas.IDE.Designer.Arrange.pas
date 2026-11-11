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
  Atlas.IDE.Designer.PropertyPainter;

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
    /// <summary>Namen der Stapel-Einträge im zuletzt gezeigten Menü.</summary>
    FStackNames: TArray<string>;
    function AddItem(AParent: TMenuItem; const ACaption: string; ATag: Integer; AEnabled: Boolean): TMenuItem;
    procedure AddFitItems(AEnabled, AMany: Boolean);
    procedure AddNearItems(ASelection: Boolean);
    procedure AddSizeItems(const ASettings: TAtlasPluginSettings);
    procedure AddLayerItems;
    procedure AddPaintItems;
    /// <summary>Untermenüs ab „Fast bündige Kanten“ (#746 ff.).</summary>
    procedure AddFormItems(const ASettings: TAtlasPluginSettings; ASelection: Boolean);
    procedure ItemClick(Sender: TObject);
    /// <summary>Befehl zum Menü-Tag ATag ausführen.</summary>
    procedure Run(ATag: Integer);
    procedure RunArrange(ATag: Integer);
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
  /// <summary>Ab hier TAtlasNearCommand: cNearFirst + Ord(Befehl).</summary>
  cNearFirst = 20;
  /// <summary>Ab hier TAtlasSizesCommand: cSizesFirst + Ord(Befehl).</summary>
  cSizesFirst = 30;
  /// <summary>Ab hier TAtlasLayersCommand: cLayersFirst + Ord(Befehl).</summary>
  cLayersFirst = 40;
  /// <summary>Ab hier TAtlasPaintCommand: cPaintFirst + Ord(Befehl).</summary>
  cPaintFirst = 50;
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
end;

destructor TAtlasIdeDesignerArrange.Destroy;
begin
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
    ASettings.DesignerPropertyPainter;
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
end;

procedure TAtlasIdeDesignerArrange.ApplyTheme;
begin
  FDuplicate.ApplyTheme;
  FNear.ApplyTheme;
  FSizes.ApplyTheme;
end;

end.
