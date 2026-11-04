unit Atlas.UI.Search.Bar;

// Suchleiste der Atlas-Suche (#877, #878, #893): Zeilen am unteren Rand des
// Editors (statt des früheren Suchdialogs).
// - Suchzeile, von links: Knopf zum Auf- und Zuklappen der Ersetzen-Zeile
//   (nur mit search.replace); Suchfeld mit Verlauf; Optionen Groß-/Klein-
//   schreibung, ganzes Wort, Bezeichner statt Text und „.*“ (Regex, nur mit
//   search.regex); Bereich Unit, Methode, Auswahl (nur mit Auswahl) und mit
//   search.multiFile „Offene Dateien“, „Projekt“, „Projektgruppe“; bei Methode
//   die Stufe (innerste … äußerste umgebende Routine); Zähler „n von m“;
//   voriger/nächster Treffer; „In Meldungen“; „Abbrechen“ während der Suche
//   über Dateien; rechts Schließen.
// - Ersetzen-Zeile: Feld „Ersetzen durch“ mit Verlauf, „Ersetzen“ (aktuellen
//   Treffer ersetzen, zum nächsten springen), „Alle ersetzen“ und „Auswahl …“
//   (Treffer einzeln wählen, Fenster „Atlas-Suche: Ersetzen“).
// - Hinweiszeile, nur wenn es etwas zu sagen gibt: Fehlertext eines
//   ungültigen Ausdrucks (das Suchfeld ist dann rot umrandet), die Vorschau
//   des aktuellen Treffers (alter Text durchgestrichen → neuer Text) und
//   Meldungen wie „12 Ersetzungen in 3 Dateien“.
// Tasten in allen Feldern: Enter nächster Treffer und Liste in den Meldungen
// (OnNext, dann OnList), Umschalt+Enter voriger Treffer, F3 bzw. Umschalt+F3
// wie im Editor, Esc schließt (OnClose). Im Ersetzen-Feld ersetzt Enter den
// aktuellen Treffer, Strg+Enter alle. Pfeil hoch/runter im Such- und im
// Ersetzen-Feld blättert im Verlauf (TAtlasSearchHistory), Alt+↓ öffnet die
// Liste. Bearbeitungstasten wie Strg+V behalten Such- und Ersetzen-Feld
// selbst (TAtlasSearchCombo, #1243). Jede Änderung an Text, Optionen oder
// Bereich meldet OnQueryChanged.
// Bekommt ein Feld der Leiste den Fokus, meldet OnControlEnter es (der
// Aufrufer prüft, ob die IDE ihn gleich wieder in den Editor holt). Reine
// VCL; gesucht, markiert, ersetzt und gesprungen wird vom Aufrufer
// (Atlas.IDE.Search.Commands). Die Listen brauchen ein Fenster: gefüllt wird
// in CreateWnd bzw. sofort, wenn es schon eins gibt; die Verlaufsliste beim
// Aufklappen. Ohne Fenster liest die Leiste Bereich und Stufe aus der
// vorbereiteten Suche statt aus den Listen (Features vor dem Einhängen,
// Delphi 12).

interface

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.History;

