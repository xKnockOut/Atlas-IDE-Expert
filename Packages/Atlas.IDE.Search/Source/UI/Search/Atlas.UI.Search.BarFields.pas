unit Atlas.UI.Search.BarFields;

// Was die Felder der Suchleiste (#877, #878, #893) zeigen, reine VCL: Stand
// der Leiste (vorbereitete Suche, Stufen, angebotene Bereiche,
// Einstellungen), die vorbereitete Suche in die Felder (Apply) und die Suche
// aus den Feldern (Query), Freigaben der Optionen, sichtbare Zeilen
// (Arrange), Blättern im Verlauf und die Änderungsmeldungen der Felder an den
// Aufrufer (TAtlasSearchBarEvents). Abgetrennt von der Leiste
// (TAtlasSearchBar), die Tasten, Knöpfe, Fokus und Hinweiszeile bedient.
// ItemIndex und Items.Count einer TComboBox fragen ihr Fenster ab (CB_GETCURSEL, CB_GETCOUNT) und legen es dafür
// an. Ohne übergeordnetes Fenster scheitert das mit EInvalidOperation: Unter Delphi 12 legt die Suche ihre Leiste
// vor dem Einhängen an (CreateBar setzt Features, dann ordnet Place sie ein); jedes Strg+F scheiterte so, und nach
// dem dritten Versuch schaltete die Sicherung die Atlas-Suche ab. Ohne Fenster gilt darum der
// Stand der vorbereiteten Suche; Apply schreibt ihn in die Listen, sobald es eins gibt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.StdCtrls,
  Atlas.Core.Search.Matching,
  Atlas.UI.Search.BarParts;

type
  TAtlasSearchBarFields = class
  private
    FParts: TAtlasSearchBarParts;
    FEvents: TAtlasSearchBarEvents;
    FState: TAtlasSearchBarState;
    /// <summary>Gewählter Bereich: aus der Liste, solange sie kein Fenster hat aus der vorbereiteten Suche.
    /// </summary>
    function SelectedScope: TAtlasSearchScope;
    /// <summary>Gewählte Stufe: aus der Liste, ohne Fenster aus der vorbereiteten Suche.</summary>
    function SelectedLevel: Integer;
    procedure FillScopes;
    procedure FillLevels;
  public
    constructor Create(AParts: TAtlasSearchBarParts; AEvents: TAtlasSearchBarEvents);
    /// <summary>AQuery merken; in die Felder erst mit Apply (braucht ein Fenster).</summary>
    procedure Prepare(const AQuery: TAtlasSearchQuery; const ALevels: TArray<string>; AHasSelection: Boolean);
    /// <summary>Vorbereitete Suche in die Felder (braucht ein Fenster).</summary>
    procedure Apply;
    /// <summary>Stand der Felder als vorbereitete Suche übernehmen und neu anwenden (Bereiche neu aufbauen,
    /// Auswahl beibehalten).</summary>
    procedure Reapply;
    /// <summary>Suche nach den Feldern.</summary>
    function Query: TAtlasSearchQuery;
    /// <summary>Freigaben der Optionen und Sichtbarkeit von Stufe und „.*“.</summary>
    procedure UpdateStates;
    /// <summary>Zeilen nach Einstellungen und Inhalt ein- bzw. ausblenden; liefert die Zahl der sichtbaren.</summary>
    function Arrange: Integer;
    /// <summary>Text eines Felds per Programm setzen, ohne das Blättern im Verlauf zurückzusetzen.</summary>
    procedure SetBoxText(ABox: TComboBox; const AText: string);
    /// <summary>Pfeil hoch/runter im Such- bzw. Ersetzen-Feld: im Verlauf blättern.</summary>
    procedure StepHistory(ABox: TAtlasSearchCombo; AOlder: Boolean);
    /// <summary>OnChange der Such-, Options- und Bereichsfelder.</summary>
    procedure Changed(Sender: TObject);
    /// <summary>OnChange des Ersetzen-Felds.</summary>
    procedure ReplaceChanged(Sender: TObject);
    /// <summary>Verlaufsliste beim Aufklappen füllen.</summary>
    procedure HistoryDropDown(Sender: TObject);
    /// <summary>Name des Bereichs in der Auswahlliste („Unit“, „Projekt“ …).</summary>
    class function ScopeCaption(AScope: TAtlasSearchScope): string; static;
    property Features: TAtlasSearchBarFeatures read FState.Features write FState.Features;
    property ReplaceShown: Boolean read FState.ReplaceShown write FState.ReplaceShown;
    /// <summary>Prepare ohne Fenster: Apply folgt in CreateWnd.</summary>
    property Pending: Boolean read FState.Pending;
  end;

