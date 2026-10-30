unit Atlas.UI.Query.Frame;

// Inhalt des Fensters „Atlas-Abfrage“ (#1351), reine VCL:
// - oben die Auswahl gespeicherter Abfragen (queries aus atlas.json; Wahl
//   setzt die Abfrage ein und führt sie aus), „Ausführen“, „Abbrechen“,
//   „Als Regel speichern …“ und „Als CSV kopieren“,
// - darunter die Eingabezeile mit Vervollständigung: Mengen, Felder,
//   Prädikate, Schlüsselwörter und @name aus dem Katalog des Servers
//   (TAtlasQueryCompletion), hinter inherits, implements, uses, calls und has
//   attribute Symbolnamen über OnSymbols. Die Liste erscheint beim Tippen und
//   mit Strg+Leer; Pfeile wählen, Enter oder Tab übernimmt, Esc schließt.
//   Enter ohne Liste führt aus. Ein Fehler steht unter der Zeile mit Spalte
//   und Vorschlag, die Schreibmarke springt an die Spalte.
// - die Ergebnisliste mit einer Spalte je Feld der Antwort und „Datei“
//   (Pfad:Zeile, erschlossene Treffer mit Vermerk). Klick auf eine Spalte
//   sortiert (nochmals: umgekehrt; bei Gleichstand eindeutig nach Pfad,
//   Zeile, Spalte), Doppelklick oder Enter springt zur Deklaration
//   (OnOpenLocation, Zeile und Spalte ab 1). Die Liste ist virtuell
//   (OwnerData), auch viele Zeilen füllen sofort.
// - unten die Statuszeile mit Treffern, Laufzeit und erschlossenen Treffern
//   bzw. einem Hinweis.
// Die IDE-Schicht bettet den Frame in ein andockbares Fenster ein, fragt den
// Server und ruft SetCatalog, SetAnswer, SetRunning bzw. SetMessage. Die DFM
// ist leer (TCustomFrame.Create verlangt eine Ressource); aufgebaut wird im
// Code, gefüllt erst mit Fenster (CreateWnd).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Core.Query.Model;

