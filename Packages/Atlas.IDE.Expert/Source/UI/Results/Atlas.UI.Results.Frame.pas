unit Atlas.UI.Results.Frame;

// Inhalt des Ergebnisfensters (#400), reine VCL: oben eine Titelzeile, darunter
// ein Baum. Fundstellen (Referenzen, Implementierungen) stehen nach Unit
// gruppiert, je Zeile „Zeile: Text“; Hierarchien (Aufrufer, Aufrufe,
// Vorfahren, Nachfahren) laden ihre nächste Ebene erst beim Aufklappen über
// OnExpand. Doppelklick oder Enter springt über OnOpen zur Stelle. Die Liste
// „Atlas-Änderungen“ (#721) zeigt die Sätze des Änderungsprotokolls mit ihren
// Dateien; Doppelklick oder Enter zeigt den Unterschied (OnChangeDiff), das
// Kontextmenü nimmt einen Satz zurück oder stellt ihn wieder her. Die DFM
// ist leer, weil TCustomFrame.Create für abgeleitete Frames eine Ressource
// verlangt; aufgebaut wird im Code. Die IDE-Schicht bettet den Frame in ein
// andockbares Fenster ein. Vor dem Titel steht das Atlas-Symbol (#751).
// Die Liste der persönlichen Notizen (#545) zeigt je Datei „Zeile: Titel“ und
// verwaiste Notizen in einer Gruppe am Ende; Doppelklick oder Enter springt,
// das Kontextmenü bearbeitet oder löscht die Notiz (Entf löscht ebenfalls).
// Verwendungen mit erschlossenen Treffern (#1119) stehen in zwei Abschnitten,
// „Sicher (n)“ und „Erschlossen (n) · vor dem Umbenennen prüfen“, darin nach
// Unit gruppiert; erschlossene Zeilen tragen ≈ und ihren Grund, der Hinweis
// unter der Maus erklärt ihn. „Nur sichere“ in der Titelzeile blendet die
// erschlossenen aus. Erschlossene Aufrufer der Hierarchie sind ebenso markiert.
// Die Auswirkungsanalyse (#1120) steht in drei Abschnitten: „Direkt“ (Ebene 1),
// „Indirekt“ als Baum über die verursachende Stelle und „Betroffene Tests“;
// Formularbindungen hängen unter ihrer Stelle, erreichte Grenzen stehen am
// Ende. In der Titelzeile wählt „Tiefe“ 1–5 (OnImpactDepth rechnet neu), und
// „Betroffene Tests ausführen“ gibt die Tests an OnImpactRunTests.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Vcl.Menus,
  Vcl.ExtCtrls,
  Atlas.Core.Results.Model,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Style.Symbol,
  Atlas.UI.Style.Symbol,
  Atlas.Core.Undo.Contract,
  Atlas.Core.Notes.Store;

