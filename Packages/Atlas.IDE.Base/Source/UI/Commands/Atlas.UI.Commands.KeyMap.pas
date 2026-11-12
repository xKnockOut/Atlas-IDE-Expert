unit Atlas.UI.Commands.KeyMap;

// Fenster „Atlas – Tastenkürzel“ (#520), reine VCL: oben das Suchfeld (Taste
// wie „Strg+Umschalt+P“ oder Text aus Befehl, Kategorie, Herkunft), „Nur
// Konflikte“ und die Anzahl; darunter die Liste mit Taste, Befehl, Herkunft
// (IDE, Atlas, Erweiterung), Kontext (global, Editor, Designer,
// Willkommensseite), „Selten per Tastatur“ (Zählung der Tastenkürzel-Tipps,
// #600: „5× Maus, 0× Tastatur“) und Hinweis. Doppelt belegte Kürzel stehen rot, der
// Hinweis sagt, welche Belegung gewinnt und warum. Unten „Als HTML
// exportieren“ (OnExport; die IDE-Schicht schreibt die Datei und öffnet sie im
// Browser), „Tastenkonflikte…“ (OnSettings), „Aktualisieren“ (OnRefresh) und
// „Schließen“. Das Fenster ist nicht modal und schließt mit Esc; es zeigt, was
// SetItems bekommt (ausgewertet mit TAtlasKeyMap.Analyze).
// Grundlage ist TAtlasDialog: Fläche, Liste und Knöpfe zeichnet das IDE-Thema,
// auch nach einem Themenwechsel; eigene Farbe hat nur die Schrift der
// Konflikte (Fehlerfarbe aus TAtlasUiTheme). Die Spalte „Hinweis“ nimmt die
// übrige Breite der Liste (TAtlasListView.FillColumn) und wächst mit dem
// Fenster.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Commands.KeyMap,
  Atlas.UI.Foundation.Dialog,
  Atlas.UI.Foundation.ListView;

