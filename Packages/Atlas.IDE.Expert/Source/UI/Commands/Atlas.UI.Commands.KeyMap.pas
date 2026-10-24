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
  TAtlasKeyMapWindow = class(TForm)
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
    FOnExport: TProc;
    FOnSettings: TProc;
    FOnRefresh: TProc;
    procedure ApplyFilter;
    procedure SearchChange(Sender: TObject);
    procedure OnlyConflictsClick(Sender: TObject);
    procedure ListData(Sender: TObject; Item: TListItem);
    procedure ListCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure ExportClick(Sender: TObject);
    procedure SettingsClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    function AddButton(const ACaption: string; AOnClick: TNotifyEvent): TButton;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor CreateKeyMap(AOwner: TComponent; const AColors: TAtlasColors);
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
    property OnExport: TProc read FOnExport write FOnExport;
    property OnSettings: TProc read FOnSettings write FOnSettings;
    property OnRefresh: TProc read FOnRefresh write FOnRefresh;
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
    Result := TrimRight(Copy(Result, 1, Length(Result) - 1));
end;

{ TAtlasKeyMapWindow }

constructor TAtlasKeyMapWindow.CreateKeyMap(AOwner: TComponent; const AColors: TAtlasColors);
var
  Column: TListColumn;
  Header: string;
  Widths: TArray<Integer>;
  Index: Integer;
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
  Widths := [150, 260, 130, 110, 150, 400];
  Index := 0;
  for Header in Headers do
  begin
    Column := FList.Columns.Add;
    Column.Caption := Header;
    Column.Width := Widths[Index];
    Inc(Index);
  end;
  SetColors(AColors);
  ApplyFilter;
end;

