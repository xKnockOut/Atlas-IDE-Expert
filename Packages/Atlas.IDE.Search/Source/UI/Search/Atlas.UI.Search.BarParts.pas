unit Atlas.UI.Search.BarParts;

// Steuerelemente der Suchleiste (#877, #878, #893) und ihr Aufbau, reine VCL:
// Such- bzw. Ersetzen-Feld mit Verlauf (TAtlasSearchCombo, #1243),
// Hinweiszeile (TAtlasSearchInfoLine), Ereignisse für den Aufrufer
// (TAtlasSearchBarEvents), die Steuerelemente selbst (TAtlasSearchBarParts)
// und der Aufbau der Zeilen (TAtlasSearchBarBuilder). Was die Felder zeigen,
// hält TAtlasSearchBarFields, die Leiste selbst ist TAtlasSearchBar.

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
  Atlas.Core.Search.History,
  Atlas.UI.Search.Strings;

type
  TAtlasSearchBarParts = class;

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
  public const
    /// <summary>Farbe eines Fehlers (Text der Zeile, Rahmen des Suchfelds).</summary>
    cErrorColor = TColor($0000C0);
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
    /// <summary>Knöpfe, die vorher den Verlauf merken (In Meldungen, Ersetzen, Alle ersetzen, Auswählen): True mit
    /// dem Ereignis des Knopfs ASender aus AParts.</summary>
    function RememberingButton(AParts: TAtlasSearchBarParts; ASender: TObject; out AEvent: TProc): Boolean;
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

  /// <summary>Ereignisse der Steuerelemente, die der Aufbau verdrahtet.</summary>
  TAtlasSearchBarHandlers = record
    /// <summary>Text, Option, Bereich oder Stufe geändert.</summary>
    OnChanged: TNotifyEvent;
    OnReplaceChanged: TNotifyEvent;
    OnDropDown: TNotifyEvent;
    OnEnter: TNotifyEvent;
    OnKeyDown: TKeyEvent;
    OnButton: TNotifyEvent;
  end;

  /// <summary>Baut die Zeilen der Leiste (Such-, Ersetzen- und Hinweiszeile) in AParts auf.</summary>
  TAtlasSearchBarBuilder = class
  public const
    /// <summary>Höhe einer Zeile vor dem Skalieren.</summary>
    cRowHeight = 30;
  private
    FBar: TWinControl;
    FParts: TAtlasSearchBarParts;
    FHandlers: TAtlasSearchBarHandlers;
    FScale: TFunc<Integer, Integer>;
    function AddRow(ATop: Integer): TPanel;
    procedure Place(ARow: TPanel; AControl: TControl; AWidth: Integer);
    function AddLabel(ARow: TPanel; const ACaption: string): TLabel;
    function AddPanel(ARow: TPanel; AWidth: Integer): TPanel;
    function AddCheck(const ACaption: string; AHint: TAtlasSearchTextId): TCheckBox;
    function AddButton(ARow: TPanel; const ACaption: string; AHint: TAtlasSearchTextId; AWidth: Integer): TButton;
    function AddCombo(AParent: TWinControl; AStyle: TComboBoxStyle): TAtlasSearchCombo;
    procedure BuildTextPart;
    procedure BuildSearchRow;
    procedure BuildReplaceRow;
  public
    /// <summary>Steuerelemente in ABar (Besitzer und Eltern); AScale skaliert Bildpunkte nach der DPI der Leiste.
    /// </summary>
    class procedure Build(ABar: TWinControl; AParts: TAtlasSearchBarParts; const AHandlers: TAtlasSearchBarHandlers;
      const AScale: TFunc<Integer, Integer>); static;
  end;

implementation

uses
  Vcl.Forms;

const
  cGap = 6;
  cToggleWidth = 24;
  cTextBoxWidth = 200;
  cScopeWidth = 120;
  cLevelWidth = 240;
  cButtonWidth = 28;
  // Knöpfe mit Text (Abbrechen, Ersetzen, Auswählen) und „Alle ersetzen“.
  cTextButtonWidth = 90;
  cReplaceAllWidth = 110;
  // Rand über und unter jedem Element einer Zeile.
  cMarginY = 3;
  // Geschätzte Breite eines Kästchens vor dem Messen: Kästchen plus Zeichen mal Zeichenbreite.
  cCheckMarkWidth = 24;
  cCharWidth = 7;
  // Abstand der Left-Werte, nach denen alLeft die Elemente einer Zeile ordnet.
  cPlaceStep = 10000;
  // Top-Werte, nach denen alTop die Zeilen ordnet: Suche, Ersetzen, Hinweis.
  cReplaceRowTop = 1000;
  cInfoRowTop = 2000;