implementation

uses
  Atlas.UI.Search.Strings;

{ TAtlasSearchBarFields }

constructor TAtlasSearchBarFields.Create(AParts: TAtlasSearchBarParts; AEvents: TAtlasSearchBarEvents);
begin
  inherited Create;
  FParts := AParts;
  FEvents := AEvents;
  FState := Default(TAtlasSearchBarState);
  FState.Query.Scope := TAtlasSearchScope.UnitFile;
end;

function TAtlasSearchBarFields.SelectedScope: TAtlasSearchScope;
var
  mIndex: Integer;
begin
  Result := FState.Query.Scope;
  if not FParts.ScopeBox.HandleAllocated then
  begin
    Exit;
  end;
  mIndex := FParts.ScopeBox.ItemIndex;
  if (mIndex >= 0) and (mIndex <= High(FState.Scopes)) then
  begin
    Result := FState.Scopes[mIndex];
  end;
end;

function TAtlasSearchBarFields.SelectedLevel: Integer;
begin
  Result := FState.Query.Level;
  if FParts.LevelBox.HandleAllocated then
  begin
    Result := FParts.LevelBox.ItemIndex;
  end;
end;

procedure TAtlasSearchBarFields.FillScopes;
var
  mScope: TAtlasSearchScope;
  mIndex: Integer;
  mBox: TComboBox;
begin
  mBox := FParts.ScopeBox;
  FState.Scopes := [TAtlasSearchScope.UnitFile, TAtlasSearchScope.Method];
  if FState.HasSelection then
  begin
    FState.Scopes := FState.Scopes + [TAtlasSearchScope.Selection];
  end;
  if FState.Features.MultiFile then
  begin
    FState.Scopes := FState.Scopes + [TAtlasSearchScope.OpenFiles, TAtlasSearchScope.Project,
      TAtlasSearchScope.ProjectGroup];
  end;
  mBox.Items.BeginUpdate;
  try
    mBox.Items.Clear;
    for mScope in FState.Scopes do
    begin
      mBox.Items.Add(ScopeCaption(mScope));
    end;
  finally
    mBox.Items.EndUpdate;
  end;
  mBox.ItemIndex := 0;
  for mIndex := 0 to High(FState.Scopes) do
  begin
    if FState.Scopes[mIndex] = FState.Query.Scope then
    begin
      mBox.ItemIndex := mIndex;
    end;
  end;
  FState.Query.Scope := FState.Scopes[mBox.ItemIndex];
end;

procedure TAtlasSearchBarFields.FillLevels;
var
  mLevel: string;
  mBox: TComboBox;
begin
  mBox := FParts.LevelBox;
  mBox.Items.BeginUpdate;
  try
    mBox.Items.Clear;
    for mLevel in FState.Levels do
    begin
      mBox.Items.Add(mLevel);
    end;
  finally
    mBox.Items.EndUpdate;
  end;
  mBox.ItemIndex := -1;
  if Length(FState.Levels) > 0 then
  begin
    mBox.ItemIndex := FState.Query.Level;
    if mBox.ItemIndex < 0 then
    begin
      mBox.ItemIndex := 0;
    end;
  end;
end;

procedure TAtlasSearchBarFields.Prepare(const AQuery: TAtlasSearchQuery; const ALevels: TArray<string>;
  AHasSelection: Boolean);
begin
  FState.Query := AQuery;
  FState.Levels := ALevels;
  FState.HasSelection := AHasSelection;
  FState.Pending := True;
end;

procedure TAtlasSearchBarFields.Apply;
var
  mParts: TAtlasSearchBarParts;
  mQuery: TAtlasSearchQuery;
begin
  mParts := FParts;
  mQuery := FState.Query;
  FState.Pending := False;
  FState.Updating := True;
  try
    mParts.TextEdit.Text := mQuery.Text;
    mParts.CaseBox.Checked := mQuery.Options.CaseSensitive;
    mParts.WholeBox.Checked := mQuery.Options.WholeWord;
    mParts.IdentifierBox.Checked := mQuery.Options.Identifier;
    mParts.RegexBox.Checked := mQuery.Options.Regex and FState.Features.Regex;
    FillScopes;
    FillLevels;
    UpdateStates;
  finally
    FState.Updating := False;
  end;