type
  TAtlasResultsOpen = reference to procedure(const AFileName: string; ALine, ACharacter: Integer);
  TAtlasHierarchyExpand = reference to function(ADirection: TAtlasHierarchyDirection;
    const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>;
  /// <summary>Satz (#721) zurücknehmen bzw. wiederherstellen.</summary>
  TAtlasChangeSetAction = reference to procedure(ASetId: Integer);
  /// <summary>Unterschied eines Satzes zeigen; AFileName = '' für alle Dateien.</summary>
  TAtlasChangeDiff = reference to procedure(ASetId: Integer; const AFileName: string);
  /// <summary>Notiz (#545) bearbeiten bzw. löschen.</summary>
  TAtlasNoteAction = reference to procedure(const ANoteId: string);
  /// <summary>Auswirkungsanalyse (#1120) mit anderer Tiefe neu rechnen.</summary>
  TAtlasImpactDepthChange = reference to procedure(ADepth: Integer);
  /// <summary>Betroffene Tests der gezeigten Analyse ausführen.</summary>
  TAtlasImpactRunTests = reference to procedure(const AImpact: TAtlasImpact);

  TAtlasResultsFrame = class(TFrame)
  private type
{$SCOPEDENUMS ON}
    TNodeKind = (Group, Entry, Hierarchy, Placeholder, ChangeSet, ChangeFile, Note);
{$SCOPEDENUMS OFF}
    TNodeData = record
      Kind: TNodeKind;
      FileName: string;
      Line: Integer;
      Character: Integer;
      Item: TAtlasHierarchyItem;
      Loaded: Boolean;
      /// <summary>Kennung des Satzes (#721) und sein Zustand.</summary>
      SetId: Integer;
      State: TAtlasChangeSetState;
      /// <summary>Kennung der Notiz (#545).</summary>
      NoteId: string;
      /// <summary>Hinweis unter der Maus: Erklärung eines erschlossenen Treffers (#1119).</summary>
      Hint: string;
    end;
  private
    FTitle: TLabel;
    FSymbol: TAtlasSymbolImage;
    FTree: TTreeView;
    FData: TList<TNodeData>;
    FDirection: TAtlasHierarchyDirection;
    FOnOpen: TAtlasResultsOpen;
    FOnExpand: TAtlasHierarchyExpand;
    FMenu: TPopupMenu;
    FUndoItem: TMenuItem;
    FRedoItem: TMenuItem;
    FDiffItem: TMenuItem;
    FShowsChanges: Boolean;
    FOnChangeUndo: TAtlasChangeSetAction;
    FOnChangeRedo: TAtlasChangeSetAction;
    FOnChangeDiff: TAtlasChangeDiff;
    FNoteEditItem: TMenuItem;
    FNoteDeleteItem: TMenuItem;
    FShowsNotes: Boolean;
    FOnNoteEdit: TAtlasNoteAction;
    FOnNoteDelete: TAtlasNoteAction;
    FOnlySure: TCheckBox;
    FRatedTitle: string;
    FRatedEntries: TArray<TAtlasResultEntry>;
    FSureCaption: string;
    FInferredCaption: string;
    FHintNode: TTreeNode;
    FDepthLabel: TLabel;
    FDepth: TComboBox;
    FRunTests: TButton;
    FImpact: TAtlasImpact;
    FShowsImpact: Boolean;
    FOnImpactDepth: TAtlasImpactDepthChange;
    FOnImpactRunTests: TAtlasImpactRunTests;
    function AddImpactPlace(AParent: TTreeNode; APlace: Integer): TTreeNode;
    procedure AddImpactBranch(AParent: TTreeNode; ACause: Integer);
    procedure AddImpactForms(AParent: TTreeNode; const AForms: TArray<TAtlasImpactForm>);
    procedure DepthChange(Sender: TObject);
    procedure RunTestsClick(Sender: TObject);
    function AddNode(AParent: TTreeNode; const AText: string; const AData: TNodeData): TTreeNode;
    function DataOf(ANode: TTreeNode): TNodeData;
    procedure AddHierarchy(AParent: TTreeNode; const AItems: TArray<TAtlasHierarchyItem>);
    procedure AddGroups(AParent: TTreeNode; const AGroups: TArray<TAtlasResultGroup>);
    procedure RenderRated;
    procedure OnlySureClick(Sender: TObject);
    procedure TreeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure Clear(const ATitle: string);
    procedure OpenSelected;
    procedure TreeDblClick(Sender: TObject);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
    function SelectedSet: TNodeData;
    procedure MenuPopup(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    procedure DiffClick(Sender: TObject);
    procedure NoteEditClick(Sender: TObject);
    procedure NoteDeleteClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Fundstellen nach Unit gruppiert; alle Gruppen aufgeklappt.</summary>
    procedure ShowEntries(const ATitle: string; const AGroups: TArray<TAtlasResultGroup>);
    /// <summary>Fundstellen nach Treffersicherheit (#1119): ohne erschlossene wie ShowEntries; sonst zwei Abschnitte
    /// mit ASureCaption bzw. AInferredCaption (Format mit der Anzahl), darin nach Unit gruppiert.</summary>
    procedure ShowRated(const ATitle: string; const AEntries: TArray<TAtlasResultEntry>;
      const ASureCaption, AInferredCaption: string);
    /// <summary>Wurzeln einer Hierarchie; die erste Ebene wird gleich geladen.</summary>
    procedure ShowHierarchy(const ATitle: string; ADirection: TAtlasHierarchyDirection;
      const ARoots: TArray<TAtlasHierarchyItem>);
    /// <summary>Liste „Atlas-Änderungen“ (#721): neueste Sätze zuerst, je Satz seine Dateien (zugeklappt).
    /// AKeepSelection: den bisher gewählten Satz wieder wählen (nach Zurücknehmen).</summary>
    procedure ShowChanges(const ATitle: string; const ASets: TArray<TAtlasChangeSet>; ANow: TDateTime;
      AKeepSelection: Boolean);
    /// <summary>Unterschied, Zurücknehmen und Wiederherstellen für den gewählten Satz
    /// bzw. die gewählte Datei.</summary>
    procedure ShowSelectedDiff;
    procedure UndoSelected;
    procedure RedoSelected;
    /// <summary>Notizen des Projekts (#545): je Datei eine Gruppe, verwaiste am Ende; alles aufgeklappt.</summary>
    procedure ShowNotes(const ATitle: string; const AGroups: TArray<TAtlasNoteGroup>); overload;
    /// <summary>Wie oben; ASelectId: diese Notiz wählen (nach Bearbeiten).</summary>
    procedure ShowNotes(const ATitle: string; const AGroups: TArray<TAtlasNoteGroup>;
      const ASelectId: string); overload;
    /// <summary>Kennung der gewählten Notiz; '' ohne.</summary>
    function SelectedNoteId: string;
    procedure EditSelectedNote;
    procedure DeleteSelectedNote;
    /// <summary>Gruppe: "Kunde.pas (2)" bzw. "Verwaist (1)".</summary>
    class function NoteGroupText(const AGroup: TAtlasNoteGroup): string; static;
    /// <summary>Eintrag: "42: Titel" bzw. verwaist "Kunde.pas, Zeile 42: Titel".</summary>
    class function NoteText(const ANote: TAtlasNote; AOrphaned: Boolean): string; static;
    /// <summary>Text einer Fundstelle: "12: Kunde.Laden;" bzw. mit Vorschau "alt  →  neu"; erschlossen
    /// "≈ 12: S.Speichern;  [über Interface]" (#1119).</summary>
    class function EntryText(const AEntry: TAtlasResultEntry): string; static;
    /// <summary>Kurzer Grund eines erschlossenen Treffers, etwa "über Interface"; '' bei sicheren.</summary>
    class function ReasonText(const AConfidence: TAtlasConfidence): string; static;
    /// <summary>Text eines Hierarchie-Eintrags: "Laden · TKunde  (Kunden.pas:12)".</summary>
    class function HierarchyText(const AItem: TAtlasHierarchyItem): string; static;
    /// <summary>Auswirkungsanalyse (#1120): Abschnitte „Direkt“, „Indirekt“ (Baum über die Ursache),
    /// „Betroffene Tests“, darunter erreichte Grenzen; Tiefe und „Betroffene Tests ausführen“ in der Titelzeile.
    /// </summary>
    procedure ShowImpact(const ATitle: string; const AImpact: TAtlasImpact);
    /// <summary>Text einer betroffenen Stelle: wie HierarchyText, mit Art (Override, Umsetzung …), Zahl der
    /// Verwendungen und Test-Kennzeichen.</summary>
    class function ImpactPlaceText(const APlace: TAtlasImpactPlace): string; static;
    /// <summary>"Formular: OnClick = Button1Click  (Main.dfm:12)".</summary>
    class function ImpactFormText(const AForm: TAtlasImpactForm): string; static;
    /// <summary>Je erreichte Grenze eine Zeile; leer ohne.</summary>
    class function ImpactLimitTexts(const AImpact: TAtlasImpact): TArray<string>; static;
    /// <summary>Zeigt gerade eine Auswirkungsanalyse (#1120).</summary>
    property ShowsImpact: Boolean read FShowsImpact;
    property Impact: TAtlasImpact read FImpact;
    property DepthBox: TComboBox read FDepth;
    property RunTestsButton: TButton read FRunTests;
    property OnImpactDepth: TAtlasImpactDepthChange read FOnImpactDepth write FOnImpactDepth;
    property OnImpactRunTests: TAtlasImpactRunTests read FOnImpactRunTests write FOnImpactRunTests;
    property Tree: TTreeView read FTree;
    property OnOpen: TAtlasResultsOpen read FOnOpen write FOnOpen;
    property OnExpand: TAtlasHierarchyExpand read FOnExpand write FOnExpand;
    property Menu: TPopupMenu read FMenu;
    property Symbol: TAtlasSymbolImage read FSymbol;
    /// <summary>Zeigt gerade die Liste „Atlas-Änderungen“.</summary>
    property ShowsChanges: Boolean read FShowsChanges;
    property OnChangeUndo: TAtlasChangeSetAction read FOnChangeUndo write FOnChangeUndo;
    property OnChangeRedo: TAtlasChangeSetAction read FOnChangeRedo write FOnChangeRedo;
    property OnChangeDiff: TAtlasChangeDiff read FOnChangeDiff write FOnChangeDiff;
    /// <summary>Zeigt gerade die Liste der Notizen (#545).</summary>
    property ShowsNotes: Boolean read FShowsNotes;
    property OnNoteEdit: TAtlasNoteAction read FOnNoteEdit write FOnNoteEdit;
    property OnNoteDelete: TAtlasNoteAction read FOnNoteDelete write FOnNoteDelete;
    /// <summary>„Nur sichere“ (#1119); sichtbar, solange erschlossene Treffer da sind.</summary>
    property OnlySure: TCheckBox read FOnlySure;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.UI.Strings,
  Atlas.UI.Undo.Messages;

{$R *.dfm}

{ TAtlasResultsFrame }

constructor TAtlasResultsFrame.Create(AOwner: TComponent);
var
  Header: TPanel;
begin
  inherited Create(AOwner);
  FData := TList<TNodeData>.Create;
  // Titelzeile: Symbol (#751) und Titel.
  Header := TPanel.Create(Self);
  Header.Parent := Self;
  Header.Align := alTop;
  Header.BevelOuter := bvNone;
  Header.ParentBackground := True;
  Header.Height := 22;
  FSymbol := TAtlasSymbolImage.Create(Self);
  FSymbol.Parent := Header;
  FSymbol.LogicalSize := TAtlasSymbol.MenuSize;
  FSymbol.Align := alLeft;
  FSymbol.AlignWithMargins := True;
  // Filter „Nur sichere“ (#1119), rechts in der Titelzeile.
  FOnlySure := TCheckBox.Create(Self);
  FOnlySure.Parent := Header;
  FOnlySure.Align := alRight;
  FOnlySure.AlignWithMargins := True;
  FOnlySure.Caption := TAtlasStrings.Text(TAtlasTextId.ResultsOnlySure);
  FOnlySure.Width := 110;
  FOnlySure.Visible := False;
  FOnlySure.OnClick := OnlySureClick;
  // Auswirkungsanalyse (#1120): Tiefe und Testlauf, rechts in der Titelzeile. Die Liste der Tiefen füllt
  // ShowImpact: Ein Kombinationsfeld braucht dafür ein Fenster.
  FRunTests := TButton.Create(Self);
  FRunTests.Parent := Header;
  FRunTests.Align := alRight;
  FRunTests.AlignWithMargins := True;
  FRunTests.Caption := TAtlasStrings.Text(TAtlasTextId.ImpactRunTests);
  FRunTests.Width := 170;
  FRunTests.Visible := False;
  FRunTests.OnClick := RunTestsClick;
  FDepth := TComboBox.Create(Self);
  FDepth.Parent := Header;
  FDepth.Align := alRight;
  FDepth.AlignWithMargins := True;
  FDepth.Style := csDropDownList;
  FDepth.Width := 44;
  FDepth.Visible := False;
  FDepth.OnChange := DepthChange;
  FDepthLabel := TLabel.Create(Self);
  FDepthLabel.Parent := Header;
  FDepthLabel.Align := alRight;
  FDepthLabel.AlignWithMargins := True;
  FDepthLabel.Layout := tlCenter;
  FDepthLabel.Caption := TAtlasStrings.Text(TAtlasTextId.ImpactDepth);
  FDepthLabel.Visible := False;
  FTitle := TLabel.Create(Self);
  FTitle.Parent := Header;
  FTitle.Align := alClient;
  FTitle.Layout := tlCenter;
  FTitle.AlignWithMargins := True;
  FTitle.ShowAccelChar := False;
  FTitle.EllipsisPosition := epEndEllipsis;
  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.Align := alClient;
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.RowSelect := True;
  FTree.ShowLines := False;
  FTree.BorderStyle := bsNone;
  FTree.OnDblClick := TreeDblClick;
  FTree.OnKeyDown := TreeKeyDown;
  FTree.OnExpanding := TreeExpanding;
  FTree.OnMouseMove := TreeMouseMove;
  FTree.ShowHint := True;
  // Kontextmenü der Liste „Atlas-Änderungen“ (#721); in anderen Listen ohne Einträge.
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FUndoItem := TMenuItem.Create(FMenu);
  FUndoItem.Caption := TAtlasStrings.Text(TAtlasTextId.UndoActionUndo);
  FUndoItem.OnClick := UndoClick;
  FMenu.Items.Add(FUndoItem);
  FRedoItem := TMenuItem.Create(FMenu);
  FRedoItem.Caption := TAtlasStrings.Text(TAtlasTextId.UndoActionRedo);
  FRedoItem.OnClick := RedoClick;
  FMenu.Items.Add(FRedoItem);
  FDiffItem := TMenuItem.Create(FMenu);
  FDiffItem.Caption := TAtlasStrings.Text(TAtlasTextId.UndoActionDiff);
  FDiffItem.OnClick := DiffClick;
  FMenu.Items.Add(FDiffItem);
  // Notizen (#545).
  FNoteEditItem := TMenuItem.Create(FMenu);
  FNoteEditItem.Caption := TAtlasStrings.Text(TAtlasTextId.NotesEdit);
  FNoteEditItem.OnClick := NoteEditClick;
  FMenu.Items.Add(FNoteEditItem);
  FNoteDeleteItem := TMenuItem.Create(FMenu);
  FNoteDeleteItem.Caption := TAtlasStrings.Text(TAtlasTextId.NotesDelete);
  FNoteDeleteItem.OnClick := NoteDeleteClick;
  FMenu.Items.Add(FNoteDeleteItem);
  FTree.PopupMenu := FMenu;
end;

destructor TAtlasResultsFrame.Destroy;
begin
  FData.Free;
  inherited;
end;

class function TAtlasResultsFrame.ReasonText(const AConfidence: TAtlasConfidence): string;
begin
  Result := '';
  if not AConfidence.Inferred then
    Exit;
  if AConfidence.Reason = 'interface' then
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonInterface)
  else if AConfidence.Reason = 'virtual' then
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonVirtual)
  else if AConfidence.Reason = 'ambiguous' then
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonAmbiguous)
  else if AConfidence.Reason = 'unresolved' then
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonUnresolved)
  else if AConfidence.Reason = 'inactiveBranch' then
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonInactiveBranch)
  else if AConfidence.Reason = 'text' then
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonText)
  else
    // Gründe neuerer Server: wie geliefert.
    Result := AConfidence.Reason;
