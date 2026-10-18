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
  TypenFile = 'C:\P\Typen.pas';
  MainFile = 'C:\P\Haupt.pas';
  UnitTypen =
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
  UnitMain =
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
  Store: IDocumentStore;
  Index: ISymbolIndex;
  Arguments: TJSONArray;
  Position: TJSONObject;
  Answer: TJSONValue;
  Item: TJSONValue;
begin
  Store := TDocumentStore.Create;
  Store.Open(TDocumentUris.FromPath(MainFile), 'delphi', 1, UnitMain);
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(UnitTypen, TypenFile, nil));
  Index.AddUnit(TIndexExtractor.ExtractText(UnitMain, MainFile, nil));
  Arguments := TJSONArray.Create;
  try
    Arguments.Add(TDocumentUris.FromPath(MainFile));
    Position := TJSONObject.Create;
    Position.AddPair('line', TJSONNumber.Create(ALine));
    Position.AddPair('character', TJSONNumber.Create(ACharacter));
    Arguments.AddElement(Position);
    Answer := TEnumValueCommands.Execute(Store, Index, nil, nil,
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := UnitTypen;
        Result := SameText(AFileName, TypenFile);
      end, Arguments);
    try
      Result := '';
      for Item in Answer as TJSONArray do
        Result := Trim(Result + ' ' + Item.Value);
    finally
      Answer.Free;
    end;
  finally
    Arguments.Free;
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
    begin
      Arguments := TJSONArray.Create;
      try
        Arguments.Add('file:///C:/P/Fehlt.pas');
        TEnumValueCommands.Execute(TDocumentStore.Create, TSymbolIndex.Create, nil, nil, nil, Arguments).Free;
      finally
        Arguments.Free;
      end;
    end, EJsonRpcError);
end;

initialization
  TDUnitX.RegisterTestFixture(TEnumValueCommandsTests);

end.
