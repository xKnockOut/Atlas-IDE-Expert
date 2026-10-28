unit Atlas.UI.Search.Bar;

// Suchleiste der Atlas-Suche (#877, #878): eine Zeile am unteren Rand des
// Editors (statt des früheren Suchdialogs). Von links: Suchfeld; Optionen
// Groß-/Kleinschreibung, ganzes Wort, Bezeichner statt Text; Bereich Methode,
// Unit oder Auswahl (nur mit Auswahl), bei Methode die Stufe (innerste …
// äußerste umgebende Routine); Zähler „n von m“; voriger/nächster Treffer;
// „In Meldungen“; rechts Schließen.
// Tasten in allen Feldern der Leiste: Enter nächster Treffer und Liste in den
// Meldungen (OnNext, dann OnList), Umschalt+Enter voriger Treffer, F3 bzw.
// Umschalt+F3 wie im Editor, Esc schließt (OnClose). Bearbeitungstasten wie Strg+V
// behält das Suchfeld (TAtlasSearchEdit, #1243). Jede Änderung an Text,
// Optionen oder Bereich meldet OnQueryChanged. Bekommt ein Feld der Leiste den
// Fokus, meldet OnControlEnter es (der Aufrufer prüft, ob die IDE ihn gleich
// wieder in den Editor holt). Reine VCL; gesucht, markiert
// und gesprungen wird vom Aufrufer (Atlas.IDE.Search.Commands). Die Listen
// brauchen ein Fenster: gefüllt wird in CreateWnd bzw. sofort, wenn es schon
// eins gibt.

interface

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Search.Matching;

type
  TAtlasSearchBarStep = reference to procedure(ABackward: Boolean);

  /// <summary>Suchfeld, das Bearbeitungstasten (Strg+V/C/X/A/Z/Y, Entf, Umschalt+Einfg …) selbst behält (#1243).
  /// Sonst prüft das Editorfenster der IDE sie zuerst als eigene Tastenkürzel und fügt etwa in den Editor ein.
  /// </summary>
  TAtlasSearchEdit = class(TEdit)
  private
    procedure CNKeyDown(var Message: TWMKeyDown); message CN_KEYDOWN;
  public
    /// <summary>Bleibt die Taste im Feld, statt als Tastenkürzel der IDE zu gelten?</summary>
    class function KeepsKey(AKey: Word; AShift: TShiftState): Boolean; static;
  end;

  TAtlasSearchBar = class(TCustomPanel)
  private
    FTextLabel: TLabel;
    FText: TAtlasSearchEdit;
    FCase: TCheckBox;
    FWhole: TCheckBox;
    FIdentifier: TCheckBox;
    FScopeLabel: TLabel;
    FScope: TComboBox;
    FLevel: TComboBox;
    FCounter: TLabel;
    FPrevious: TButton;
    FNext: TButton;
    FList: TButton;
    FClose: TButton;
    FQuery: TAtlasSearchQuery;
    FLevels: TArray<string>;
    FHasSelection: Boolean;
    FPending: Boolean;
    FUpdating: Boolean;
    FNextLeft: Integer;
    FOnQueryChanged: TProc;
    FOnStep: TAtlasSearchBarStep;
    FOnList: TProc;
    FOnClose: TProc;
    FOnControlEnter: TProc<TWinControl>;
    procedure Place(AControl: TControl; AWidth: Integer);
    function AddLabel(const ACaption: string): TLabel;
    function AddCheck(const ACaption, AHint: string): TCheckBox;
    function AddButton(const ACaption, AHint: string; AWidth: Integer): TButton;
    procedure Apply;
    procedure UpdateStates;
    procedure FitWidths;
    procedure Changed(Sender: TObject);
    procedure ControlEnter(Sender: TObject);
    procedure ControlKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure PreviousClick(Sender: TObject);
    procedure NextClick(Sender: TObject);
    procedure ListClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure Step(ABackward: Boolean);
    function GetListVisible: Boolean;
    procedure SetListVisible(AValue: Boolean);
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
    /// <summary>Fokus ins Suchfeld, Text markiert.</summary>
    procedure FocusText;
    /// <summary>Hat ein Feld der Leiste den Fokus?</summary>
    function HasFocus: Boolean;
    /// <summary>Schaltfläche „In Meldungen“ (search.resultsInMessages).</summary>
    property ListVisible: Boolean read GetListVisible write SetListVisible;
    property OnQueryChanged: TProc read FOnQueryChanged write FOnQueryChanged;
    property OnStep: TAtlasSearchBarStep read FOnStep write FOnStep;
    property OnList: TProc read FOnList write FOnList;
    property OnClose: TProc read FOnClose write FOnClose;
    /// <summary>Ein Feld der Leiste hat den Fokus bekommen.</summary>
    property OnControlEnter: TProc<TWinControl> read FOnControlEnter write FOnControlEnter;
    // Für Tests.
    property TextEdit: TAtlasSearchEdit read FText;
    property ScopeBox: TComboBox read FScope;
    property LevelBox: TComboBox read FLevel;
    property CaseBox: TCheckBox read FCase;
    property WholeBox: TCheckBox read FWhole;
    property IdentifierBox: TCheckBox read FIdentifier;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.UI.Strings;

