unit Atlas.UI.Query.Parts;

// Teile des Fensters „Atlas-Abfrage“ (#1351), reine VCL; TAtlasCodeQueryFrame
// setzt sie zusammen:
// - TAtlasCodeQueryEvents: die Ereignisse, die die IDE-Schicht setzt.
// - TAtlasQueryToolbar: gespeicherte Abfragen, „Ausführen“, „Abbrechen“,
//   „Als Regel speichern …“, „Als CSV kopieren“ und „Hilfe“.
// - TAtlasQueryInput: Eingabezeile mit Vervollständigung (Katalog und
//   Symbolnamen über OnSymbols) und der Fehlerzeile darunter. Die Liste
//   erscheint beim Tippen und mit Strg+Leer; Pfeile wählen, Enter oder Tab
//   übernimmt, Esc schließt. Enter ohne Liste meldet OnSubmit.
// - TAtlasQueryResults: virtuelle Ergebnisliste (OwnerData) mit einer Spalte
//   je Feld und „Datei“, Sortieren per Spaltenklick, Doppelklick oder Enter
//   öffnet die Zeile (OnOpenLocation).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Query.Model;

type
  /// <summary>Symbolnamen für die Vervollständigung: APredicate (inherits, implements, uses, calls, attribute) und
  /// der getippte Anfang APrefix.</summary>
  TAtlasCodeQuerySymbols = reference to function(const APredicate, APrefix: string): TArray<string>;

  /// <summary>Ereignisse des Fensters; die IDE-Schicht setzt sie, die Teile rufen sie. Gehört dem Frame.</summary>
  TAtlasCodeQueryEvents = class(TComponent)
  public
    /// <summary>Text der Eingabezeile.</summary>
    OnRun: TProc<string>;
    OnCancel: TProc;
    /// <summary>„Als Regel speichern …“ mit dem Text der Eingabezeile.</summary>
    OnSaveRule: TProc<string>;
    /// <summary>CSV liegt in der Zwischenablage; Anzahl der Zeilen.</summary>
    OnCopied: TProc<Integer>;
    /// <summary>Absoluter Pfad, Zeile und Spalte ab 1.</summary>
    OnOpenLocation: TProc<string, Integer, Integer>;
    OnSymbols: TAtlasCodeQuerySymbols;
  end;

  /// <summary>Obere Leiste: Auswahl gespeicherter Abfragen und die Knöpfe; die Klicks setzt der Frame.</summary>
  TAtlasQueryToolbar = class(TFlowPanel)
  private
    FSaved: TComboBox;
    FRun: TButton;
    FCancel: TButton;
    FSaveRule: TButton;
    FCopyCsv: TButton;
    FHelpButton: TButton;
    function NewButton(const ACaption: string; AWidth: Integer): TButton;
  public
    constructor Create(AParent: TWinControl); reintroduce;
    /// <summary>Gespeicherte Abfragen aus dem Katalog; vorn ein Hinweis. Nichts ohne Fenster.</summary>
    procedure FillSaved(const ACatalog: TAtlasQueryCatalog);
    property SavedCombo: TComboBox read FSaved;
    property RunButton: TButton read FRun;
    property CancelButton: TButton read FCancel;
    property SaveRuleButton: TButton read FSaveRule;
    property CopyCsvButton: TButton read FCopyCsv;
    property HelpButton: TButton read FHelpButton;
  end;

  /// <summary>Eingabezeile mit Vervollständigung und Fehlerzeile.</summary>
  TAtlasQueryInput = class(TPanel)
  private
    FEdit: TEdit;
    FError: TLabel;
    /// <summary>Liegt im Frame (AHost), damit sie nicht von der Leiste abgeschnitten wird.</summary>
    FSuggest: TListBox;
    FEvents: TAtlasCodeQueryEvents;
    FCatalog: TAtlasQueryCatalog;
    /// <summary>Gezeigte Vorschläge und der Anfang des Worts, das sie ersetzen (0-basiert).</summary>
    FSuggestions: TArray<string>;
    FSuggestStart: Integer;
    FUpdating: Boolean;
    FOnSubmit: TNotifyEvent;
    FOnEdited: TNotifyEvent;
    procedure PlaceSuggest;
    procedure MoveSuggestion(ADelta: Integer);
    procedure EditChange(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditKeyPress(Sender: TObject; var Key: Char);
    procedure EditExit(Sender: TObject);
    procedure SuggestClick(Sender: TObject);
  public
    constructor Create(AHost: TWinControl; AEvents: TAtlasCodeQueryEvents); reintroduce;
    /// <summary>Vorschläge an der Schreibmarke neu bestimmen und zeigen (wie Strg+Leer).</summary>
    procedure ShowSuggestions;
    /// <summary>Vorschlag AIndex übernehmen: ersetzt das Wort an der Schreibmarke, dahinter ein Leerzeichen.
    /// </summary>
    procedure AcceptSuggestion(AIndex: Integer);
    procedure HideSuggest;
    /// <summary>Text setzen, ohne Vorschläge zu zeigen; Schreibmarke ans Ende.</summary>
    procedure ReplaceText(const AText: string);
    /// <summary>Fehler der Antwort mit Spalte und Vorschlag zeigen, Schreibmarke an die Spalte; sonst verbergen.
    /// </summary>
    procedure ShowError(const AAnswer: TAtlasQueryAnswer; AHasAnswer: Boolean);
    property Edit: TEdit read FEdit;
    property ErrorLabel: TLabel read FError;
    property SuggestList: TListBox read FSuggest;
    property Suggestions: TArray<string> read FSuggestions;
    property Catalog: TAtlasQueryCatalog read FCatalog write FCatalog;
    /// <summary>Enter ohne Vorschlagsliste.</summary>
    property OnSubmit: TNotifyEvent read FOnSubmit write FOnSubmit;
    /// <summary>Der Text hat sich geändert.</summary>
    property OnEdited: TNotifyEvent read FOnEdited write FOnEdited;
  end;

  /// <summary>Ergebnisliste; hält die Antwort und ihre Sortierung.</summary>
  TAtlasQueryResults = class(TListView)
  private
    FEvents: TAtlasCodeQueryEvents;
    FAnswer: TAtlasQueryAnswer;
    FHasAnswer: Boolean;
    /// <summary>Spalte der Sortierung; -1 = Reihenfolge des Servers.</summary>
    FSortColumn: Integer;
    FSortDescending: Boolean;
    procedure ListData(Sender: TObject; Item: TListItem);
  protected
    procedure ColClick(Field: TListColumn); override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AParent: TWinControl; AEvents: TAtlasCodeQueryEvents); reintroduce;
    /// <summary>Spalten je Feld der Antwort und „Datei“.</summary>
    procedure FillColumns;
    /// <summary>Zeilenzahl der virtuellen Liste; nichts ohne Fenster.</summary>
    procedure FillRows;
    /// <summary>Antwort zeigen; die gewählte Sortierung bleibt.</summary>
    procedure SetAnswer(const AAnswer: TAtlasQueryAnswer);
    procedure ClearAnswer;
    /// <summary>Nach Spalte AColumn sortieren (Spaltenklick); dieselbe Spalte nochmals kehrt um.</summary>
    procedure SortBy(AColumn: Integer);
    /// <summary>Zeile AIndex öffnen (OnOpenLocation).</summary>
    procedure OpenRow(AIndex: Integer);
    /// <summary>Treffer als CSV (wie der Server).</summary>
    function CsvText: string;
    /// <summary>Zeile für Zeile der Text der Liste, Zellen mit " | " (für Tests und Bildschirmleser).</summary>
    function RowText: TArray<string>;
    property Answer: TAtlasQueryAnswer read FAnswer;
    property HasAnswer: Boolean read FHasAnswer;
    property SortColumn: Integer read FSortColumn;
    property SortDescending: Boolean read FSortDescending;
  end;