type
  /// <summary>Grundlage des Fensters: Texte der Spalten und Hinweise sowie die Ereignisse der Knöpfe.</summary>
  TAtlasKeyMapForm = class(TAtlasDialog)
  private
    FOnExport: TProc;
    FOnSettings: TProc;
    FOnRefresh: TProc;
  protected
    procedure ExportClick(Sender: TObject);
    procedure SettingsClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  public
    /// <summary>Name einer Atlas-Funktion wie in Menü und Einstellungen, ohne „:“ und „…“.</summary>
    class function FunctionCaption(AFunc: TAtlasKeyFunction): string; static;
    class function OriginText(const AItem: TAtlasKeyItem): string; static;
    class function ContextText(AContext: TAtlasKeyContext): string; static;
    class function ReasonText(AReason: TAtlasKeyReason): string; static;
    /// <summary>Hinweis zur Belegung AItems[AIndex]: wer gewinnt und warum; '' ohne Konflikt.</summary>
    class function HintText(const AItems: TArray<TAtlasKeyItem>; AIndex: Integer): string; static;
    /// <summary>Spaltenköpfe: Taste, Befehl, Herkunft, Kontext, Hinweis.</summary>
    class function Headers: TArray<string>; static;
    /// <summary>Zellen der Belegung AItems[AIndex] in der Reihenfolge von Headers.</summary>
    class function Cells(const AItems: TArray<TAtlasKeyItem>; AIndex: Integer): TArray<string>; static;
    /// <summary>Spalte „Selten per Tastatur“ (#600): „5× Maus, 0× Tastatur“, sonst leer.</summary>
    class function RarelyText(const AItem: TAtlasKeyItem): string; static;
    /// <summary>„812 Kürzel, 3 Konflikte“ bzw. „12 von 812 Kürzeln, 3 Konflikte“.</summary>
    class function SummaryText(AShown, ATotal, AConflicts: Integer): string; static;
    property OnExport: TProc read FOnExport write FOnExport;
    property OnSettings: TProc read FOnSettings write FOnSettings;
    property OnRefresh: TProc read FOnRefresh write FOnRefresh;
  end;

  TAtlasKeyMapWindow = class(TAtlasKeyMapForm)
  public const
    /// <summary>Innenbreite und -höhe beim Öffnen, logische Pixel.</summary>
    cWidth = 1150;
    cHeight = 560;
    /// <summary>Mindestbreite der Spalte „Hinweis“, logische Pixel.</summary>
    cHintMinWidth = 240;
  private
    FItems: TArray<TAtlasKeyItem>;
    FShown: TArray<Integer>;
    FTop: TPanel;
    FBottom: TPanel;
    FSearch: TEdit;
    FOnlyConflicts: TCheckBox;
    FSummary: TLabel;
    FList: TAtlasListView;
    FButtons: TAtlasButtonRow;
    FExportButton: TButton;
    FSettingsButton: TButton;
    FRefreshButton: TButton;
    FCloseButton: TButton;
    procedure ApplyFilter;
    procedure SearchChange(Sender: TObject);
    procedure OnlyConflictsClick(Sender: TObject);
    procedure ListData(Sender: TObject; Item: TListItem);
    procedure ListCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    function AddButton(const ACaption: string; AOnClick: TNotifyEvent): TButton;
    function StyleColor(AColor: TColor): TColor;
    /// <summary>Kopf mit Suchfeld, „Nur Konflikte“ und Anzahl.</summary>
    procedure CreateTop;
    /// <summary>Fuß mit den Knöpfen.</summary>
    procedure CreateBottom;
    /// <summary>Liste mit den Spalten aus Headers.</summary>
    procedure CreateList;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    /// <summary>Nach dem Anwenden des Themas (das Fenster ist neu erzeugt): Zeilenzahl der virtuellen Liste und
    /// Breite der Spalte „Hinweis“ neu setzen.</summary>
    procedure DoShow; override;
    procedure ThemeChanged; override;
  public
    constructor CreateKeyMap(AOwner: TComponent);
    /// <summary>Druckbare HTML-Seite der gezeigten Zeilen; ACreated ist der Zeitpunkt als Text.</summary>
    function ExportHtml(const ACreated: string): string;
    /// <summary>Belegungen setzen (auch bei offenem Fenster); Suche und Filter bleiben.</summary>
    procedure SetItems(const AItems: TArray<TAtlasKeyItem>);
    /// <summary>Suchtext setzen, z. B. für einen Einstieg mit Taste (#600, #766).</summary>
    procedure SetQuery(const AText: string);
    property Items: TArray<TAtlasKeyItem> read FItems;
    /// <summary>Indizes in Items der gezeigten Zeilen, in Reihenfolge der Liste.</summary>
    property Shown: TArray<Integer> read FShown;
    property List: TAtlasListView read FList;
    property SearchEdit: TEdit read FSearch;
    property OnlyConflictsBox: TCheckBox read FOnlyConflicts;
    property SummaryLabel: TLabel read FSummary;
    property ExportButton: TButton read FExportButton;
    property SettingsButton: TButton read FSettingsButton;
    property RefreshButton: TButton read FRefreshButton;
    property CloseButton: TButton read FCloseButton;
  end;

implementation

uses
  Vcl.Themes,
  Winapi.Windows,
  Atlas.Core.Style.Signal,
  Atlas.UI.Foundation.Theme,
  Atlas.UI.Strings,
  Atlas.UI.Commands.Strings;

const
  /// <summary>Breiten der Spalten Taste bis „Selten per Tastatur“, logische Pixel; „Hinweis“ füllt den Rest.</summary>
  cColumnWidths: array[0..4] of Integer = (140, 260, 90, 120, 140);

/// <summary>Text ohne „:“ und „…“ am Ende.</summary>
function Plain(const AText: string): string;
begin
  Result := Trim(AText);
  while (Result <> '') and ((Result[Length(Result)] = ':') or (Result[Length(Result)] = '…') or
    (Result[Length(Result)] = '.')) do
  begin
    Result := TrimRight(Copy(Result, 1, Length(Result) - 1));
  end;
end;

