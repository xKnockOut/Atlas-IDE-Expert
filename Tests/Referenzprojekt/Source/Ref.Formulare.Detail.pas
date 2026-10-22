unit Ref.Formulare.Detail;

// Geerbtes Formular: die DFM beginnt mit inherited.

interface

uses
  System.Classes,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Ref.Formulare.Basis,
  Ref.Komponenten.Anzeige;

type
  TDetailFormular = class(TBasisFormular)
    NameEdit: TEdit;
    Anzeige: TRefAnzeige;
    procedure NameEditChange(Sender: TObject);
  protected
    procedure Initialisieren; override;
  end;

var
  // Automatisch erzeugt nach HauptFormular (RefApp.dpr); Ziel der Mutation für form-access-before-create.
  DetailFormular: TDetailFormular;

implementation

{$R *.dfm}

procedure TDetailFormular.Initialisieren;
begin
  inherited;
  Anzeige.Beschriftung := 'Zeichen';
end;

procedure TDetailFormular.NameEditChange(Sender: TObject);
begin
  Anzeige.Wert := Length(NameEdit.Text);
end;

end.
