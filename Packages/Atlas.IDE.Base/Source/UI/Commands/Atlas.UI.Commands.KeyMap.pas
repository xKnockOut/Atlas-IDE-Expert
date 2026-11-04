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
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Commands.KeyMap;

type
  /// <summary>Grundlage des Fensters: Texte der Spalten und Hinweise sowie die Ereignisse der Knöpfe.</summary>
  TAtlasKeyMapForm = class(TForm)
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
  private
    FColors: TAtlasColors;
    FItems: TArray<TAtlasKeyItem>;
    FShown: TArray<Integer>;
    FTop: TPanel;
    FBottom: TPanel;
    FSearch: TEdit;
    FOnlyConflicts: TCheckBox;
    FSummary: TLabel;
    FList: TListView;
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
    /// <summary>Kopf mit Suchfeld, „Nur Konflikte“ und Anzahl.</summary>
    procedure CreateTop;
    /// <summary>Fuß mit den Knöpfen.</summary>
    procedure CreateBottom;
    /// <summary>Liste mit den Spalten aus Headers.</summary>
    procedure CreateList;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor CreateKeyMap(AOwner: TComponent; const AColors: TAtlasColors);
    /// <summary>Druckbare HTML-Seite der gezeigten Zeilen; ACreated ist der Zeitpunkt als Text.</summary>
    function ExportHtml(const ACreated: string): string;
    /// <summary>Belegungen setzen (auch bei offenem Fenster); Suche und Filter bleiben.</summary>
    procedure SetItems(const AItems: TArray<TAtlasKeyItem>);
    procedure SetColors(const AColors: TAtlasColors);
    /// <summary>Suchtext setzen, z. B. für einen Einstieg mit Taste (#600, #766).</summary>
    procedure SetQuery(const AText: string);
    property Items: TArray<TAtlasKeyItem> read FItems;
    /// <summary>Indizes in Items der gezeigten Zeilen, in Reihenfolge der Liste.</summary>
    property Shown: TArray<Integer> read FShown;
    property List: TListView read FList;
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
  Winapi.Windows,
  Atlas.UI.Strings;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

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
    TAtlasTextId.DesignerBarSearchHint); // DesignerSearch

{ TAtlasKeyMapForm, TAtlasKeyMapWindow }

constructor TAtlasKeyMapWindow.CreateKeyMap(AOwner: TComponent; const AColors: TAtlasColors);
begin
  inherited CreateNew(AOwner);
  Caption := TAtlasStrings.Text(TAtlasTextId.KeyMapTitle);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu, biMaximize];
  Position := poMainFormCenter;
  KeyPreview := True;
  Width := 900;
  Height := 560;
  Constraints.MinWidth := 560;
  Constraints.MinHeight := 320;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  OnClose := FormClose;
  CreateTop;
  CreateBottom;
  CreateList;
  SetColors(AColors);
  ApplyFilter;
end;

procedure TAtlasKeyMapWindow.CreateTop;
begin
  FTop := TPanel.Create(Self);
  FTop.Parent := Self;
  FTop.Align := alTop;
  FTop.Height := 40;
  FTop.BevelOuter := bvNone;
  FTop.ParentBackground := False;
  FSearch := TEdit.Create(Self);
  FSearch.Parent := FTop;
  FSearch.SetBounds(12, 9, 360, 23);
  FSearch.TextHint := TAtlasStrings.Text(TAtlasTextId.KeyMapSearchHint);
  FSearch.OnChange := SearchChange;
  FOnlyConflicts := TCheckBox.Create(Self);
  FOnlyConflicts.Parent := FTop;
  FOnlyConflicts.SetBounds(388, 11, 160, 19);
  FOnlyConflicts.Caption := TAtlasStrings.Text(TAtlasTextId.KeyMapOnlyConflicts);
  FOnlyConflicts.OnClick := OnlyConflictsClick;
  FSummary := TLabel.Create(Self);
  FSummary.Parent := FTop;
  // Rechts im Kopf, mit dem Fenster mitwachsend (alRight statt Anker: die Breite steht erst nach dem Anzeigen fest).
  FSummary.AutoSize := False;
  FSummary.Align := alRight;
  FSummary.AlignWithMargins := True;
  FSummary.Margins.SetBounds(8, 0, 12, 0);
  FSummary.Width := 300;
  FSummary.Alignment := taRightJustify;
  FSummary.Layout := tlCenter;
end;