const
  /// <summary>Text je Atlas-Funktion (Name wie in Menü und Einstellungen). Bei Deklaration ⇄ Implementierung trägt
  /// die erste Taste den Namen des Befehls (Tipps #600), die zweite den Zusatz „Taste 2“.</summary>
  cFunctionTexts: array[TAtlasKeyFunction] of TAtlasTextId = (
    TAtlasTextId.SettingsPaletteKey, // Palette
    TAtlasTextId.SettingsCheckKey, // Check
    TAtlasTextId.SettingsCompletionKey, // Completion
    TAtlasTextId.SettingsSignatureKey, // Signature
    TAtlasTextId.SettingsQuickToggleKey, // QuickToggle
    TAtlasTextId.SettingsDiagnosticModeKey, // DiagnosticMode
    TAtlasTextId.EditorActions, // CodeActions
    TAtlasTextId.EditorExpand, // ExpandSelection
    TAtlasTextId.EditorShrink, // ShrinkSelection
    TAtlasTextId.MenuImplementations, // GoToImplementation
    TAtlasTextId.EditorTypeDefinition, // TypeDefinition
    TAtlasTextId.UndoMenu, // UndoChange
    TAtlasTextId.RedoMenu, // RedoChange
    TAtlasTextId.SettingsWelcomeSearchKey, // WelcomeSearch
    TAtlasTextId.EditorMethodToggle, // MethodToggleUp
    TAtlasTextId.SettingsMethodToggleDown, // MethodToggleDown
    TAtlasTextId.EditorTestUnit, // TestUnit
    TAtlasTextId.UnitSearchTitle, // UnitSearch
    TAtlasTextId.KeyMapUnitSearchIde, // UnitSearchIde
    TAtlasTextId.BookmarksMenuAdd, // Bookmark
    TAtlasTextId.GenerateMenuCommand, // GenerateMenu
    TAtlasTextId.NotificationsCommand, // Notifications
    TAtlasTextId.SettingsWelcomeQuickActionsBuildKey, // WelcomeQuickBuild
    TAtlasTextId.SettingsWelcomeQuickActionsTestKey, // WelcomeQuickTests
    TAtlasTextId.HideElementCommand, // HideElement
    TAtlasTextId.ProblemNextCommand, // NextProblem
    TAtlasTextId.ProblemPreviousCommand, // PreviousProblem
    TAtlasTextId.QuickOpenTitle, // QuickOpen
    TAtlasTextId.NavBackCommand, // NavBack
    TAtlasTextId.NavForwardCommand, // NavForward
    TAtlasTextId.NavLastEditCommand, // LastEdit
    TAtlasTextId.PeekDefinitionCommand, // PeekDefinition
    TAtlasTextId.PeekReferencesCommand, // PeekReferences
    TAtlasTextId.BreadcrumbsCommand, // Breadcrumbs
    TAtlasTextId.JumpToMatchCommand, // JumpToMatch
    TAtlasTextId.JumpToMatchSelectCommand, // JumpToMatchSelect
    TAtlasTextId.NextChangeCommand, // NextChange
    TAtlasTextId.PreviousChangeCommand, // PreviousChange
    TAtlasTextId.MoveLinesUpCommand, // MoveLinesUp
    TAtlasTextId.MoveLinesDownCommand, // MoveLinesDown
    TAtlasTextId.DuplicateLinesUpCommand, // DuplicateLinesUp
    TAtlasTextId.DuplicateLinesDownCommand, // DuplicateLinesDown
    TAtlasTextId.CompleteStatementCommand, // CompleteStatement
    TAtlasTextId.MultiCursorNextCommand, // MultiCursorNext
    TAtlasTextId.MultiCursorSkipCommand, // MultiCursorSkip
    TAtlasTextId.MultiCursorLineEndsCommand, // MultiCursorLineEnds
    TAtlasTextId.MultiCursorAboveCommand, // MultiCursorAbove
    TAtlasTextId.MultiCursorBelowCommand, // MultiCursorBelow
    TAtlasTextId.SearchCommand, // Search
    TAtlasTextId.SearchNextCommand, // SearchNext
    TAtlasTextId.SearchPreviousCommand, // SearchPrevious
    TAtlasTextId.SearchInMethodCommand, // SearchMethod
    TAtlasTextId.FormatCodeCommand, // FormatCode
    TAtlasTextId.ToggleBlockCommentCommand, // ToggleBlockComment
    TAtlasTextId.NewLineBelowCommand, // NewLineBelow
    TAtlasTextId.NewLineAboveCommand, // NewLineAbove
    TAtlasTextId.UnwrapCommand, // Unwrap
    TAtlasTextId.ProblemsWindowCommand, // ProblemsWindow
    TAtlasTextId.GotoInterfaceCommand, // SectionInterface
    TAtlasTextId.GotoImplementationCommand, // SectionImplementation
    TAtlasTextId.QuickBookmarkToggleCommand, // QuickBookmark
    TAtlasTextId.QuickBookmarkSetCommand, // QuickBookmarkSet
    TAtlasTextId.QuickBookmarkJumpCommand, // QuickBookmarkJump
    TAtlasTextId.NextBookmarkCommand, // NextBookmark
    TAtlasTextId.PreviousBookmarkCommand, // PreviousBookmark
    TAtlasTextId.SearchReplaceCommand, // SearchReplace
    TAtlasTextId.StepIntoTargetCommand, // StepIntoTarget
    TAtlasTextId.ExpressionTypeCommand, // ExpressionType
    TAtlasTextId.SafeDeleteCommand, // SafeDelete
    TAtlasTextId.CreateIssueCommand, // CreateIssue
    TAtlasTextId.DesignerBarSearchHint, // DesignerSearch
    TAtlasTextId.ProblemsCheckFileCommand, // CheckFile
    TAtlasTextId.SectionAppendCommand, // SectionAppend
    TAtlasTextId.DesignerSelectionSetsSaveCommand, // DesignerSelectionSetsSave
    TAtlasTextId.DesignerShowComponentCommand, // DesignerShowComponent
    TAtlasTextId.DesignerInlineCaptionCommand, // DesignerInlineCaption
    TAtlasTextId.DesignerSelectionBarCommand, // DesignerSelectionBar
    TAtlasTextId.DesignerMagnifierCommand, // DesignerMagnifier
    TAtlasTextId.DesignerUsagesCommand); // DesignerUsages