type
  TAtlasSearchBarStep = reference to procedure(ABackward: Boolean);

  /// <summary>Teile der Leiste nach den Einstellungen (#893); Vorgabe (Default) alles aus.</summary>
  TAtlasSearchBarFeatures = record
    /// <summary>search.replace: Ersetzen-Zeile und Knopf zum Aufklappen.</summary>
    Replace: Boolean;
    /// <summary>search.regex: Option „.*“ und Vorschau.</summary>
    Regex: Boolean;
    /// <summary>search.multiFile: Bereiche über Dateien.</summary>
    MultiFile: Boolean;
    class function Create(AReplace, ARegex, AMultiFile: Boolean): TAtlasSearchBarFeatures; static;
  end;

  /// <summary>Such- bzw. Ersetzen-Feld mit Verlauf, das Bearbeitungstasten (Strg+V/C/X/A/Z/Y, Entf, Umschalt+Einfg …)
  /// selbst behält (#1243). Sonst prüft das Editorfenster der IDE sie zuerst als eigene Tastenkürzel und fügt etwa in
  /// den Editor ein. CN_KEYDOWN des inneren Eingabefelds kommt bei der Combobox an.</summary>
  TAtlasSearchCombo = class(TComboBox)
  private
    procedure CNKeyDown(var Message: TWMKeyDown); message CN_KEYDOWN;
  public
    /// <summary>Bleibt die Taste im Feld, statt als Tastenkürzel der IDE zu gelten?</summary>
    class function KeepsKey(AKey: Word; AShift: TShiftState): Boolean; static;
  end;

  TAtlasSearchBar = class(TCustomPanel)
  private type
{$SCOPEDENUMS ON}
    TInfoKind = (None, Error, Notice);
{$SCOPEDENUMS OFF}
  private
    FSearchRow: TPanel;
    FReplaceRow: TPanel;
    FInfoRow: TPanel;
    FToggle: TButton;
    FTextLabel: TLabel;
    FTextFrame: TPanel;
    FText: TAtlasSearchCombo;
    FCase: TCheckBox;
    FWhole: TCheckBox;
    FIdentifier: TCheckBox;
    FRegex: TCheckBox;
    FScopeLabel: TLabel;
    FScope: TComboBox;
    FLevel: TComboBox;
    FCounter: TLabel;
    FPrevious: TButton;
    FNext: TButton;
    FList: TButton;
    FCancel: TButton;
    FClose: TButton;
    FReplaceSpacer: TPanel;
    FReplaceLabel: TLabel;
    FReplaceText: TAtlasSearchCombo;
    FReplaceOne: TButton;
    FReplaceAll: TButton;
    FChoose: TButton;
    FInfo: TPaintBox;
    FQuery: TAtlasSearchQuery;
    FLevels: TArray<string>;
    FScopes: TArray<TAtlasSearchScope>;
    FHasSelection: Boolean;
    FFeatures: TAtlasSearchBarFeatures;
    FReplaceShown: Boolean;
    FPending: Boolean;
    FUpdating: Boolean;
    FInfoKind: TInfoKind;
    FInfoText: string;
    FPreviewBefore: string;
    FPreviewAfter: string;
    FHasPreview: Boolean;
    FSearchHistory: TAtlasSearchHistory;
    FReplaceHistory: TAtlasSearchHistory;
    FOnQueryChanged: TProc;
    FOnStep: TAtlasSearchBarStep;
    FOnList: TProc;
    FOnClose: TProc;
    FOnControlEnter: TProc<TWinControl>;
    FOnReplace: TProc;
    FOnReplaceAll: TProc;
    FOnChoose: TProc;
    FOnCancel: TProc;
    FOnReplaceShown: TProc;
    function AddRow(ATop: Integer): TPanel;
    procedure Place(ARow: TPanel; AControl: TControl; AWidth: Integer);
    function AddLabel(ARow: TPanel; const ACaption: string): TLabel;
    function AddCheck(const ACaption, AHint: string): TCheckBox;
    function AddButton(ARow: TPanel; const ACaption, AHint: string; AWidth: Integer): TButton;
    function AddCombo(ARow: TPanel; AStyle: TComboBoxStyle; AWidth: Integer): TComboBox;
    procedure Apply;
    /// <summary>Gewählter Bereich: aus der Liste, solange sie kein Fenster hat aus der vorbereiteten Suche.</summary>
    function SelectedScope: TAtlasSearchScope;
    /// <summary>Gewählte Stufe: aus der Liste, ohne Fenster aus der vorbereiteten Suche.</summary>
    function SelectedLevel: Integer;
    procedure UpdateStates;
    procedure UpdateLayout;
    procedure FitWidths;
    procedure Changed(Sender: TObject);
    procedure ReplaceChanged(Sender: TObject);
    procedure ControlEnter(Sender: TObject);
    procedure ControlKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HistoryDropDown(Sender: TObject);
    procedure ToggleClick(Sender: TObject);
    procedure PreviousClick(Sender: TObject);
    procedure NextClick(Sender: TObject);
    procedure ListClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure ReplaceOneClick(Sender: TObject);
    procedure ReplaceAllClick(Sender: TObject);
    procedure ChooseClick(Sender: TObject);
    procedure InfoPaint(Sender: TObject);
    procedure Step(ABackward: Boolean);
    procedure Fire(const AEvent: TProc);
    function HistoryOf(ABox: TComboBox): TAtlasSearchHistory;
    function GetListVisible: Boolean;
    procedure SetListVisible(AValue: Boolean);
    procedure SetFeatures(const AValue: TAtlasSearchBarFeatures);
    procedure SetReplaceShown(AValue: Boolean);
    function GetReplaceText: string;
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Felder nach AQuery setzen; ALevels sind die umgebenden Routinen (innerste zuerst).</summary>
    procedure Prepare(const AQuery: TAtlasSearchQuery; const ALevels: TArray<string>; AHasSelection: Boolean);
    /// <summary>Suche nach den Feldern der Leiste.</summary>
    function Query: TAtlasSearchQuery;
    /// <summary>Text des Zählers: „3 von 9“, „9 Treffer“, „Keine Treffer“ oder eine Meldung.</summary>
    procedure SetCounter(const AText: string);
    function Counter: string;
    /// <summary>Fehlertext eines ungültigen Ausdrucks ('' = keiner): Suchfeld rot umrandet, Zeile darunter.
    /// </summary>
    procedure SetError(const AText: string);
    /// <summary>Vorschau des aktuellen Treffers (alter Text durchgestrichen → neuer Text).</summary>
    procedure SetPreview(const ABefore, AAfter: string);
    procedure ClearPreview;
    /// <summary>Meldung in der Hinweiszeile ('' = keine), etwa „12 Ersetzungen in 3 Dateien“.</summary>
    procedure SetNotice(const AText: string);
    /// <summary>Text der Hinweiszeile, wie er gezeichnet wird (für Tests und das Protokoll).</summary>
    function InfoText: string;
    function HasError: Boolean;
    /// <summary>Suche über Dateien läuft: „Abbrechen“ zeigen.</summary>
    procedure SetSearching(AValue: Boolean);
    /// <summary>Verläufe für Such- und Ersetzen-Feld (gehören dem Aufrufer; nil = kein Verlauf).</summary>
    procedure SetHistories(ASearch, AReplace: TAtlasSearchHistory);
    /// <summary>Suchtext (und bei offener Ersetzen-Zeile den Ersatztext) in den Verlauf.</summary>
    procedure Remember;
    /// <summary>Fokus ins Suchfeld, Text markiert.</summary>
    procedure FocusText;
    /// <summary>Fokus ins Ersetzen-Feld, Text markiert.</summary>
    procedure FocusReplace;
    /// <summary>Hat ein Feld der Leiste den Fokus?</summary>
    function HasFocus: Boolean;
    /// <summary>Name des Bereichs in der Auswahlliste („Unit“, „Projekt“ …).</summary>
    class function ScopeCaption(AScope: TAtlasSearchScope): string; static;
    /// <summary>Schaltfläche „In Meldungen“ (search.resultsInMessages).</summary>
    property ListVisible: Boolean read GetListVisible write SetListVisible;
    property Features: TAtlasSearchBarFeatures read FFeatures write SetFeatures;
    /// <summary>Ersetzen-Zeile offen (nur mit Features.Replace).</summary>
    property ReplaceShown: Boolean read FReplaceShown write SetReplaceShown;
    property ReplaceText: string read GetReplaceText;
    property OnQueryChanged: TProc read FOnQueryChanged write FOnQueryChanged;
    property OnStep: TAtlasSearchBarStep read FOnStep write FOnStep;
    property OnList: TProc read FOnList write FOnList;
    property OnClose: TProc read FOnClose write FOnClose;
    /// <summary>Ein Feld der Leiste hat den Fokus bekommen.</summary>
    property OnControlEnter: TProc<TWinControl> read FOnControlEnter write FOnControlEnter;
    property OnReplace: TProc read FOnReplace write FOnReplace;
    property OnReplaceAll: TProc read FOnReplaceAll write FOnReplaceAll;
    property OnChoose: TProc read FOnChoose write FOnChoose;
    property OnCancel: TProc read FOnCancel write FOnCancel;
    /// <summary>Ersetzen-Zeile auf- oder zugeklappt bzw. Ersatztext geändert.</summary>
    property OnReplaceShown: TProc read FOnReplaceShown write FOnReplaceShown;
    // Für Tests.
    property TextEdit: TAtlasSearchCombo read FText;
    property ReplaceEdit: TAtlasSearchCombo read FReplaceText;
    property ScopeBox: TComboBox read FScope;
    property LevelBox: TComboBox read FLevel;
    property CaseBox: TCheckBox read FCase;
    property WholeBox: TCheckBox read FWhole;
    property IdentifierBox: TCheckBox read FIdentifier;
    property RegexBox: TCheckBox read FRegex;
    property ReplaceRow: TPanel read FReplaceRow;
    property ToggleButton: TButton read FToggle;
    property CancelButton: TButton read FCancel;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.UI.Search.Strings;