/// <summary>True, wenn AControl Einträge halten kann (Fenster da oder bald da).</summary>
function CanFill(AControl: TWinControl): Boolean;

implementation

uses
  Winapi.Windows,
  System.Types,
  System.Math,
  Vcl.Forms,
  Atlas.UI.Search.Strings;

const
  /// <summary>So viele Zeilen hat die Vorschlagsliste höchstens sichtbar.</summary>
  cSuggestRows = 8;
  /// <summary>So viele Symbolnamen kommen höchstens in die Liste.</summary>
  cMaxSymbols = 30;
  /// <summary>Symbolsuche erst ab so vielen getippten Zeichen.</summary>
  cSymbolMinChars = 2;

function CanFill(AControl: TWinControl): Boolean;
begin
  Result := AControl.HandleAllocated or (GetParentForm(AControl) <> nil);
end;

{ TAtlasQueryToolbar }

constructor TAtlasQueryToolbar.Create(AParent: TWinControl);
begin
  inherited Create(AParent);
  Parent := AParent;
  Align := alTop;
  BevelOuter := bvNone;
  ShowCaption := False;
  // Fließende Leiste: bei schmalem Fenster brechen die Knöpfe in weitere Zeilen um.
  AutoWrap := True;
  AutoSize := True;
  Padding.SetBounds(2, 2, 2, 0);

  FSaved := TComboBox.Create(Self);
  FSaved.Parent := Self;
  FSaved.AlignWithMargins := True;
  FSaved.Style := csDropDownList;
  FSaved.Width := FSaved.ScaleValue(220);
  FSaved.Hint := TAtlasSearchStrings.Text(TAtlasSearchTextId.QuerySavedHint);
  FSaved.ShowHint := True;

  FRun := NewButton(TAtlasSearchStrings.Text(TAtlasSearchTextId.QueryRun), 90);
  FCancel := NewButton(TAtlasSearchStrings.Text(TAtlasSearchTextId.QueryCancel), 90);
  FSaveRule := NewButton(TAtlasSearchStrings.Text(TAtlasSearchTextId.QuerySaveRule), 140);
  FCopyCsv := NewButton(TAtlasSearchStrings.Text(TAtlasSearchTextId.QueryCopyCsv), 120);
  FHelpButton := NewButton(TAtlasSearchStrings.Text(TAtlasSearchTextId.QueryHelp), 70);
