unit Atlas.Common.Lsp.UnitRename.Tests;

// Tests für atlas.server.unitRenamed (#512): drei Units passen sich an, die
// umbenannte Datei und Dateien ohne Verwendung bleiben außen vor.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspUnitRenameTests = class
  public
    [Test]
    procedure AdjustsUsingUnits;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.UnitRename;

function TextOf(const AFileName: string): string;
begin
  Result := '';
  if SameText(AFileName, 'C:\P\KundenDaten.pas') then
    Result := 'unit KundenDaten;'#10'interface'#10'type'#10'  TKunde = class'#10'  end;'#10'implementation'#10'end.'#10
  else if SameText(AFileName, 'C:\P\A.pas') then
    Result := 'unit A;'#10'interface'#10'uses Kunden;'#10'implementation'#10'end.'#10
  else if SameText(AFileName, 'C:\P\B.pas') then
    Result := 'unit B;'#10'interface'#10'implementation'#10'uses Kunden;'#10'var'#10'  K: Kunden.TKunde;'#10'end.'#10
  else if SameText(AFileName, 'C:\P\C.pas') then
    Result := 'unit C;'#10'interface'#10'uses'#10'  System.Classes,'#10'  Kunden;'#10'implementation'#10'end.'#10
  else if SameText(AFileName, 'C:\P\D.pas') then
    Result := 'unit D;'#10'interface'#10'implementation'#10'end.'#10;
end;

procedure TLspUnitRenameTests.AdjustsUsingUnits;
var
  Answer: TJSONObject;
  Changes: TJSONArray;
  Index: Integer;
  Uris: string;
begin
  Answer := TLspUnitRename.Execute('C:\P\Kunden.pas', 'C:\P\KundenDaten.pas', ['C:\P\KundenDaten.pas',
    'C:\P\A.pas', 'C:\P\B.pas', 'C:\P\C.pas', 'C:\P\D.pas'],
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := TextOf(AFileName);
      Result := AText <> '';
    end);
  try
    Assert.AreEqual(3, (Answer.GetValue('count') as TJSONNumber).AsInt);
    Assert.AreEqual('Kunden', Answer.GetValue('old').Value);
    Changes := (Answer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray;
    Uris := '';
    for Index := 0 to Changes.Count - 1 do
      Uris := Uris + ExtractFileName(TDocumentUris.ToPath((((Changes.Items[Index] as TJSONObject).GetValue(
        'textDocument')) as TJSONObject).GetValue('uri').Value)) + '|';
    Assert.AreEqual('A.pas|B.pas|C.pas|', Uris);
    // B: uses und der qualifizierte Typ.
    Assert.AreEqual(2, ((Changes.Items[1] as TJSONObject).GetValue('edits') as TJSONArray).Count);
  finally
    Answer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspUnitRenameTests);

end.
