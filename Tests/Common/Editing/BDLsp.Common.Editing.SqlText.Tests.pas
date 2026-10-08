unit BDLsp.Common.Editing.SqlText.Tests;

// Tests für den SQL-Text der Datenbank-Schnellbefehle (#302).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSqlTextTests = class
  public
    [Test]
    procedure ParamsInOrder;
    [Test]
    procedure LayoutBreaksBeforeClauses;
    [Test]
    procedure SqlFromSource;
    [Test]
    procedure SqlFromForm;
    [Test]
    procedure AssignedAndMissing;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Editing.SqlText;

function Joined(const AItems: TArray<string>): string;
begin
  Result := string.Join('|', AItems);
end;

procedure TSqlTextTests.ParamsInOrder;
begin
  Assert.AreEqual('Nr|Name', Joined(TSqlText.Params(
    'select * from Kunde where Nr = :Nr and Name = :Name or Nr = :nr')));
  // Nicht in Strings, Kommentaren und bei ::.
  Assert.AreEqual('A', Joined(TSqlText.Params('select '':X'', a::int, "b:c" from T -- :Y'#10'where A = :A')));
end;

procedure TSqlTextTests.LayoutBreaksBeforeClauses;
begin
  Assert.AreEqual('select * from T', Joined(TSqlText.Layout('select * from T', 80)));
  Assert.AreEqual('select K.Nr, A.Datum|from Kunde K|left outer join Auftrag A on A.Kunde = K.Nr|' +
    'where K.Ort = ''Bad Oldesloe''|and A.Datum > :Ab|order by A.Datum', Joined(TSqlText.Layout(
    'select K.Nr, A.Datum from Kunde K left outer join Auftrag A on A.Kunde = K.Nr ' +
    'where K.Ort = ''Bad Oldesloe'' and A.Datum > :Ab order by A.Datum', 40)));
end;

procedure TSqlTextTests.SqlFromSource;
const
  Source = 'begin'#10 +
    '  Q.SQL.Text := ''select * from T'' + sLineBreak + ''where A = :A'';'#10 +
    '  DM.Q.SQL.Text := ''falsch'';'#10 +
    '  Q2.SQL.Clear;'#10 +
    '  Q2.SQL.Add(''select 1'');'#10 +
    '  Q2.SQL.Add(''from T where B = :B'');'#10 +
    'end;';
begin
  Assert.AreEqual('select * from T'#13#10'where A = :A', TSqlText.FromSource(Source, 'Q'));
  Assert.AreEqual('falsch', TSqlText.FromSource(Source, 'DM.Q'));
  Assert.AreEqual('select 1'#13#10'from T where B = :B', TSqlText.FromSource(Source, 'q2'));
  Assert.AreEqual('', TSqlText.FromSource(Source, 'Q3'));
end;

procedure TSqlTextTests.SqlFromForm;
const
  Form = 'object DM: TDM'#13#10 +
    '  object Q: TFDQuery'#13#10 +
    '    SQL.Strings = ('#13#10 +
    '      ''select * from T'''#13#10 +
    '      ''where A = :A and B = '' +'#13#10 +
    '      '':B'')'#13#10 +
    '  end'#13#10 +
    'end'#13#10;
begin
  Assert.AreEqual('select * from T'#13#10'where A = :A and B = :B', TSqlText.FromForm(Form, 'DM.Q'));
  Assert.AreEqual('', TSqlText.FromForm(Form, 'Fehlt'));
end;

procedure TSqlTextTests.AssignedAndMissing;
const
  Source = 'begin'#10 +
    '  Q.ParamByName(''A'').AsInteger := 1;'#10 +
    '  Q.Params.ParamByName(''b'').Value := 2;'#10 +
    '  Ado.Parameters.ParamByName(''C'').Value := 3;'#10 +
    '  Q2.ParamByName(''X'').Value := 4;'#10 +
    'end;';
begin
  Assert.AreEqual('A|b', Joined(TSqlText.AssignedParams(Source, 'Q')));
  Assert.AreEqual('C', Joined(TSqlText.AssignedParams(Source, 'Ado')));
  Assert.AreEqual('C', Joined(TSqlText.Missing(['A', 'B', 'C'], TSqlText.AssignedParams(Source, 'Q'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TSqlTextTests);

end.
