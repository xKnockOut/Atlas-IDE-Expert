unit Atlas.Core.Outline.Interfaces.Tests;

// Interface-Marke an Methodengliedern (#1785): Antwort lesen, Ziele je Knoten
// über Zeile und Namen, Text der Marke.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasOutlineInterfacesTests = class
  public
    [Test]
    procedure ReadsAnswer;
    [Test]
    procedure TargetsOfMethodDeclarationOnly;
    [Test]
    procedure MarkTextCountsMore;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.Interfaces;

const
  cCode =
    'unit Kunden;'#13#10 +                                          // 0
    'interface'#13#10 +                                             // 1
    'uses KundenApi;'#13#10 +                                       // 2
    'type'#13#10 +                                                  // 3
    '  TKunde = class(TInterfacedObject, IKunde)'#13#10 +           // 4
    '    procedure Speichern;'#13#10 +                              // 5
    '    procedure Hilfe;'#13#10 +                                  // 6
    '  end;'#13#10 +                                                // 7
    'implementation'#13#10 +                                        // 8
    'procedure TKunde.Speichern;'#13#10 +                           // 9
    'begin'#13#10 +                                                 // 10
    'end;'#13#10 +                                                  // 11
    'procedure TKunde.Hilfe;'#13#10 +                               // 12
    'begin'#13#10 +                                                 // 13
    'end;'#13#10 +                                                  // 14
    'end.';

  cAnswer =
    '{"methods": [{"line": 5, "name": "TKunde.Speichern", "interfaces": [' +
    '{"name": "IKunde.Speichern", "unit": "KundenApi", "uri": "file:///C:/P/KundenApi.pas", "line": 30, ' +
    '"character": 14},' +
    '{"name": "IDruck.Speichern", "unit": "DruckApi", "uri": "file:///C:/P/DruckApi.pas", "line": 7, ' +
    '"character": 14}]},' +
    '{"line": 6, "name": "TKunde.Hilfe", "interfaces": []}]}';

function Nodes: TAtlasOutlineNodes;
var
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
begin
  mTree := TPascalParser.Parse(cCode);
  try
    mSymbols := TLspDocumentSymbols.BuildSymbols(mTree, cCode);
  finally
    mTree.Free;
  end;
  try
    Result := TAtlasOutline.FromJson(mSymbols);
  finally
    mSymbols.Free;
  end;
end;

function Methods: TAtlasInterfaceMethods;
var
  mJson: TJSONValue;
begin
  mJson := TJSONObject.ParseJSONValue(cAnswer);
  try
    Result := TAtlasOutlineInterfaces.FromJson(mJson);
  finally
    mJson.Free;
  end;
end;

function NodeAt(const ANodes: TAtlasOutlineNodes; const AName: string; ALine: Integer): Integer;
begin
  for Result := 0 to High(ANodes) do
  begin
    if (ANodes[Result].Name = AName) and (ANodes[Result].NameLine = ALine) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

procedure TAtlasOutlineInterfacesTests.ReadsAnswer;
var
  mMethods: TAtlasInterfaceMethods;
begin
  mMethods := Methods;
  // Ohne Ziele fällt die Methode weg.
  Assert.AreEqual(1, Integer(Length(mMethods)));
  Assert.AreEqual(5, mMethods[0].Line);
  Assert.AreEqual(2, Integer(Length(mMethods[0].Targets)));
  Assert.AreEqual('IKunde', mMethods[0].Targets[0].InterfaceName);
  Assert.AreEqual('KundenApi', mMethods[0].Targets[0].UnitName);
  Assert.AreEqual(30, mMethods[0].Targets[0].Line);
  Assert.AreEqual('KundenApi.pas', ExtractFileName(mMethods[0].Targets[0].FileName));
  Assert.AreEqual(0, Integer(Length(TAtlasOutlineInterfaces.FromJson(nil))));
end;

procedure TAtlasOutlineInterfacesTests.TargetsOfMethodDeclarationOnly;
var
  mNodes: TAtlasOutlineNodes;
begin
  mNodes := Nodes;
  Assert.AreEqual(2, Integer(Length(TAtlasOutlineInterfaces.TargetsOf(Methods, mNodes,
    NodeAt(mNodes, 'Speichern', 5)))));
  Assert.AreEqual(0, Integer(Length(TAtlasOutlineInterfaces.TargetsOf(Methods, mNodes, NodeAt(mNodes, 'Hilfe', 6)))));
  Assert.AreEqual(0, Integer(Length(TAtlasOutlineInterfaces.TargetsOf(Methods, mNodes, NodeAt(mNodes, 'TKunde', 4)))));
  Assert.AreEqual(0, Integer(Length(TAtlasOutlineInterfaces.TargetsOf(Methods, mNodes, -1))));
end;

procedure TAtlasOutlineInterfacesTests.MarkTextCountsMore;
var
  mTargets: TAtlasInterfaceTargets;
begin
  mTargets := Methods[0].Targets;
  Assert.AreEqual('[IKunde +1]', TAtlasOutlineInterfaces.MarkText(mTargets));
  Assert.AreEqual('[IKunde]', TAtlasOutlineInterfaces.MarkText(Copy(mTargets, 0, 1)));
  Assert.AreEqual('', TAtlasOutlineInterfaces.MarkText(nil));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOutlineInterfacesTests);

end.