type
  /// <summary>Symbolnamen für die Vervollständigung: APredicate (inherits, implements, uses, calls, attribute) und
  /// der getippte Anfang APrefix.</summary>
  TAtlasCodeQuerySymbols = reference to function(const APredicate, APrefix: string): TArray<string>;

  TAtlasCodeQueryFrame = class(TFrame)
  private
    FTop: TPanel;
    FSaved: TComboBox;
    FRun: TButton;
    FCancel: TButton;
    FSaveRule: TButton;
    FCopyCsv: TButton;
    FInputBar: TPanel;
    FInput: TEdit;
    FError: TLabel;
    FSuggest: TListBox;
    FList: TListView;
    FStatus: TLabel;
    FCatalog: TAtlasQueryCatalog;
    FAnswer: TAtlasQueryAnswer;
    FHasAnswer: Boolean;
    FRunning: Boolean;
    FMessageText: string;
    /// <summary>Gezeigte Vorschläge und der Anfang des Worts, das sie ersetzen (0-basiert).</summary>
    FSuggestions: TArray<string>;
    FSuggestStart: Integer;
    FUpdating: Boolean;
    /// <summary>Spalte der Sortierung; -1 = Reihenfolge des Servers.</summary>
    FSortColumn: Integer;
    FSortDescending: Boolean;
    FOnRun: TProc<string>;
    FOnCancel: TProc;
    FOnSaveRule: TProc<string>;
    FOnCopied: TProc<Integer>;
    FOnOpenLocation: TProc<string, Integer, Integer>;
    FOnSymbols: TAtlasCodeQuerySymbols;
    function NewButton(const ACaption: string; AWidth: Integer; AClick: TNotifyEvent): TButton;
    function CanFill(AControl: TWinControl): Boolean;
    procedure FillSaved;
    procedure FillColumns;
    procedure FillRows;
    procedure UpdateButtons;
    procedure UpdateStatus;
    procedure UpdateError;
    procedure PlaceSuggest;
    procedure HideSuggest;
    procedure SavedChange(Sender: TObject);
    procedure RunClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure SaveRuleClick(Sender: TObject);
    procedure CopyCsvClick(Sender: TObject);
    procedure InputChange(Sender: TObject);
    procedure InputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure InputKeyPress(Sender: TObject; var Key: Char);
    procedure InputExit(Sender: TObject);
    procedure SuggestClick(Sender: TObject);
    procedure ListData(Sender: TObject; Item: TListItem);
    procedure ListColumnClick(Sender: TObject; Column: TListColumn);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Katalog des Servers (Vervollständigung, gespeicherte Abfragen).</summary>
    procedure SetCatalog(const ACatalog: TAtlasQueryCatalog);
    /// <summary>Antwort zeigen; die gewählte Sortierung bleibt.</summary>
    procedure SetAnswer(const AAnswer: TAtlasQueryAnswer);
    /// <summary>Abfrage läuft: „Abbrechen“ an, „Ausführen“ aus, Hinweis in der Statuszeile.</summary>
    procedure SetRunning(ARunning: Boolean);
    /// <summary>Hinweis in der Statuszeile (kein Projekt, kein Server, abgebrochen …); AKeep: bisherige Treffer
    /// stehen lassen.</summary>
    procedure SetMessage(const AText: string; AKeep: Boolean);
    /// <summary>Vorschläge an der Schreibmarke neu bestimmen und zeigen (wie Strg+Leer).</summary>
    procedure ShowSuggestions;
    /// <summary>Vorschlag AIndex übernehmen: ersetzt das Wort an der Schreibmarke, dahinter ein Leerzeichen.
    /// </summary>
    procedure AcceptSuggestion(AIndex: Integer);
    /// <summary>Abfrage ausführen (OnRun mit dem Text der Eingabezeile); nichts bei leerer Zeile.</summary>
    procedure Run;
    /// <summary>Nach Spalte AColumn sortieren (Spaltenklick); dieselbe Spalte nochmals kehrt um.</summary>
    procedure SortBy(AColumn: Integer);
    /// <summary>Zeile AIndex der Liste öffnen (OnOpenLocation).</summary>
    procedure OpenRow(AIndex: Integer);
    /// <summary>Treffer als CSV (wie der Server).</summary>
    function CsvText: string;
    /// <summary>Zeile für Zeile der Text der Liste, Zellen mit " | " (für Tests und Bildschirmleser).</summary>
    function RowText: TArray<string>;
    property Answer: TAtlasQueryAnswer read FAnswer;
    property HasAnswer: Boolean read FHasAnswer;
    property Running: Boolean read FRunning;
    property Input: TEdit read FInput;
    property SavedCombo: TComboBox read FSaved;
    property RunButton: TButton read FRun;
    property CancelButton: TButton read FCancel;
    property SaveRuleButton: TButton read FSaveRule;
    property CopyCsvButton: TButton read FCopyCsv;
    property SuggestList: TListBox read FSuggest;
    property Suggestions: TArray<string> read FSuggestions;
    property ResultList: TListView read FList;
    property ErrorLabel: TLabel read FError;
    property StatusLabel: TLabel read FStatus;
    property SortColumn: Integer read FSortColumn;
    property SortDescending: Boolean read FSortDescending;
    /// <summary>Text der Eingabezeile.</summary>
    property OnRun: TProc<string> read FOnRun write FOnRun;
    property OnCancel: TProc read FOnCancel write FOnCancel;
    /// <summary>„Als Regel speichern …“ mit dem Text der Eingabezeile.</summary>
    property OnSaveRule: TProc<string> read FOnSaveRule write FOnSaveRule;
    /// <summary>CSV liegt in der Zwischenablage; Anzahl der Zeilen.</summary>
    property OnCopied: TProc<Integer> read FOnCopied write FOnCopied;
    /// <summary>Absoluter Pfad, Zeile und Spalte ab 1.</summary>
    property OnOpenLocation: TProc<string, Integer, Integer> read FOnOpenLocation write FOnOpenLocation;
    property OnSymbols: TAtlasCodeQuerySymbols read FOnSymbols write FOnSymbols;
  end;

implementation

uses
  Winapi.Windows,
  System.Types,
  System.Math,
  Vcl.Clipbrd,
  Atlas.UI.Strings;

{$R *.dfm}

const
  /// <summary>So viele Zeilen hat die Vorschlagsliste höchstens sichtbar.</summary>
  cSuggestRows = 8;
  /// <summary>So viele Symbolnamen kommen höchstens in die Liste.</summary>
  cMaxSymbols = 30;
  /// <summary>Symbolsuche erst ab so vielen getippten Zeichen.</summary>
  cSymbolMinChars = 2;

