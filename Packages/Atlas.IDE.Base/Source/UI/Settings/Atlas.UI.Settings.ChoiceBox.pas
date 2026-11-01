unit Atlas.UI.Settings.ChoiceBox;

// Auswahlliste der Optionsseiten (aus Atlas.UI.Settings.Page herausgelöst,
// damit Dialoge der Seite sie nutzen, ohne die Seite einzubinden, #1450).

interface

uses
  System.Classes,
  Vcl.StdCtrls;

type
  /// <summary>Auswahlliste, die Einträge und Auswahl ohne Fensterhandle hält: Die IDE erzeugt und lädt die
  /// Optionsseiten, bevor sie ein übergeordnetes Fenster haben; Items.Add bräuchte dann schon eins.</summary>
  TAtlasChoiceBox = class(TComboBox)
  private
    FChoices: TArray<string>;
    FChoice: Integer;
    function GetChoice: Integer;
    procedure SetChoice(AValue: Integer);
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetChoices(const AItems: array of string);
    /// <summary>Gewählter Eintrag, -1 = keiner; gilt auch ohne Fenster.</summary>
    property Choice: Integer read GetChoice write SetChoice;
  end;

implementation

{ TAtlasChoiceBox }

constructor TAtlasChoiceBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Style := csDropDownList;
  FChoice := -1;
end;

procedure TAtlasChoiceBox.SetChoices(const AItems: array of string);
var
  Index: Integer;
begin
  SetLength(FChoices, Length(AItems));
  for Index := 0 to High(AItems) do
    FChoices[Index] := AItems[Index];
  if HandleAllocated then
  begin
    Items.Clear;
    for Index := 0 to High(FChoices) do
      Items.Add(FChoices[Index]);
    ItemIndex := FChoice;
  end;
end;

procedure TAtlasChoiceBox.CreateWnd;
var
  Item: string;
begin
  inherited CreateWnd;
  if Items.Count = 0 then
    for Item in FChoices do
      Items.Add(Item);
  ItemIndex := FChoice;
end;

procedure TAtlasChoiceBox.DestroyWnd;
begin
  // Auswahl sichern, bevor das Fenster wegfällt (RecreateWnd); CreateWnd setzt sie wieder. So ändert der
  // Getter nichts (getter-side-effect, #1052).
  FChoice := ItemIndex;
  inherited DestroyWnd;
end;

function TAtlasChoiceBox.GetChoice: Integer;
begin
  if HandleAllocated then
    Result := ItemIndex
  else
    Result := FChoice;
end;

procedure TAtlasChoiceBox.SetChoice(AValue: Integer);
begin
  FChoice := AValue;
  if HandleAllocated then
    ItemIndex := AValue;
end;

end.