const
  BarHeight = 30;
  Gap = 6;
  TextBoxWidth = 200;
  ScopeWidth = 100;
  LevelWidth = 240;
  ButtonWidth = 28;

{ TAtlasSearchEdit }

class function TAtlasSearchEdit.KeepsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  if AShift = [ssCtrl] then
    Result := CharInSet(Char(AKey), ['A', 'C', 'V', 'X', 'Y', 'Z']) or (AKey = VK_INSERT) or (AKey = VK_BACK) or
      (AKey = VK_DELETE) or (AKey = VK_LEFT) or (AKey = VK_RIGHT)
  else if AShift = [ssShift] then
    Result := (AKey = VK_INSERT) or (AKey = VK_DELETE) or (AKey = VK_HOME) or (AKey = VK_END) or (AKey = VK_LEFT) or
      (AKey = VK_RIGHT)
  else if AShift = [ssCtrl, ssShift] then
    Result := (AKey = Ord('Z')) or (AKey = VK_LEFT) or (AKey = VK_RIGHT)
  else if AShift = [] then
    Result := (AKey = VK_DELETE) or (AKey = VK_HOME) or (AKey = VK_END) or (AKey = VK_BACK)
  else
    Result := False;
end;

procedure TAtlasSearchEdit.CNKeyDown(var Message: TWMKeyDown);
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
  Height := ScaleValue(BarHeight);
  ShowHint := True;
  FQuery := Default(TAtlasSearchQuery);
  FQuery.Scope := TAtlasSearchScope.UnitFile;

  FClose := TButton.Create(Self);
  FClose.Parent := Self;
  FClose.Align := alRight;
  FClose.AlignWithMargins := True;
  FClose.Margins.SetBounds(Gap, 3, Gap, 3);
  FClose.Width := ScaleValue(ButtonWidth);
  FClose.Caption := '×';
  FClose.Hint := TAtlasStrings.Text(TAtlasTextId.SearchCloseHint);
  FClose.OnClick := CloseClick;
  FClose.OnKeyDown := ControlKeyDown;
  FClose.OnEnter := ControlEnter;

  FTextLabel := AddLabel(TAtlasStrings.Text(TAtlasTextId.SearchTextLabel));
  FText := TAtlasSearchEdit.Create(Self);
  FText.Parent := Self;
  Place(FText, TextBoxWidth);
  FText.OnChange := Changed;
  FText.OnKeyDown := ControlKeyDown;
  FText.OnEnter := ControlEnter;
  FTextLabel.FocusControl := FText;

  FCase := AddCheck(TAtlasStrings.Text(TAtlasTextId.SearchCaseSensitive),
    TAtlasStrings.Text(TAtlasTextId.SearchCaseHint));
  FWhole := AddCheck(TAtlasStrings.Text(TAtlasTextId.SearchWholeWord),
    TAtlasStrings.Text(TAtlasTextId.SearchWholeHint));
  FIdentifier := AddCheck(TAtlasStrings.Text(TAtlasTextId.SearchIdentifier),
    TAtlasStrings.Text(TAtlasTextId.SearchIdentifierHint));

  FScopeLabel := AddLabel(TAtlasStrings.Text(TAtlasTextId.SearchScopeLabel));
  FScope := TComboBox.Create(Self);
  FScope.Parent := Self;
  FScope.Style := csDropDownList;
  Place(FScope, ScopeWidth);
  FScope.OnChange := Changed;
  FScope.OnKeyDown := ControlKeyDown;
  FScope.OnEnter := ControlEnter;
  FScopeLabel.FocusControl := FScope;
  FLevel := TComboBox.Create(Self);
  FLevel.Parent := Self;
  FLevel.Style := csDropDownList;
  Place(FLevel, LevelWidth);
  FLevel.OnChange := Changed;
  FLevel.OnKeyDown := ControlKeyDown;
  FLevel.OnEnter := ControlEnter;

  FCounter := AddLabel('');
  FPrevious := AddButton('↑', TAtlasStrings.Text(TAtlasTextId.SearchPreviousHint), ButtonWidth);
  FPrevious.OnClick := PreviousClick;
  FNext := AddButton('↓', TAtlasStrings.Text(TAtlasTextId.SearchNextHint), ButtonWidth);
  FNext.OnClick := NextClick;
  FList := AddButton(TAtlasStrings.Text(TAtlasTextId.SearchListButton), TAtlasStrings.Text(TAtlasTextId.SearchListHint),
    100);
  FList.OnClick := ListClick;
