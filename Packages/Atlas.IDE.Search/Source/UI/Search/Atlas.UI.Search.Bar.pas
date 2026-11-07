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
// Aufbau: Die Steuerelemente stehen in TAtlasSearchBarParts, die Ereignisse für den Aufrufer in
// TAtlasSearchBarEvents, die Hinweiszeile zeichnet TAtlasSearchInfoLine.

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
    /// <summary>Verlauf des Felds (gehört dem Aufrufer; nil = kein Verlauf).</summary>
    History: TAtlasSearchHistory;
    /// <summary>Bleibt die Taste im Feld, statt als Tastenkürzel der IDE zu gelten?</summary>
    class function KeepsKey(AKey: Word; AShift: TShiftState): Boolean; static;
  end;

  /// <summary>Hinweiszeile: Fehlertext eines ungültigen Ausdrucks, Vorschau des aktuellen Treffers (alter Text
  /// durchgestrichen → neuer Text) und Meldungen.</summary>
  TAtlasSearchInfoLine = class(TPaintBox)
  private type
{$SCOPEDENUMS ON}
    TKind = (None, Error, Notice);
{$SCOPEDENUMS OFF}
  private
    FKind: TKind;
    FMessage: string;
    FBefore: string;
    FAfter: string;
    FHasPreview: Boolean;
  protected
    procedure Paint; override;
  public
    procedure ShowError(const AText: string);
    procedure ClearError;
    procedure ShowPreview(const ABefore, AAfter: string);
    procedure ClearPreview;
    /// <summary>Meldung ('' = keine); bei einem Fehler ohne Wirkung.</summary>
    procedure ShowNotice(const AText: string);
    /// <summary>Text der Zeile, wie er gezeichnet wird.</summary>
    function Content: string;
    function IsError: Boolean;
    /// <summary>Gibt es etwas zu zeigen?</summary>
    function HasContent: Boolean;
  end;

  /// <summary>Ereignisse der Leiste für den Aufrufer.</summary>
  TAtlasSearchBarEvents = class(TComponent)
  public
    /// <summary>Text, Optionen oder Bereich geändert.</summary>
    OnQueryChanged: TProc;
    OnStep: TAtlasSearchBarStep;
    OnList: TProc;
    OnClose: TProc;
    /// <summary>Ein Feld der Leiste hat den Fokus bekommen.</summary>
    OnControlEnter: TProc<TWinControl>;
    OnReplace: TProc;
    OnReplaceAll: TProc;
    OnChoose: TProc;
    OnCancel: TProc;
    /// <summary>Ersetzen-Zeile auf- oder zugeklappt bzw. Ersatztext geändert.</summary>
    OnReplaceShown: TProc;
    class procedure Fire(const AEvent: TProc); static;
  end;

  /// <summary>Steuerelemente der Leiste (gehören der Leiste; auch für Tests).</summary>
  TAtlasSearchBarParts = class(TComponent)
  public
    SearchRow: TPanel;
    ReplaceRow: TPanel;
    InfoRow: TPanel;
    ToggleButton: TButton;
    TextFrame: TPanel;
    TextEdit: TAtlasSearchCombo;
    CaseBox: TCheckBox;
    WholeBox: TCheckBox;
    IdentifierBox: TCheckBox;
    RegexBox: TCheckBox;
    ScopeBox: TComboBox;
    LevelBox: TComboBox;
    CounterLabel: TLabel;
    PreviousButton: TButton;
    NextButton: TButton;
    ListButton: TButton;
    CancelButton: TButton;
    CloseButton: TButton;
    ReplaceEdit: TAtlasSearchCombo;
    ReplaceOneButton: TButton;
    ReplaceAllButton: TButton;
    ChooseButton: TButton;
    InfoLine: TAtlasSearchInfoLine;
  end;

  /// <summary>Stand der Leiste: vorbereitete Suche, Stufen, angebotene Bereiche, Einstellungen.</summary>
  TAtlasSearchBarState = record
    Query: TAtlasSearchQuery;
    Levels: TArray<string>;
    Scopes: TArray<TAtlasSearchScope>;
    HasSelection: Boolean;
    Features: TAtlasSearchBarFeatures;
    ReplaceShown: Boolean;
    // Prepare ohne Fenster: Apply folgt in CreateWnd.
    Pending: Boolean;
    // Felder werden per Programm gesetzt: keine Änderung melden.
    Updating: Boolean;
  end;

  TAtlasSearchBar = class(TCustomPanel)
  private
    FParts: TAtlasSearchBarParts;
    FEvents: TAtlasSearchBarEvents;
    FState: TAtlasSearchBarState;
    procedure FitWidths;
    procedure Changed(Sender: TObject);
    procedure ReplaceChanged(Sender: TObject);
    procedure ControlEnter(Sender: TObject);
    procedure ControlKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HistoryDropDown(Sender: TObject);
    procedure ButtonClick(Sender: TObject);
    procedure SetFeatures(const AValue: TAtlasSearchBarFeatures);
    procedure SetReplaceShown(AValue: Boolean);
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
    /// <summary>Schaltfläche „In Meldungen“ (search.resultsInMessages).</summary>
    procedure SetListVisible(AValue: Boolean);
    /// <summary>Verläufe für Such- und Ersetzen-Feld (gehören dem Aufrufer; nil = kein Verlauf).</summary>
    procedure SetHistories(ASearch, AReplace: TAtlasSearchHistory);
    /// <summary>Suchtext (und bei offener Ersetzen-Zeile den Ersatztext) in den Verlauf.</summary>
    procedure Remember;
    /// <summary>Fokus ins Suchfeld, Text markiert.</summary>
    procedure FocusText;
    /// <summary>Hat ein Feld der Leiste den Fokus?</summary>
    function HasFocus: Boolean;
    function ReplaceText: string;
    /// <summary>Name des Bereichs in der Auswahlliste („Unit“, „Projekt“ …).</summary>
    class function ScopeCaption(AScope: TAtlasSearchScope): string; static;
    property Features: TAtlasSearchBarFeatures read FState.Features write SetFeatures;
    /// <summary>Ersetzen-Zeile offen (nur mit Features.Replace).</summary>
    property ReplaceShown: Boolean read FState.ReplaceShown write SetReplaceShown;
    property Events: TAtlasSearchBarEvents read FEvents;
    property Parts: TAtlasSearchBarParts read FParts;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.UI.Search.Strings;

