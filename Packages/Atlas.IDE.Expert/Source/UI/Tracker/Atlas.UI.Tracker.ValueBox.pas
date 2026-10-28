unit Atlas.UI.Tracker.ValueBox;

// Klappliste mit Eingabe von Hand für Werte vom Tracker (#1266): Zustände,
// Felder und Benutzer kommen als Vorschläge, der Text bleibt frei. Hält Text
// und Vorschläge ohne Fensterhandle (die IDE erzeugt Optionsseiten, bevor sie
// ein übergeordnetes Fenster haben; Items.Add bräuchte dann schon eins).
// Genutzt von der Seite Issue-Tracker und dem Beenden-Dialog.

interface

uses
  System.Classes,
  Vcl.StdCtrls;

type
  /// <summary>Klappliste mit Eingabe von Hand (#1266): Werte vom Tracker als Vorschläge, Text frei. Hält Text und
  /// Vorschläge ohne Fensterhandle wie TAtlasChoiceBox.</summary>
  TAtlasValueBox = class(TComboBox)
  private
    FValues: TArray<string>;
    FValue: string;
    function GetValue: string;
    procedure SetValue(const AValue: string);
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Vorschläge ersetzen; der Text bleibt.</summary>
    procedure SetValues(const AItems: TArray<string>);
    property Values: TArray<string> read FValues;
    /// <summary>Eingegebener Text ohne Leerraum außen; gilt auch ohne Fenster.</summary>
    property Value: string read GetValue write SetValue;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasValueBox }

constructor TAtlasValueBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Style := csDropDown;
  FValue := '';
end;

procedure TAtlasValueBox.SetValues(const AItems: TArray<string>);
var
  mItem, mText: string;
begin
  FValues := Copy(AItems);
  if not HandleAllocated then
    Exit;
  // Items.Clear leert auch das Eingabefeld: Text merken und wieder setzen.
  mText := Text;
  Items.BeginUpdate;
  try
    Items.Clear;
    for mItem in FValues do
      Items.Add(mItem);
  finally
    Items.EndUpdate;
  end;
  Text := mText;
end;

procedure TAtlasValueBox.CreateWnd;
var
  mItem: string;
begin
  inherited CreateWnd;
  if Items.Count = 0 then
    for mItem in FValues do
      Items.Add(mItem);
  Text := FValue;
end;

procedure TAtlasValueBox.DestroyWnd;
begin
  // Text sichern, bevor das Fenster wegfällt (RecreateWnd); CreateWnd setzt ihn wieder.
  FValue := Text;
  inherited DestroyWnd;
end;

function TAtlasValueBox.GetValue: string;
begin
  if HandleAllocated then
    Result := Trim(Text)
  else
    Result := Trim(FValue);
end;

procedure TAtlasValueBox.SetValue(const AValue: string);
begin
  FValue := AValue;
  if HandleAllocated then
    Text := AValue;
end;

end.