{ TAtlasCodeQueryFrame }

constructor TAtlasCodeQueryFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FSortColumn := -1;

  FTop := TPanel.Create(Self);
  FTop.Parent := Self;
  FTop.Align := alTop;
  FTop.BevelOuter := bvNone;
  FTop.ShowCaption := False;
  FTop.AutoSize := True;
  FTop.Padding.SetBounds(2, 2, 2, 0);

  FSaved := TComboBox.Create(Self);
  FSaved.Parent := FTop;
  FSaved.Align := alLeft;
  FSaved.AlignWithMargins := True;
  FSaved.Style := csDropDownList;
  FSaved.Width := 220;
  FSaved.Hint := TAtlasStrings.Text(TAtlasTextId.QuerySavedHint);
  FSaved.ShowHint := True;
  FSaved.OnChange := SavedChange;

  FRun := NewButton(TAtlasStrings.Text(TAtlasTextId.QueryRun), 90, RunClick);
  FCancel := NewButton(TAtlasStrings.Text(TAtlasTextId.QueryCancel), 90, CancelClick);
  FSaveRule := NewButton(TAtlasStrings.Text(TAtlasTextId.QuerySaveRule), 140, SaveRuleClick);
  FCopyCsv := NewButton(TAtlasStrings.Text(TAtlasTextId.QueryCopyCsv), 120, CopyCsvClick);

  FInputBar := TPanel.Create(Self);
  FInputBar.Parent := Self;
  FInputBar.Align := alTop;
  FInputBar.Top := FTop.Top + FTop.Height + 1;
  FInputBar.BevelOuter := bvNone;
  FInputBar.ShowCaption := False;
  FInputBar.AutoSize := True;
  FInputBar.Padding.SetBounds(2, 0, 2, 2);

  FInput := TEdit.Create(Self);
  FInput.Parent := FInputBar;
  FInput.Align := alTop;
  FInput.AlignWithMargins := True;
  FInput.TextHint := TAtlasStrings.Text(TAtlasTextId.QueryInputHint);
  FInput.OnChange := InputChange;
  FInput.OnKeyDown := InputKeyDown;
  FInput.OnKeyPress := InputKeyPress;
  FInput.OnExit := InputExit;

  FError := TLabel.Create(Self);
  FError.Parent := FInputBar;
  FError.Align := alTop;
  FError.Top := FInput.Top + FInput.Height + 1;
  FError.AlignWithMargins := True;
  FError.ShowAccelChar := False;
  FError.Visible := False;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.AlignWithMargins := True;
  FStatus.ShowAccelChar := False;

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.RowSelect := True;
  FList.ReadOnly := True;
  FList.HideSelection := False;
  FList.OwnerData := True;
  FList.ColumnClick := True;
  FList.OnData := ListData;
  FList.OnColumnClick := ListColumnClick;
  FList.OnDblClick := ListDblClick;
  FList.OnKeyDown := ListKeyDown;

  // Über der Liste, unter der Eingabezeile; liegt im Frame, damit sie nicht vom Panel abgeschnitten wird.
  FSuggest := TListBox.Create(Self);
  FSuggest.Parent := Self;
  FSuggest.Visible := False;
  FSuggest.TabStop := False;
  FSuggest.OnClick := SuggestClick;

  UpdateButtons;
end;

function TAtlasCodeQueryFrame.NewButton(const ACaption: string; AWidth: Integer; AClick: TNotifyEvent): TButton;
var
  mLeft: Integer;
  mIndex: Integer;
begin
  // Rechts an die bisherigen Steuerelemente anhängen (alLeft ordnet nach Left).
  mLeft := 0;
  for mIndex := 0 to FTop.ControlCount - 1 do
    mLeft := Max(mLeft, FTop.Controls[mIndex].Left + FTop.Controls[mIndex].Width + 1);
  Result := TButton.Create(Self);
  Result.Parent := FTop;
  Result.Align := alLeft;
  Result.AlignWithMargins := True;
  Result.Left := mLeft;
  Result.Caption := ACaption;
  Result.Width := AWidth;
  Result.OnClick := AClick;
end;

procedure TAtlasCodeQueryFrame.CreateWnd;
begin
  inherited CreateWnd;
  // Auswahl und Liste halten ihre Einträge im Fenster: erst jetzt füllen.
  FillSaved;
  FillColumns;
  FillRows;
  UpdateStatus;