end;

class function TAtlasResultsFrame.EntryText(const AEntry: TAtlasResultEntry): string;
begin
  Result := Format('%d: %s', [AEntry.Line + 1, AEntry.Text]);
  if AEntry.Detail <> '' then
    Result := Result + '  →  ' + AEntry.Detail;
  if AEntry.Confidence.Inferred then
    Result := '≈ ' + Result + '  [' + ReasonText(AEntry.Confidence) + ']';
end;

class function TAtlasResultsFrame.HierarchyText(const AItem: TAtlasHierarchyItem): string;
begin
  Result := AItem.Name;
  if AItem.Detail <> '' then
    Result := Result + ' · ' + AItem.Detail;
  if AItem.FileName <> '' then
    Result := Result + Format('  (%s:%d)', [ExtractFileName(AItem.FileName), AItem.Line + 1]);
  if AItem.Confidence.Inferred then
    Result := '≈ ' + Result + '  [' + ReasonText(AItem.Confidence) + ']';
end;

class function TAtlasResultsFrame.ImpactPlaceText(const APlace: TAtlasImpactPlace): string;
var
  Edge: string;
begin
  if APlace.Terminal then
    Result := APlace.Item.Name + ' · ' + TAtlasStrings.Text(TAtlasTextId.ImpactUnitLevel) +
      Format('  (%s:%d)', [ExtractFileName(APlace.Item.FileName), APlace.UseLine + 1])
  else
    Result := HierarchyText(APlace.Item);
  Edge := '';
  if APlace.Edge = 'reference' then
    Edge := TAtlasStrings.Text(TAtlasTextId.ImpactEdgeReference)
  else if APlace.Edge = 'override' then
    Edge := TAtlasStrings.Text(TAtlasTextId.ImpactEdgeOverride)
  else if APlace.Edge = 'baseMethod' then
    Edge := TAtlasStrings.Text(TAtlasTextId.ImpactEdgeBase)
  else if APlace.Edge = 'interfaceMethod' then
    Edge := TAtlasStrings.Text(TAtlasTextId.ImpactEdgeInterface)
  else if APlace.Edge = 'implementation' then
    Edge := TAtlasStrings.Text(TAtlasTextId.ImpactEdgeImplementation);
  if Edge <> '' then
    Result := Result + '  · ' + Edge;
  if APlace.UseCount > 1 then
    Result := Result + Format('  ×%d', [APlace.UseCount]);
  if APlace.Test <> '' then
    Result := Result + '  · Test';