end;

procedure TAtlasSearchBarFields.Reapply;
begin
  FState.Query := Query;
  Apply;
end;

function TAtlasSearchBarFields.Query: TAtlasSearchQuery;
begin
  Result := FState.Query;
  Result.Text := FParts.TextEdit.Text;
  Result.Options := TAtlasSearchOptions.Create(FParts.CaseBox.Checked, FParts.WholeBox.Checked,
    FParts.IdentifierBox.Checked, FParts.RegexBox.Checked and FState.Features.Regex);
  Result.Scope := SelectedScope;
  Result.Level := SelectedLevel;
  if Result.Level < 0 then
  begin
    Result.Level := 0;
  end;
end;

procedure TAtlasSearchBarFields.UpdateStates;
var
  mParts: TAtlasSearchBarParts;
begin
  mParts := FParts;
  // State.Levels sind die Einträge der Stufenliste (Apply füllt sie daraus); Items.Count bräuchte ein Fenster.
  mParts.LevelBox.Visible := (SelectedScope = TAtlasSearchScope.Method) and (Length(FState.Levels) > 0);
  // Bezeichner-Modus ohne Regex kennt nur ganze Bezeichner ohne Rücksicht auf die Schreibweise; mit Regex filtert
  // er nur Kommentare und Strings heraus.
  mParts.CaseBox.Enabled := not mParts.IdentifierBox.Checked or mParts.RegexBox.Checked;
  mParts.WholeBox.Enabled := not mParts.IdentifierBox.Checked or mParts.RegexBox.Checked;
  mParts.RegexBox.Visible := FState.Features.Regex;
end;

function TAtlasSearchBarFields.Arrange: Integer;
var
  mParts: TAtlasSearchBarParts;
begin
  mParts := FParts;
  mParts.ToggleButton.Visible := FState.Features.Replace;
  if not FState.Features.Replace then
  begin
    FState.ReplaceShown := False;
  end;
  if FState.ReplaceShown then
  begin
    mParts.ToggleButton.Caption := '▾';
  end
  else
  begin
    mParts.ToggleButton.Caption := '▸';
  end;
  mParts.ReplaceRow.Visible := FState.ReplaceShown;
  mParts.InfoRow.Visible := mParts.InfoLine.HasContent;
  // Reihenfolge der Zeilen festhalten: sichtbar gewordene alTop-Panels ordnen sich nach Top.
  mParts.SearchRow.Top := 0;
  mParts.ReplaceRow.Top := mParts.SearchRow.Height;
  mParts.InfoRow.Top := 2 * mParts.SearchRow.Height;
  mParts.InfoLine.Invalidate;
  Result := 1;
  if mParts.ReplaceRow.Visible then
  begin
    Inc(Result);
  end;
  if mParts.InfoRow.Visible then
  begin
    Inc(Result);
  end;
end;

procedure TAtlasSearchBarFields.SetBoxText(ABox: TComboBox; const AText: string);
begin
  FState.Updating := True;
  try
    ABox.Text := AText;
    ABox.SelectAll;
  finally
    FState.Updating := False;
  end;
end;

procedure TAtlasSearchBarFields.StepHistory(ABox: TAtlasSearchCombo; AOlder: Boolean);
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
  SetBoxText(ABox, mNext);
  // Text per Programm löst OnChange nicht aus: Suche bzw. Vorschau selbst anstoßen.
  if ABox = FParts.TextEdit then
  begin
    UpdateStates;
    TAtlasSearchBarEvents.Fire(FEvents.OnQueryChanged);
  end
  else
  begin
    TAtlasSearchBarEvents.Fire(FEvents.OnReplaceShown);
  end;
end;

procedure TAtlasSearchBarFields.Changed(Sender: TObject);
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
  UpdateStates;
  TAtlasSearchBarEvents.Fire(FEvents.OnQueryChanged);
end;

procedure TAtlasSearchBarFields.ReplaceChanged(Sender: TObject);
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

procedure TAtlasSearchBarFields.HistoryDropDown(Sender: TObject);
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

class function TAtlasSearchBarFields.ScopeCaption(AScope: TAtlasSearchScope): string;
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

end.