const
  cBarHeight = 30;
  cGap = 6;
  cToggleWidth = 24;
  cTextBoxWidth = 200;
  cScopeWidth = 120;
  cLevelWidth = 240;
  cButtonWidth = 28;
  cErrorColor = TColor($0000C0);

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

{ TAtlasSearchInfoLine }

procedure TAtlasSearchInfoLine.ShowError(const AText: string);
begin
  FKind := TKind.Error;
  FMessage := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchRegexError, [AText]);
end;

procedure TAtlasSearchInfoLine.ClearError;
begin
  if FKind = TKind.Error then
  begin
    FKind := TKind.None;
    FMessage := '';
  end;
end;

procedure TAtlasSearchInfoLine.ShowPreview(const ABefore, AAfter: string);
begin
  FBefore := ABefore;
  FAfter := AAfter;
  FHasPreview := True;
  if FKind = TKind.None then
  begin
    FKind := TKind.Notice;
  end;
end;

procedure TAtlasSearchInfoLine.ClearPreview;
begin
  FHasPreview := False;
  FBefore := '';
  FAfter := '';
  if (FKind = TKind.Notice) and (FMessage = '') then
  begin
    FKind := TKind.None;
  end;
end;

procedure TAtlasSearchInfoLine.ShowNotice(const AText: string);
begin
  if FKind = TKind.Error then
  begin
    Exit;
  end;
  FMessage := AText;
  if (AText <> '') or FHasPreview then
  begin
    FKind := TKind.Notice;
  end
  else
  begin
    FKind := TKind.None;
  end;
end;

function TAtlasSearchInfoLine.Content: string;
begin
  Result := '';
  case FKind of
    TKind.Error:
      Result := FMessage;
    TKind.Notice:
      begin
        if FHasPreview then
        begin
          Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchPreviewLabel) + ' ' + FBefore + ' → ' + FAfter;
        end;
        if (Result <> '') and (FMessage <> '') then
        begin
          Result := Result + '   ·   ';
        end;
        Result := Result + FMessage;
      end;
  else
    // Ohne Inhalt bleibt die Zeile leer.
  end;
end;

function TAtlasSearchInfoLine.IsError: Boolean;
begin
  Result := FKind = TKind.Error;
end;

function TAtlasSearchInfoLine.HasContent: Boolean;
begin
  Result := FKind <> TKind.None;
end;

procedure TAtlasSearchInfoLine.Paint;
var
  mX, mY: Integer;

  procedure Put(const AText: string; AStyle: TFontStyles);
  begin
    Canvas.Font.Style := AStyle;
    Canvas.TextOut(mX, mY, AText);
    Inc(mX, Canvas.TextWidth(AText));
  end;

begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  mY := (Height - Canvas.TextHeight('Ag')) div 2;
  mX := 0;
  if FKind = TKind.Error then
  begin
    Canvas.Font.Color := cErrorColor;
    Put(FMessage, []);
    Exit;
  end;
  if FHasPreview then
  begin
    Put(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchPreviewLabel) + ' ', []);
    Put(FBefore, [fsStrikeOut]);
    Put(' → ', []);
    Put(FAfter, [fsBold]);
    if FMessage <> '' then
    begin
      Put('   ·   ', []);
    end;
  end;
  Put(FMessage, []);
end;

{ TAtlasSearchBarEvents }

class procedure TAtlasSearchBarEvents.Fire(const AEvent: TProc);
begin
  if Assigned(AEvent) then
  begin
    AEvent();
  end;
end;

{ Aufbau der Leiste }

function AddRow(ABar: TAtlasSearchBar; ATop: Integer): TPanel;
begin
  Result := TPanel.Create(ABar);
  Result.Parent := ABar;
  Result.BevelOuter := bvNone;
  Result.Caption := '';
  Result.ShowCaption := False;
  Result.Top := ATop;
  Result.Height := ABar.ScaleValue(cBarHeight);
  Result.Align := alTop;
end;

