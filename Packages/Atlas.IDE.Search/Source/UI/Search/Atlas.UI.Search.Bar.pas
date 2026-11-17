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
// Aufbau: Die Steuerelemente stehen in TAtlasSearchBarParts (Aufbau TAtlasSearchBarBuilder), die Ereignisse für
// den Aufrufer in TAtlasSearchBarEvents, die Hinweiszeile zeichnet TAtlasSearchInfoLine (alle
// Atlas.UI.Search.BarParts); was die Felder zeigen, hält TAtlasSearchBarFields.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.History,
  Atlas.UI.Search.BarParts,
  Atlas.UI.Search.BarFields;

type
  /// <summary>Schritt zum nächsten bzw. vorigen Treffer (für Aufrufer ohne BarParts).</summary>
  TAtlasSearchBarStep = Atlas.UI.Search.BarParts.TAtlasSearchBarStep;
  /// <summary>Teile der Leiste nach den Einstellungen (für Aufrufer ohne BarParts).</summary>
  TAtlasSearchBarFeatures = Atlas.UI.Search.BarParts.TAtlasSearchBarFeatures;

  TAtlasSearchBar = class(TCustomPanel)
  private
    FParts: TAtlasSearchBarParts;
    FEvents: TAtlasSearchBarEvents;
    /// <summary>Was die Felder zeigen.</summary>
    FFields: TAtlasSearchBarFields;
    procedure FitWidths;
    procedure ControlEnter(Sender: TObject);
    procedure ControlKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ButtonClick(Sender: TObject);
    function GetFeatures: TAtlasSearchBarFeatures;
    procedure SetFeatures(const AValue: TAtlasSearchBarFeatures);
    function GetReplaceShown: Boolean;
    procedure SetReplaceShown(AValue: Boolean);
    /// <summary>Zeilen ein- bzw. ausblenden und die Höhe danach.</summary>
    procedure UpdateLayout;
    /// <summary>Verlauf merken, dann nächster bzw. voriger Treffer.</summary>
    procedure Step(ABackward: Boolean);
    /// <summary>Enter: im Ersetzen-Feld ersetzen (Strg: alle), sonst nächster bzw. voriger Treffer und Liste.
    /// </summary>
    procedure PressReturn(ASender: TObject; AShift: TShiftState);
    procedure ToggleReplace;
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
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
    property Features: TAtlasSearchBarFeatures read GetFeatures write SetFeatures;
    /// <summary>Ersetzen-Zeile offen (nur mit Features.Replace).</summary>
    property ReplaceShown: Boolean read GetReplaceShown write SetReplaceShown;
    property Events: TAtlasSearchBarEvents read FEvents;
    property Parts: TAtlasSearchBarParts read FParts;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.StdCtrls;

procedure FocusBox(ABox: TComboBox);
begin
  if ABox.CanFocus then
  begin
    ABox.SetFocus;
    ABox.SelectAll;
  end;
end;

{ TAtlasSearchBar }

constructor TAtlasSearchBar.Create(AOwner: TComponent);
var
  mHandlers: TAtlasSearchBarHandlers;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';
  ShowCaption := False;
  ShowHint := True;
  FEvents := TAtlasSearchBarEvents.Create(Self);
  FParts := TAtlasSearchBarParts.Create(Self);
  FFields := TAtlasSearchBarFields.Create(FParts, FEvents);
  mHandlers := Default(TAtlasSearchBarHandlers);
  mHandlers.OnChanged := FFields.Changed;
  mHandlers.OnReplaceChanged := FFields.ReplaceChanged;
  mHandlers.OnDropDown := FFields.HistoryDropDown;
  mHandlers.OnEnter := ControlEnter;
  mHandlers.OnKeyDown := ControlKeyDown;
  mHandlers.OnButton := ButtonClick;
  TAtlasSearchBarBuilder.Build(Self, FParts, mHandlers,
    function(AValue: Integer): Integer
    begin
      Result := ScaleValue(AValue);
    end);
  UpdateLayout;
end;

destructor TAtlasSearchBar.Destroy;
begin
  // Die Steuerelemente gehören der Leiste und gehen mit ihr; die Felder halten nur Verweise darauf.
  FreeAndNil(FFields);
  inherited Destroy;
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
    FFields.StepHistory(TAtlasSearchCombo(Sender), mKey = VK_UP);
    Exit;
  end;
  case mKey of
    VK_RETURN:
      begin
        Key := 0;
        PressReturn(Sender, Shift);
      end;
    VK_F3:
      begin
        Key := 0;
        Step(ssShift in Shift);
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
  if FEvents.RememberingButton(FParts, Sender, mEvent) then
  begin
    Remember;
    TAtlasSearchBarEvents.Fire(mEvent);
  end
  else if Sender = FParts.ToggleButton then
  begin
    ToggleReplace;
  end
  else if (Sender = FParts.PreviousButton) or (Sender = FParts.NextButton) then
  begin
    Step(Sender = FParts.PreviousButton);
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