function TAtlasKeyMapWindow.AddButton(const ACaption: string; AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := FBottom;
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
end;

class function TAtlasKeyMapWindow.FunctionCaption(AFunc: TAtlasKeyFunction): string;
var
  Id: TAtlasTextId;
begin
  case AFunc of
    TAtlasKeyFunction.Palette:
      Id := TAtlasTextId.SettingsPaletteKey;
    TAtlasKeyFunction.Check:
      Id := TAtlasTextId.SettingsCheckKey;
    TAtlasKeyFunction.Completion:
      Id := TAtlasTextId.SettingsCompletionKey;
    TAtlasKeyFunction.Signature:
      Id := TAtlasTextId.SettingsSignatureKey;
    TAtlasKeyFunction.QuickToggle:
      Id := TAtlasTextId.SettingsQuickToggleKey;
    TAtlasKeyFunction.DiagnosticMode:
      Id := TAtlasTextId.SettingsDiagnosticModeKey;
    TAtlasKeyFunction.CodeActions:
      Id := TAtlasTextId.EditorActions;
    TAtlasKeyFunction.ExpandSelection:
      Id := TAtlasTextId.EditorExpand;
    TAtlasKeyFunction.ShrinkSelection:
      Id := TAtlasTextId.EditorShrink;
    TAtlasKeyFunction.GoToImplementation:
      Id := TAtlasTextId.MenuImplementations;
    TAtlasKeyFunction.TypeDefinition:
      Id := TAtlasTextId.EditorTypeDefinition;
    TAtlasKeyFunction.UndoChange:
      Id := TAtlasTextId.UndoMenu;
    TAtlasKeyFunction.RedoChange:
      Id := TAtlasTextId.RedoMenu;
    TAtlasKeyFunction.WelcomeSearch:
      Id := TAtlasTextId.SettingsWelcomeSearchKey;
    // Die erste Taste trägt den Namen des Befehls (Tipps #600), die zweite den Zusatz „Taste 2“.
    TAtlasKeyFunction.MethodToggleUp:
      Id := TAtlasTextId.EditorMethodToggle;
    TAtlasKeyFunction.MethodToggleDown:
      Id := TAtlasTextId.SettingsMethodToggleDown;
    TAtlasKeyFunction.TestUnit:
      Id := TAtlasTextId.EditorTestUnit;
    TAtlasKeyFunction.UnitSearch:
      Id := TAtlasTextId.UnitSearchTitle;
    TAtlasKeyFunction.Bookmark:
      Id := TAtlasTextId.BookmarksMenuAdd;
    TAtlasKeyFunction.GenerateMenu:
      Id := TAtlasTextId.GenerateMenuCommand;
    TAtlasKeyFunction.Notifications:
      Id := TAtlasTextId.NotificationsCommand;
    TAtlasKeyFunction.WelcomeQuickBuild:
      Id := TAtlasTextId.SettingsWelcomeQuickActionsBuildKey;
    TAtlasKeyFunction.WelcomeQuickTests:
      Id := TAtlasTextId.SettingsWelcomeQuickActionsTestKey;
    TAtlasKeyFunction.HideElement:
      Id := TAtlasTextId.HideElementCommand;
    TAtlasKeyFunction.NextProblem:
      Id := TAtlasTextId.ProblemNextCommand;
    TAtlasKeyFunction.PreviousProblem:
      Id := TAtlasTextId.ProblemPreviousCommand;
    TAtlasKeyFunction.QuickOpen:
      Id := TAtlasTextId.QuickOpenTitle;
    TAtlasKeyFunction.NavBack:
      Id := TAtlasTextId.NavBackCommand;
    TAtlasKeyFunction.NavForward:
      Id := TAtlasTextId.NavForwardCommand;
    TAtlasKeyFunction.LastEdit:
      Id := TAtlasTextId.NavLastEditCommand;
    TAtlasKeyFunction.PeekDefinition:
      Id := TAtlasTextId.PeekDefinitionCommand;
    TAtlasKeyFunction.PeekReferences:
      Id := TAtlasTextId.PeekReferencesCommand;
    TAtlasKeyFunction.Breadcrumbs:
      Id := TAtlasTextId.BreadcrumbsCommand;
    TAtlasKeyFunction.JumpToMatch:
      Id := TAtlasTextId.JumpToMatchCommand;
    TAtlasKeyFunction.JumpToMatchSelect:
      Id := TAtlasTextId.JumpToMatchSelectCommand;
    TAtlasKeyFunction.NextChange:
      Id := TAtlasTextId.NextChangeCommand;
    TAtlasKeyFunction.PreviousChange:
      Id := TAtlasTextId.PreviousChangeCommand;
    TAtlasKeyFunction.MoveLinesUp:
      Id := TAtlasTextId.MoveLinesUpCommand;
    TAtlasKeyFunction.MoveLinesDown:
      Id := TAtlasTextId.MoveLinesDownCommand;
    TAtlasKeyFunction.DuplicateLinesUp:
      Id := TAtlasTextId.DuplicateLinesUpCommand;
    TAtlasKeyFunction.DuplicateLinesDown:
      Id := TAtlasTextId.DuplicateLinesDownCommand;
    TAtlasKeyFunction.CompleteStatement:
      Id := TAtlasTextId.CompleteStatementCommand;
    TAtlasKeyFunction.MultiCursorNext:
      Id := TAtlasTextId.MultiCursorNextCommand;
    TAtlasKeyFunction.MultiCursorSkip:
      Id := TAtlasTextId.MultiCursorSkipCommand;
    TAtlasKeyFunction.MultiCursorLineEnds:
      Id := TAtlasTextId.MultiCursorLineEndsCommand;
    TAtlasKeyFunction.MultiCursorAbove:
      Id := TAtlasTextId.MultiCursorAboveCommand;
    TAtlasKeyFunction.MultiCursorBelow:
      Id := TAtlasTextId.MultiCursorBelowCommand;
    TAtlasKeyFunction.Search:
      Id := TAtlasTextId.SearchCommand;
    TAtlasKeyFunction.SearchNext:
      Id := TAtlasTextId.SearchNextCommand;
    TAtlasKeyFunction.SearchPrevious:
      Id := TAtlasTextId.SearchPreviousCommand;
    TAtlasKeyFunction.SearchMethod:
      Id := TAtlasTextId.SearchInMethodCommand;
    TAtlasKeyFunction.SearchReplace:
      Id := TAtlasTextId.SearchReplaceCommand;
    TAtlasKeyFunction.FormatCode:
      Id := TAtlasTextId.FormatCodeCommand;
    TAtlasKeyFunction.ToggleBlockComment:
      Id := TAtlasTextId.ToggleBlockCommentCommand;
    TAtlasKeyFunction.NewLineBelow:
      Id := TAtlasTextId.NewLineBelowCommand;
    TAtlasKeyFunction.NewLineAbove:
      Id := TAtlasTextId.NewLineAboveCommand;
    TAtlasKeyFunction.Unwrap:
      Id := TAtlasTextId.UnwrapCommand;
    TAtlasKeyFunction.ProblemsWindow:
      Id := TAtlasTextId.ProblemsWindowCommand;
    TAtlasKeyFunction.SectionInterface:
      Id := TAtlasTextId.GotoInterfaceCommand;
    TAtlasKeyFunction.SectionImplementation:
      Id := TAtlasTextId.GotoImplementationCommand;
    TAtlasKeyFunction.QuickBookmark:
      Id := TAtlasTextId.QuickBookmarkToggleCommand;
    TAtlasKeyFunction.QuickBookmarkSet:
      Id := TAtlasTextId.QuickBookmarkSetCommand;
    TAtlasKeyFunction.QuickBookmarkJump:
      Id := TAtlasTextId.QuickBookmarkJumpCommand;
    TAtlasKeyFunction.NextBookmark:
      Id := TAtlasTextId.NextBookmarkCommand;
    TAtlasKeyFunction.PreviousBookmark:
      Id := TAtlasTextId.PreviousBookmarkCommand;
    TAtlasKeyFunction.StepIntoTarget:
      Id := TAtlasTextId.StepIntoTargetCommand;
    TAtlasKeyFunction.ExpressionType:
      Id := TAtlasTextId.ExpressionTypeCommand;
    TAtlasKeyFunction.SafeDelete:
      Id := TAtlasTextId.SafeDeleteCommand;
  else
    Id := TAtlasTextId.KeyMapUnitSearchIde;
  end;
  Result := Plain(TAtlasStrings.Text(Id));
end;

class function TAtlasKeyMapWindow.OriginText(const AItem: TAtlasKeyItem): string;
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

class function TAtlasKeyMapWindow.ContextText(AContext: TAtlasKeyContext): string;
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

class function TAtlasKeyMapWindow.ReasonText(AReason: TAtlasKeyReason): string;
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

class function TAtlasKeyMapWindow.HintText(const AItems: TArray<TAtlasKeyItem>; AIndex: Integer): string;
var
  Item: TAtlasKeyItem;
begin
  Result := '';
  if (AIndex < 0) or (AIndex > High(AItems)) or not AItems[AIndex].Conflict then
    Exit;
  Item := AItems[AIndex];
  if Item.Winner < 0 then
    Result := ReasonText(TAtlasKeyReason.NoneActive)
  else if Item.Wins then
    Result := TAtlasStrings.Fmt(TAtlasTextId.KeyMapWins, [ReasonText(Item.Reason)])
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.KeyMapLoses, [AItems[Item.Winner].Command,
      OriginText(AItems[Item.Winner]), ReasonText(Item.Reason)]);
