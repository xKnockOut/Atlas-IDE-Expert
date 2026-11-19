unit Atlas.UI.Tracker.NewIssueBox;

// Klappliste des Dialogs „Issue anlegen“ (#1268, #2137): Die Einträge kommen
// erst mit Fenster in die Liste (CreateWnd), Values und Choice gelten auch
// ohne Fenster. So lassen sich Dialog und Formularfelder im Konstruktor und in
// Tests ohne Fenster füllen. Reine VCL.

interface

uses
  System.Classes,
  Atlas.UI.Settings.ChoiceBox;

type
  /// <summary>Klappliste, deren Einträge erst mit Fenster in die Liste kommen (CreateWnd); Values und Choice gelten
  /// auch ohne Fenster.</summary>
  TAtlasNewIssueBox = class(TAtlasHeldChoiceBox)
  private
    FValues: TArray<string>;
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
  public
    destructor Destroy; override;
    /// <summary>Einträge setzen; ein eingetippter Text bleibt.</summary>
    procedure SetValues(const AValues: TArray<string>);
    property Values: TArray<string> read FValues;
  end;

implementation

uses
  Vcl.StdCtrls;

{ TAtlasNewIssueBox }

destructor TAtlasNewIssueBox.Destroy;
begin
  FValues := nil;
  inherited Destroy;
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

end.