end;

function TAtlasQueryToolbar.NewButton(const ACaption: string; AWidth: Integer): TButton;
begin
  // TFlowPanel hängt in Erzeugungsreihenfolge an.
  Result := TButton.Create(Self);
  Result.Parent := Self;
  Result.AlignWithMargins := True;
  Result.Caption := ACaption;
  Result.Width := AWidth;
end;

function SavedCaption(const ASaved: TAtlasSavedQuery): string;
begin
  Result := ASaved.Name;
  if ASaved.Description <> '' then
  begin
    Result := Result + ' – ' + ASaved.Description;
  end;
end;

procedure TAtlasQueryToolbar.FillSaved(const ACatalog: TAtlasQueryCatalog);
var
  mSaved: TAtlasSavedQuery;
  mChange: TNotifyEvent;
begin
  if not CanFill(FSaved) then
  begin
    Exit;
  end;
  // Füllen wählt keine Abfrage.
  mChange := FSaved.OnChange;
  FSaved.OnChange := nil;
  try
    FSaved.Items.BeginUpdate;
    try
      FSaved.Items.Clear;
      // Erster Eintrag: Hinweis statt Wahl (eine Klappliste zeigt keinen TextHint).
      FSaved.Items.Add(TAtlasSearchStrings.Text(TAtlasSearchTextId.QuerySavedHint));
      for mSaved in ACatalog.Saved do
      begin
        FSaved.Items.Add(SavedCaption(mSaved));
      end;
    finally
      FSaved.Items.EndUpdate;
    end;
    FSaved.ItemIndex := 0;
    FSaved.Enabled := Length(ACatalog.Saved) > 0;
  finally
    FSaved.OnChange := mChange;
  end;