end;

class function TAtlasResultsFrame.ImpactFormText(const AForm: TAtlasImpactForm): string;
begin
  Result := Format(TAtlasStrings.Text(TAtlasTextId.ImpactForm), [AForm.Text, ExtractFileName(AForm.FileName),
    AForm.Line + 1]);
end;

class function TAtlasResultsFrame.ImpactLimitTexts(const AImpact: TAtlasImpact): TArray<string>;
begin
  Result := nil;
  if AImpact.DepthReached then
    Result := Result + [Format(TAtlasStrings.Text(TAtlasTextId.ImpactLimitDepth), [AImpact.Depth,
      AImpact.Unexpanded])];
  if AImpact.CountReached then
    Result := Result + [Format(TAtlasStrings.Text(TAtlasTextId.ImpactLimitCount), [AImpact.MaxPlaces])];
  if AImpact.TimeReached then
    Result := Result + [Format(TAtlasStrings.Text(TAtlasTextId.ImpactLimitTime), [AImpact.TimeoutMs])];
end;

procedure TAtlasResultsFrame.AddImpactForms(AParent: TTreeNode; const AForms: TArray<TAtlasImpactForm>);
var
  Form: TAtlasImpactForm;
  Data: TNodeData;
begin
  for Form in AForms do
  begin
    Data := Default(TNodeData);
    Data.Kind := TNodeKind.Entry;
    Data.FileName := Form.FileName;
    Data.Line := Form.Line;
    Data.Character := Form.Character;
    AddNode(AParent, ImpactFormText(Form), Data);
  end;
