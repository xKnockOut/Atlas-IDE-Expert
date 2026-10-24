unit Ref.Formulare.Detail;

// Geerbtes Formular: die DFM beginnt mit inherited.
//
// Ref.Formulare.Haupt verwendet diese Unit im implementation-uses, diese Unit
// verwendet Ref.Formulare.Haupt ebenso: ein erlaubter Zyklus über
// implementation-uses, den uses-cycle mit vollständigem Pfad meldet (#64).

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
    // Eigener Handler mit inherited; Ziel der Mutation für inherited-form-handler-without-inherited.
    procedure SchliessenButtonClick(Sender: TObject);
  protected
    procedure Initialisieren; override;
  end;

var
  // Automatisch erzeugt nach HauptFormular (RefApp.dpr); Ziel der Mutation für form-access-before-create.
  DetailFormular: TDetailFormular;

implementation

uses
  Ref.Formulare.Haupt; // ERWARTET-PROJEKT: uses-cycle

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

procedure TDetailFormular.SchliessenButtonClick(Sender: TObject);
begin
  inherited;
  NameEdit.Clear;
  // Auswahl im Hauptformular zurücksetzen; dafür steht Ref.Formulare.Haupt im implementation-uses.
  HauptFormular.KundenListe.ItemIndex := -1;
end;

end.