function TAtlasSearchBar.GetFeatures: TAtlasSearchBarFeatures;
begin
  Result := FFields.Features;
end;

procedure TAtlasSearchBar.SetFeatures(const AValue: TAtlasSearchBarFeatures);
begin
  FFields.Features := AValue;
  if not AValue.Regex then
  begin
    FParts.RegexBox.Checked := False;
    ClearPreview;
  end;
  FFields.UpdateStates;
  UpdateLayout;
  if HandleAllocated and not FFields.Pending then
  begin
    // Bereiche neu aufbauen (Dateien ein/aus), Auswahl beibehalten.
    FFields.Reapply;
  end;
end;

function TAtlasSearchBar.GetReplaceShown: Boolean;
begin
  Result := FFields.ReplaceShown;
end;

procedure TAtlasSearchBar.SetReplaceShown(AValue: Boolean);
var
  mShown: Boolean;
begin
  mShown := AValue and FFields.Features.Replace;
  if mShown = FFields.ReplaceShown then
  begin
    Exit;
  end;
  FFields.ReplaceShown := mShown;
  if not FFields.ReplaceShown then
  begin
    ClearPreview;
  end;
  UpdateLayout;
end;

procedure TAtlasSearchBar.UpdateLayout;
begin
  Height := FFields.Arrange * ScaleValue(TAtlasSearchBarBuilder.cRowHeight);
end;

procedure TAtlasSearchBar.Step(ABackward: Boolean);
begin
  Remember;
  if Assigned(FEvents.OnStep) then
  begin
    FEvents.OnStep(ABackward);
  end;
end;

procedure TAtlasSearchBar.PressReturn(ASender: TObject; AShift: TShiftState);
begin
  if ASender = FParts.ReplaceEdit then
  begin
    Remember;
    if ssCtrl in AShift then
    begin
      TAtlasSearchBarEvents.Fire(FEvents.OnReplaceAll);
    end
    else
    begin
      TAtlasSearchBarEvents.Fire(FEvents.OnReplace);
    end;
    Exit;
  end;
  Step(ssShift in AShift);
  if not (ssShift in AShift) and FParts.ListButton.Visible then
  begin
    TAtlasSearchBarEvents.Fire(FEvents.OnList);
  end;
end;

procedure TAtlasSearchBar.ToggleReplace;
begin
  ReplaceShown := not ReplaceShown;
  if ReplaceShown then
  begin
    FocusBox(FParts.ReplaceEdit);
  end
  else
  begin
    FocusBox(FParts.TextEdit);
  end;
  TAtlasSearchBarEvents.Fire(FEvents.OnReplaceShown);
end;

procedure TAtlasSearchBar.CreateWnd;
begin
  inherited CreateWnd;
  FitWidths;
  if FFields.Pending then
  begin
    FFields.Apply;
  end;
end;

procedure TAtlasSearchBar.Prepare(const AQuery: TAtlasSearchQuery; const ALevels: TArray<string>;
  AHasSelection: Boolean);
begin
  FFields.Prepare(AQuery, ALevels, AHasSelection);
  if HandleAllocated then
  begin
    FFields.Apply;
  end;
end;

function TAtlasSearchBar.Query: TAtlasSearchQuery;
begin
  Result := FFields.Query;
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
    FParts.TextFrame.Color := TAtlasSearchInfoLine.cErrorColor;
  end
  else
  begin
    FParts.InfoLine.ClearError;
    FParts.TextFrame.StyleElements := FParts.TextFrame.StyleElements + [seClient];
    FParts.TextFrame.ParentColor := True;
    FParts.TextFrame.ParentBackground := True;
  end;
  UpdateLayout;
end;

procedure TAtlasSearchBar.SetPreview(const ABefore, AAfter: string);
begin
  FParts.InfoLine.ShowPreview(ABefore, AAfter);
  UpdateLayout;
end;

procedure TAtlasSearchBar.ClearPreview;
begin
  FParts.InfoLine.ClearPreview;
  UpdateLayout;
end;

procedure TAtlasSearchBar.SetNotice(const AText: string);
begin
  if FParts.InfoLine.IsError then
  begin
    Exit;
  end;
  FParts.InfoLine.ShowNotice(AText);
  UpdateLayout;
end;

function TAtlasSearchBar.InfoText: string;
begin
  Result := FParts.InfoLine.Content;
end;

function TAtlasSearchBar.HasError: Boolean;
begin
  Result := FParts.InfoLine.IsError;
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
  if FFields.ReplaceShown and (FParts.ReplaceEdit.History <> nil) then
  begin
    FParts.ReplaceEdit.History.Remember(FParts.ReplaceEdit.Text);
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

function TAtlasSearchBar.ReplaceText: string;
begin
  Result := FParts.ReplaceEdit.Text;
end;

class function TAtlasSearchBar.ScopeCaption(AScope: TAtlasSearchScope): string;
begin
  Result := TAtlasSearchBarFields.ScopeCaption(AScope);
end;

end.