{ TAtlasSearchBarFeatures }

class function TAtlasSearchBarFeatures.Create(AReplace, ARegex, AMultiFile: Boolean): TAtlasSearchBarFeatures;
begin
  Result.Replace := AReplace;
  Result.Regex := ARegex;
  Result.MultiFile := AMultiFile;
end;

{ TAtlasSearchCombo }

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

{ TAtlasSearchInfoLine }

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

{ TAtlasSearchBarEvents }

class procedure TAtlasSearchBarEvents.Fire(const AEvent: TProc);
begin
  if Assigned(AEvent) then
  begin
    AEvent();
  end;
end;

function TAtlasSearchBarEvents.RememberingButton(AParts: TAtlasSearchBarParts; ASender: TObject;
  out AEvent: TProc): Boolean;
begin
  AEvent := nil;
  Result := True;
  if ASender = AParts.ListButton then
  begin
    AEvent := OnList;
  end
  else if ASender = AParts.ReplaceOneButton then
  begin
    AEvent := OnReplace;
  end
  else if ASender = AParts.ReplaceAllButton then
  begin
    AEvent := OnReplaceAll;
  end
  else if ASender = AParts.ChooseButton then
  begin
    AEvent := OnChoose;
  end
  else
  begin
    Result := False;
  end;
end;

{ TAtlasSearchBarBuilder }

function TAtlasSearchBarBuilder.AddRow(ATop: Integer): TPanel;
begin
  Result := TPanel.Create(FBar);
  Result.Parent := FBar;
  Result.BevelOuter := bvNone;
  Result.Caption := '';
  Result.ShowCaption := False;
  Result.Top := ATop;
  Result.Height := FScale(cRowHeight);
  Result.Align := alTop;
end;

procedure TAtlasSearchBarBuilder.Place(ARow: TPanel; AControl: TControl; AWidth: Integer);
begin
  // alLeft ordnet nach Left: jedes neue Element rechts an die vorigen (Tag zählt je Zeile).
  ARow.Tag := ARow.Tag + cPlaceStep;
  AControl.Left := ARow.Tag;
  AControl.Align := alLeft;
  AControl.AlignWithMargins := True;
  AControl.Margins.SetBounds(cGap, cMarginY, 0, cMarginY);
  if AWidth > 0 then
  begin
    AControl.Width := FScale(AWidth);
  end;
end;