const
  BarHeight = 30;
  Gap = 6;
  ToggleWidth = 24;
  TextBoxWidth = 200;
  ScopeWidth = 120;
  LevelWidth = 240;
  ButtonWidth = 28;
  ErrorColor = TColor($0000C0);

{ TAtlasSearchBarFeatures }

class function TAtlasSearchBarFeatures.Create(AReplace, ARegex, AMultiFile: Boolean): TAtlasSearchBarFeatures;
begin
  Result.Replace := AReplace;
  Result.Regex := ARegex;
  Result.MultiFile := AMultiFile;
end;

{ TAtlasSearchCombo }

class function TAtlasSearchCombo.KeepsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  if AShift = [ssCtrl] then
  begin
    Result := CharInSet(Char(AKey), ['A', 'C', 'V', 'X', 'Y', 'Z']) or (AKey = VK_INSERT) or (AKey = VK_BACK) or
      (AKey = VK_DELETE) or (AKey = VK_LEFT) or (AKey = VK_RIGHT);
  end
  else if AShift = [ssShift] then
  begin
    Result := (AKey = VK_INSERT) or (AKey = VK_DELETE) or (AKey = VK_HOME) or (AKey = VK_END) or (AKey = VK_LEFT) or
      (AKey = VK_RIGHT);
  end
  else if AShift = [ssCtrl, ssShift] then
  begin
    Result := (AKey = Ord('Z')) or (AKey = VK_LEFT) or (AKey = VK_RIGHT);
  end
  else if AShift = [] then
  begin
    Result := (AKey = VK_DELETE) or (AKey = VK_HOME) or (AKey = VK_END) or (AKey = VK_BACK);
  end
  else
  begin
    Result := False;
  end;
end;

procedure TAtlasSearchCombo.CNKeyDown(var Message: TWMKeyDown);
begin
  // Vor der Prüfung der Tastenkürzel des Formulars (IsMenuKey): Result 0 lässt die Taste als WM_KEYDOWN ins Feld.
  if KeepsKey(Message.CharCode, KeyDataToShiftState(Message.KeyData)) then
  begin
    Message.Result := 0;
    Exit;
  end;
  inherited;
end;

{ TAtlasSearchBar }