{ TAtlasKeyMapForm, TAtlasKeyMapWindow }

constructor TAtlasKeyMapWindow.CreateKeyMap(AOwner: TComponent);
begin
  inherited CreateDialog(AOwner, TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapTitle), cWidth);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu, biMaximize];
  KeyPreview := True;
  ClientHeight := ScaleValue(cHeight);
  Constraints.MinWidth := ScaleValue(640);
  Constraints.MinHeight := ScaleValue(320);
  OnClose := FormClose;
  CreateTop;
  CreateBottom;
  CreateList;
  ApplyFilter;
end;

procedure TAtlasKeyMapWindow.CreateTop;
begin
  FTop := TPanel.Create(Self);
  FTop.Height := ScaleValue(40);
  FTop.Align := alTop;
  FTop.Parent := Self;
  FTop.BevelOuter := bvNone;
  FSearch := TEdit.Create(Self);
  FSearch.Parent := FTop;
  FSearch.SetBounds(ScaleValue(12), ScaleValue(9), ScaleValue(360), ScaleValue(23));
  FSearch.TextHint := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapSearchHint);
  FSearch.OnChange := SearchChange;
  FOnlyConflicts := TCheckBox.Create(Self);
  FOnlyConflicts.Parent := FTop;
  FOnlyConflicts.SetBounds(ScaleValue(388), ScaleValue(11), ScaleValue(180), ScaleValue(19));
  FOnlyConflicts.Caption := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapOnlyConflicts);
  FOnlyConflicts.OnClick := OnlyConflictsClick;
  FSummary := TLabel.Create(Self);
  FSummary.Parent := FTop;
  // Rechts im Kopf, mit dem Fenster mitwachsend (alRight statt Anker: die Breite steht erst nach dem Anzeigen fest).
  FSummary.AutoSize := False;
  FSummary.Align := alRight;
  FSummary.AlignWithMargins := True;
  FSummary.Margins.SetBounds(ScaleValue(8), 0, ScaleValue(12), 0);
  FSummary.Width := ScaleValue(300);
  FSummary.Alignment := taRightJustify;
  FSummary.Layout := tlCenter;
