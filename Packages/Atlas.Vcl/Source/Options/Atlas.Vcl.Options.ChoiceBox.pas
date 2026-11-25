unit Atlas.Vcl.Options.ChoiceBox;

// Auswahlliste der Optionsseiten (eigene Unit, damit Dialoge der Seite sie
// nutzen, ohne die Seite einzubinden, #1450).

interface

uses
  System.Classes,
  Vcl.StdCtrls;

type
  /// <summary>Klappliste, deren Auswahl auch ohne Fensterhandle gilt: Choice liest und setzt mit Fenster
  /// ItemIndex, ohne Fenster den gemerkten Wert FChoice. Nachfahren setzen FChoice in CreateWnd wieder und
  /// sichern es in DestroyWnd.</summary>
  TAtlasHeldChoiceBox = class(TComboBox)
  private
    function GetChoice: Integer;
    procedure SetChoice(AValue: Integer);
  protected
    /// <summary>Auswahl ohne Fenster, -1 = keine.</summary>
    FChoice: Integer;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Gewählter Eintrag, -1 = keiner; gilt auch ohne Fenster.</summary>
    property Choice: Integer read GetChoice write SetChoice;
  end;

  /// <summary>Auswahlliste, die Einträge und Auswahl ohne Fensterhandle hält: Die IDE erzeugt und lädt die
  /// Optionsseiten, bevor sie ein übergeordnetes Fenster haben; Items.Add bräuchte dann schon eins. Mit
  /// Style = csDropDown (freie Eingabe) bleibt ein Text ohne passenden Eintrag (Choice = -1) beim Anlegen des
  /// Fensters und beim Füllen der Einträge stehen.</summary>
  TAtlasChoiceBox = class(TAtlasHeldChoiceBox)
  private
    FChoices: TArray<string>;
    /// <summary>Freie Eingabe AText wieder zeigen, wenn kein Eintrag gewählt ist (nur csDropDown).</summary>
    procedure KeepFreeText(const AText: string);
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetChoices(const AItems: array of string);
  end;

implementation

{ TAtlasHeldChoiceBox }

constructor TAtlasHeldChoiceBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FChoice := -1;
end;

function TAtlasHeldChoiceBox.GetChoice: Integer;
begin
  if HandleAllocated then
  begin
    Result := ItemIndex;
  end
  else
  begin
    Result := FChoice;
  end;
end;

procedure TAtlasHeldChoiceBox.SetChoice(AValue: Integer);
begin
  FChoice := AValue;
  if HandleAllocated then
  begin
    ItemIndex := AValue;
  end;
end;

{ TAtlasChoiceBox }

constructor TAtlasChoiceBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Style := csDropDownList;
end;

procedure TAtlasChoiceBox.CreateWnd;
var
  mItem: string;
  mText: string;
begin
  // Ohne Fenster liest Text den gemerkten Wert (auch den, den DestroyWnd beim RecreateWnd sichert).
  mText := Text;
  inherited CreateWnd;
  if Items.Count = 0 then
  begin
    for mItem in FChoices do
    begin
      Items.Add(mItem);
    end;
  end;
  ItemIndex := FChoice;
  KeepFreeText(mText);
end;

procedure TAtlasChoiceBox.KeepFreeText(const AText: string);
begin
  // ItemIndex := -1 und Items.Clear leeren das Eingabefeld.
  if (Style = csDropDown) and (FChoice < 0) and (Text <> AText) then
  begin
    Text := AText;
  end;
end;

procedure TAtlasChoiceBox.DestroyWnd;
begin
  // Auswahl sichern, bevor das Fenster wegfällt (RecreateWnd); CreateWnd setzt sie wieder. So ändert der
  // Getter nichts (getter-side-effect, #1052).
  FChoice := ItemIndex;
  inherited DestroyWnd;
end;

procedure TAtlasChoiceBox.SetChoices(const AItems: array of string);
var
  mIndex: Integer;
  mText: string;
begin
  SetLength(FChoices, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    FChoices[mIndex] := AItems[mIndex];
  end;
  if HandleAllocated then
  begin
    mText := Text;
    Items.Clear;
    for mIndex := 0 to High(FChoices) do
    begin
      Items.Add(FChoices[mIndex]);
    end;
    ItemIndex := FChoice;
    KeepFreeText(mText);
  end;
end;

end.
