unit Ref.Formulare.Haupt;

interface

uses
  System.Classes,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Grids,
  Vcl.DBGrids,
  Data.DB,
  Ref.Formulare.Suchrahmen;

type
  THauptFormular = class(TForm)
    Suche: TSuchrahmen;
    KundenGrid: TDBGrid;
    KundenQuelle: TDataSource;
    DetailButton: TButton;
    procedure FormCreate(Sender: TObject);
    procedure DetailButtonClick(Sender: TObject);
  private
    procedure SucheAusfuehren(Sender: TObject);
  end;

var
  HauptFormular: THauptFormular;

implementation

uses
  Ref.Daten.Kunden,
  Ref.Formulare.Detail;

{$R *.dfm}

procedure THauptFormular.FormCreate(Sender: TObject);
begin
  Suche.OnSuchen := SucheAusfuehren;
end;

procedure THauptFormular.SucheAusfuehren(Sender: TObject);
begin
  KundenQuelle.DataSet := TKundenDaten.Instanz.Suchen(Suche.SuchEdit.Text);
end;

procedure THauptFormular.DetailButtonClick(Sender: TObject);
var
  Formular: TDetailFormular;
begin
  Formular := TDetailFormular.Create(Self);
  try
    Formular.ShowModal;
  finally
    Formular.Free;
  end;
end;

end.