end;

function TAtlasCodeQueryFrame.CanFill(AControl: TWinControl): Boolean;
begin
  Result := AControl.HandleAllocated or (GetParentForm(AControl) <> nil);
end;

procedure TAtlasCodeQueryFrame.FillSaved;
var
  mSaved: TAtlasSavedQuery;
begin
  if not CanFill(FSaved) then
    Exit;
  FUpdating := True;
  try
    FSaved.Items.BeginUpdate;
    try
      FSaved.Items.Clear;
      // Erster Eintrag: Hinweis statt Wahl (eine Klappliste zeigt keinen TextHint).
      FSaved.Items.Add(TAtlasStrings.Text(TAtlasTextId.QuerySavedHint));
      for mSaved in FCatalog.Saved do
        if mSaved.Description <> '' then
          FSaved.Items.Add(mSaved.Name + ' – ' + mSaved.Description)
        else
          FSaved.Items.Add(mSaved.Name);
    finally
      FSaved.Items.EndUpdate;
    end;
    FSaved.ItemIndex := 0;
    FSaved.Enabled := Length(FCatalog.Saved) > 0;
  finally
    FUpdating := False;
  end;
end;

procedure TAtlasCodeQueryFrame.FillColumns;
var
  mColumn: TListColumn;
  mName: string;
  mIndex: Integer;
begin
  FList.Columns.BeginUpdate;
  try
    FList.Columns.Clear;
    if not FHasAnswer then
      Exit;
    for mIndex := 0 to High(FAnswer.Columns) do
    begin
      mName := FAnswer.Columns[mIndex];
      mColumn := FList.Columns.Add;
      mColumn.Caption := mName;
      if mIndex = 0 then
        mColumn.Width := MulDiv(220, CurrentPPI, 96)
      else
        mColumn.Width := MulDiv(90, CurrentPPI, 96);
    end;
    mColumn := FList.Columns.Add;
    mColumn.Caption := TAtlasStrings.Text(TAtlasTextId.QueryColumnFile);
    mColumn.Width := MulDiv(320, CurrentPPI, 96);
  finally
    FList.Columns.EndUpdate;
  end;
end;

procedure TAtlasCodeQueryFrame.FillRows;
begin
  if not CanFill(FList) then
    Exit;
  FList.Items.BeginUpdate;
  try
    if FHasAnswer then
      FList.Items.Count := Length(FAnswer.Rows)
    else
      FList.Items.Count := 0;
  finally
    FList.Items.EndUpdate;
  end;
  FList.Invalidate;
end;

procedure TAtlasCodeQueryFrame.SetCatalog(const ACatalog: TAtlasQueryCatalog);
begin
  FCatalog := ACatalog;
  FillSaved;
end;

procedure TAtlasCodeQueryFrame.SetAnswer(const AAnswer: TAtlasQueryAnswer);
begin
  FAnswer := AAnswer;
  FHasAnswer := True;
  FRunning := False;
  FMessageText := '';
  if (FSortColumn >= 0) and (FSortColumn <= High(FAnswer.Columns)) then
    FAnswer.Sort(FSortColumn, FSortDescending)
  else
    FSortColumn := -1;
  FillColumns;
  FillRows;
  UpdateError;
  UpdateButtons;
  UpdateStatus;
end;

procedure TAtlasCodeQueryFrame.SetRunning(ARunning: Boolean);
begin
  FRunning := ARunning;
  if ARunning then
    FMessageText := TAtlasStrings.Text(TAtlasTextId.QueryRunning);
  UpdateButtons;
  UpdateStatus;
end;

procedure TAtlasCodeQueryFrame.SetMessage(const AText: string; AKeep: Boolean);
begin
  FMessageText := AText;
  FRunning := False;
  if not AKeep then
  begin
    FAnswer := Default(TAtlasQueryAnswer);
    FHasAnswer := False;
    FillColumns;
    FillRows;
    UpdateError;
  end;
  UpdateButtons;
  UpdateStatus;
end;

procedure TAtlasCodeQueryFrame.UpdateButtons;
begin
  FRun.Enabled := not FRunning;
  FCancel.Enabled := FRunning;
  FSaveRule.Enabled := Trim(FInput.Text) <> '';
  FCopyCsv.Enabled := FHasAnswer and (Length(FAnswer.Rows) > 0);
