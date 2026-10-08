unit Ref.Formulare.Basis;

interface

uses
  System.Classes,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls;

type
  TBasisFormular = class(TForm)
    KopfPanel: TPanel;
    TitelLabel: TLabel;
    SchliessenButton: TButton;
    procedure SchliessenButtonClick(Sender: TObject);
  protected
    procedure Initialisieren; virtual;
  end;

implementation

{$R *.dfm}

procedure TBasisFormular.Initialisieren;
begin
  TitelLabel.Caption := Caption;
end;

procedure TBasisFormular.SchliessenButtonClick(Sender: TObject);
begin
  Close;
end;

end.