constructor TAtlasSearchBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';
  ShowCaption := False;
  ShowHint := True;
  FQuery := Default(TAtlasSearchQuery);
  FQuery.Scope := TAtlasSearchScope.UnitFile;
  FFeatures := Default(TAtlasSearchBarFeatures);

  FSearchRow := AddRow(0);
  FReplaceRow := AddRow(1000);
  FInfoRow := AddRow(2000);

  FClose := TButton.Create(Self);
  FClose.Parent := FSearchRow;
  FClose.Align := alRight;
  FClose.AlignWithMargins := True;
  FClose.Margins.SetBounds(Gap, 3, Gap, 3);
  FClose.Width := ScaleValue(ButtonWidth);
  FClose.Caption := '×';
  FClose.Hint := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchCloseHint);
  FClose.OnClick := CloseClick;
  FClose.OnKeyDown := ControlKeyDown;
  FClose.OnEnter := ControlEnter;

  FToggle := AddButton(FSearchRow, '▸', TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchToggleReplaceHint),
    ToggleWidth);
  FToggle.OnClick := ToggleClick;
  FTextLabel := AddLabel(FSearchRow, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchTextLabel));
  // Rahmen um das Suchfeld: rot bei ungültigem Ausdruck.
  FTextFrame := TPanel.Create(Self);
  FTextFrame.Parent := FSearchRow;
  FTextFrame.BevelOuter := bvNone;
  FTextFrame.Caption := '';
  FTextFrame.ShowCaption := False;
  FTextFrame.Padding.SetBounds(1, 1, 1, 1);
  Place(FSearchRow, FTextFrame, TextBoxWidth + 2);
  FTextFrame.Margins.SetBounds(Gap, 2, 0, 2);
  FText := TAtlasSearchCombo.Create(Self);
  FText.Parent := FTextFrame;
  FText.Style := csDropDown;
  FText.Align := alClient;
  FText.OnChange := Changed;
  FText.OnKeyDown := ControlKeyDown;
  FText.OnEnter := ControlEnter;
  FText.OnDropDown := HistoryDropDown;
  FTextLabel.FocusControl := FText;

  FCase := AddCheck(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchCaseSensitive),
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchCaseHint));
  FWhole := AddCheck(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchWholeWord),
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchWholeHint));
  FIdentifier := AddCheck(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchIdentifier),
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchIdentifierHint));
  FRegex := AddCheck('.*', TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchRegexHint));

  FScopeLabel := AddLabel(FSearchRow, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchScopeLabel));
  FScope := AddCombo(FSearchRow, csDropDownList, ScopeWidth);
  FScope.OnChange := Changed;
  FScopeLabel.FocusControl := FScope;
  FLevel := AddCombo(FSearchRow, csDropDownList, LevelWidth);
  FLevel.OnChange := Changed;

  FCounter := AddLabel(FSearchRow, '');
  FPrevious := AddButton(FSearchRow, '↑', TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchPreviousHint), ButtonWidth);
  FPrevious.OnClick := PreviousClick;
  FNext := AddButton(FSearchRow, '↓', TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchNextHint), ButtonWidth);
  FNext.OnClick := NextClick;
  FList := AddButton(FSearchRow, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchListButton),
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchListHint), 100);
  FList.OnClick := ListClick;
  FCancel := AddButton(FSearchRow, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchCancelButton),
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchCancelHint), 90);
  FCancel.OnClick := CancelClick;
  FCancel.Visible := False;

  // Ersetzen-Zeile: das Feld steht unter dem Suchfeld (Platz für den Knopf zum Aufklappen).
  FReplaceSpacer := TPanel.Create(Self);
  FReplaceSpacer.Parent := FReplaceRow;
  FReplaceSpacer.BevelOuter := bvNone;
  FReplaceSpacer.Caption := '';
  FReplaceSpacer.ShowCaption := False;
  Place(FReplaceRow, FReplaceSpacer, ToggleWidth);
  FReplaceLabel := AddLabel(FReplaceRow, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceLabel));
  FReplaceText := AddCombo(FReplaceRow, csDropDown, TextBoxWidth) as TAtlasSearchCombo;
  FReplaceText.OnChange := ReplaceChanged;
  FReplaceText.OnDropDown := HistoryDropDown;
  FReplaceLabel.FocusControl := FReplaceText;
  FReplaceOne := AddButton(FReplaceRow, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceButton),
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceHint), 90);
  FReplaceOne.OnClick := ReplaceOneClick;
  FReplaceAll := AddButton(FReplaceRow, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceAllButton),
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceAllHint), 110);
  FReplaceAll.OnClick := ReplaceAllClick;
  FChoose := AddButton(FReplaceRow, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchChooseButton),
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchChooseHint), 90);
  FChoose.OnClick := ChooseClick;

  FInfo := TPaintBox.Create(Self);
  FInfo.Parent := FInfoRow;
  FInfo.Align := alClient;
  FInfo.AlignWithMargins := True;
  FInfo.Margins.SetBounds(Gap + ScaleValue(ToggleWidth), 2, Gap, 2);
  FInfo.OnPaint := InfoPaint;

  UpdateLayout;
end;

function TAtlasSearchBar.AddRow(ATop: Integer): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := Self;
  Result.BevelOuter := bvNone;
  Result.Caption := '';
  Result.ShowCaption := False;
  Result.Top := ATop;
  Result.Height := ScaleValue(BarHeight);
  Result.Align := alTop;
end;

procedure TAtlasSearchBar.Place(ARow: TPanel; AControl: TControl; AWidth: Integer);
begin
  // alLeft ordnet nach Left: jedes neue Element rechts an die vorigen (Tag zählt je Zeile).
  ARow.Tag := ARow.Tag + 10000;
  AControl.Left := ARow.Tag;
  AControl.Align := alLeft;
  AControl.AlignWithMargins := True;
  AControl.Margins.SetBounds(Gap, 3, 0, 3);
  if AWidth > 0 then
  begin
    AControl.Width := ScaleValue(AWidth);
  end;
end;