end;

class function TAtlasKeyMapWindow.Headers: TArray<string>;
begin
  Result := [TAtlasStrings.Text(TAtlasTextId.KeyMapColumnKey), TAtlasStrings.Text(TAtlasTextId.KeyMapColumnCommand),
    TAtlasStrings.Text(TAtlasTextId.KeyMapColumnOrigin), TAtlasStrings.Text(TAtlasTextId.KeyMapColumnContext),
    TAtlasStrings.Text(TAtlasTextId.KeyMapColumnRarely), TAtlasStrings.Text(TAtlasTextId.KeyMapColumnHint)];
end;

class function TAtlasKeyMapWindow.Cells(const AItems: TArray<TAtlasKeyItem>; AIndex: Integer): TArray<string>;
begin
  Result := [AItems[AIndex].KeyText, AItems[AIndex].Command, OriginText(AItems[AIndex]),
    ContextText(AItems[AIndex].Context), RarelyText(AItems[AIndex]), HintText(AItems, AIndex)];
end;

class function TAtlasKeyMapWindow.RarelyText(const AItem: TAtlasKeyItem): string;
begin
  // Aus der Zählung der Tastenkürzel-Tipps (#600); leer, solange der Befehl selten genutzt oder nicht gezählt ist.
  if AItem.RarelyByKeyboard then
    Result := TAtlasStrings.Fmt(TAtlasTextId.KeyMapRarely, [AItem.MouseUses, AItem.KeyUses])
  else
    Result := '';