end;

procedure TAtlasKeyMapWindow.CreateBottom;
begin
  FBottom := TPanel.Create(Self);
  FBottom.Height := ScaleValue(44);
  FBottom.Align := alBottom;
  FBottom.Parent := Self;
  FBottom.BevelOuter := bvNone;
  FCloseButton := TButton.Create(Self);
  FCloseButton.Parent := FBottom;
  FCloseButton.Caption := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapClose);
  FCloseButton.OnClick := CloseClick;
  FCloseButton.Align := alRight;
  FCloseButton.AlignWithMargins := True;
  FCloseButton.Margins.SetBounds(ScaleValue(8), ScaleValue(9), ScaleValue(12), ScaleValue(9));
  FCloseButton.Cancel := True;
  // Knöpfe links in der Knopfleiste der Atlas-Dialoge: Breite nach dem Text (auch englisch).
  FButtons := TAtlasButtonRow.Create(Self);
  FButtons.Parent := FBottom;
  FButtons.AutoSize := False;
  FButtons.Align := alClient;
  FButtons.Margins.SetBounds(ScaleValue(12), ScaleValue(9), 0, 0);
  FCloseButton.Width := FButtons.ButtonWidth(FCloseButton.Caption);
  FExportButton := AddButton(TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapExport), ExportClick);
  FSettingsButton := AddButton(TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapConflictsButton), SettingsClick);
  FRefreshButton := AddButton(TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapRefresh), RefreshClick);
end;

procedure TAtlasKeyMapWindow.CreateList;
var
  mHeaders: TArray<string>;
  mIndex: Integer;
begin
  FList := TAtlasListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(ScaleValue(12), 0, ScaleValue(12), 0);
  FList.OwnerData := True;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.OnData := ListData;
  FList.OnCustomDrawItem := ListCustomDrawItem;
  mHeaders := Headers;
  for mIndex := 0 to High(mHeaders) do
  begin
    if mIndex <= High(cColumnWidths) then
    begin
      FList.AddColumn(mHeaders[mIndex], cColumnWidths[mIndex]);
    end
    else
    begin
      FList.AddColumn(mHeaders[mIndex], cHintMinWidth);
    end;
  end;
  // „Hinweis“ (letzte Spalte) nimmt die übrige Breite, statt rechts abgeschnitten zu werden.
  FList.FillColumn(High(mHeaders), cHintMinWidth);
end;

function TAtlasKeyMapWindow.AddButton(const ACaption: string; AOnClick: TNotifyEvent): TButton;
begin
  Result := FButtons.AddButton(ACaption);
  Result.OnClick := AOnClick;
end;

function TAtlasKeyMapWindow.StyleColor(AColor: TColor): TColor;
begin
  Result := StyleServices(FList).GetSystemColor(AColor);
end;

class function TAtlasKeyMapForm.FunctionCaption(AFunc: TAtlasKeyFunction): string;
begin
  Result := Plain(TAtlasStrings.Text(cFunctionTexts[AFunc]));
end;

class function TAtlasKeyMapForm.OriginText(const AItem: TAtlasKeyItem): string;
begin
  case AItem.Origin of
    TAtlasKeyOrigin.Atlas:
      Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapOriginAtlas);
    TAtlasKeyOrigin.Plugin:
      Result := TAtlasCommandsStrings.Fmt(TAtlasCommandsTextId.KeyMapOriginPlugin, [AItem.OriginName]);
  else
    Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapOriginIde);
  end;
end;

class function TAtlasKeyMapForm.ContextText(AContext: TAtlasKeyContext): string;
begin
  case AContext of
    TAtlasKeyContext.Editor:
      Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapContextEditor);
    TAtlasKeyContext.Designer:
      Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapContextDesigner);
    TAtlasKeyContext.WelcomePage:
      Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapContextWelcome);
  else
    Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapContextGlobal);
  end;
end;

