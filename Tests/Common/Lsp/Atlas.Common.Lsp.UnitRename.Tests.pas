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
  begin
    Result := 'unit KundenDaten;'#10'interface'#10'type'#10'  TKunde = class'#10'  end;'#10'implementation'#10'end.'#10;
  end
  else if SameText(AFileName, 'C:\P\A.pas') then
  begin
    Result := 'unit A;'#10'interface'#10'uses Kunden;'#10'implementation'#10'end.'#10;
  end
  else if SameText(AFileName, 'C:\P\B.pas') then
  begin
    Result := 'unit B;'#10'interface'#10'implementation'#10'uses Kunden;'#10'var'#10'  K: Kunden.TKunde;'#10'end.'#10;
  end
  else if SameText(AFileName, 'C:\P\C.pas') then
  begin
    Result := 'unit C;'#10'interface'#10'uses'#10'  System.Classes,'#10'  Kunden;'#10'implementation'#10'end.'#10;
  end
  else if SameText(AFileName, 'C:\P\D.pas') then
  begin
    Result := 'unit D;'#10'interface'#10'implementation'#10'end.'#10;
  end;
end;

procedure TLspUnitRenameTests.AdjustsUsingUnits;
var
  mAnswer: TJSONObject;
  mChanges: TJSONArray;
  mIndex: Integer;
  mUris: string;
begin
  mAnswer := TLspUnitRename.Execute('C:\P\Kunden.pas', 'C:\P\KundenDaten.pas', ['C:\P\KundenDaten.pas',
    'C:\P\A.pas', 'C:\P\B.pas', 'C:\P\C.pas', 'C:\P\D.pas'],
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := TextOf(AFileName);
      Result := AText <> '';
    end);
  try
    Assert.AreEqual(3, (mAnswer.GetValue('count') as TJSONNumber).AsInt);
    Assert.AreEqual('Kunden', mAnswer.GetValue('old').Value);
    mChanges := (mAnswer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray;
    mUris := '';
    for mIndex := 0 to mChanges.Count - 1 do
    begin
      mUris := mUris + ExtractFileName(TDocumentUris.ToPath((((mChanges.Items[mIndex] as TJSONObject).GetValue(
        'textDocument')) as TJSONObject).GetValue('uri').Value)) + '|';
    end;
    Assert.AreEqual('A.pas|B.pas|C.pas|', mUris);
    // B: uses und der qualifizierte Typ.
    Assert.AreEqual(2, ((mChanges.Items[1] as TJSONObject).GetValue('edits') as TJSONArray).Count);
  finally
    mAnswer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspUnitRenameTests);

end.