procedure TAtlasKeyMapWindow.CreateBottom;
begin
  FBottom := TPanel.Create(Self);
  FBottom.Parent := Self;
  FBottom.Align := alBottom;
  FBottom.Height := 44;
  FBottom.BevelOuter := bvNone;
  FBottom.ParentBackground := False;
  FExportButton := AddButton(TAtlasStrings.Text(TAtlasTextId.KeyMapExport), ExportClick);
  FExportButton.SetBounds(12, 9, 150, 26);
  FSettingsButton := AddButton(TAtlasStrings.Text(TAtlasTextId.KeyMapConflictsButton), SettingsClick);
  FSettingsButton.SetBounds(170, 9, 140, 26);
  FRefreshButton := AddButton(TAtlasStrings.Text(TAtlasTextId.KeyMapRefresh), RefreshClick);
  FRefreshButton.SetBounds(318, 9, 120, 26);
  FCloseButton := AddButton(TAtlasStrings.Text(TAtlasTextId.KeyMapClose), CloseClick);
  FCloseButton.Align := alRight;
  FCloseButton.AlignWithMargins := True;
  FCloseButton.Margins.SetBounds(8, 9, 12, 9);
  FCloseButton.Width := 100;
  FCloseButton.Cancel := True;
end;

procedure TAtlasKeyMapWindow.CreateList;
var
  mColumn: TListColumn;
  mHeader: string;
  mWidths: TArray<Integer>;
  mIndex: Integer;
begin
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(12, 0, 12, 0);
  FList.ViewStyle := vsReport;
  FList.OwnerData := True;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.OnData := ListData;
  FList.OnCustomDrawItem := ListCustomDrawItem;
  mWidths := [150, 260, 130, 110, 150, 400];
  mIndex := 0;
  for mHeader in Headers do
  begin
    mColumn := FList.Columns.Add;
    mColumn.Caption := mHeader;
    mColumn.Width := mWidths[mIndex];
    Inc(mIndex);
  end;
end;

function TAtlasKeyMapWindow.AddButton(const ACaption: string; AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := FBottom;
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
end;

class function TAtlasKeyMapForm.FunctionCaption(AFunc: TAtlasKeyFunction): string;
begin
  Result := Plain(TAtlasStrings.Text(cFunctionTexts[AFunc]));
end;

class function TAtlasKeyMapForm.OriginText(const AItem: TAtlasKeyItem): string;
begin
  case AItem.Origin of
    TAtlasKeyOrigin.Atlas:
      Result := TAtlasStrings.Text(TAtlasTextId.KeyMapOriginAtlas);
    TAtlasKeyOrigin.Plugin:
      Result := TAtlasStrings.Fmt(TAtlasTextId.KeyMapOriginPlugin, [AItem.OriginName]);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.KeyMapOriginIde);
  end;
end;

class function TAtlasKeyMapForm.ContextText(AContext: TAtlasKeyContext): string;
begin
  case AContext of
    TAtlasKeyContext.Editor:
      Result := TAtlasStrings.Text(TAtlasTextId.KeyMapContextEditor);
    TAtlasKeyContext.Designer:
      Result := TAtlasStrings.Text(TAtlasTextId.KeyMapContextDesigner);
    TAtlasKeyContext.WelcomePage:
      Result := TAtlasStrings.Text(TAtlasTextId.KeyMapContextWelcome);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.KeyMapContextGlobal);
  end;
end;

class function TAtlasKeyMapForm.ReasonText(AReason: TAtlasKeyReason): string;
begin
  case AReason of
    TAtlasKeyReason.AtlasPriority:
      Result := TAtlasStrings.Text(TAtlasTextId.KeyMapReasonAtlasPriority);
    TAtlasKeyReason.AtlasYields:
      Result := TAtlasStrings.Text(TAtlasTextId.KeyMapReasonAtlasYields);
    TAtlasKeyReason.EditorBinding:
      Result := TAtlasStrings.Text(TAtlasTextId.KeyMapReasonEditorBinding);
    TAtlasKeyReason.LastBinding:
      Result := TAtlasStrings.Text(TAtlasTextId.KeyMapReasonLastBinding);
    TAtlasKeyReason.FirstAction:
      Result := TAtlasStrings.Text(TAtlasTextId.KeyMapReasonFirstAction);
    TAtlasKeyReason.OwnWindow:
      Result := TAtlasStrings.Text(TAtlasTextId.KeyMapReasonOwnWindow);
    TAtlasKeyReason.NoneActive:
      Result := TAtlasStrings.Text(TAtlasTextId.KeyMapNoneActive);
  else
    Result := '';
  end;
end;

class function TAtlasKeyMapForm.HintText(const AItems: TArray<TAtlasKeyItem>; AIndex: Integer): string;
var
  Item: TAtlasKeyItem;