end;

{ TAtlasQueryInput }

constructor TAtlasQueryInput.Create(AHost: TWinControl; AEvents: TAtlasCodeQueryEvents);
begin
  inherited Create(AHost);
  FEvents := AEvents;
  Parent := AHost;
  Align := alTop;
  BevelOuter := bvNone;
  ShowCaption := False;
  AutoSize := True;
  Padding.SetBounds(2, 0, 2, 2);

  FEdit := TEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.Align := alTop;
  FEdit.AlignWithMargins := True;
  FEdit.TextHint := TAtlasSearchStrings.Text(TAtlasSearchTextId.QueryInputHint);
  FEdit.OnChange := EditChange;
  FEdit.OnKeyDown := EditKeyDown;
  FEdit.OnKeyPress := EditKeyPress;
  FEdit.OnExit := EditExit;

  FError := TLabel.Create(Self);
  FError.Parent := Self;
  FError.Align := alTop;
  FError.Top := FEdit.Top + FEdit.Height + 1;
  FError.AlignWithMargins := True;
  FError.ShowAccelChar := False;
  FError.Visible := False;

  // Über der Liste, unter der Eingabezeile.
  FSuggest := TListBox.Create(Self);
  FSuggest.Parent := AHost;
  FSuggest.Visible := False;
  FSuggest.TabStop := False;
  FSuggest.OnClick := SuggestClick;
end;

/// <summary>AName in AList und ASeen aufnehmen, falls neu und nicht leer.</summary>
procedure AddUnique(var AList: TArray<string>; ASeen: TStringList; const AName: string);
begin
  if (AName <> '') and (ASeen.IndexOf(AName) < 0) then
  begin
    ASeen.Add(AName);
    AList := AList + [AName];
  end;
end;

/// <summary>Vorschläge aus dem Katalog an ACursor, dahinter Symbolnamen über AEvents.OnSymbols; doppelte Namen
/// (ohne Groß-/Kleinschreibung) nur einmal. AStart: Anfang des ersetzten Worts.</summary>
function CompletionNames(const ACatalog: TAtlasQueryCatalog; AEvents: TAtlasCodeQueryEvents; const AText: string;
  ACursor: Integer; out AStart: Integer): TArray<string>;
var
  mItem: TAtlasQuerySuggestion;
  mSymbolStart: Integer;
  mPrefix, mPredicate, mName: string;
  mSeen: TStringList;
begin
  Result := nil;
  mSeen := TStringList.Create;
  try
    mSeen.CaseSensitive := False;
    mSeen.Sorted := True;
    mSeen.Duplicates := dupIgnore;
    for mItem in TAtlasQueryCompletion.Suggest(ACatalog, AText, ACursor, AStart) do
    begin
      AddUnique(Result, mSeen, mItem.Text);
    end;
    if not TAtlasQueryCompletion.SymbolPredicate(AText, ACursor, mSymbolStart, mPrefix, mPredicate) or
      (Length(mPrefix) < cSymbolMinChars) or not Assigned(AEvents.OnSymbols) then
    begin
      Exit;
    end;
    AStart := mSymbolStart;
    for mName in AEvents.OnSymbols(mPredicate, mPrefix) do
    begin
      if Length(Result) >= cMaxSymbols then
      begin
        Break;
      end;
      AddUnique(Result, mSeen, mName);
    end;
  finally
    mSeen.Free;
  end;
end;

procedure TAtlasQueryInput.ShowSuggestions;
var
  mName: string;
begin
  FSuggestions := CompletionNames(FCatalog, FEvents, FEdit.Text, FEdit.SelStart, FSuggestStart);
  if (Length(FSuggestions) = 0) or not CanFill(FSuggest) then
  begin
    HideSuggest;
    Exit;
  end;
  FSuggest.Items.BeginUpdate;
  try
    FSuggest.Items.Clear;
    for mName in FSuggestions do
    begin
      FSuggest.Items.Add(mName);
    end;
  finally
    FSuggest.Items.EndUpdate;
  end;
  FSuggest.ItemIndex := 0;
  PlaceSuggest;
  FSuggest.Visible := True;
  FSuggest.BringToFront;