end;

procedure TAtlasCodeQueryFrame.UpdateStatus;
var
  mText: string;
begin
  if FMessageText <> '' then
    mText := FMessageText
  else if not FHasAnswer or FAnswer.Failed then
    mText := ''
  else if Length(FAnswer.Rows) = 0 then
    mText := TAtlasStrings.Text(TAtlasTextId.QueryEmpty)
  else
  begin
    if FAnswer.Truncated then
      mText := TAtlasStrings.Fmt(TAtlasTextId.QueryStatusTruncated, [Length(FAnswer.Rows), FAnswer.Total,
        FAnswer.ElapsedMs])
    else
      mText := TAtlasStrings.Fmt(TAtlasTextId.QueryStatus, [FAnswer.Total, FAnswer.ElapsedMs]);
    if FAnswer.InferredCount > 0 then
      mText := mText + TAtlasStrings.Fmt(TAtlasTextId.QueryStatusInferred, [FAnswer.InferredCount]);
  end;
  FStatus.Caption := mText;
end;

procedure TAtlasCodeQueryFrame.UpdateError;
var
  mText: string;
begin
  if not FHasAnswer or not FAnswer.Failed then
  begin
    FError.Visible := False;
    FError.Caption := '';
    Exit;
  end;
  if FAnswer.ErrorColumn > 0 then
    mText := TAtlasStrings.Fmt(TAtlasTextId.QueryError, [FAnswer.ErrorColumn, FAnswer.Error])
  else
    mText := FAnswer.Error;
  if FAnswer.Suggestion <> '' then
    mText := mText + ' ' + TAtlasStrings.Fmt(TAtlasTextId.QuerySuggestion, [FAnswer.Suggestion]);
  FError.Caption := mText;
  FError.Visible := True;
  // Schreibmarke an die Fehlerstelle, damit man gleich verbessern kann.
  if (FAnswer.ErrorColumn > 0) and (FAnswer.ErrorColumn <= Length(FInput.Text) + 1) then
  begin
    FInput.SelStart := FAnswer.ErrorColumn - 1;
    FInput.SelLength := 0;
  end;
end;

procedure TAtlasCodeQueryFrame.Run;
var
  mText: string;
begin
  HideSuggest;
  mText := Trim(FInput.Text);
  if (mText = '') or FRunning then
    Exit;
  if Assigned(FOnRun) then
    FOnRun(mText);
end;

procedure TAtlasCodeQueryFrame.ShowSuggestions;
var
  mItems: TArray<TAtlasQuerySuggestion>;
  mItem: TAtlasQuerySuggestion;
  mStart, mSymbolStart: Integer;
  mPrefix, mPredicate, mName: string;
  mNames: TArray<string>;
  mSeen: TStringList;
begin
  FSuggestions := nil;
  mItems := TAtlasQueryCompletion.Suggest(FCatalog, FInput.Text, FInput.SelStart, mStart);
  FSuggestStart := mStart;
  mSeen := TStringList.Create;
  try
    mSeen.CaseSensitive := False;
    mSeen.Sorted := True;
    mSeen.Duplicates := dupIgnore;
    for mItem in mItems do
      if mSeen.IndexOf(mItem.Text) < 0 then
      begin
        mSeen.Add(mItem.Text);
        FSuggestions := FSuggestions + [mItem.Text];
      end;
    if TAtlasQueryCompletion.SymbolPredicate(FInput.Text, FInput.SelStart, mSymbolStart, mPrefix, mPredicate) and
      (Length(mPrefix) >= cSymbolMinChars) and Assigned(FOnSymbols) then
    begin
      FSuggestStart := mSymbolStart;
      mNames := FOnSymbols(mPredicate, mPrefix);
      for mName in mNames do
      begin
        if Length(FSuggestions) >= cMaxSymbols then
          Break;
        if (mName <> '') and (mSeen.IndexOf(mName) < 0) then
        begin
          mSeen.Add(mName);
          FSuggestions := FSuggestions + [mName];
        end;
      end;
    end;
  finally
    mSeen.Free;
  end;
  if (Length(FSuggestions) = 0) or not CanFill(FSuggest) then
  begin
    HideSuggest;
    Exit;
  end;
  FSuggest.Items.BeginUpdate;
  try
    FSuggest.Items.Clear;
    for mName in FSuggestions do
      FSuggest.Items.Add(mName);
  finally
    FSuggest.Items.EndUpdate;
  end;
  FSuggest.ItemIndex := 0;
  PlaceSuggest;
  FSuggest.Visible := True;
  FSuggest.BringToFront;