function TAtlasSearchBar.AddLabel(ARow: TPanel; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := ARow;
  Result.ShowAccelChar := False;
  Result.Layout := tlCenter;
  Result.AutoSize := True;
  Result.Caption := ACaption;
  Place(ARow, Result, 0);
  Result.Margins.Top := 0;
  Result.Margins.Bottom := 0;
end;

function TAtlasSearchBar.AddCheck(const ACaption, AHint: string): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := FSearchRow;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  // Breite nach dem Text erst mit Fenster (FitWidths); bis dahin geschätzt.
  Place(FSearchRow, Result, 24 + 7 * Length(ACaption));
  Result.OnClick := Changed;
  Result.OnKeyDown := ControlKeyDown;
  Result.OnEnter := ControlEnter;
end;

function TAtlasSearchBar.AddButton(ARow: TPanel; const ACaption, AHint: string; AWidth: Integer): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := ARow;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Place(ARow, Result, AWidth);
  Result.OnKeyDown := ControlKeyDown;
  Result.OnEnter := ControlEnter;
end;

function TAtlasSearchBar.AddCombo(ARow: TPanel; AStyle: TComboBoxStyle; AWidth: Integer): TComboBox;
begin
  // Mit Tasten wie im Suchfeld (#1243): Im Ersetzen-Feld fügte Strg+V sonst in den Editor ein.
  Result := TAtlasSearchCombo.Create(Self);
  Result.Parent := ARow;
  Result.Style := AStyle;
  Place(ARow, Result, AWidth);
  Result.OnKeyDown := ControlKeyDown;
  Result.OnEnter := ControlEnter;
end;

procedure TAtlasSearchBar.CreateWnd;
begin
  inherited CreateWnd;
  FitWidths;
  if FPending then
  begin
    Apply;
  end;
end;

procedure TAtlasSearchBar.FitWidths;
var
  Boxes: TArray<TCheckBox>;
  Box: TCheckBox;
  Buttons: TArray<TButton>;
  Button: TButton;
begin
  Canvas.Font := Font;
  Boxes := [FCase, FWhole, FIdentifier, FRegex];
  for Box in Boxes do
  begin
    Box.Width := Canvas.TextWidth(Box.Caption) + ScaleValue(24);
  end;
  Buttons := [FList, FCancel, FReplaceOne, FReplaceAll, FChoose];
  for Button in Buttons do
  begin
    Button.Width := Canvas.TextWidth(Button.Caption) + ScaleValue(20);
  end;
end;

procedure TAtlasSearchBar.Prepare(const AQuery: TAtlasSearchQuery; const ALevels: TArray<string>;
  AHasSelection: Boolean);
begin
  FQuery := AQuery;
  FLevels := ALevels;
  FHasSelection := AHasSelection;
  FPending := True;
  if HandleAllocated then
  begin
    Apply;
  end;
end;

procedure TAtlasSearchBar.Apply;
var
  Level: string;
  Scope: TAtlasSearchScope;
  Index: Integer;
begin
  FPending := False;
  FUpdating := True;
  try
    FText.Text := FQuery.Text;
    FCase.Checked := FQuery.Options.CaseSensitive;
    FWhole.Checked := FQuery.Options.WholeWord;
    FIdentifier.Checked := FQuery.Options.Identifier;
    FRegex.Checked := FQuery.Options.Regex and FFeatures.Regex;
    // Reihenfolge wie TAtlasSearchScope: Unit, Methode, Auswahl, offene Dateien, Projekt, Projektgruppe.
    FScopes := [TAtlasSearchScope.UnitFile, TAtlasSearchScope.Method];
    if FHasSelection then
    begin
      FScopes := FScopes + [TAtlasSearchScope.Selection];
    end;
    if FFeatures.MultiFile then
    begin
      FScopes := FScopes + [TAtlasSearchScope.OpenFiles, TAtlasSearchScope.Project, TAtlasSearchScope.ProjectGroup];
    end;
    FScope.Items.BeginUpdate;
    try
      FScope.Items.Clear;
      for Scope in FScopes do
      begin
        FScope.Items.Add(ScopeCaption(Scope));
      end;
    finally
      FScope.Items.EndUpdate;
    end;
    // Ein Bereich, den es gerade nicht gibt (Auswahl ohne Auswahl, Dateien mit search.multiFile aus), wird Unit.
    FScope.ItemIndex := 0;
    for Index := 0 to High(FScopes) do
    begin
      if FScopes[Index] = FQuery.Scope then
      begin
        FScope.ItemIndex := Index;
      end;
    end;
    FQuery.Scope := FScopes[FScope.ItemIndex];
    FLevel.Items.BeginUpdate;
    try
      FLevel.Items.Clear;
      for Level in FLevels do
      begin
        FLevel.Items.Add(Level);
      end;
    finally
      FLevel.Items.EndUpdate;
    end;
    FLevel.ItemIndex := -1;
    if Length(FLevels) > 0 then
    begin
      FLevel.ItemIndex := FQuery.Level;
      if FLevel.ItemIndex < 0 then
      begin
        FLevel.ItemIndex := 0;
      end;
    end;
    UpdateStates;
  finally
    FUpdating := False;
  end;
end;

class function TAtlasSearchBar.ScopeCaption(AScope: TAtlasSearchScope): string;
begin
  case AScope of
    TAtlasSearchScope.Method:
      Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchScopeMethod);
    TAtlasSearchScope.Selection:
      Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchScopeSelection);
    TAtlasSearchScope.OpenFiles:
      Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchScopeOpenFiles);
    TAtlasSearchScope.Project:
      Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchScopeProject);
    TAtlasSearchScope.ProjectGroup:
      Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchScopeProjectGroup);
  else
    Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchScopeUnit);
  end;