end;

procedure TAtlasQueryInput.PlaceSuggest;
var
  mPoint: TPoint;
  mRows: Integer;
begin
  mPoint := FSuggest.Parent.ScreenToClient(FEdit.ClientToScreen(Point(0, FEdit.Height)));
  mRows := Min(cSuggestRows, Max(1, FSuggest.Items.Count));
  FSuggest.SetBounds(mPoint.X, mPoint.Y, Min(FEdit.Width, MulDiv(320, CurrentPPI, 96)),
    mRows * FSuggest.ItemHeight + 4);
end;

procedure TAtlasQueryInput.HideSuggest;
begin
  FSuggest.Visible := False;
end;

procedure TAtlasQueryInput.AcceptSuggestion(AIndex: Integer);
var
  mText, mWord: string;
  mCursor: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FSuggestions)) then
  begin
    Exit;
  end;
  mWord := FSuggestions[AIndex];
  mText := FEdit.Text;
  mCursor := Min(FEdit.SelStart, Length(mText));
  FUpdating := True;
  try
    FEdit.Text := Copy(mText, 1, FSuggestStart) + mWord + ' ' + Copy(mText, mCursor + 1, MaxInt);
    FEdit.SelStart := FSuggestStart + Length(mWord) + 1;
    FEdit.SelLength := 0;
  finally
    FUpdating := False;
  end;
  HideSuggest;
end;

procedure TAtlasQueryInput.ReplaceText(const AText: string);
begin
  FUpdating := True;
  try
    FEdit.Text := AText;
    FEdit.SelStart := Length(FEdit.Text);
  finally
    FUpdating := False;
  end;
end;

/// <summary>Fehlertext der Antwort: Meldung, Spalte und Vorschlag.</summary>
function ErrorText(const AAnswer: TAtlasQueryAnswer): string;
begin
  Result := AAnswer.Error;
  if AAnswer.ErrorColumn > 0 then
  begin
    Result := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.QueryError, [AAnswer.ErrorColumn, AAnswer.Error]);
  end;
  if AAnswer.Suggestion <> '' then
  begin
    Result := Result + ' ' + TAtlasSearchStrings.Fmt(TAtlasSearchTextId.QuerySuggestion, [AAnswer.Suggestion]);
  end;
end;

procedure TAtlasQueryInput.ShowError(const AAnswer: TAtlasQueryAnswer; AHasAnswer: Boolean);
begin
  if not AHasAnswer or not AAnswer.Failed then
  begin
    FError.Visible := False;
    FError.Caption := '';
    Exit;
  end;
  FError.Caption := ErrorText(AAnswer);
  FError.Visible := True;
  // Schreibmarke an die Fehlerstelle, damit man gleich verbessern kann.
  if (AAnswer.ErrorColumn > 0) and (AAnswer.ErrorColumn <= Length(FEdit.Text) + 1) then
  begin
    FEdit.SelStart := AAnswer.ErrorColumn - 1;
    FEdit.SelLength := 0;
  end;
end;

procedure TAtlasQueryInput.EditChange(Sender: TObject);
begin
  if Assigned(FOnEdited) then
  begin
    FOnEdited(Self);
  end;
  if not FUpdating and FEdit.Focused then
  begin
    ShowSuggestions;
  end;
end;

procedure TAtlasQueryInput.MoveSuggestion(ADelta: Integer);
begin
  FSuggest.ItemIndex := EnsureRange(FSuggest.ItemIndex + ADelta, 0, FSuggest.Items.Count - 1);
end;