end;

function TAtlasResultsFrame.AddImpactPlace(AParent: TTreeNode; APlace: Integer): TTreeNode;
var
  Place: TAtlasImpactPlace;
  Data: TNodeData;
begin
  Place := FImpact.Places[APlace];
  Data := Default(TNodeData);
  Data.Kind := TNodeKind.Entry;
  // Doppelklick springt zur Verwendung der Ursache in der Stelle.
  Data.FileName := Place.Item.FileName;
  Data.Line := Place.UseLine;
  Data.Character := Place.UseCharacter;
  Data.Hint := Place.Item.Confidence.Explanation;
  Result := AddNode(AParent, ImpactPlaceText(Place), Data);
  AddImpactForms(Result, Place.Forms);
end;

procedure TAtlasResultsFrame.AddImpactBranch(AParent: TTreeNode; ACause: Integer);
var
  Child: Integer;
begin
  // Jede Stelle hat genau eine Ursache: Der Baum endet, Zyklen gibt es nicht.
  for Child in FImpact.Children(ACause) do
    AddImpactBranch(AddImpactPlace(AParent, Child), Child);
end;

procedure TAtlasResultsFrame.ShowImpact(const ATitle: string; const AImpact: TAtlasImpact);
var
  Data: TNodeData;
  Section, Node: TTreeNode;
  Index, Depth: Integer;
  Test: TAtlasImpactTest;
  Limit: string;
begin
  Clear(ATitle);
  FImpact := AImpact;
  FShowsImpact := True;
  FDepthLabel.Visible := True;
  FDepth.Visible := True;
  FRunTests.Visible := True;
  FRunTests.Enabled := Length(AImpact.Tests) > 0;
  if FDepth.Items.Count = 0 then
    for Depth := 1 to 5 do
      FDepth.Items.Add(IntToStr(Depth));
  FDepth.OnChange := nil;
  try
    FDepth.ItemIndex := AImpact.Depth - 1;
  finally
    FDepth.OnChange := DepthChange;
  end;
  Data := Default(TNodeData);
  Data.Kind := TNodeKind.Placeholder;
  FTree.Items.BeginUpdate;
  try
    Section := AddNode(nil, Format(TAtlasStrings.Text(TAtlasTextId.ImpactDirect), [AImpact.LevelCount(1)]), Data);
    AddImpactForms(Section, AImpact.SymbolForms);
    for Index := 0 to High(AImpact.Places) do
      if AImpact.Places[Index].Level = 1 then
        AddImpactPlace(Section, Index);
    Section.Expand(False);
    Section := AddNode(nil, Format(TAtlasStrings.Text(TAtlasTextId.ImpactIndirect), [AImpact.CountFrom(2)]), Data);
    for Index in AImpact.Children(-1) do
      if Length(AImpact.Children(Index)) > 0 then
      begin
        Node := AddImpactPlace(Section, Index);
        AddImpactBranch(Node, Index);
      end;
    Section.Expand(AImpact.CountFrom(2) <= 200);
    if Length(AImpact.Tests) = 0 then
      AddNode(nil, TAtlasStrings.Text(TAtlasTextId.ImpactNoTests), Data)
    else
    begin
      Section := AddNode(nil, Format(TAtlasStrings.Text(TAtlasTextId.ImpactTests), [Length(AImpact.Tests)]), Data);
      for Test in AImpact.Tests do
      begin
        Data.Kind := TNodeKind.Entry;
        Data.FileName := Test.FileName;
        Data.Line := Test.Line;
        Data.Character := 0;
        AddNode(Section, Test.Name + Format('  (%s:%d)', [ExtractFileName(Test.FileName), Test.Line + 1]),
          Data);
      end;
      Data := Default(TNodeData);
      Data.Kind := TNodeKind.Placeholder;
      Section.Expand(False);
    end;
    for Limit in ImpactLimitTexts(AImpact) do
      AddNode(nil, '⚠ ' + Limit, Data);
  finally
    FTree.Items.EndUpdate;
  end;
  if FTree.Items.Count > 0 then
    FTree.Selected := FTree.Items[0];