procedure Place(ABar: TAtlasSearchBar; ARow: TPanel; AControl: TControl; AWidth: Integer);
begin
  // alLeft ordnet nach Left: jedes neue Element rechts an die vorigen (Tag zählt je Zeile).
  ARow.Tag := ARow.Tag + 10000;
  AControl.Left := ARow.Tag;
  AControl.Align := alLeft;
  AControl.AlignWithMargins := True;
  AControl.Margins.SetBounds(cGap, 3, 0, 3);
  if AWidth > 0 then
  begin
    AControl.Width := ABar.ScaleValue(AWidth);
  end;
end;

function AddLabel(ABar: TAtlasSearchBar; ARow: TPanel; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(ABar);
  Result.Parent := ARow;
  Result.ShowAccelChar := False;
  Result.Layout := tlCenter;
  Result.AutoSize := True;
  Result.Caption := ACaption;
  Place(ABar, ARow, Result, 0);
  Result.Margins.Top := 0;
  Result.Margins.Bottom := 0;
end;

function AddPanel(ABar: TAtlasSearchBar; ARow: TPanel; AWidth: Integer): TPanel;
begin
  Result := TPanel.Create(ABar);
  Result.Parent := ARow;
  Result.BevelOuter := bvNone;
  Result.Caption := '';
  Result.ShowCaption := False;
  Place(ABar, ARow, Result, AWidth);
end;

function AddCheck(ABar: TAtlasSearchBar; const ACaption: string; AHint: TAtlasSearchTextId): TCheckBox;
begin
  Result := TCheckBox.Create(ABar);
  Result.Parent := ABar.FParts.SearchRow;
  Result.Caption := ACaption;
  Result.Hint := TAtlasSearchStrings.Text(AHint);
  // Breite nach dem Text erst mit Fenster (FitWidths); bis dahin geschätzt.
  Place(ABar, ABar.FParts.SearchRow, Result, 24 + 7 * Length(ACaption));
  Result.OnClick := ABar.Changed;
  Result.OnKeyDown := ABar.ControlKeyDown;
  Result.OnEnter := ABar.ControlEnter;
end;

function AddButton(ABar: TAtlasSearchBar; ARow: TPanel; const ACaption: string; AHint: TAtlasSearchTextId;
  AWidth: Integer): TButton;
begin
  Result := TButton.Create(ABar);
  Result.Parent := ARow;
  Result.Caption := ACaption;
  Result.Hint := TAtlasSearchStrings.Text(AHint);
  Place(ABar, ARow, Result, AWidth);
  Result.OnClick := ABar.ButtonClick;
  Result.OnKeyDown := ABar.ControlKeyDown;
  Result.OnEnter := ABar.ControlEnter;
end;

function AddCombo(ABar: TAtlasSearchBar; AParent: TWinControl; AStyle: TComboBoxStyle): TAtlasSearchCombo;
begin
  // Mit Tasten wie im Suchfeld (#1243): Im Ersetzen-Feld fügte Strg+V sonst in den Editor ein.
  Result := TAtlasSearchCombo.Create(ABar);
  Result.Parent := AParent;
  Result.Style := AStyle;
  Result.OnKeyDown := ABar.ControlKeyDown;
  Result.OnEnter := ABar.ControlEnter;
end;

/// <summary>Schließen rechts, Knopf zum Aufklappen, Suchfeld im Rahmen (rot bei ungültigem Ausdruck).</summary>
procedure BuildTextPart(ABar: TAtlasSearchBar; AParts: TAtlasSearchBarParts);
var
  mLabel: TLabel;
begin
  AParts.CloseButton := TButton.Create(ABar);
  AParts.CloseButton.Parent := AParts.SearchRow;
  AParts.CloseButton.Align := alRight;
  AParts.CloseButton.AlignWithMargins := True;
  AParts.CloseButton.Margins.SetBounds(cGap, 3, cGap, 3);
  AParts.CloseButton.Width := ABar.ScaleValue(cButtonWidth);
  AParts.CloseButton.Caption := '×';
  AParts.CloseButton.Hint := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchCloseHint);
  AParts.CloseButton.OnClick := ABar.ButtonClick;
  AParts.CloseButton.OnKeyDown := ABar.ControlKeyDown;
  AParts.CloseButton.OnEnter := ABar.ControlEnter;
  AParts.ToggleButton := AddButton(ABar, AParts.SearchRow, '▸', TAtlasSearchTextId.SearchToggleReplaceHint,
    cToggleWidth);
  mLabel := AddLabel(ABar, AParts.SearchRow, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchTextLabel));
  AParts.TextFrame := AddPanel(ABar, AParts.SearchRow, cTextBoxWidth + 2);
  AParts.TextFrame.Padding.SetBounds(1, 1, 1, 1);
  AParts.TextFrame.Margins.SetBounds(cGap, 2, 0, 2);
  AParts.TextEdit := AddCombo(ABar, AParts.TextFrame, csDropDown);
  AParts.TextEdit.Align := alClient;
  AParts.TextEdit.OnChange := ABar.Changed;
  AParts.TextEdit.OnDropDown := ABar.HistoryDropDown;
  mLabel.FocusControl := AParts.TextEdit;
end;

/// <summary>Optionen, Bereich, Stufe, Zähler und Knöpfe der Suchzeile.</summary>
procedure BuildSearchRow(ABar: TAtlasSearchBar; AParts: TAtlasSearchBarParts);
var
  mLabel: TLabel;