procedure TAtlasQueryInput.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_SPACE) and (ssCtrl in Shift) then
  begin
    ShowSuggestions;
    Key := 0;
  end
  else if not FSuggest.Visible then
  begin
    if (Key = VK_RETURN) and Assigned(FOnSubmit) then
    begin
      FOnSubmit(Self);
      Key := 0;
    end;
  end
  else
  begin
    case Key of
      VK_DOWN:
        MoveSuggestion(1);
      VK_UP:
        MoveSuggestion(-1);
      VK_RETURN, VK_TAB:
        AcceptSuggestion(FSuggest.ItemIndex);
      VK_ESCAPE:
        HideSuggest;
    else
      Exit;
    end;
    Key := 0;
  end;
end;

procedure TAtlasQueryInput.EditKeyPress(Sender: TObject; var Key: Char);
begin
  // Enter, Esc und Strg+Leer sind schon verarbeitet: kein Piepen, kein Leerzeichen.
  if (Key = #13) or (Key = #27) or ((Key = ' ') and (GetKeyState(VK_CONTROL) < 0)) then
  begin
    Key := #0;
  end;
end;

procedure TAtlasQueryInput.EditExit(Sender: TObject);
begin
  // Ein Klick in die Vorschlagsliste nimmt den Fokus nicht (TabStop aus, OnClick übernimmt vorher).
  if not FSuggest.Focused then
  begin
    HideSuggest;
  end;
end;

procedure TAtlasQueryInput.SuggestClick(Sender: TObject);
begin
  AcceptSuggestion(FSuggest.ItemIndex);
  if FEdit.CanFocus and Showing then
  begin
    FEdit.SetFocus;
  end;
end;

{ TAtlasQueryResults }

constructor TAtlasQueryResults.Create(AParent: TWinControl; AEvents: TAtlasCodeQueryEvents);
begin
  inherited Create(AParent);
  FEvents := AEvents;
  FSortColumn := -1;
  Parent := AParent;
  Align := alClient;
  ViewStyle := vsReport;
  RowSelect := True;
  ReadOnly := True;
  HideSelection := False;
  OwnerData := True;
  ColumnClick := True;
  OnData := ListData;
end;

procedure TAtlasQueryResults.FillColumns;
var
  mColumn: TListColumn;
  mIndex: Integer;
begin
  Columns.BeginUpdate;
  try
    Columns.Clear;
    if not FHasAnswer then
    begin
      Exit;
    end;
    for mIndex := 0 to High(FAnswer.Columns) do
    begin
      mColumn := Columns.Add;
      mColumn.Caption := FAnswer.Columns[mIndex];
      mColumn.Width := MulDiv(90, CurrentPPI, 96);
      if mIndex = 0 then
      begin
        mColumn.Width := MulDiv(220, CurrentPPI, 96);
      end;
    end;
    mColumn := Columns.Add;
    mColumn.Caption := TAtlasSearchStrings.Text(TAtlasSearchTextId.QueryColumnFile);
    mColumn.Width := MulDiv(320, CurrentPPI, 96);
  finally
    Columns.EndUpdate;
  end;
end;

procedure TAtlasQueryResults.FillRows;
begin
  if not CanFill(Self) then
  begin
    Exit;
  end;
  Items.BeginUpdate;
  try
    Items.Count := 0;
    if FHasAnswer then
    begin
      Items.Count := Length(FAnswer.Rows);
    end;
  finally
    Items.EndUpdate;
  end;
  Invalidate;
end;

procedure TAtlasQueryResults.SetAnswer(const AAnswer: TAtlasQueryAnswer);
begin
  FAnswer := AAnswer;
  FHasAnswer := True;
  if (FSortColumn >= 0) and (FSortColumn <= High(FAnswer.Columns)) then
  begin
    FAnswer.Sort(FSortColumn, FSortDescending);
  end
  else
  begin
    FSortColumn := -1;
  end;
  FillColumns;
  FillRows;
end;

procedure TAtlasQueryResults.ClearAnswer;
begin
  FAnswer := Default(TAtlasQueryAnswer);
  FHasAnswer := False;
  FillColumns;
  FillRows;
end;

procedure TAtlasQueryResults.SortBy(AColumn: Integer);
begin
  if not FHasAnswer then
  begin
    Exit;
  end;
  if (AColumn < 0) or (AColumn > High(FAnswer.Columns)) then
  begin
    // Spalte „Datei“: Reihenfolge nach Pfad, Zeile und Spalte.
    AColumn := -1;
  end;
  if AColumn = FSortColumn then
  begin
    FSortDescending := not FSortDescending;
  end
  else
  begin
    FSortColumn := AColumn;
    // Zahlen zuerst die größten, Text alphabetisch.
    FSortDescending := (AColumn >= 0) and (Length(FAnswer.Rows) > 0) and
      (AColumn <= High(FAnswer.Rows[0].Cells)) and FAnswer.Rows[0].Cells[AColumn].IsNumber;
  end;
  FAnswer.Sort(FSortColumn, FSortDescending);
  FillRows;
end;

procedure TAtlasQueryResults.OpenRow(AIndex: Integer);
var
  mRow: TAtlasQueryRow;
begin
  if not FHasAnswer or (AIndex < 0) or (AIndex > High(FAnswer.Rows)) then
  begin
    Exit;
  end;
  mRow := FAnswer.Rows[AIndex];
  if (mRow.FileName <> '') and Assigned(FEvents.OnOpenLocation) then
  begin
    FEvents.OnOpenLocation(mRow.FileName, Max(1, mRow.Line), Max(1, mRow.Character));
  end;
end;

function TAtlasQueryResults.CsvText: string;
begin
  Result := '';
  if FHasAnswer then
  begin
    Result := FAnswer.Csv;
  end;
end;

function LocationText(const ARow: TAtlasQueryRow): string;
begin
  Result := ARow.Path;
  if Result = '' then
  begin
    Result := ARow.FileName;
  end;
  if ARow.Line > 0 then
  begin
    Result := Result + ':' + IntToStr(ARow.Line);
  end;
  if ARow.Inferred then
  begin
    Result := Result + ' · ' + TAtlasSearchStrings.Text(TAtlasSearchTextId.QueryInferred);
  end;
end;

function TAtlasQueryResults.RowText: TArray<string>;
var
  mRow: TAtlasQueryRow;
  mCells: TArray<string>;
  mCell: TAtlasQueryCell;
begin
  Result := nil;
  if not FHasAnswer then
  begin
    Exit;
  end;
  for mRow in FAnswer.Rows do
  begin
    mCells := nil;
    for mCell in mRow.Cells do
    begin
      mCells := mCells + [mCell.Text];
    end;
    mCells := mCells + [LocationText(mRow)];
    Result := Result + [string.Join(' | ', mCells)];
  end;
end;

procedure TAtlasQueryResults.ListData(Sender: TObject; Item: TListItem);
var
  mRow: TAtlasQueryRow;
  mIndex: Integer;
begin
  if not FHasAnswer or (Item.Index < 0) or (Item.Index > High(FAnswer.Rows)) then
  begin
    Exit;
  end;
  mRow := FAnswer.Rows[Item.Index];
  Item.Caption := '';
  if Length(mRow.Cells) > 0 then
  begin
    Item.Caption := mRow.Cells[0].Text;
  end;
  for mIndex := 1 to High(mRow.Cells) do
  begin
    Item.SubItems.Add(mRow.Cells[mIndex].Text);
  end;
  // Fehlen Zellen (kürzere Zeile), bleibt „Datei“ trotzdem in seiner Spalte.
  for mIndex := Max(1, Length(mRow.Cells)) to High(FAnswer.Columns) do
  begin
    Item.SubItems.Add('');
  end;
  Item.SubItems.Add(LocationText(mRow));
end;

procedure TAtlasQueryResults.ColClick(Field: TListColumn);
begin
  inherited ColClick(Field);
  SortBy(Field.Index);
end;

procedure TAtlasQueryResults.DblClick;
begin
  inherited DblClick;
  OpenRow(ItemIndex);
end;

procedure TAtlasQueryResults.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if Key = VK_RETURN then
  begin
    OpenRow(ItemIndex);
    Key := 0;
  end;
end;

end.