end;

procedure TAtlasResultsFrame.DepthChange(Sender: TObject);
begin
  if FShowsImpact and (FDepth.ItemIndex >= 0) and Assigned(FOnImpactDepth) then
    FOnImpactDepth(FDepth.ItemIndex + 1);
end;

procedure TAtlasResultsFrame.RunTestsClick(Sender: TObject);
begin
  if FShowsImpact and (Length(FImpact.Tests) > 0) and Assigned(FOnImpactRunTests) then
    FOnImpactRunTests(FImpact);
end;

function TAtlasResultsFrame.AddNode(AParent: TTreeNode; const AText: string; const AData: TNodeData): TTreeNode;
begin
  Result := FTree.Items.AddChild(AParent, AText);
  // Index in FData; 0 wäre nil, deshalb um eins verschoben.
  Result.Data := Pointer(NativeInt(FData.Add(AData) + 1));
end;

function TAtlasResultsFrame.DataOf(ANode: TTreeNode): TNodeData;
var
  Index: NativeInt;
begin
  Result := Default(TNodeData);
  Result.Kind := TNodeKind.Placeholder;
  if ANode = nil then
    Exit;
  Index := NativeInt(ANode.Data) - 1;
  if (Index >= 0) and (Index < FData.Count) then
    Result := FData[Integer(Index)];
end;

procedure TAtlasResultsFrame.Clear(const ATitle: string);
begin
  FShowsChanges := False;
  FShowsNotes := False;
  FOnlySure.Visible := False;
  FShowsImpact := False;
  FDepthLabel.Visible := False;
  FDepth.Visible := False;
  FRunTests.Visible := False;
  FHintNode := nil;
  FTree.Hint := '';
  FTitle.Caption := ATitle;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
  finally
    FTree.Items.EndUpdate;
  end;
  FData.Clear;
end;

procedure TAtlasResultsFrame.AddGroups(AParent: TTreeNode; const AGroups: TArray<TAtlasResultGroup>);
var
  Group: TAtlasResultGroup;
  Entry: TAtlasResultEntry;
  Data: TNodeData;
  GroupNode: TTreeNode;
begin
  for Group in AGroups do
  begin
    Data := Default(TNodeData);
    Data.Kind := TNodeKind.Group;
    Data.FileName := Group.FileName;
    GroupNode := AddNode(AParent, Group.Caption, Data);
    for Entry in Group.Entries do
    begin
      Data := Default(TNodeData);
      Data.Kind := TNodeKind.Entry;
      Data.FileName := Entry.FileName;
      Data.Line := Entry.Line;
      Data.Character := Entry.Character;
      Data.Hint := Entry.Confidence.Explanation;
      AddNode(GroupNode, EntryText(Entry), Data);
    end;
    GroupNode.Expand(False);
  end;
end;

procedure TAtlasResultsFrame.ShowEntries(const ATitle: string; const AGroups: TArray<TAtlasResultGroup>);
begin
  Clear(ATitle);
  FTree.Items.BeginUpdate;
  try
    AddGroups(nil, AGroups);
  finally
    FTree.Items.EndUpdate;
  end;
  if FTree.Items.Count > 0 then
    FTree.Selected := FTree.Items[0];
end;

procedure TAtlasResultsFrame.ShowRated(const ATitle: string; const AEntries: TArray<TAtlasResultEntry>;
  const ASureCaption, AInferredCaption: string);
begin
  FRatedTitle := ATitle;
  FRatedEntries := AEntries;
  FSureCaption := ASureCaption;
  FInferredCaption := AInferredCaption;
  RenderRated;
end;

procedure TAtlasResultsFrame.RenderRated;
var
  Sure, Inferred: TArray<TAtlasResultEntry>;
  Entry: TAtlasResultEntry;
  Data: TNodeData;
  Section: TTreeNode;
begin
  Sure := TAtlasResults.SureOnly(FRatedEntries);
  Inferred := nil;
  for Entry in FRatedEntries do
    if Entry.Confidence.Inferred then
      Inferred := Inferred + [Entry];
  if Length(Inferred) = 0 then
  begin
    ShowEntries(FRatedTitle, TAtlasResults.Group(FRatedEntries));
    Exit;
  end;
  Clear(FRatedTitle);
  FOnlySure.Visible := True;
  FTree.Items.BeginUpdate;
  try
    if FOnlySure.Checked then
      AddGroups(nil, TAtlasResults.Group(Sure))
    else
    begin
      Data := Default(TNodeData);
      Data.Kind := TNodeKind.Placeholder;
      Section := AddNode(nil, Format(FSureCaption, [Length(Sure)]), Data);
      AddGroups(Section, TAtlasResults.Group(Sure));
      Section.Expand(False);
      Section := AddNode(nil, Format(FInferredCaption, [Length(Inferred)]), Data);
      AddGroups(Section, TAtlasResults.Group(Inferred));
      Section.Expand(False);
    end;
  finally
    FTree.Items.EndUpdate;
  end;
  if FTree.Items.Count > 0 then
    FTree.Selected := FTree.Items[0];
end;

procedure TAtlasResultsFrame.OnlySureClick(Sender: TObject);
begin
  // Clear blendet den Filter aus und RenderRated wieder ein; Checked bleibt.
  if Length(FRatedEntries) > 0 then
    RenderRated;
