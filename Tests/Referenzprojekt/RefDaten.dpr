program RefDaten;

// Optionales Projekt mit FireDAC (#94): RefApp plus Datenbankzugriffe. Nicht
// Teil von RefGruppe, weil FireDAC nicht in jeder Edition enthalten ist.

uses
  Vcl.Forms,
  Ref.Komponenten.Anzeige in 'Source\Ref.Komponenten.Anzeige.pas',
  Ref.Formulare.Basis in 'Source\Ref.Formulare.Basis.pas' {BasisFormular},
  Ref.Formulare.Detail in 'Source\Ref.Formulare.Detail.pas' {DetailFormular},
  Ref.Formulare.Suchrahmen in 'Source\Ref.Formulare.Suchrahmen.pas' {Suchrahmen: TFrame},
  Ref.Formulare.Haupt in 'Source\Ref.Formulare.Haupt.pas' {HauptFormular},
  Ref.Sprache.Merkmale in 'Source\Ref.Sprache.Merkmale.pas',
  Ref.Daten.Suche in 'Source\Ref.Daten.Suche.pas',
  Ref.Pruefung.Verstoesse in 'Source\Ref.Pruefung.Verstoesse.pas',
  Ref.Daten.Auftraege in 'Source\Ref.Daten.Auftraege.pas',
  Ref.Daten.Verwendung in 'Source\Ref.Daten.Verwendung.pas',
  Ref.Daten.Kunden in 'Source\Ref.Daten.Kunden.pas',
  Ref.Pruefung.Datenbank in 'Source\Ref.Pruefung.Datenbank.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(THauptFormular, HauptFormular);
  Application.CreateForm(TDetailFormular, DetailFormular);
  Application.Run;
end.
