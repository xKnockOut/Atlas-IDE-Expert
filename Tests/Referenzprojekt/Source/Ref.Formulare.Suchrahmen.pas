unit Ref.Formulare.Suchrahmen;

interface

uses
  System.Classes,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls;

type
  TSuchrahmen = class(TFrame)
    SuchEdit: TEdit;
    SuchenButton: TButton;
    procedure SuchenButtonClick(Sender: TObject);
  private
    FOnSuchen: TNotifyEvent;
  public
    property OnSuchen: TNotifyEvent read FOnSuchen write FOnSuchen;
  end;

implementation

{$R *.dfm}

procedure TSuchrahmen.SuchenButtonClick(Sender: TObject);
begin
  if Assigned(FOnSuchen) then
    FOnSuchen(Self);
end;

end.