begin
  BuildTextPart(ABar, AParts);
  AParts.CaseBox := AddCheck(ABar, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchCaseSensitive),
    TAtlasSearchTextId.SearchCaseHint);
  AParts.WholeBox := AddCheck(ABar, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchWholeWord),
    TAtlasSearchTextId.SearchWholeHint);
  AParts.IdentifierBox := AddCheck(ABar, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchIdentifier),
    TAtlasSearchTextId.SearchIdentifierHint);
  AParts.RegexBox := AddCheck(ABar, '.*', TAtlasSearchTextId.SearchRegexHint);
  mLabel := AddLabel(ABar, AParts.SearchRow, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchScopeLabel));
  AParts.ScopeBox := AddCombo(ABar, AParts.SearchRow, csDropDownList);
  Place(ABar, AParts.SearchRow, AParts.ScopeBox, cScopeWidth);
  AParts.ScopeBox.OnChange := ABar.Changed;
  mLabel.FocusControl := AParts.ScopeBox;
  AParts.LevelBox := AddCombo(ABar, AParts.SearchRow, csDropDownList);
  Place(ABar, AParts.SearchRow, AParts.LevelBox, cLevelWidth);
  AParts.LevelBox.OnChange := ABar.Changed;
  AParts.CounterLabel := AddLabel(ABar, AParts.SearchRow, '');
  AParts.PreviousButton := AddButton(ABar, AParts.SearchRow, '↑', TAtlasSearchTextId.SearchPreviousHint, cButtonWidth);
  AParts.NextButton := AddButton(ABar, AParts.SearchRow, '↓', TAtlasSearchTextId.SearchNextHint, cButtonWidth);
  AParts.ListButton := AddButton(ABar, AParts.SearchRow, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchListButton),
    TAtlasSearchTextId.SearchListHint, 100);
  AParts.CancelButton := AddButton(ABar, AParts.SearchRow,
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchCancelButton), TAtlasSearchTextId.SearchCancelHint, 90);
  AParts.CancelButton.Visible := False;
end;

/// <summary>Ersetzen-Zeile: das Feld steht unter dem Suchfeld (Platz für den Knopf zum Aufklappen).</summary>
procedure BuildReplaceRow(ABar: TAtlasSearchBar; AParts: TAtlasSearchBarParts);
var
  mLabel: TLabel;
begin
  AddPanel(ABar, AParts.ReplaceRow, cToggleWidth);
  mLabel := AddLabel(ABar, AParts.ReplaceRow, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceLabel));
  AParts.ReplaceEdit := AddCombo(ABar, AParts.ReplaceRow, csDropDown);
  Place(ABar, AParts.ReplaceRow, AParts.ReplaceEdit, cTextBoxWidth);
  AParts.ReplaceEdit.OnChange := ABar.ReplaceChanged;
  AParts.ReplaceEdit.OnDropDown := ABar.HistoryDropDown;
  mLabel.FocusControl := AParts.ReplaceEdit;
  AParts.ReplaceOneButton := AddButton(ABar, AParts.ReplaceRow,
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceButton), TAtlasSearchTextId.SearchReplaceHint, 90);
  AParts.ReplaceAllButton := AddButton(ABar, AParts.ReplaceRow,
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceAllButton), TAtlasSearchTextId.SearchReplaceAllHint, 110);
  AParts.ChooseButton := AddButton(ABar, AParts.ReplaceRow,
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchChooseButton), TAtlasSearchTextId.SearchChooseHint, 90);
  AParts.InfoLine := TAtlasSearchInfoLine.Create(ABar);
  AParts.InfoLine.Parent := AParts.InfoRow;
  AParts.InfoLine.Align := alClient;
  AParts.InfoLine.AlignWithMargins := True;
  AParts.InfoLine.Margins.SetBounds(cGap + ABar.ScaleValue(cToggleWidth), 2, cGap, 2);
end;

{ Zustand der Leiste }

// ItemIndex und Items.Count einer TComboBox fragen ihr Fenster ab (CB_GETCURSEL, CB_GETCOUNT) und legen es dafür
// an. Ohne übergeordnetes Fenster scheitert das mit EInvalidOperation: Unter Delphi 12 legt die Suche ihre Leiste
// vor dem Einhängen an (CreateBar setzt Features, dann ordnet Place sie ein); jedes Strg+F scheiterte so, und nach
// dem dritten Versuch schaltete die Sicherung die Atlas-Suche ab. Ohne Fenster gilt darum der
// Stand der vorbereiteten Suche; Apply schreibt ihn in die Listen, sobald es eins gibt.

/// <summary>Gewählter Bereich: aus der Liste, solange sie kein Fenster hat aus der vorbereiteten Suche.</summary>
function SelectedScope(ABar: TAtlasSearchBar): TAtlasSearchScope;
var
  mIndex: Integer;
begin
  Result := ABar.FState.Query.Scope;
  if not ABar.FParts.ScopeBox.HandleAllocated then
  begin
    Exit;
  end;
  mIndex := ABar.FParts.ScopeBox.ItemIndex;
  if (mIndex >= 0) and (mIndex <= High(ABar.FState.Scopes)) then
  begin
    Result := ABar.FState.Scopes[mIndex];
  end;
end;