end;

// ItemIndex und Items.Count einer TComboBox fragen ihr Fenster ab (CB_GETCURSEL, CB_GETCOUNT) und legen es dafür
// an. Ohne übergeordnetes Fenster scheitert das mit EInvalidOperation: Unter Delphi 12 legt die Suche ihre Leiste
// vor dem Einhängen an (CreateBar setzt Features, dann ordnet Place sie ein); jedes Strg+F scheiterte so, und nach
// dem dritten Versuch schaltete die Sicherung die Atlas-Suche ab. Ohne Fenster gilt darum der
// Stand der vorbereiteten Suche; Apply schreibt ihn in die Listen, sobald es eins gibt.

function TAtlasSearchBar.SelectedScope: TAtlasSearchScope;
var
  mIndex: Integer;
begin
  Result := FQuery.Scope;
  if not FScope.HandleAllocated then
  begin
    Exit;
  end;
  mIndex := FScope.ItemIndex;
  if (mIndex >= 0) and (mIndex <= High(FScopes)) then
  begin
    Result := FScopes[mIndex];
  end;
end;

function TAtlasSearchBar.SelectedLevel: Integer;
begin
  Result := FQuery.Level;
  if FLevel.HandleAllocated then
  begin
    Result := FLevel.ItemIndex;
  end;
end;

procedure TAtlasSearchBar.UpdateStates;
begin
  // FLevels sind die Einträge der Stufenliste (Apply füllt sie daraus); Items.Count bräuchte ein Fenster.
  FLevel.Visible := (SelectedScope = TAtlasSearchScope.Method) and (Length(FLevels) > 0);
  // Bezeichner-Modus ohne Regex kennt nur ganze Bezeichner ohne Rücksicht auf die Schreibweise; mit Regex filtert
  // er nur Kommentare und Strings heraus.
  FCase.Enabled := not FIdentifier.Checked or FRegex.Checked;
  FWhole.Enabled := not FIdentifier.Checked or FRegex.Checked;
  FRegex.Visible := FFeatures.Regex;
end;

procedure TAtlasSearchBar.UpdateLayout;
var
  Rows: Integer;
begin
  FToggle.Visible := FFeatures.Replace;
  if not FFeatures.Replace then
  begin
    FReplaceShown := False;
  end;
  if FReplaceShown then
  begin
    FToggle.Caption := '▾';
  end
  else
  begin
    FToggle.Caption := '▸';
  end;
  FReplaceRow.Visible := FReplaceShown;
  FInfoRow.Visible := FInfoKind <> TInfoKind.None;
  // Reihenfolge der Zeilen festhalten: sichtbar gewordene alTop-Panels ordnen sich nach Top.
  FSearchRow.Top := 0;
  FReplaceRow.Top := FSearchRow.Height;
  FInfoRow.Top := 2 * FSearchRow.Height;
  Rows := 1;
  if FReplaceRow.Visible then
  begin
    Inc(Rows);
  end;
  if FInfoRow.Visible then
  begin
    Inc(Rows);
  end;
  Height := Rows * ScaleValue(BarHeight);
  FInfo.Invalidate;
end;

procedure TAtlasSearchBar.SetFeatures(const AValue: TAtlasSearchBarFeatures);
begin
  FFeatures := AValue;
  if not FFeatures.Regex then
  begin
    FRegex.Checked := False;
  end;
  if not FFeatures.Regex then
  begin
    ClearPreview;
  end;
  UpdateStates;
  UpdateLayout;
  if HandleAllocated and not FPending then
  begin
    // Bereiche neu aufbauen (Dateien ein/aus), Auswahl beibehalten.
    FQuery := Query;
    Apply;
  end;
end;

procedure TAtlasSearchBar.SetReplaceShown(AValue: Boolean);
begin
  AValue := AValue and FFeatures.Replace;
  if AValue = FReplaceShown then
  begin
    Exit;
  end;
  FReplaceShown := AValue;
  if not FReplaceShown then
  begin
    ClearPreview;
  end;
  UpdateLayout;
end;

function TAtlasSearchBar.GetReplaceText: string;
begin
  Result := FReplaceText.Text;
end;

function TAtlasSearchBar.Query: TAtlasSearchQuery;
begin
  Result := FQuery;
  Result.Text := FText.Text;
  Result.Options := TAtlasSearchOptions.Create(FCase.Checked, FWhole.Checked, FIdentifier.Checked,
    FRegex.Checked and FFeatures.Regex);
  Result.Scope := SelectedScope;
  Result.Level := SelectedLevel;
  if Result.Level < 0 then
  begin
    Result.Level := 0;
  end;
end;

procedure TAtlasSearchBar.SetCounter(const AText: string);
begin
  FCounter.Caption := AText;
end;

function TAtlasSearchBar.Counter: string;
begin
  Result := FCounter.Caption;
end;