end;

procedure TAtlasCodeQueryFrame.PlaceSuggest;
var
  mPoint: TPoint;
  mRows: Integer;
begin
  mPoint := ScreenToClient(FInput.ClientToScreen(Point(0, FInput.Height)));
  mRows := Min(cSuggestRows, Max(1, FSuggest.Items.Count));
  FSuggest.SetBounds(mPoint.X, mPoint.Y, Min(FInput.Width, MulDiv(320, CurrentPPI, 96)),
    mRows * FSuggest.ItemHeight + 4);
end;

procedure TAtlasCodeQueryFrame.HideSuggest;
begin
  FSuggest.Visible := False;
end;

procedure TAtlasCodeQueryFrame.AcceptSuggestion(AIndex: Integer);
var
  mText, mWord: string;
  mCursor: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FSuggestions)) then
    Exit;
  mWord := FSuggestions[AIndex];
  mText := FInput.Text;
  mCursor := Min(FInput.SelStart, Length(mText));
  FUpdating := True;
  try
    FInput.Text := Copy(mText, 1, FSuggestStart) + mWord + ' ' + Copy(mText, mCursor + 1, MaxInt);
    FInput.SelStart := FSuggestStart + Length(mWord) + 1;
    FInput.SelLength := 0;
  finally
    FUpdating := False;
  end;
  HideSuggest;
  UpdateButtons;
end;

procedure TAtlasCodeQueryFrame.SortBy(AColumn: Integer);
begin
  if not FHasAnswer then
    Exit;
  if (AColumn < 0) or (AColumn > High(FAnswer.Columns)) then
    // Spalte „Datei“: Reihenfolge nach Pfad, Zeile und Spalte.
    AColumn := -1;
  if AColumn = FSortColumn then
    FSortDescending := not FSortDescending
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

procedure TAtlasCodeQueryFrame.OpenRow(AIndex: Integer);
var
  mRow: TAtlasQueryRow;
begin
  if not FHasAnswer or (AIndex < 0) or (AIndex > High(FAnswer.Rows)) then
    Exit;
  mRow := FAnswer.Rows[AIndex];
  if (mRow.FileName <> '') and Assigned(FOnOpenLocation) then
    FOnOpenLocation(mRow.FileName, Max(1, mRow.Line), Max(1, mRow.Character));
end;

function TAtlasCodeQueryFrame.CsvText: string;
begin
  Result := '';
  if FHasAnswer then
    Result := FAnswer.Csv;
end;

function LocationText(const ARow: TAtlasQueryRow): string;
begin
  Result := ARow.Path;
  if Result = '' then
    Result := ARow.FileName;
  if ARow.Line > 0 then
    Result := Result + ':' + IntToStr(ARow.Line);
  if ARow.Inferred then
    Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.QueryInferred);
end;

function TAtlasCodeQueryFrame.RowText: TArray<string>;
var
  mRow: TAtlasQueryRow;
  mCells: TArray<string>;
  mCell: TAtlasQueryCell;
begin
  Result := nil;
  if not FHasAnswer then
    Exit;
  for mRow in FAnswer.Rows do
  begin
    mCells := nil;
    for mCell in mRow.Cells do
      mCells := mCells + [mCell.Text];
    mCells := mCells + [LocationText(mRow)];
    Result := Result + [string.Join(' | ', mCells)];
  end;
end;

procedure TAtlasCodeQueryFrame.SavedChange(Sender: TObject);
var
  mIndex: Integer;
begin
  if FUpdating then
    Exit;
  mIndex := FSaved.ItemIndex - 1;
  if (mIndex < 0) or (mIndex > High(FCatalog.Saved)) then
    Exit;
  FUpdating := True;
  try
    FInput.Text := FCatalog.Saved[mIndex].Query;
    FInput.SelStart := Length(FInput.Text);
  finally
    FUpdating := False;
  end;
  UpdateButtons;
  Run;
end;

procedure TAtlasCodeQueryFrame.RunClick(Sender: TObject);
begin
  Run;
end;