/// <summary>Gewählte Stufe: aus der Liste, ohne Fenster aus der vorbereiteten Suche.</summary>
function SelectedLevel(ABar: TAtlasSearchBar): Integer;
begin
  Result := ABar.FState.Query.Level;
  if ABar.FParts.LevelBox.HandleAllocated then
  begin
    Result := ABar.FParts.LevelBox.ItemIndex;
  end;
end;

procedure UpdateStates(ABar: TAtlasSearchBar);
var
  mParts: TAtlasSearchBarParts;
begin
  mParts := ABar.FParts;
  // State.Levels sind die Einträge der Stufenliste (Apply füllt sie daraus); Items.Count bräuchte ein Fenster.
  mParts.LevelBox.Visible := (SelectedScope(ABar) = TAtlasSearchScope.Method) and (Length(ABar.FState.Levels) > 0);
  // Bezeichner-Modus ohne Regex kennt nur ganze Bezeichner ohne Rücksicht auf die Schreibweise; mit Regex filtert
  // er nur Kommentare und Strings heraus.
  mParts.CaseBox.Enabled := not mParts.IdentifierBox.Checked or mParts.RegexBox.Checked;
  mParts.WholeBox.Enabled := not mParts.IdentifierBox.Checked or mParts.RegexBox.Checked;
  mParts.RegexBox.Visible := ABar.FState.Features.Regex;
end;

procedure UpdateLayout(ABar: TAtlasSearchBar);
var
  mParts: TAtlasSearchBarParts;
  mRows: Integer;
begin
  mParts := ABar.FParts;
  mParts.ToggleButton.Visible := ABar.FState.Features.Replace;
  if not ABar.FState.Features.Replace then
  begin
    ABar.FState.ReplaceShown := False;
  end;
  if ABar.FState.ReplaceShown then
  begin
    mParts.ToggleButton.Caption := '▾';
  end
  else
  begin
    mParts.ToggleButton.Caption := '▸';
  end;
  mParts.ReplaceRow.Visible := ABar.FState.ReplaceShown;
  mParts.InfoRow.Visible := mParts.InfoLine.HasContent;
  // Reihenfolge der Zeilen festhalten: sichtbar gewordene alTop-Panels ordnen sich nach Top.
  mParts.SearchRow.Top := 0;
  mParts.ReplaceRow.Top := mParts.SearchRow.Height;
  mParts.InfoRow.Top := 2 * mParts.SearchRow.Height;
  mRows := 1;
  if mParts.ReplaceRow.Visible then
  begin
    Inc(mRows);
  end;
  if mParts.InfoRow.Visible then
  begin
    Inc(mRows);
  end;
  ABar.Height := mRows * ABar.ScaleValue(cBarHeight);
  mParts.InfoLine.Invalidate;
end;

/// <summary>Bereiche in der Reihenfolge von TAtlasSearchScope: Unit, Methode, Auswahl, offene Dateien, Projekt,
/// Projektgruppe. Ein Bereich, den es gerade nicht gibt (Auswahl ohne Auswahl, Dateien mit search.multiFile aus),
/// wird Unit.</summary>
procedure FillScopes(ABar: TAtlasSearchBar);
var
  mScope: TAtlasSearchScope;
  mIndex: Integer;
  mBox: TComboBox;
begin
  mBox := ABar.FParts.ScopeBox;
  ABar.FState.Scopes := [TAtlasSearchScope.UnitFile, TAtlasSearchScope.Method];
  if ABar.FState.HasSelection then
  begin
    ABar.FState.Scopes := ABar.FState.Scopes + [TAtlasSearchScope.Selection];
  end;
  if ABar.FState.Features.MultiFile then
  begin
    ABar.FState.Scopes := ABar.FState.Scopes + [TAtlasSearchScope.OpenFiles, TAtlasSearchScope.Project,
      TAtlasSearchScope.ProjectGroup];
  end;
  mBox.Items.BeginUpdate;
  try
    mBox.Items.Clear;
    for mScope in ABar.FState.Scopes do
    begin
      mBox.Items.Add(TAtlasSearchBar.ScopeCaption(mScope));
    end;
  finally
    mBox.Items.EndUpdate;
  end;
  mBox.ItemIndex := 0;
  for mIndex := 0 to High(ABar.FState.Scopes) do
  begin
    if ABar.FState.Scopes[mIndex] = ABar.FState.Query.Scope then
    begin
      mBox.ItemIndex := mIndex;
    end;
  end;
  ABar.FState.Query.Scope := ABar.FState.Scopes[mBox.ItemIndex];
end;

procedure FillLevels(ABar: TAtlasSearchBar);
var
  mLevel: string;
  mBox: TComboBox;
begin
  mBox := ABar.FParts.LevelBox;
  mBox.Items.BeginUpdate;
  try
    mBox.Items.Clear;
    for mLevel in ABar.FState.Levels do
    begin
      mBox.Items.Add(mLevel);
    end;
  finally
    mBox.Items.EndUpdate;
  end;
  mBox.ItemIndex := -1;
  if Length(ABar.FState.Levels) > 0 then
  begin
    mBox.ItemIndex := ABar.FState.Query.Level;
    if mBox.ItemIndex < 0 then
    begin
      mBox.ItemIndex := 0;
    end;
  end;
end;