procedure TAtlasSearchBar.SetError(const AText: string);
begin
  if AText <> '' then
  begin
    FInfoKind := TInfoKind.Error;
    FInfoText := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchRegexError, [AText]);
    FTextFrame.ParentBackground := False;
    FTextFrame.StyleElements := FTextFrame.StyleElements - [seClient];
    FTextFrame.Color := ErrorColor;
  end
  else
  begin
    if FInfoKind = TInfoKind.Error then
    begin
      FInfoKind := TInfoKind.None;
      FInfoText := '';
    end;
    FTextFrame.StyleElements := FTextFrame.StyleElements + [seClient];
    FTextFrame.ParentColor := True;
    FTextFrame.ParentBackground := True;
  end;
  UpdateLayout;
end;

function TAtlasSearchBar.HasError: Boolean;
begin
  Result := FInfoKind = TInfoKind.Error;
end;

procedure TAtlasSearchBar.SetPreview(const ABefore, AAfter: string);
begin
  FPreviewBefore := ABefore;
  FPreviewAfter := AAfter;
  FHasPreview := True;
  if FInfoKind = TInfoKind.None then
  begin
    FInfoKind := TInfoKind.Notice;
  end;
  UpdateLayout;
end;

procedure TAtlasSearchBar.ClearPreview;
begin
  FHasPreview := False;
  FPreviewBefore := '';
  FPreviewAfter := '';
  if (FInfoKind = TInfoKind.Notice) and (FInfoText = '') then
  begin
    FInfoKind := TInfoKind.None;
  end;
  if FInfo <> nil then
  begin
    UpdateLayout;
  end;
end;

procedure TAtlasSearchBar.SetNotice(const AText: string);
begin
  if FInfoKind = TInfoKind.Error then
  begin
    Exit;
  end;
  FInfoText := AText;
  if (AText <> '') or FHasPreview then
  begin
    FInfoKind := TInfoKind.Notice;
  end
  else
  begin
    FInfoKind := TInfoKind.None;
  end;
  UpdateLayout;
end;

function TAtlasSearchBar.InfoText: string;
begin
  Result := '';
  case FInfoKind of
    TInfoKind.Error:
      Result := FInfoText;
    TInfoKind.Notice:
      begin
        if FHasPreview then
        begin
          Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchPreviewLabel) + ' ' + FPreviewBefore + ' → ' +
            FPreviewAfter;
        end;
        if (Result <> '') and (FInfoText <> '') then
        begin
          Result := Result + '   ·   ';
        end;
        Result := Result + FInfoText;
      end;
  end;
end;

procedure TAtlasSearchBar.InfoPaint(Sender: TObject);
var
  Canvas: TCanvas;
  X, Y: Integer;

  procedure Put(const AText: string; AStyle: TFontStyles);
  begin
    Canvas.Font.Style := AStyle;
    Canvas.TextOut(X, Y, AText);
    Inc(X, Canvas.TextWidth(AText));
  end;

begin
  Canvas := FInfo.Canvas;
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  Y := (FInfo.Height - Canvas.TextHeight('Ag')) div 2;
  X := 0;
  if FInfoKind = TInfoKind.Error then
  begin
    Canvas.Font.Color := ErrorColor;
    Put(FInfoText, []);
    Exit;
  end;
  if FHasPreview then
  begin
    Put(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchPreviewLabel) + ' ', []);
    Put(FPreviewBefore, [fsStrikeOut]);
    Put(' → ', []);
    Put(FPreviewAfter, [fsBold]);
    if FInfoText <> '' then
    begin
      Put('   ·   ', []);
    end;
  end;
  Put(FInfoText, []);
end;

procedure TAtlasSearchBar.SetSearching(AValue: Boolean);
begin
  FCancel.Visible := AValue;
end;

procedure TAtlasSearchBar.SetHistories(ASearch, AReplace: TAtlasSearchHistory);
begin
  FSearchHistory := ASearch;
  FReplaceHistory := AReplace;
end;

procedure TAtlasSearchBar.Remember;
begin
  if FSearchHistory <> nil then
  begin
    FSearchHistory.Remember(FText.Text);
  end;
  if FReplaceShown and (FReplaceHistory <> nil) then
  begin
    FReplaceHistory.Remember(FReplaceText.Text);
  end;
end;

function TAtlasSearchBar.HistoryOf(ABox: TComboBox): TAtlasSearchHistory;
begin
  Result := nil;
  if ABox = FText then
  begin
    Result := FSearchHistory;
  end
  else if ABox = FReplaceText then
  begin
    Result := FReplaceHistory;
  end;
end;

procedure TAtlasSearchBar.HistoryDropDown(Sender: TObject);
var
  Box: TComboBox;
  History: TAtlasSearchHistory;
  Item, Text: string;
begin
  if not (Sender is TComboBox) then
  begin
    Exit;
  end;
  Box := TComboBox(Sender);
  History := HistoryOf(Box);
  // Liste erst beim Aufklappen füllen (sie braucht ein Fenster); der Text im Feld bleibt.
  Text := Box.Text;
  FUpdating := True;
  try
    Box.Items.BeginUpdate;
    try
      Box.Items.Clear;
      if History <> nil then
      begin
        for Item in History.Items do
        begin
          Box.Items.Add(Item);
        end;
      end;
    finally
      Box.Items.EndUpdate;
    end;
    Box.Text := Text;
  finally
    FUpdating := False;
  end;
end;

function TAtlasSearchBar.GetListVisible: Boolean;
begin
  Result := FList.Visible;
end;

procedure TAtlasSearchBar.SetListVisible(AValue: Boolean);
begin
  FList.Visible := AValue;
end;