procedure TAtlasCodeQueryFrame.CancelClick(Sender: TObject);
begin
  if FRunning and Assigned(FOnCancel) then
    FOnCancel();
end;

procedure TAtlasCodeQueryFrame.SaveRuleClick(Sender: TObject);
begin
  HideSuggest;
  if (Trim(FInput.Text) <> '') and Assigned(FOnSaveRule) then
    FOnSaveRule(Trim(FInput.Text));
end;

procedure TAtlasCodeQueryFrame.CopyCsvClick(Sender: TObject);
begin
  if not FHasAnswer or (Length(FAnswer.Rows) = 0) then
    Exit;
  Clipboard.AsText := FAnswer.Csv;
  FMessageText := TAtlasStrings.Fmt(TAtlasTextId.QueryCopied, [Length(FAnswer.Rows)]);
  UpdateStatus;
  if Assigned(FOnCopied) then
    FOnCopied(Length(FAnswer.Rows));
end;

procedure TAtlasCodeQueryFrame.InputChange(Sender: TObject);
begin
  UpdateButtons;
  if FUpdating then
    Exit;
  if FInput.Focused then
    ShowSuggestions;
end;

procedure TAtlasCodeQueryFrame.InputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  mIndex: Integer;
begin
  if (Key = VK_SPACE) and (ssCtrl in Shift) then
  begin
    ShowSuggestions;
    Key := 0;
    Exit;
  end;
  if not FSuggest.Visible then
  begin
    if Key = VK_RETURN then
    begin
      Run;
      Key := 0;
    end;
    Exit;
  end;
  case Key of
    VK_DOWN, VK_UP:
      begin
        mIndex := FSuggest.ItemIndex;
        if Key = VK_DOWN then
          Inc(mIndex)
        else
          Dec(mIndex);
        FSuggest.ItemIndex := EnsureRange(mIndex, 0, FSuggest.Items.Count - 1);
        Key := 0;
      end;
    VK_RETURN, VK_TAB:
      begin
        AcceptSuggestion(FSuggest.ItemIndex);
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        HideSuggest;
        Key := 0;
      end;
  end;
end;

procedure TAtlasCodeQueryFrame.InputKeyPress(Sender: TObject; var Key: Char);
begin
  // Enter, Esc und Strg+Leer sind schon verarbeitet: kein Piepen, kein Leerzeichen.
  if (Key = #13) or (Key = #27) or ((Key = ' ') and (GetKeyState(VK_CONTROL) < 0)) then
    Key := #0;
end;

procedure TAtlasCodeQueryFrame.InputExit(Sender: TObject);
begin
  // Ein Klick in die Vorschlagsliste nimmt den Fokus nicht (TabStop aus, OnClick übernimmt vorher).
  if not FSuggest.Focused then
    HideSuggest;
end;

procedure TAtlasCodeQueryFrame.SuggestClick(Sender: TObject);
begin
  AcceptSuggestion(FSuggest.ItemIndex);
  if FInput.CanFocus and Showing then
    FInput.SetFocus;
end;

procedure TAtlasCodeQueryFrame.ListData(Sender: TObject; Item: TListItem);
var
  mRow: TAtlasQueryRow;
  mIndex: Integer;
begin
  if not FHasAnswer or (Item.Index < 0) or (Item.Index > High(FAnswer.Rows)) then
    Exit;
  mRow := FAnswer.Rows[Item.Index];
  if Length(mRow.Cells) > 0 then
    Item.Caption := mRow.Cells[0].Text
  else
    Item.Caption := '';
  for mIndex := 1 to High(mRow.Cells) do
    Item.SubItems.Add(mRow.Cells[mIndex].Text);
  // Fehlen Zellen (kürzere Zeile), bleibt „Datei“ trotzdem in seiner Spalte.
  for mIndex := Max(1, Length(mRow.Cells)) to High(FAnswer.Columns) do
    Item.SubItems.Add('');
  Item.SubItems.Add(LocationText(mRow));
end;

procedure TAtlasCodeQueryFrame.ListColumnClick(Sender: TObject; Column: TListColumn);
begin
  SortBy(Column.Index);
end;

procedure TAtlasCodeQueryFrame.ListDblClick(Sender: TObject);
begin
  OpenRow(FList.ItemIndex);
end;

procedure TAtlasCodeQueryFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key <> VK_RETURN then
    Exit;
  OpenRow(FList.ItemIndex);
  Key := 0;
end;

end.