/// <summary>Vorbereitete Suche in die Felder (braucht ein Fenster).</summary>
procedure Apply(ABar: TAtlasSearchBar);
var
  mParts: TAtlasSearchBarParts;
  mQuery: TAtlasSearchQuery;
begin
  mParts := ABar.FParts;
  mQuery := ABar.FState.Query;
  ABar.FState.Pending := False;
  ABar.FState.Updating := True;
  try
    mParts.TextEdit.Text := mQuery.Text;
    mParts.CaseBox.Checked := mQuery.Options.CaseSensitive;
    mParts.WholeBox.Checked := mQuery.Options.WholeWord;
    mParts.IdentifierBox.Checked := mQuery.Options.Identifier;
    mParts.RegexBox.Checked := mQuery.Options.Regex and ABar.FState.Features.Regex;
    FillScopes(ABar);
    FillLevels(ABar);
    UpdateStates(ABar);
  finally
    ABar.FState.Updating := False;
  end;
end;

/// <summary>Text eines Felds per Programm setzen, ohne das Blättern im Verlauf zurückzusetzen.</summary>
procedure SetBoxText(ABar: TAtlasSearchBar; ABox: TComboBox; const AText: string);
begin
  ABar.FState.Updating := True;
  try
    ABox.Text := AText;
    ABox.SelectAll;
  finally
    ABar.FState.Updating := False;
  end;
end;

/// <summary>Pfeil hoch/runter im Such- bzw. Ersetzen-Feld: im Verlauf blättern.</summary>
procedure StepHistory(ABar: TAtlasSearchBar; ABox: TAtlasSearchCombo; AOlder: Boolean);
var
  mNext: string;
begin
  if ABox.History = nil then
  begin
    Exit;
  end;
  mNext := ABox.History.Step(ABox.Text, AOlder);
  if mNext = ABox.Text then
  begin
    Exit;
  end;
  // Ohne Updating setzte Changed das Blättern zurück.
  SetBoxText(ABar, ABox, mNext);
  // Text per Programm löst OnChange nicht aus: Suche bzw. Vorschau selbst anstoßen.
  if ABox = ABar.FParts.TextEdit then
  begin
    UpdateStates(ABar);
    TAtlasSearchBarEvents.Fire(ABar.FEvents.OnQueryChanged);
  end
  else
  begin
    TAtlasSearchBarEvents.Fire(ABar.FEvents.OnReplaceShown);
  end;
end;

procedure Step(ABar: TAtlasSearchBar; ABackward: Boolean);
begin
  ABar.Remember;
  if Assigned(ABar.FEvents.OnStep) then
  begin
    ABar.FEvents.OnStep(ABackward);
  end;
end;

/// <summary>Enter: im Ersetzen-Feld ersetzen (Strg: alle), sonst nächster bzw. voriger Treffer und Liste.</summary>
procedure PressReturn(ABar: TAtlasSearchBar; ASender: TObject; AShift: TShiftState);
begin
  if ASender = ABar.FParts.ReplaceEdit then
  begin
    ABar.Remember;
    if ssCtrl in AShift then
    begin
      TAtlasSearchBarEvents.Fire(ABar.FEvents.OnReplaceAll);
    end
    else
    begin
      TAtlasSearchBarEvents.Fire(ABar.FEvents.OnReplace);
    end;
    Exit;
  end;
  Step(ABar, ssShift in AShift);
  if not (ssShift in AShift) and ABar.FParts.ListButton.Visible then
  begin
    TAtlasSearchBarEvents.Fire(ABar.FEvents.OnList);
  end;
end;

procedure FocusBox(ABox: TComboBox);
begin
  if ABox.CanFocus then
  begin
    ABox.SetFocus;
    ABox.SelectAll;
  end;
end;

procedure ToggleReplace(ABar: TAtlasSearchBar);
begin
  ABar.ReplaceShown := not ABar.ReplaceShown;
  if ABar.ReplaceShown then
  begin
    FocusBox(ABar.FParts.ReplaceEdit);
  end
  else
  begin
    FocusBox(ABar.FParts.TextEdit);
  end;
  TAtlasSearchBarEvents.Fire(ABar.FEvents.OnReplaceShown);
end;

/// <summary>Knöpfe, die vorher den Verlauf merken: In Meldungen, Ersetzen, Alle ersetzen, Auswählen.</summary>
function IsRemembering(ABar: TAtlasSearchBar; ASender: TObject; out AEvent: TProc): Boolean;
var
  mParts: TAtlasSearchBarParts;
begin
  mParts := ABar.FParts;
  AEvent := nil;
  Result := True;
  if ASender = mParts.ListButton then
  begin
    AEvent := ABar.FEvents.OnList;
  end
  else if ASender = mParts.ReplaceOneButton then
  begin
    AEvent := ABar.FEvents.OnReplace;
  end
  else if ASender = mParts.ReplaceAllButton then
  begin
    AEvent := ABar.FEvents.OnReplaceAll;
  end
  else if ASender = mParts.ChooseButton then
  begin
    AEvent := ABar.FEvents.OnChoose;
  end
  else
  begin
    Result := False;
  end;
end;

{ TAtlasSearchBar }