class function TAtlasKeyMapForm.ReasonText(AReason: TAtlasKeyReason): string;
begin
  case AReason of
    TAtlasKeyReason.AtlasPriority:
      Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapReasonAtlasPriority);
    TAtlasKeyReason.AtlasYields:
      Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapReasonAtlasYields);
    TAtlasKeyReason.EditorBinding:
      Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapReasonEditorBinding);
    TAtlasKeyReason.LastBinding:
      Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapReasonLastBinding);
    TAtlasKeyReason.FirstAction:
      Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapReasonFirstAction);
    TAtlasKeyReason.OwnWindow:
      Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapReasonOwnWindow);
    TAtlasKeyReason.NoneActive:
      Result := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapNoneActive);
  else
    Result := '';
  end;
end;

class function TAtlasKeyMapForm.HintText(const AItems: TArray<TAtlasKeyItem>; AIndex: Integer): string;
var
  mItem: TAtlasKeyItem;
begin
  Result := '';
  if (AIndex < 0) or (AIndex > High(AItems)) or not AItems[AIndex].Conflict then
  begin
    Exit;
  end;
  mItem := AItems[AIndex];
  if mItem.Winner < 0 then
  begin
    Result := ReasonText(TAtlasKeyReason.NoneActive);
  end
  else if mItem.Wins then
  begin
    Result := TAtlasCommandsStrings.Fmt(TAtlasCommandsTextId.KeyMapWins, [ReasonText(mItem.Reason)]);
  end
  else
  begin
    Result := TAtlasCommandsStrings.Fmt(TAtlasCommandsTextId.KeyMapLoses, [AItems[mItem.Winner].Command,
      OriginText(AItems[mItem.Winner]), ReasonText(mItem.Reason)]);
  end;
end;

class function TAtlasKeyMapForm.Headers: TArray<string>;
begin
  Result := [TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapColumnKey),
    TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapColumnCommand),
    TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapColumnOrigin),
    TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapColumnContext),
    TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapColumnRarely),
    TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapColumnHint)];
end;

class function TAtlasKeyMapForm.Cells(const AItems: TArray<TAtlasKeyItem>; AIndex: Integer): TArray<string>;
begin
  Result := [AItems[AIndex].KeyText, AItems[AIndex].Command, OriginText(AItems[AIndex]),
    ContextText(AItems[AIndex].Context), RarelyText(AItems[AIndex]), HintText(AItems, AIndex)];
end;

class function TAtlasKeyMapForm.RarelyText(const AItem: TAtlasKeyItem): string;
begin
  // Aus der Zählung der Tastenkürzel-Tipps (#600); leer, solange der Befehl selten genutzt oder nicht gezählt ist.
  if AItem.RarelyByKeyboard then
  begin
    Result := TAtlasCommandsStrings.Fmt(TAtlasCommandsTextId.KeyMapRarely, [AItem.MouseUses, AItem.KeyUses]);
  end
  else
  begin
    Result := '';
  end;
end;

class function TAtlasKeyMapForm.SummaryText(AShown, ATotal, AConflicts: Integer): string;
begin
  if AShown = ATotal then
  begin
    Result := TAtlasCommandsStrings.Fmt(TAtlasCommandsTextId.KeyMapSummary, [ATotal, AConflicts]);
  end
  else
  begin
    Result := TAtlasCommandsStrings.Fmt(TAtlasCommandsTextId.KeyMapSummaryFiltered, [AShown, ATotal, AConflicts]);
  end;
end;

function TAtlasKeyMapWindow.ExportHtml(const ACreated: string): string;
var
  mRows: TArray<TAtlasKeyHtmlRow>;
  mIndex: Integer;
  mSubtitle: string;
begin
  mRows := nil;
  for mIndex in FShown do
  begin
    mRows := mRows + [TAtlasKeyHtmlRow.Create(Cells(FItems, mIndex), FItems[mIndex].Conflict)];
  end;
  mSubtitle := TAtlasCommandsStrings.Fmt(TAtlasCommandsTextId.KeyMapCreated, [ACreated,
    SummaryText(Length(FShown), Length(FItems), TAtlasKeyMap.ConflictCount(FItems))]);
  if Trim(FSearch.Text) <> '' then
  begin
    mSubtitle := mSubtitle + ' · ' + TAtlasCommandsStrings.Fmt(TAtlasCommandsTextId.KeyMapFilter, [Trim(FSearch.Text)]);
  end;
  if TAtlasStrings.Language = TAtlasLanguage.German then
  begin
    Result := TAtlasKeyMap.Html('de', TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapTitle), mSubtitle,
      TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapPrint), Headers, mRows);
  end
  else
  begin
    Result := TAtlasKeyMap.Html('en', TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapTitle), mSubtitle,
      TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapPrint), Headers, mRows);
  end;