end;

procedure TAtlasSearchBar.Place(AControl: TControl; AWidth: Integer);
begin
  // alLeft ordnet nach Left: jedes neue Element rechts an die vorigen.
  Inc(FNextLeft, 10000);
  AControl.Left := FNextLeft;
  AControl.Align := alLeft;
  AControl.AlignWithMargins := True;
  AControl.Margins.SetBounds(Gap, 3, 0, 3);
  if AWidth > 0 then
    AControl.Width := ScaleValue(AWidth);
end;

function TAtlasSearchBar.AddLabel(const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.ShowAccelChar := False;
  Result.Layout := tlCenter;
  Result.AutoSize := True;
  Result.Caption := ACaption;
  Place(Result, 0);
  Result.Margins.Top := 0;
  Result.Margins.Bottom := 0;
end;

function TAtlasSearchBar.AddCheck(const ACaption, AHint: string): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := Self;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  // Breite nach dem Text erst mit Fenster (FitWidths); bis dahin geschätzt.
  Place(Result, 24 + 7 * Length(ACaption));
  Result.OnClick := Changed;
  Result.OnKeyDown := ControlKeyDown;
  Result.OnEnter := ControlEnter;
end;

function TAtlasSearchBar.AddButton(const ACaption, AHint: string; AWidth: Integer): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := Self;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Place(Result, AWidth);
  Result.OnKeyDown := ControlKeyDown;
  Result.OnEnter := ControlEnter;
end;

procedure TAtlasSearchBar.CreateWnd;
begin
  inherited CreateWnd;
  FitWidths;
  if FPending then
    Apply;
end;

procedure TAtlasSearchBar.FitWidths;
var
  Boxes: TArray<TCheckBox>;
  Box: TCheckBox;
begin
  Canvas.Font := Font;
  Boxes := [FCase, FWhole, FIdentifier];
  for Box in Boxes do
    Box.Width := Canvas.TextWidth(Box.Caption) + ScaleValue(24);
  FList.Width := Canvas.TextWidth(FList.Caption) + ScaleValue(20);
end;

procedure TAtlasSearchBar.Prepare(const AQuery: TAtlasSearchQuery; const ALevels: TArray<string>;
  AHasSelection: Boolean);
begin
  FQuery := AQuery;
  FLevels := ALevels;
  FHasSelection := AHasSelection;
  FPending := True;
  if HandleAllocated then
    Apply;
end;

procedure TAtlasSearchBar.Apply;
var
  Level: string;
begin
  FPending := False;
  FUpdating := True;
  try
    FText.Text := FQuery.Text;
    FCase.Checked := FQuery.Options.CaseSensitive;
    FWhole.Checked := FQuery.Options.WholeWord;
    FIdentifier.Checked := FQuery.Options.Identifier;
    FScope.Items.BeginUpdate;
    try
      FScope.Items.Clear;
      // Reihenfolge wie TAtlasSearchScope: Unit, Methode, Auswahl.
      FScope.Items.Add(TAtlasStrings.Text(TAtlasTextId.SearchScopeUnit));
      FScope.Items.Add(TAtlasStrings.Text(TAtlasTextId.SearchScopeMethod));
      if FHasSelection then
        FScope.Items.Add(TAtlasStrings.Text(TAtlasTextId.SearchScopeSelection));
    finally
      FScope.Items.EndUpdate;
    end;
    // Ohne Auswahl fällt „Auswahl“ auf „Unit“ zurück.
    if (FQuery.Scope = TAtlasSearchScope.Selection) and not FHasSelection then
      FQuery.Scope := TAtlasSearchScope.UnitFile;
    FScope.ItemIndex := Ord(FQuery.Scope);
    FLevel.Items.BeginUpdate;
    try
      FLevel.Items.Clear;
      for Level in FLevels do
        FLevel.Items.Add(Level);
    finally
      FLevel.Items.EndUpdate;
    end;
    FLevel.ItemIndex := -1;
    if Length(FLevels) > 0 then
    begin
      FLevel.ItemIndex := FQuery.Level;
      if FLevel.ItemIndex < 0 then
        FLevel.ItemIndex := 0;
    end;
    UpdateStates;
  finally
    FUpdating := False;
  end;
end;

procedure TAtlasSearchBar.UpdateStates;
begin
  FLevel.Visible := (FScope.ItemIndex = Ord(TAtlasSearchScope.Method)) and (FLevel.Items.Count > 0);
  // Bezeichner-Modus kennt nur ganze Bezeichner ohne Rücksicht auf die Schreibweise.
  FCase.Enabled := not FIdentifier.Checked;
  FWhole.Enabled := not FIdentifier.Checked;
end;

function TAtlasSearchBar.Query: TAtlasSearchQuery;
begin
  Result := FQuery;
  Result.Text := FText.Text;
  Result.Options := TAtlasSearchOptions.Create(FCase.Checked, FWhole.Checked, FIdentifier.Checked);
  if FScope.ItemIndex >= 0 then
    Result.Scope := TAtlasSearchScope(FScope.ItemIndex);
  Result.Level := FLevel.ItemIndex;
  if Result.Level < 0 then
    Result.Level := 0;
end;

procedure TAtlasSearchBar.SetCounter(const AText: string);
begin
  FCounter.Caption := AText;
end;

function TAtlasSearchBar.Counter: string;
begin
  Result := FCounter.Caption;
end;

procedure TAtlasSearchBar.FocusText;
begin
  if FText.CanFocus then
  begin
    FText.SetFocus;
    FText.SelectAll;
  end;
end;

function TAtlasSearchBar.HasFocus: Boolean;
var
  Focused: HWND;
begin
  Focused := Winapi.Windows.GetFocus;
  Result := HandleAllocated and (Focused <> 0) and ((Focused = Handle) or IsChild(Handle, Focused));
end;

function TAtlasSearchBar.GetListVisible: Boolean;
begin
  Result := FList.Visible;
end;

procedure TAtlasSearchBar.SetListVisible(AValue: Boolean);
begin
  FList.Visible := AValue;
end;

procedure TAtlasSearchBar.Changed(Sender: TObject);
begin
  if FUpdating then
    Exit;
  UpdateStates;
  if Assigned(FOnQueryChanged) then
    FOnQueryChanged();
end;

procedure TAtlasSearchBar.ControlEnter(Sender: TObject);
begin
  if Assigned(FOnControlEnter) and (Sender is TWinControl) then
    FOnControlEnter(TWinControl(Sender));
end;

procedure TAtlasSearchBar.Step(ABackward: Boolean);
begin
  if Assigned(FOnStep) then
    FOnStep(ABackward);
end;

procedure TAtlasSearchBar.ControlKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // Offene Auswahlliste: Enter und Esc gehören ihr.
  if (Sender is TComboBox) and TComboBox(Sender).DroppedDown then
    Exit;
  case Key of
    VK_RETURN:
      begin
        Key := 0;
        Step(ssShift in Shift);
        if not (ssShift in Shift) and FList.Visible and Assigned(FOnList) then
          FOnList();
      end;
    VK_F3:
      begin
        Key := 0;
        Step(ssShift in Shift);
      end;
    VK_ESCAPE:
      begin
        Key := 0;
        if Assigned(FOnClose) then
          FOnClose();
      end;
  end;
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
  if Assigned(FOnList) then
    FOnList();
end;

procedure TAtlasSearchBar.CloseClick(Sender: TObject);
begin
  if Assigned(FOnClose) then
    FOnClose();
end;

end.