end;

procedure TAtlasResultsFrame.TreeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Node: TTreeNode;
begin
  Node := FTree.GetNodeAt(X, Y);
  if Node = FHintNode then
    Exit;
  FHintNode := Node;
  FTree.Hint := DataOf(Node).Hint;
  Application.CancelHint;
end;

procedure TAtlasResultsFrame.AddHierarchy(AParent: TTreeNode; const AItems: TArray<TAtlasHierarchyItem>);
var
  Item: TAtlasHierarchyItem;
  Data: TNodeData;
  Node: TTreeNode;
begin
  for Item in AItems do
  begin
    Data := Default(TNodeData);
    Data.Kind := TNodeKind.Hierarchy;
    Data.FileName := Item.FileName;
    Data.Line := Item.Line;
    Data.Character := Item.Character;
    Data.Item := Item;
    Data.Hint := Item.Confidence.Explanation;
    Node := AddNode(AParent, HierarchyText(Item), Data);
    // Platzhalter, damit sich der Knoten aufklappen lässt; geladen wird erst dann.
    Data := Default(TNodeData);
    Data.Kind := TNodeKind.Placeholder;
    AddNode(Node, '…', Data);
  end;
end;

procedure TAtlasResultsFrame.ShowHierarchy(const ATitle: string; ADirection: TAtlasHierarchyDirection;
  const ARoots: TArray<TAtlasHierarchyItem>);
begin
  Clear(ATitle);
  FDirection := ADirection;
  FTree.Items.BeginUpdate;
  try
    AddHierarchy(nil, ARoots);
  finally
    FTree.Items.EndUpdate;
  end;
  if FTree.Items.Count > 0 then
  begin
    FTree.Selected := FTree.Items[0];
    FTree.Items[0].Expand(False);
  end;
end;

procedure TAtlasResultsFrame.TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
var
  Index: NativeInt;
  Data: TNodeData;
  Children: TArray<TAtlasHierarchyItem>;
begin
  Data := DataOf(Node);
  if (Data.Kind <> TNodeKind.Hierarchy) or Data.Loaded then
    Exit;
  Index := NativeInt(Node.Data) - 1;
  Data.Loaded := True;
  FData[Integer(Index)] := Data;
  Children := nil;
  if Assigned(FOnExpand) then
  begin
    Screen.Cursor := crHourGlass;
    try
      Children := FOnExpand(FDirection, Data.Item);
    finally
      Screen.Cursor := crDefault;
    end;
  end;
  FTree.Items.BeginUpdate;
  try
    Node.DeleteChildren;
    AddHierarchy(Node, Children);
  finally
    FTree.Items.EndUpdate;
  end;
  AllowExpansion := Node.HasChildren;
end;

procedure TAtlasResultsFrame.ShowChanges(const ATitle: string; const ASets: TArray<TAtlasChangeSet>; ANow: TDateTime;
  AKeepSelection: Boolean);
var
  ChangeSet: TAtlasChangeSet;
  Change: TAtlasFileChange;
  Data: TNodeData;
  SetNode, Selected: TTreeNode;
  PreviousId: Integer;
begin
  PreviousId := 0;
  if AKeepSelection and FShowsChanges then
    PreviousId := SelectedSet.SetId;
  Clear(ATitle);
  FShowsChanges := True;
  Selected := nil;
  FTree.Items.BeginUpdate;
  try
    for ChangeSet in ASets do
    begin
      Data := Default(TNodeData);
      Data.Kind := TNodeKind.ChangeSet;
      Data.SetId := ChangeSet.Id;
      Data.State := ChangeSet.State;
      SetNode := AddNode(nil, TAtlasUndoMessages.SetCaption(ChangeSet, ANow), Data);
      if ChangeSet.Id = PreviousId then
        Selected := SetNode;
      for Change in ChangeSet.Files do
      begin
        Data.Kind := TNodeKind.ChangeFile;
        Data.FileName := Change.FileName;
        AddNode(SetNode, TAtlasUndoMessages.FileCaption(Change), Data);
      end;
    end;
  finally
    FTree.Items.EndUpdate;
  end;
  if Selected <> nil then
    FTree.Selected := Selected
  else if FTree.Items.Count > 0 then
    FTree.Selected := FTree.Items[0];
end;

function TAtlasResultsFrame.SelectedSet: TNodeData;
begin
  Result := DataOf(FTree.Selected);
  if not (Result.Kind in [TNodeKind.ChangeSet, TNodeKind.ChangeFile]) then
    Result := Default(TNodeData);
end;

procedure TAtlasResultsFrame.MenuPopup(Sender: TObject);
var
  Data: TNodeData;
begin
  Data := SelectedSet;
  FUndoItem.Visible := FShowsChanges;
  FRedoItem.Visible := FShowsChanges;
  FDiffItem.Visible := FShowsChanges;
  FUndoItem.Enabled := (Data.SetId > 0) and (Data.State <> TAtlasChangeSetState.Undone);
  FRedoItem.Enabled := (Data.SetId > 0) and (Data.State <> TAtlasChangeSetState.Applied);
  FDiffItem.Enabled := Data.SetId > 0;
  FNoteEditItem.Visible := FShowsNotes;
  FNoteDeleteItem.Visible := FShowsNotes;
  FNoteEditItem.Enabled := SelectedNoteId <> '';
  FNoteDeleteItem.Enabled := SelectedNoteId <> '';
end;