end;

procedure TAtlasKeyMapWindow.ApplyFilter;
begin
  FShown := TAtlasKeyMap.Filter(FItems, FSearch.Text, FOnlyConflicts.Checked);
  FList.Items.Count := Length(FShown);
  FList.FitColumns;
  FList.Invalidate;
  FSummary.Caption := SummaryText(Length(FShown), Length(FItems), TAtlasKeyMap.ConflictCount(FItems));
end;

procedure TAtlasKeyMapWindow.SetItems(const AItems: TArray<TAtlasKeyItem>);
begin
  FItems := AItems;
  ApplyFilter;
end;

procedure TAtlasKeyMapWindow.DoShow;
begin
  inherited;
  ApplyFilter;
end;

procedure TAtlasKeyMapWindow.ThemeChanged;
begin
  inherited;
  ApplyFilter;
end;

procedure TAtlasKeyMapWindow.SetQuery(const AText: string);
begin
  FSearch.Text := AText;
  ApplyFilter;
end;

procedure TAtlasKeyMapWindow.SearchChange(Sender: TObject);
begin
  ApplyFilter;
end;

procedure TAtlasKeyMapWindow.OnlyConflictsClick(Sender: TObject);
begin
  ApplyFilter;
end;

procedure TAtlasKeyMapWindow.ListData(Sender: TObject; Item: TListItem);
var
  mValues: TArray<string>;
  mIndex: Integer;
begin
  if (Item.Index < 0) or (Item.Index > High(FShown)) then
  begin
    Exit;
  end;
  mValues := Cells(FItems, FShown[Item.Index]);
  Item.Caption := mValues[0];
  for mIndex := 1 to High(mValues) do
  begin
    Item.SubItems.Add(mValues[mIndex]);
  end;
end;

procedure TAtlasKeyMapWindow.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  if (Item.Index < 0) or (Item.Index > High(FShown)) then
  begin
    Exit;
  end;
  // Hintergrund und Schrift in den Farben des Themas, sonst zeichnet die Zeile weiß bzw. schwarz (clWindow,
  // clWindowText ohne Stil).
  if cdsSelected in State then
  begin
    Sender.Canvas.Font.Color := StyleColor(clHighlightText);
  end
  else
  begin
    Sender.Canvas.Brush.Color := StyleColor(clWindow);
    Sender.Canvas.Font.Color := StyleColor(clWindowText);
  end;
  // Doppelt belegte Kürzel in der Fehlerfarbe der Fensterfläche (#520); ausgewählt in der Farbe der Auswahl.
  if FItems[FShown[Item.Index]].Conflict and not (cdsSelected in State) then
  begin
    Sender.Canvas.Font.Color := TAtlasUiTheme.TextColor(TAtlasSignalKind.Error);
  end;
end;

procedure TAtlasKeyMapForm.ExportClick(Sender: TObject);
begin
  if Assigned(FOnExport) then
  begin
    FOnExport();
  end;
end;

procedure TAtlasKeyMapForm.SettingsClick(Sender: TObject);
begin
  if Assigned(FOnSettings) then
  begin
    FOnSettings();
  end;
end;

procedure TAtlasKeyMapForm.RefreshClick(Sender: TObject);
begin
  if Assigned(FOnRefresh) then
  begin
    FOnRefresh();
  end;
end;

procedure TAtlasKeyMapForm.CloseClick(Sender: TObject);
begin
  Close;
end;

procedure TAtlasKeyMapForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  // Nur verstecken: Die IDE-Schicht hält das Fenster und gibt es beim Entladen frei.
  Action := caHide;
end;

procedure TAtlasKeyMapWindow.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and (Shift = []) then
  begin
    Key := 0;
    Close;
    Exit;
  end;
  inherited;
end;

end.