constructor TAtlasSearchBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';
  ShowCaption := False;
  ShowHint := True;
  FEvents := TAtlasSearchBarEvents.Create(Self);
  FParts := TAtlasSearchBarParts.Create(Self);
  FState := Default(TAtlasSearchBarState);
  FState.Query.Scope := TAtlasSearchScope.UnitFile;
  FParts.SearchRow := AddRow(Self, 0);
  FParts.ReplaceRow := AddRow(Self, 1000);
  FParts.InfoRow := AddRow(Self, 2000);
  BuildSearchRow(Self, FParts);
  BuildReplaceRow(Self, FParts);
  UpdateLayout(Self);
end;

procedure TAtlasSearchBar.CreateWnd;
begin
  inherited CreateWnd;
  FitWidths;
  if FState.Pending then
  begin
    Apply(Self);
  end;
end;

procedure TAtlasSearchBar.FitWidths;
var
  mBoxes: TArray<TCheckBox>;
  mBox: TCheckBox;
  mButtons: TArray<TButton>;
  mButton: TButton;
begin
  Canvas.Font := Font;
  mBoxes := [FParts.CaseBox, FParts.WholeBox, FParts.IdentifierBox, FParts.RegexBox];
  for mBox in mBoxes do
  begin
    mBox.Width := Canvas.TextWidth(mBox.Caption) + ScaleValue(24);
  end;
  mButtons := [FParts.ListButton, FParts.CancelButton, FParts.ReplaceOneButton, FParts.ReplaceAllButton,
    FParts.ChooseButton];
  for mButton in mButtons do
  begin
    mButton.Width := Canvas.TextWidth(mButton.Caption) + ScaleValue(20);
  end;
end;

procedure TAtlasSearchBar.Prepare(const AQuery: TAtlasSearchQuery; const ALevels: TArray<string>;
  AHasSelection: Boolean);
begin
  FState.Query := AQuery;
  FState.Levels := ALevels;
  FState.HasSelection := AHasSelection;
  FState.Pending := True;
  if HandleAllocated then
  begin
    Apply(Self);
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

procedure TAtlasSearchBar.SetFeatures(const AValue: TAtlasSearchBarFeatures);
begin
  FState.Features := AValue;
  if not FState.Features.Regex then
  begin
    FParts.RegexBox.Checked := False;
    ClearPreview;
  end;
  UpdateStates(Self);
  UpdateLayout(Self);
  if HandleAllocated and not FState.Pending then
  begin
    // Bereiche neu aufbauen (Dateien ein/aus), Auswahl beibehalten.
    FState.Query := Query;
    Apply(Self);
  end;
end;

procedure TAtlasSearchBar.SetReplaceShown(AValue: Boolean);
var
  mShown: Boolean;
begin
  mShown := AValue and FState.Features.Replace;
  if mShown = FState.ReplaceShown then
  begin
    Exit;
  end;
  FState.ReplaceShown := mShown;
  if not FState.ReplaceShown then
  begin
    ClearPreview;
  end;
  UpdateLayout(Self);
end;

function TAtlasSearchBar.ReplaceText: string;
begin
  Result := FParts.ReplaceEdit.Text;
end;

function TAtlasSearchBar.Query: TAtlasSearchQuery;
begin
  Result := FState.Query;
  Result.Text := FParts.TextEdit.Text;
  Result.Options := TAtlasSearchOptions.Create(FParts.CaseBox.Checked, FParts.WholeBox.Checked,
    FParts.IdentifierBox.Checked, FParts.RegexBox.Checked and FState.Features.Regex);
  Result.Scope := SelectedScope(Self);
  Result.Level := SelectedLevel(Self);
  if Result.Level < 0 then
  begin
    Result.Level := 0;
  end;
end;

procedure TAtlasSearchBar.SetCounter(const AText: string);
begin
  FParts.CounterLabel.Caption := AText;
end;

procedure TAtlasSearchBar.SetError(const AText: string);
begin
  if AText <> '' then
  begin
    FParts.InfoLine.ShowError(AText);
    FParts.TextFrame.ParentBackground := False;
    FParts.TextFrame.StyleElements := FParts.TextFrame.StyleElements - [seClient];
    FParts.TextFrame.Color := cErrorColor;
  end
  else
  begin
    FParts.InfoLine.ClearError;
    FParts.TextFrame.StyleElements := FParts.TextFrame.StyleElements + [seClient];
    FParts.TextFrame.ParentColor := True;
    FParts.TextFrame.ParentBackground := True;
  end;
  UpdateLayout(Self);
end;

function TAtlasSearchBar.HasError: Boolean;
begin
  Result := FParts.InfoLine.IsError;
end;

procedure TAtlasSearchBar.SetPreview(const ABefore, AAfter: string);
begin
  FParts.InfoLine.ShowPreview(ABefore, AAfter);
  UpdateLayout(Self);
end;

procedure TAtlasSearchBar.ClearPreview;
begin
  FParts.InfoLine.ClearPreview;
  UpdateLayout(Self);
end;

procedure TAtlasSearchBar.SetNotice(const AText: string);
begin
  if FParts.InfoLine.IsError then
  begin
    Exit;
  end;
  FParts.InfoLine.ShowNotice(AText);
  UpdateLayout(Self);
end;

function TAtlasSearchBar.InfoText: string;
begin
  Result := FParts.InfoLine.Content;
end;

procedure TAtlasSearchBar.SetSearching(AValue: Boolean);
begin
  FParts.CancelButton.Visible := AValue;
end;