end;

class function TAtlasKeyMapWindow.SummaryText(AShown, ATotal, AConflicts: Integer): string;
begin
  if AShown = ATotal then
    Result := TAtlasStrings.Fmt(TAtlasTextId.KeyMapSummary, [ATotal, AConflicts])
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.KeyMapSummaryFiltered, [AShown, ATotal, AConflicts]);
end;

function TAtlasKeyMapWindow.ExportHtml(const ACreated: string): string;
var
  Rows: TArray<TAtlasKeyHtmlRow>;
  Index: Integer;
  Subtitle: string;
begin
  Rows := nil;
  for Index in FShown do
    Rows := Rows + [TAtlasKeyHtmlRow.Create(Cells(FItems, Index), FItems[Index].Conflict)];
  Subtitle := TAtlasStrings.Fmt(TAtlasTextId.KeyMapCreated, [ACreated,
    SummaryText(Length(FShown), Length(FItems), TAtlasKeyMap.ConflictCount(FItems))]);
  if Trim(FSearch.Text) <> '' then
    Subtitle := Subtitle + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.KeyMapFilter, [Trim(FSearch.Text)]);
  if TAtlasStrings.Language = TAtlasLanguage.German then
    Result := TAtlasKeyMap.Html('de', TAtlasStrings.Text(TAtlasTextId.KeyMapTitle), Subtitle,
      TAtlasStrings.Text(TAtlasTextId.KeyMapPrint), Headers, Rows)
  else
    Result := TAtlasKeyMap.Html('en', TAtlasStrings.Text(TAtlasTextId.KeyMapTitle), Subtitle,
      TAtlasStrings.Text(TAtlasTextId.KeyMapPrint), Headers, Rows);
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
    Exit;
  Values := Cells(FItems, FShown[Item.Index]);
  Item.Caption := Values[0];
  for Index := 1 to High(Values) do
    Item.SubItems.Add(Values[Index]);
end;

procedure TAtlasKeyMapWindow.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  if (Item.Index < 0) or (Item.Index > High(FShown)) then
    Exit;
  // Doppelt belegte Kürzel rot (#520).
  if FItems[FShown[Item.Index]].Conflict then
    Sender.Canvas.Font.Color := ToColor(FColors.Error)
  else
    Sender.Canvas.Font.Color := ToColor(FColors.Text);
end;

procedure TAtlasKeyMapWindow.ExportClick(Sender: TObject);
begin
  if Assigned(FOnExport) then
    FOnExport();
end;

procedure TAtlasKeyMapWindow.SettingsClick(Sender: TObject);
begin
  if Assigned(FOnSettings) then
    FOnSettings();
end;

procedure TAtlasKeyMapWindow.RefreshClick(Sender: TObject);
begin
  if Assigned(FOnRefresh) then
    FOnRefresh();
end;

procedure TAtlasKeyMapWindow.CloseClick(Sender: TObject);
begin
  Close;
end;

procedure TAtlasKeyMapWindow.FormClose(Sender: TObject; var Action: TCloseAction);
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
