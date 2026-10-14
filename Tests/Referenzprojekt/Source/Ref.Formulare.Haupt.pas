unit Ref.Formulare.Haupt;

interface

uses
  System.Classes,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls,
  Ref.Formulare.Suchrahmen;

type
  THauptFormular = class(TForm)
    Suche: TSuchrahmen;
    KundenListe: TListBox;
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
  Ref.Daten.Suche,
  Ref.Formulare.Detail;

{$R *.dfm}

procedure THauptFormular.FormCreate(Sender: TObject);
begin
  Suche.OnSuchen := SucheAusfuehren;
end;

procedure THauptFormular.SucheAusfuehren(Sender: TObject);
begin
  // Ohne Datenbank (RefApp) bleibt die Liste leer; RefDaten meldet die Suche über FireDAC an.
  KundenListe.Items.BeginUpdate;
  try
    KundenListe.Items.Clear;
    for var Kunde in TKundenSuche.Suchen(Suche.SuchEdit.Text) do
      KundenListe.Items.Add(Kunde);
  finally
    KundenListe.Items.EndUpdate;
  end;
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