function TAtlasSearchBarBuilder.AddLabel(ARow: TPanel; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(FBar);
  Result.Parent := ARow;
  Result.ShowAccelChar := False;
  Result.Layout := tlCenter;
  Result.AutoSize := True;
  Result.Caption := ACaption;
  Place(ARow, Result, 0);
  Result.Margins.Top := 0;
  Result.Margins.Bottom := 0;
end;

function TAtlasSearchBarBuilder.AddPanel(ARow: TPanel; AWidth: Integer): TPanel;
begin
  Result := TPanel.Create(FBar);
  Result.Parent := ARow;
  Result.BevelOuter := bvNone;
  Result.Caption := '';
  Result.ShowCaption := False;
  Place(ARow, Result, AWidth);
end;

function TAtlasSearchBarBuilder.AddCheck(const ACaption: string; AHint: TAtlasSearchTextId): TCheckBox;
begin
  Result := TCheckBox.Create(FBar);
  Result.Parent := FParts.SearchRow;
  Result.Caption := ACaption;
  Result.Hint := TAtlasSearchStrings.Text(AHint);
  // Breite nach dem Text erst mit Fenster (FitWidths); bis dahin geschätzt.
  Place(FParts.SearchRow, Result, cCheckMarkWidth + cCharWidth * Length(ACaption));
  Result.OnClick := FHandlers.OnChanged;
  Result.OnKeyDown := FHandlers.OnKeyDown;
  Result.OnEnter := FHandlers.OnEnter;
end;

function TAtlasSearchBarBuilder.AddButton(ARow: TPanel; const ACaption: string; AHint: TAtlasSearchTextId;
  AWidth: Integer): TButton;
begin
  Result := TButton.Create(FBar);
  Result.Parent := ARow;
  Result.Caption := ACaption;
  Result.Hint := TAtlasSearchStrings.Text(AHint);
  Place(ARow, Result, AWidth);
  Result.OnClick := FHandlers.OnButton;
  Result.OnKeyDown := FHandlers.OnKeyDown;
  Result.OnEnter := FHandlers.OnEnter;
end;

function TAtlasSearchBarBuilder.AddCombo(AParent: TWinControl; AStyle: TComboBoxStyle): TAtlasSearchCombo;
begin
  // Mit Tasten wie im Suchfeld (#1243): Im Ersetzen-Feld fügte Strg+V sonst in den Editor ein.
  Result := TAtlasSearchCombo.Create(FBar);
  Result.Parent := AParent;
  Result.Style := AStyle;
  // Ohne Vervollständigung aus dem Verlauf: Sie setzt den Text per Programm (der ergänzte Rest markiert) und
  // verschluckt die Taste, ohne OnChange auszulösen. Im Feld stand dann etwa „acmemmo“ aus dem Verlauf, gesucht
  // und gesprungen wurde aber noch mit dem Text vor der Taste („acme“ trifft „acMem“). Den Verlauf gibt es weiter
  // über Pfeil hoch/runter und die Liste.
  Result.AutoComplete := False;
  Result.OnKeyDown := FHandlers.OnKeyDown;
  Result.OnEnter := FHandlers.OnEnter;
end;

/// <summary>Schließen rechts, Knopf zum Aufklappen, Suchfeld im Rahmen (rot bei ungültigem Ausdruck).</summary>
procedure TAtlasSearchBarBuilder.BuildTextPart;
var
  mLabel: TLabel;
begin
  FParts.CloseButton := TButton.Create(FBar);
  FParts.CloseButton.Parent := FParts.SearchRow;
  FParts.CloseButton.Align := alRight;
  FParts.CloseButton.AlignWithMargins := True;
  FParts.CloseButton.Margins.SetBounds(cGap, cMarginY, cGap, cMarginY);
  FParts.CloseButton.Width := FScale(cButtonWidth);
  FParts.CloseButton.Caption := '×';
  FParts.CloseButton.Hint := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchCloseHint);
  FParts.CloseButton.OnClick := FHandlers.OnButton;
  FParts.CloseButton.OnKeyDown := FHandlers.OnKeyDown;
  FParts.CloseButton.OnEnter := FHandlers.OnEnter;
  FParts.ToggleButton := AddButton(FParts.SearchRow, '▸', TAtlasSearchTextId.SearchToggleReplaceHint,
    cToggleWidth);
  mLabel := AddLabel(FParts.SearchRow, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchTextLabel));
  FParts.TextFrame := AddPanel(FParts.SearchRow, cTextBoxWidth + 2);
  FParts.TextFrame.Padding.SetBounds(1, 1, 1, 1);
  FParts.TextFrame.Margins.SetBounds(cGap, 2, 0, 2);
  FParts.TextEdit := AddCombo(FParts.TextFrame, csDropDown);
  FParts.TextEdit.Align := alClient;
  FParts.TextEdit.OnChange := FHandlers.OnChanged;
  FParts.TextEdit.OnDropDown := FHandlers.OnDropDown;
  mLabel.FocusControl := FParts.TextEdit;
end;

/// <summary>Optionen, Bereich, Stufe, Zähler und Knöpfe der Suchzeile.</summary>
procedure TAtlasSearchBarBuilder.BuildSearchRow;
var
  mLabel: TLabel;