procedure TAtlasSearchBar.SetListVisible(AValue: Boolean);
begin
  FParts.ListButton.Visible := AValue;
end;

procedure TAtlasSearchBar.SetHistories(ASearch, AReplace: TAtlasSearchHistory);
begin
  FParts.TextEdit.History := ASearch;
  FParts.ReplaceEdit.History := AReplace;
end;

procedure TAtlasSearchBar.Remember;
begin
  if FParts.TextEdit.History <> nil then
  begin
    FParts.TextEdit.History.Remember(FParts.TextEdit.Text);
  end;
  if FState.ReplaceShown and (FParts.ReplaceEdit.History <> nil) then
  begin
    FParts.ReplaceEdit.History.Remember(FParts.ReplaceEdit.Text);
  end;
end;

procedure TAtlasSearchBar.HistoryDropDown(Sender: TObject);
var
  mBox: TAtlasSearchCombo;
  mItem, mText: string;
begin
  if not (Sender is TAtlasSearchCombo) then
  begin
    Exit;
  end;
  mBox := TAtlasSearchCombo(Sender);
  // Liste erst beim Aufklappen füllen (sie braucht ein Fenster); der Text im Feld bleibt.
  mText := mBox.Text;
  FState.Updating := True;
  try
    mBox.Items.BeginUpdate;
    try
      mBox.Items.Clear;
      if mBox.History <> nil then
      begin
        for mItem in mBox.History.Items do
        begin
          mBox.Items.Add(mItem);
        end;
      end;
    finally
      mBox.Items.EndUpdate;
    end;
    mBox.Text := mText;
  finally
    FState.Updating := False;
  end;
end;

procedure TAtlasSearchBar.FocusText;
begin
  FocusBox(FParts.TextEdit);
end;

function TAtlasSearchBar.HasFocus: Boolean;
var
  mFocused: HWND;
begin
  mFocused := Winapi.Windows.GetFocus;
  Result := HandleAllocated and (mFocused <> 0) and ((mFocused = Handle) or IsChild(Handle, mFocused));
end;

procedure TAtlasSearchBar.Changed(Sender: TObject);
begin
  if FState.Updating then
  begin
    Exit;
  end;
  // Von Hand geändert: Blättern im Verlauf beginnt beim nächsten Pfeil von vorn.
  if (Sender = FParts.TextEdit) and (FParts.TextEdit.History <> nil) then
  begin
    FParts.TextEdit.History.Reset;
  end;
  UpdateStates(Self);
  TAtlasSearchBarEvents.Fire(FEvents.OnQueryChanged);
end;

procedure TAtlasSearchBar.ReplaceChanged(Sender: TObject);
begin
  if FState.Updating then
  begin
    Exit;
  end;
  if FParts.ReplaceEdit.History <> nil then
  begin
    FParts.ReplaceEdit.History.Reset;
  end;
  TAtlasSearchBarEvents.Fire(FEvents.OnReplaceShown);
end;

procedure TAtlasSearchBar.ControlEnter(Sender: TObject);
begin
  if Assigned(FEvents.OnControlEnter) and (Sender is TWinControl) then
  begin
    FEvents.OnControlEnter(TWinControl(Sender));
  end;
end;

procedure TAtlasSearchBar.ControlKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  mKey: Word;
begin
  // Offene Auswahlliste: Enter, Esc und die Pfeile gehören ihr.
  if (Sender is TComboBox) and TComboBox(Sender).DroppedDown then
  begin
    Exit;
  end;
  mKey := Key;
  // Pfeil hoch/runter im Such- bzw. Ersetzen-Feld: Verlauf (Alt+↓ öffnet die Liste wie gewohnt).
  if ((mKey = VK_UP) or (mKey = VK_DOWN)) and not (ssAlt in Shift) and
    ((Sender = FParts.TextEdit) or (Sender = FParts.ReplaceEdit)) then
  begin
    Key := 0;
    StepHistory(Self, TAtlasSearchCombo(Sender), mKey = VK_UP);
    Exit;
  end;
  case mKey of
    VK_RETURN:
      begin
        Key := 0;
        PressReturn(Self, Sender, Shift);
      end;
    VK_F3:
      begin
        Key := 0;
        Step(Self, ssShift in Shift);
      end;
    VK_ESCAPE:
      begin
        Key := 0;
        TAtlasSearchBarEvents.Fire(FEvents.OnClose);
      end;
  else
    // Übrige Tasten gehören dem Feld.
  end;
end;

procedure TAtlasSearchBar.ButtonClick(Sender: TObject);
var
  mEvent: TProc;
begin
  if IsRemembering(Self, Sender, mEvent) then
  begin
    Remember;
    TAtlasSearchBarEvents.Fire(mEvent);
  end
  else if Sender = FParts.ToggleButton then
  begin
    ToggleReplace(Self);
  end
  else if (Sender = FParts.PreviousButton) or (Sender = FParts.NextButton) then
  begin
    Step(Self, Sender = FParts.PreviousButton);
  end
  else if Sender = FParts.CancelButton then
  begin
    TAtlasSearchBarEvents.Fire(FEvents.OnCancel);
  end
  else if Sender = FParts.CloseButton then
  begin
    TAtlasSearchBarEvents.Fire(FEvents.OnClose);
  end;
end;

end.