class function TAtlasResultsFrame.NoteGroupText(const AGroup: TAtlasNoteGroup): string;
begin
  if AGroup.Orphaned then
    Result := Format(TAtlasStrings.Text(TAtlasTextId.NotesOrphanGroup), [Length(AGroup.Notes)])
  else
    Result := Format('%s (%d)', [ExtractFileName(AGroup.FileName), Length(AGroup.Notes)]);
end;

class function TAtlasResultsFrame.NoteText(const ANote: TAtlasNote; AOrphaned: Boolean): string;
begin
  if AOrphaned then
    Result := Format(TAtlasStrings.Text(TAtlasTextId.NotesOrphanEntry), [ExtractFileName(ANote.FileName),
      ANote.Line + 1, ANote.Title])
  else
    Result := Format('%d: %s', [ANote.Line + 1, ANote.Title]);
end;

procedure TAtlasResultsFrame.ShowNotes(const ATitle: string; const AGroups: TArray<TAtlasNoteGroup>);
begin
  ShowNotes(ATitle, AGroups, '');
end;

procedure TAtlasResultsFrame.ShowNotes(const ATitle: string; const AGroups: TArray<TAtlasNoteGroup>;
  const ASelectId: string);
var
  Group: TAtlasNoteGroup;
  Note: TAtlasNote;
  Data: TNodeData;
  GroupNode, Node, Selected: TTreeNode;
begin
  Clear(ATitle);
  FShowsNotes := True;
  Selected := nil;
  FTree.Items.BeginUpdate;
  try
    for Group in AGroups do
    begin
      Data := Default(TNodeData);
      Data.Kind := TNodeKind.Group;
      Data.FileName := Group.FileName;
      GroupNode := AddNode(nil, NoteGroupText(Group), Data);
      for Note in Group.Notes do
      begin
        Data := Default(TNodeData);
        Data.Kind := TNodeKind.Note;
        Data.FileName := Note.FileName;
        Data.Line := Note.Line;
        Data.NoteId := Note.Id;
        Node := AddNode(GroupNode, NoteText(Note, Group.Orphaned), Data);
        if (ASelectId <> '') and (Note.Id = ASelectId) then
          Selected := Node;
      end;
      GroupNode.Expand(False);
    end;
  finally
    FTree.Items.EndUpdate;
  end;
  if Selected <> nil then
    FTree.Selected := Selected
  else if FTree.Items.Count > 0 then
    FTree.Selected := FTree.Items[0];
end;

function TAtlasResultsFrame.SelectedNoteId: string;
begin
  Result := DataOf(FTree.Selected).NoteId;
end;

procedure TAtlasResultsFrame.EditSelectedNote;
var
  Id: string;
begin
  Id := SelectedNoteId;
  if (Id <> '') and Assigned(FOnNoteEdit) then
    FOnNoteEdit(Id);
end;

procedure TAtlasResultsFrame.DeleteSelectedNote;
var
  Id: string;
begin
  Id := SelectedNoteId;
  if (Id <> '') and Assigned(FOnNoteDelete) then
    FOnNoteDelete(Id);
end;

procedure TAtlasResultsFrame.NoteEditClick(Sender: TObject);
begin
  EditSelectedNote;
end;

procedure TAtlasResultsFrame.NoteDeleteClick(Sender: TObject);
begin
  DeleteSelectedNote;
end;

procedure TAtlasResultsFrame.ShowSelectedDiff;
var
  Data: TNodeData;
begin
  Data := SelectedSet;
  if (Data.SetId > 0) and Assigned(FOnChangeDiff) then
    FOnChangeDiff(Data.SetId, Data.FileName);
end;

procedure TAtlasResultsFrame.UndoSelected;
var
  Data: TNodeData;
begin
  Data := SelectedSet;
  if (Data.SetId > 0) and Assigned(FOnChangeUndo) then
    FOnChangeUndo(Data.SetId);
end;

procedure TAtlasResultsFrame.RedoSelected;
var
  Data: TNodeData;
begin
  Data := SelectedSet;
  if (Data.SetId > 0) and Assigned(FOnChangeRedo) then
    FOnChangeRedo(Data.SetId);
end;

procedure TAtlasResultsFrame.UndoClick(Sender: TObject);
begin
  UndoSelected;
end;

procedure TAtlasResultsFrame.RedoClick(Sender: TObject);
begin
  RedoSelected;
end;

procedure TAtlasResultsFrame.DiffClick(Sender: TObject);
begin
  ShowSelectedDiff;
end;

procedure TAtlasResultsFrame.OpenSelected;
var
  Data: TNodeData;
begin
  Data := DataOf(FTree.Selected);
  // Atlas-Änderungen (#721): Doppelklick zeigt den Unterschied.
  if Data.Kind in [TNodeKind.ChangeSet, TNodeKind.ChangeFile] then
  begin
    ShowSelectedDiff;
    Exit;
  end;
  // Notizen (#545) springen zu ihrer Zeile, verwaiste zur zuletzt bekannten.
  if (Data.Kind in [TNodeKind.Entry, TNodeKind.Hierarchy, TNodeKind.Note]) and (Data.FileName <> '') and
    Assigned(FOnOpen) then
    FOnOpen(Data.FileName, Data.Line, Data.Character);
end;

procedure TAtlasResultsFrame.TreeDblClick(Sender: TObject);
begin
  OpenSelected;
end;

procedure TAtlasResultsFrame.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    OpenSelected;
    Key := 0;
  end
  else if (Key = VK_DELETE) and FShowsNotes then
  begin
    DeleteSelectedNote;
    Key := 0;
  end;
end;

end.