begin
  BuildTextPart;
  FParts.CaseBox := AddCheck(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchCaseSensitive),
    TAtlasSearchTextId.SearchCaseHint);
  FParts.WholeBox := AddCheck(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchWholeWord),
    TAtlasSearchTextId.SearchWholeHint);
  FParts.IdentifierBox := AddCheck(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchIdentifier),
    TAtlasSearchTextId.SearchIdentifierHint);
  FParts.RegexBox := AddCheck('.*', TAtlasSearchTextId.SearchRegexHint);
  mLabel := AddLabel(FParts.SearchRow, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchScopeLabel));
  FParts.ScopeBox := AddCombo(FParts.SearchRow, csDropDownList);
  Place(FParts.SearchRow, FParts.ScopeBox, cScopeWidth);
  FParts.ScopeBox.OnChange := FHandlers.OnChanged;
  mLabel.FocusControl := FParts.ScopeBox;
  FParts.LevelBox := AddCombo(FParts.SearchRow, csDropDownList);
  Place(FParts.SearchRow, FParts.LevelBox, cLevelWidth);
  FParts.LevelBox.OnChange := FHandlers.OnChanged;
  FParts.CounterLabel := AddLabel(FParts.SearchRow, '');
  FParts.PreviousButton := AddButton(FParts.SearchRow, '↑', TAtlasSearchTextId.SearchPreviousHint, cButtonWidth);
  FParts.NextButton := AddButton(FParts.SearchRow, '↓', TAtlasSearchTextId.SearchNextHint, cButtonWidth);
  FParts.ListButton := AddButton(FParts.SearchRow, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchListButton),
    TAtlasSearchTextId.SearchListHint, 100);
  FParts.CancelButton := AddButton(FParts.SearchRow,
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchCancelButton), TAtlasSearchTextId.SearchCancelHint,
    cTextButtonWidth);
  FParts.CancelButton.Visible := False;
end;

/// <summary>Ersetzen-Zeile: das Feld steht unter dem Suchfeld (Platz für den Knopf zum Aufklappen).</summary>
procedure TAtlasSearchBarBuilder.BuildReplaceRow;
var
  mLabel: TLabel;
begin
  AddPanel(FParts.ReplaceRow, cToggleWidth);
  mLabel := AddLabel(FParts.ReplaceRow, TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceLabel));
  FParts.ReplaceEdit := AddCombo(FParts.ReplaceRow, csDropDown);
  Place(FParts.ReplaceRow, FParts.ReplaceEdit, cTextBoxWidth);
  FParts.ReplaceEdit.OnChange := FHandlers.OnReplaceChanged;
  FParts.ReplaceEdit.OnDropDown := FHandlers.OnDropDown;
  mLabel.FocusControl := FParts.ReplaceEdit;
  FParts.ReplaceOneButton := AddButton(FParts.ReplaceRow,
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceButton), TAtlasSearchTextId.SearchReplaceHint,
    cTextButtonWidth);
  FParts.ReplaceAllButton := AddButton(FParts.ReplaceRow,
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceAllButton), TAtlasSearchTextId.SearchReplaceAllHint,
    cReplaceAllWidth);
  FParts.ChooseButton := AddButton(FParts.ReplaceRow,
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchChooseButton), TAtlasSearchTextId.SearchChooseHint,
    cTextButtonWidth);
  FParts.InfoLine := TAtlasSearchInfoLine.Create(FBar);
  FParts.InfoLine.Parent := FParts.InfoRow;
  FParts.InfoLine.Align := alClient;
  FParts.InfoLine.AlignWithMargins := True;
  FParts.InfoLine.Margins.SetBounds(cGap + FScale(cToggleWidth), 2, cGap, 2);
end;

class procedure TAtlasSearchBarBuilder.Build(ABar: TWinControl; AParts: TAtlasSearchBarParts;
  const AHandlers: TAtlasSearchBarHandlers; const AScale: TFunc<Integer, Integer>);
var
  mBuilder: TAtlasSearchBarBuilder;
begin
  mBuilder := TAtlasSearchBarBuilder.Create;
  try
    mBuilder.FBar := ABar;
    mBuilder.FParts := AParts;
    mBuilder.FHandlers := AHandlers;
    mBuilder.FScale := AScale;
    AParts.SearchRow := mBuilder.AddRow(0);
    AParts.ReplaceRow := mBuilder.AddRow(cReplaceRowTop);
    AParts.InfoRow := mBuilder.AddRow(cInfoRowTop);
    mBuilder.BuildSearchRow;
    mBuilder.BuildReplaceRow;
  finally
    mBuilder.Free;
  end;
end;

end.