begin
  Result := '';
  if (AIndex < 0) or (AIndex > High(AItems)) or not AItems[AIndex].Conflict then
  begin
    Exit;
  end;
  Item := AItems[AIndex];
  if Item.Winner < 0 then
  begin
    Result := ReasonText(TAtlasKeyReason.NoneActive);
  end
  else if Item.Wins then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.KeyMapWins, [ReasonText(Item.Reason)]);
  end
  else
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.KeyMapLoses, [AItems[Item.Winner].Command,
      OriginText(AItems[Item.Winner]), ReasonText(Item.Reason)]);
  end;
end;

class function TAtlasKeyMapForm.Headers: TArray<string>;
begin
  Result := [TAtlasStrings.Text(TAtlasTextId.KeyMapColumnKey), TAtlasStrings.Text(TAtlasTextId.KeyMapColumnCommand),
    TAtlasStrings.Text(TAtlasTextId.KeyMapColumnOrigin), TAtlasStrings.Text(TAtlasTextId.KeyMapColumnContext),
    TAtlasStrings.Text(TAtlasTextId.KeyMapColumnRarely), TAtlasStrings.Text(TAtlasTextId.KeyMapColumnHint)];
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
    Result := TAtlasStrings.Fmt(TAtlasTextId.KeyMapRarely, [AItem.MouseUses, AItem.KeyUses]);
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
    Result := TAtlasStrings.Fmt(TAtlasTextId.KeyMapSummary, [ATotal, AConflicts]);
  end
  else
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.KeyMapSummaryFiltered, [AShown, ATotal, AConflicts]);
  end;
end;

function TAtlasKeyMapWindow.ExportHtml(const ACreated: string): string;
var
  Rows: TArray<TAtlasKeyHtmlRow>;
  Index: Integer;
  Subtitle: string;
begin
  Rows := nil;
  for Index in FShown do
  begin
    Rows := Rows + [TAtlasKeyHtmlRow.Create(Cells(FItems, Index), FItems[Index].Conflict)];
  end;
  Subtitle := TAtlasStrings.Fmt(TAtlasTextId.KeyMapCreated, [ACreated,
    SummaryText(Length(FShown), Length(FItems), TAtlasKeyMap.ConflictCount(FItems))]);
  if Trim(FSearch.Text) <> '' then
  begin
    Subtitle := Subtitle + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.KeyMapFilter, [Trim(FSearch.Text)]);
  end;
  if TAtlasStrings.Language = TAtlasLanguage.German then
  begin
    Result := TAtlasKeyMap.Html('de', TAtlasStrings.Text(TAtlasTextId.KeyMapTitle), Subtitle,
      TAtlasStrings.Text(TAtlasTextId.KeyMapPrint), Headers, Rows);
  end
  else
  begin
    Result := TAtlasKeyMap.Html('en', TAtlasStrings.Text(TAtlasTextId.KeyMapTitle), Subtitle,
      TAtlasStrings.Text(TAtlasTextId.KeyMapPrint), Headers, Rows);
  end;
end;

procedure TAtlasKeyMapWindow.ApplyFilter;
begin
  FShown := TAtlasKeyMap.Filter(FItems, FSearch.Text, FOnlyConflicts.Checked);
  FList.Items.Count := Length(FShown);
  FList.Invalidate;
  FSummary.Caption := SummaryText(Length(FShown), Length(FItems), TAtlasKeyMap.ConflictCount(FItems));
end;

procedure TAtlasKeyMapWindow.SetItems(const AItems: TArray<TAtlasKeyItem>);
begin
  FItems := AItems;
  ApplyFilter;
end;

procedure TAtlasKeyMapWindow.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Color := ToColor(FColors.Surface);
  Font.Color := ToColor(FColors.Text);
  FTop.Color := ToColor(FColors.Surface);
  FBottom.Color := ToColor(FColors.Gutter);
  FList.Color := ToColor(FColors.Surface);
  FList.Font.Color := ToColor(FColors.Text);
  FSummary.Font.Color := ToColor(FColors.Muted);
  FList.Invalidate;
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
  Values: TArray<string>;
  Index: Integer;
begin
  if (Item.Index < 0) or (Item.Index > High(FShown)) then
  begin
    Exit;
  end;
  Values := Cells(FItems, FShown[Item.Index]);
  Item.Caption := Values[0];
  for Index := 1 to High(Values) do
  begin
    Item.SubItems.Add(Values[Index]);
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
  // Doppelt belegte Kürzel rot (#520).
  if FItems[FShown[Item.Index]].Conflict then
  begin
    Sender.Canvas.Font.Color := ToColor(FColors.Error);
  end
  else
  begin
    Sender.Canvas.Font.Color := ToColor(FColors.Text);
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
