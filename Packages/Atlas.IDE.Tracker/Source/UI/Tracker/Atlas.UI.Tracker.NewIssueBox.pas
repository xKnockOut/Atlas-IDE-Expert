unit Atlas.UI.Tracker.NewIssueBox;

// Klappliste des Dialogs „Issue anlegen“ (#1268, #2137): Die Einträge kommen
// erst mit Fenster in die Liste (CreateWnd), Values und Choice gelten auch
// ohne Fenster. So lassen sich Dialog und Formularfelder im Konstruktor und in
// Tests ohne Fenster füllen. Reine VCL.

interface

uses
  System.Classes,
  Vcl.StdCtrls;

type
  /// <summary>Klappliste, deren Einträge erst mit Fenster in die Liste kommen (CreateWnd); Values und Choice gelten
  /// auch ohne Fenster.</summary>
  TAtlasNewIssueBox = class(TComboBox)
  private
    FValues: TArray<string>;
    FChoice: Integer;
    function GetChoice: Integer;
    procedure SetChoice(AValue: Integer);
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Einträge setzen; ein eingetippter Text bleibt.</summary>
    procedure SetValues(const AValues: TArray<string>);
    property Values: TArray<string> read FValues;
    /// <summary>Gewählter Eintrag (csDropDownList), -1 = keiner.</summary>
    property Choice: Integer read GetChoice write SetChoice;
  end;

implementation

{ TAtlasNewIssueBox }

constructor TAtlasNewIssueBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FChoice := -1;
end;

destructor TAtlasNewIssueBox.Destroy;
begin
  FValues := nil;
  inherited Destroy;
end;

procedure TAtlasNewIssueBox.SetValues(const AValues: TArray<string>);
var
  mText, mValue: string;
begin
  FValues := AValues;
  if not HandleAllocated then
  begin
    Exit;
  end;
  mText := Text;
  Items.BeginUpdate;
  try
    Items.Clear;
    for mValue in FValues do
    begin
      Items.Add(mValue);
    end;
  finally
    Items.EndUpdate;
  end;
  if Style = csDropDownList then
  begin
    ItemIndex := FChoice;
  end
  else
  begin
    Text := mText;
  end;
end;

procedure TAtlasNewIssueBox.CreateWnd;
var
  mText, mValue: string;
begin
  mText := Text;
  inherited CreateWnd;
  if Items.Count = 0 then
  begin
    for mValue in FValues do
    begin
      Items.Add(mValue);
    end;
  end;
  if Style = csDropDownList then
  begin
    ItemIndex := FChoice;
  end
  else
  begin
    Text := mText;
  end;
end;

procedure TAtlasNewIssueBox.DestroyWnd;
begin
  if Style = csDropDownList then
  begin
    FChoice := ItemIndex;
  end;
  inherited DestroyWnd;
end;

function TAtlasNewIssueBox.GetChoice: Integer;
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

procedure TAtlasNewIssueBox.SetChoice(AValue: Integer);
begin
  FChoice := AValue;
  if HandleAllocated then
  begin
    ItemIndex := AValue;
  end;
end;

end.
