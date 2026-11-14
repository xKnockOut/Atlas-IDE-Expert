unit Atlas.Common.Lsp.EnumValueCommands.Tests;

// Tests für atlas.server.enumValues (#671): Werte eines Aufzählungstyps aus
// einer anderen Unit, mit {$SCOPEDENUMS ON}, leer ohne Aufzählungswert.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEnumValueCommandsTests = class
  public
    [Test]
    procedure ValuesFromOtherUnit;
    [Test]
    procedure ScopedValues;
    [Test]
    procedure EmptyWithoutEnumValue;
    [Test]
    procedure RejectsBadArguments;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.EnumValueCommands;

const
  cTypenFile = 'C:\P\Typen.pas';
  cMainFile = 'C:\P\Haupt.pas';
  cUnitTypen =
    'unit Typen;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TAmpel = (Rot, Gelb,'#10 +
    '    Gruen);'#10 +
    '{$SCOPEDENUMS ON}'#10 +
    '  TForm = (Kreis, Quadrat);'#10 +
    '{$SCOPEDENUMS OFF}'#10 +
    'procedure Zeige(A: TAmpel);'#10 +
    'procedure Male(F: TForm);'#10 +
    'implementation'#10 +
    'procedure Zeige(A: TAmpel);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Male(F: TForm);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
  cUnitMain =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Typen;'#10 +
    'procedure Lauf;'#10 +
    'begin'#10 +
    '  Zeige(Rot);'#10 +
    '  Zeige(Gelb);'#10 +
    '  Male(TForm.Kreis);'#10 +
    'end;'#10 +
    'end.';

/// <summary>Werte an Zeile ALine, Zeichen ACharacter von UnitMain, mit Leerzeichen verbunden.</summary>
function ValuesAt(ALine, ACharacter: Integer): string;
var
  mStore: IDocumentStore;
  mIndex: ISymbolIndex;
  mArguments: TJSONArray;
  mPosition: TJSONObject;
  mAnswer: TJSONValue;
  mItem: TJSONValue;
begin
  mStore := TDocumentStore.Create;
  mStore.Open(TDocumentUris.FromPath(cMainFile), 'delphi', 1, cUnitMain);
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitTypen, cTypenFile, nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitMain, cMainFile, nil));
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(TDocumentUris.FromPath(cMainFile));
    mPosition := TJSONObject.Create;
    mPosition.AddPair('line', TJSONNumber.Create(ALine));
    mPosition.AddPair('character', TJSONNumber.Create(ACharacter));
    mArguments.AddElement(mPosition);
    mAnswer := TEnumValueCommands.Execute(mStore, mIndex, nil, nil,
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := cUnitTypen;
        Result := SameText(AFileName, cTypenFile);
      end, mArguments);
    try
      Result := '';
      for mItem in mAnswer as TJSONArray do
      begin
        Result := Trim(Result + ' ' + mItem.Value);
      end;
    finally
      mAnswer.Free;
    end;
  finally
    mArguments.Free;
  end;
end;

{ TEnumValueCommandsTests }

procedure TEnumValueCommandsTests.ValuesFromOtherUnit;
begin
  Assert.AreEqual('Rot Gelb Gruen', ValuesAt(7, 9));
end;

procedure TEnumValueCommandsTests.ScopedValues;
begin
  Assert.AreEqual('Kreis Quadrat', ValuesAt(8, 14));
end;

procedure TEnumValueCommandsTests.EmptyWithoutEnumValue;
begin
  Assert.AreEqual('', ValuesAt(7, 3));
end;

procedure TEnumValueCommandsTests.RejectsBadArguments;
begin
  Assert.WillRaise(
    procedure
    var
      Arguments: TJSONArray;
      Store: IDocumentStore;
      Index: ISymbolIndex;
    begin
      // Erst in Interface-Variablen: Ein Konstruktor direkt am const-Parameter würde nie freigegeben.
      Store := TDocumentStore.Create;
      Index := TSymbolIndex.Create;
      Arguments := TJSONArray.Create;
      try
        Arguments.Add('file:///C:/P/Fehlt.pas');
        TEnumValueCommands.Execute(Store, Index, nil, nil, nil, Arguments).Free;
      finally
        Arguments.Free;
      end;
    end, EJsonRpcError);
end;

initialization
  TDUnitX.RegisterTestFixture(TEnumValueCommandsTests);

end.
