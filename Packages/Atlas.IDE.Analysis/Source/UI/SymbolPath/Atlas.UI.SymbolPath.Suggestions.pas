unit Atlas.UI.SymbolPath.Suggestions;

// Vervollständigung der Felder „Von“ und „Nach“ im Dialog „Weg zwischen
// Symbolen“ (#1117), reine VCL: Beim Tippen fragt sie nach kurzer Pause
// ASuggest (Symbole des Projekts) und zeigt die Vorschläge in einer Liste
// unter dem Feld: ↓ geht in die Liste, ↑ in der ersten Zeile zurück ins Feld,
// Enter oder Doppelklick übernimmt, Esc schließt die Liste (HandleDialogKey,
// der Dialog fragt Standard- und Abbrechen-Knopf vor OnKeyDown). Betritt der
// Benutzer ein anderes Steuerelement, geht die Liste zu. Abgetrennt vom
// Dialog (TAtlasSymbolPathDialog), der Eingabe, Prüfung und Knöpfe hält.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls;

type
  /// <summary>Vorschläge zu einem Teil eines Namens; leer = keine.</summary>
  TAtlasSymbolPathSuggest = reference to function(const APattern: string): TArray<string>;

  TAtlasSymbolPathSuggestions = class(TComponent)
  private
    FList: TListBox;
    FTimer: TTimer;
    /// <summary>Feld, zu dem die Liste gehört bzw. das zuletzt getippt wurde.</summary>
    FTarget: TEdit;
    FSuggest: TAtlasSymbolPathSuggest;
    /// <summary>Text wird von hier gesetzt: kein Tippen.</summary>
    FFilling: Boolean;
    FOnTyping: TNotifyEvent;
    /// <summary>Angehängte Felder; beim Freigeben lösen sie ihre Ereignisse von hier.</summary>
    FEdits: TArray<TEdit>;
    procedure EditChange(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListDblClick(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure FocusTarget;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    /// <summary>Liste in AParent (Breite AWidth, Höhe AHeight, erst beim Tippen sichtbar).</summary>
    constructor CreateIn(AParent: TWinControl; const ASuggest: TAtlasSymbolPathSuggest; AWidth, AHeight: Integer);
    destructor Destroy; override;
    /// <summary>AEdit vervollständigen (OnChange, OnKeyDown, OnEnter).</summary>
    procedure Attach(AEdit: TEdit);
    /// <summary>OnEnter eines anderen Steuerelements: Die Liste gehört nicht dazu und verdeckte es sonst.</summary>
    procedure ControlEnter(Sender: TObject);
    /// <summary>Vorschläge für AEdit sofort holen und zeigen (ohne Pause; auch für Tests).</summary>
    procedure Show(AEdit: TEdit);
    /// <summary>Gewählten Vorschlag ins Feld übernehmen.</summary>
    procedure Take;
    procedure Hide;
    /// <summary>AText in AEdit setzen, ohne dass es als Tippen gilt.</summary>
    procedure Fill(AEdit: TEdit; const AText: string);
    /// <summary>Enter bzw. Esc bei offener Liste: übernehmen bzw. Liste schließen. True, wenn verarbeitet.</summary>
    function HandleDialogKey(ACharCode: Word): Boolean;
    property List: TListBox read FList;
    /// <summary>Der Benutzer tippt in ein angehängtes Feld.</summary>
    property OnTyping: TNotifyEvent read FOnTyping write FOnTyping;
  end;

implementation

uses
  Winapi.Windows;

const
  /// <summary>Pause nach dem letzten Tastendruck, bevor Vorschläge geholt werden.</summary>
  cSuggestDelayMs = 250;
  cMaxSuggestions = 12;

{ TAtlasSymbolPathSuggestions }

constructor TAtlasSymbolPathSuggestions.CreateIn(AParent: TWinControl; const ASuggest: TAtlasSymbolPathSuggest;
  AWidth, AHeight: Integer);
begin
  inherited Create(AParent);
  FSuggest := ASuggest;
  FList := TListBox.Create(Self);
  FList.Parent := AParent;
  FList.Visible := False;
  FList.Width := AWidth;
  FList.Height := AHeight;
  FList.OnKeyDown := ListKeyDown;
  FList.OnDblClick := ListDblClick;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := cSuggestDelayMs;
  FTimer.OnTimer := TimerTick;
end;

destructor TAtlasSymbolPathSuggestions.Destroy;
var
  mEdit: TEdit;
begin
  // Felder, die länger leben, dürfen keine Methode dieses Objekts mehr rufen.
  for mEdit in FEdits do
  begin
    mEdit.RemoveFreeNotification(Self);
    mEdit.OnChange := nil;
    mEdit.OnKeyDown := nil;
    mEdit.OnEnter := nil;
  end;
  FEdits := nil;
  inherited Destroy;
end;

procedure TAtlasSymbolPathSuggestions.Notification(AComponent: TComponent; Operation: TOperation);
var
  mIndex: Integer;
begin
  inherited Notification(AComponent, Operation);
  if Operation <> opRemove then
  begin
    Exit;
  end;
  if AComponent = FTarget then
  begin
    FTarget := nil;
  end;
  for mIndex := High(FEdits) downto 0 do
  begin
    if FEdits[mIndex] = AComponent then
    begin
      Delete(FEdits, mIndex, 1);
    end;
  end;
end;

procedure TAtlasSymbolPathSuggestions.Attach(AEdit: TEdit);
begin
  FEdits := FEdits + [AEdit];
  AEdit.FreeNotification(Self);
  AEdit.OnChange := EditChange;
  AEdit.OnKeyDown := EditKeyDown;
  AEdit.OnEnter := ControlEnter;
end;

procedure TAtlasSymbolPathSuggestions.EditChange(Sender: TObject);
begin
  if FFilling or not (Sender is TEdit) then
  begin
    Exit;
  end;
  FTarget := TEdit(Sender);
  if Assigned(FOnTyping) then
  begin
    FOnTyping(Self);
  end;
  FTimer.Enabled := False;
  FTimer.Enabled := Assigned(FSuggest);
end;

procedure TAtlasSymbolPathSuggestions.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if not FList.Visible or (Sender <> FTarget) then
  begin
    Exit;
  end;
  case Key of
    VK_DOWN:
      begin
        if FList.Showing and FList.CanFocus then
        begin
          FList.SetFocus;
        end;
        Key := 0;
      end;
  end;
end;

procedure TAtlasSymbolPathSuggestions.ControlEnter(Sender: TObject);
begin
  if Sender <> FTarget then
  begin
    Hide;
  end;
end;

procedure TAtlasSymbolPathSuggestions.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_UP:
      if (FList.ItemIndex <= 0) and (FTarget <> nil) and FTarget.Showing and FTarget.CanFocus then
      begin
        FTarget.SetFocus;
        Key := 0;
      end;
  end;
end;

procedure TAtlasSymbolPathSuggestions.ListDblClick(Sender: TObject);
begin
  Take;
end;

procedure TAtlasSymbolPathSuggestions.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  if FTarget <> nil then
  begin
    Show(FTarget);
  end;
end;

procedure TAtlasSymbolPathSuggestions.FocusTarget;
begin
  if (FTarget <> nil) and FTarget.Showing and FTarget.CanFocus then
  begin
    FTarget.SetFocus;
  end;
end;

procedure TAtlasSymbolPathSuggestions.Show(AEdit: TEdit);
var
  mItems: TArray<string>;
  mItem: string;
begin
  FTarget := AEdit;
  mItems := nil;
  if Assigned(FSuggest) and (Trim(AEdit.Text) <> '') then
  begin
    mItems := FSuggest(Trim(AEdit.Text));
  end;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mItem in mItems do
    begin
      if FList.Items.Count >= cMaxSuggestions then
      begin
        Break;
      end;
      if FList.Items.IndexOf(mItem) < 0 then
      begin
        FList.Items.Add(mItem);
      end;
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if FList.Items.Count = 0 then
  begin
    Hide;
    Exit;
  end;
  FList.Left := AEdit.Left;
  FList.Top := AEdit.Top + AEdit.Height;
  FList.Width := AEdit.Width;
  FList.ItemIndex := 0;
  FList.Visible := True;
  FList.BringToFront;
end;

procedure TAtlasSymbolPathSuggestions.Take;
begin
  if (FTarget = nil) or not FList.Visible or (FList.ItemIndex < 0) then
  begin
    Exit;
  end;
  Fill(FTarget, FList.Items[FList.ItemIndex]);
  FTarget.SelStart := Length(FTarget.Text);
  Hide;
  FocusTarget;
end;

procedure TAtlasSymbolPathSuggestions.Hide;
begin
  FList.Visible := False;
end;

procedure TAtlasSymbolPathSuggestions.Fill(AEdit: TEdit; const AText: string);
begin
  FFilling := True;
  try
    AEdit.Text := AText;
  finally
    FFilling := False;
  end;
end;

function TAtlasSymbolPathSuggestions.HandleDialogKey(ACharCode: Word): Boolean;
begin
  Result := FList.Visible and ((ACharCode = VK_RETURN) or (ACharCode = VK_ESCAPE));
  if not Result then
  begin
    Exit;
  end;
  if ACharCode = VK_RETURN then
  begin
    Take;
  end
  else
  begin
    Hide;
    FocusTarget;
  end;
end;

end.