procedure TAtlasSearchBar.FocusText;
begin
  if FText.CanFocus then
  begin
    FText.SetFocus;
    FText.SelectAll;
  end;
end;

procedure TAtlasSearchBar.FocusReplace;
begin
  if FReplaceShown and FReplaceText.CanFocus then
  begin
    FReplaceText.SetFocus;
    FReplaceText.SelectAll;
  end;
end;

function TAtlasSearchBar.HasFocus: Boolean;
var
  Focused: HWND;
begin
  Focused := Winapi.Windows.GetFocus;
  Result := HandleAllocated and (Focused <> 0) and ((Focused = Handle) or IsChild(Handle, Focused));
end;

procedure TAtlasSearchBar.Changed(Sender: TObject);
begin
  if FUpdating then
  begin
    Exit;
  end;
  // Von Hand geändert: Blättern im Verlauf beginnt beim nächsten Pfeil von vorn.
  if (Sender = FText) and (FSearchHistory <> nil) then
  begin
    FSearchHistory.Reset;
  end;
  UpdateStates;
  Fire(FOnQueryChanged);
end;

procedure TAtlasSearchBar.ReplaceChanged(Sender: TObject);
begin
  if FUpdating then
  begin
    Exit;
  end;
  if FReplaceHistory <> nil then
  begin
    FReplaceHistory.Reset;
  end;
  Fire(FOnReplaceShown);
end;

procedure TAtlasSearchBar.ControlEnter(Sender: TObject);
begin
  if Assigned(FOnControlEnter) and (Sender is TWinControl) then
  begin
    FOnControlEnter(TWinControl(Sender));
  end;
end;

procedure TAtlasSearchBar.Fire(const AEvent: TProc);
begin
  if Assigned(AEvent) then
  begin
    AEvent();
  end;
end;

procedure TAtlasSearchBar.Step(ABackward: Boolean);
begin
  Remember;
  if Assigned(FOnStep) then
  begin
    FOnStep(ABackward);
  end;
end;

procedure TAtlasSearchBar.ControlKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Box: TComboBox;
  History: TAtlasSearchHistory;
  Next: string;
  Older: Boolean;
begin
  // Offene Auswahlliste: Enter, Esc und die Pfeile gehören ihr.
  if (Sender is TComboBox) and TComboBox(Sender).DroppedDown then
  begin
    Exit;
  end;
  // Pfeil hoch/runter im Such- bzw. Ersetzen-Feld: Verlauf (Alt+↓ öffnet die Liste wie gewohnt).
  if ((Key = VK_UP) or (Key = VK_DOWN)) and not (ssAlt in Shift) and ((Sender = FText) or (Sender = FReplaceText))
  then
  begin
    Box := TComboBox(Sender);
    History := HistoryOf(Box);
    Older := Key = VK_UP;
    Key := 0;
    if History = nil then
    begin
      Exit;
    end;
    Next := History.Step(Box.Text, Older);
    if Next = Box.Text then
    begin
      Exit;
    end;
    // Ohne FUpdating setzte Changed das Blättern zurück.
    FUpdating := True;
    try
      Box.Text := Next;
      Box.SelectAll;
    finally
      FUpdating := False;
    end;
    // Text per Programm löst OnChange nicht aus: Suche bzw. Vorschau selbst anstoßen.
    if Box = FText then
    begin
      UpdateStates;
      Fire(FOnQueryChanged);
    end
    else
    begin
      Fire(FOnReplaceShown);
    end;
    Exit;
  end;
  case Key of
    VK_RETURN:
      begin
        Key := 0;
        if Sender = FReplaceText then
        begin
          Remember;
          if ssCtrl in Shift then
          begin
            Fire(FOnReplaceAll);
          end
          else
          begin
            Fire(FOnReplace);
          end;
          Exit;
        end;
        Step(ssShift in Shift);
        if not (ssShift in Shift) and FList.Visible then
        begin
          Fire(FOnList);
        end;
      end;
    VK_F3:
      begin
        Key := 0;
        Step(ssShift in Shift);
      end;
    VK_ESCAPE:
      begin
        Key := 0;
        Fire(FOnClose);
      end;
  end;
end;

procedure TAtlasSearchBar.ToggleClick(Sender: TObject);
begin
  ReplaceShown := not ReplaceShown;
  if ReplaceShown then
  begin
    FocusReplace;
  end
  else
  begin
    FocusText;
  end;
  Fire(FOnReplaceShown);
end;

procedure TAtlasSearchBar.PreviousClick(Sender: TObject);
begin
  Step(True);
end;

procedure TAtlasSearchBar.NextClick(Sender: TObject);
begin
  Step(False);
end;

procedure TAtlasSearchBar.ListClick(Sender: TObject);
begin
  Remember;
  Fire(FOnList);
end;

procedure TAtlasSearchBar.CancelClick(Sender: TObject);
begin
  Fire(FOnCancel);
end;

procedure TAtlasSearchBar.CloseClick(Sender: TObject);
begin
  Fire(FOnClose);
end;

procedure TAtlasSearchBar.ReplaceOneClick(Sender: TObject);
begin
  Remember;
  Fire(FOnReplace);
end;

procedure TAtlasSearchBar.ReplaceAllClick(Sender: TObject);
begin
  Remember;
  Fire(FOnReplaceAll);
end;

procedure TAtlasSearchBar.ChooseClick(Sender: TObject);
begin
  Remember;
  Fire(FOnChoose);
end;

end.
