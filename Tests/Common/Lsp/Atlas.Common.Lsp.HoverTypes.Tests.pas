unit Atlas.Common.Lsp.HoverTypes.Tests;

// Tests für Typverweise, Vererbungskette, Art und Herkunft im Hover (#588) und
// für den Hover auf nicht geöffnete Dateien.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Hover;

type
  [TestFixture]
  TLspHoverTypesTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function InfoAt(const AMarker: string): THoverInfo;
  public
    /// <summary>Ein Hover vorab; einmalig angelegte Daten zählen sonst als Leck des ersten Tests.</summary>
    [SetupFixture]
    procedure WarmUp;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ClassShowsKindLocationAndChain;
    [Test]
    procedure DeclarationLinksTypes;
    [Test]
    procedure ClassReferenceShowsTargetChain;
    [Test]
    procedure InterfaceChainEndsAtIInterface;
    [Test]
    procedure LocalVariableLinksItsType;
    [Test]
    procedure OriginOfLibraryUnits;
    [Test]
    procedure AtlasJsonCarriesLinksAndChain;
    [Test]
    procedure HoverReadsFilesThatAreNotOpen;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.HoverTypes;

const
  SystemFile = 'C:\P\System.pas';
  BasisFile = 'C:\P\Basis.pas';
  HauptFile = 'C:\P\Haupt.pas';

  UnitSystem =
    'unit System;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TObject = class'#10 +
    '  end;'#10 +
    '  IInterface = interface'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  UnitBasis =
    'unit Basis;'#10 +                         // 0
    'interface'#10 +                           // 1
    'type'#10 +                                // 2
    '  TBasis = class'#10 +                    // 3
    '  end;'#10 +                              // 4
    '  TMitte = class(TBasis)'#10 +            // 5
    '  end;'#10 +                              // 6
    '  TBlatt = class(TMitte)'#10 +            // 7
    '    Teil: TMitte;'#10 +                   // 8
    '  end;'#10 +                              // 9
    '  TBlattKlasse = class of TBlatt;'#10 +   // 10
    '  IFoo = interface'#10 +                  // 11
    '  end;'#10 +                              // 12
    'implementation'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'implementation'#10 +
    'procedure Lauf;'#10 +
    'var'#10 +
    '  B: TBlatt;'#10 +
    '  K: TBlattKlasse;'#10 +
    '  F: IFoo;'#10 +
    'begin'#10 +
    '  B := nil;'#10 +
    '  K := nil;'#10 +
    '  F := nil;'#10 +
    'end;'#10 +
    'end.';

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  Index, Run, Line, LineStart: Integer;
begin
  Index := Pos(AMarker, AText);
  if Index = 0 then
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  Line := 0;
  LineStart := 1;
  for Run := 1 to Index - 1 do
    if AText[Run] = #10 then
    begin
      Inc(Line);
      LineStart := Run + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, BasisFile) then
    AText := UnitBasis
  else if SameText(AFileName, SystemFile) then
    AText := UnitSystem
  else if SameText(AFileName, HauptFile) then
    AText := UnitHaupt
  else
    Result := False;
end;

{ TLspHoverTypesTests }

procedure TLspHoverTypesTests.WarmUp;
begin
  Setup;
  try
    InfoAt('B :=');
    InfoAt('TBlatt;');
  finally
    TearDown;
  end;
  Setup;
  try
    HoverReadsFilesThatAreNotOpen;
  finally
    TearDown;
  end;
end;

procedure TLspHoverTypesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitSystem, SystemFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, BasisFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspHoverTypesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspHoverTypesTests.InfoAt(const AMarker: string): THoverInfo;
var
  Tree: TSyntaxTree;
begin
  Tree := TSyntaxTreeCache.Parse(UnitHaupt);
  try
    Result := TLspHover.InfoAt(FResolver, FIndex, Tree, UnitHaupt, HauptFile, PositionOf(UnitHaupt, AMarker),
      ReadText);
  finally
    Tree.Free;
  end;
end;

procedure TLspHoverTypesTests.ClassShowsKindLocationAndChain;
var
  Info: THoverInfo;
begin
  Info := InfoAt('TBlatt;');
  Assert.AreEqual('TBlatt = class(TMitte)', Info.Declaration);
  Assert.AreEqual('class', Info.Kind);
  Assert.AreEqual('', Info.Origin, 'eigene Unit');
  Assert.AreEqual(BasisFile, Info.FileName);
  Assert.AreEqual(7, Info.Line);
  Assert.AreEqual(2, Info.Character);
  Assert.AreEqual('TBlatt', Info.ChainOf);
  Assert.AreEqual(4, Integer(Length(Info.Ancestors)));
  Assert.AreEqual('TBlatt', Info.Ancestors[0].Name);
  Assert.AreEqual('TMitte', Info.Ancestors[1].Name);
  Assert.AreEqual(5, Info.Ancestors[1].Line);
  Assert.AreEqual('TBasis', Info.Ancestors[2].Name);
  Assert.AreEqual('TObject', Info.Ancestors[3].Name);
  Assert.AreEqual(SystemFile, Info.Ancestors[3].FileName);
end;

procedure TLspHoverTypesTests.DeclarationLinksTypes;
var
  Info: THoverInfo;
begin
  Info := InfoAt('TBlatt;');
  // Der eigene Name ist kein Link, der Vorfahr schon.
  Assert.AreEqual(1, Integer(Length(Info.Links)));
  Assert.AreEqual(Pos('TMitte', Info.Declaration) - 1, Info.Links[0].Start);
  Assert.AreEqual(6, Info.Links[0].Length);
  Assert.AreEqual('TMitte', Info.Links[0].Target.Name);
  Assert.AreEqual(BasisFile, Info.Links[0].Target.FileName);
  Assert.AreEqual(5, Info.Links[0].Target.Line);
  Assert.AreEqual(2, Info.Links[0].Target.Character);
end;

procedure TLspHoverTypesTests.ClassReferenceShowsTargetChain;
var
  Info: THoverInfo;
begin
  Info := InfoAt('TBlattKlasse;');
  Assert.AreEqual('TBlattKlasse = class of TBlatt;', Info.Declaration);
  Assert.AreEqual(TLspHoverTypes.KindClassRef, Info.Kind);
  Assert.AreEqual('TBlatt', Info.ChainOf);
  Assert.AreEqual('TBlatt', Info.Ancestors[0].Name);
  Assert.AreEqual('TObject', Info.Ancestors[High(Info.Ancestors)].Name);
  Assert.AreEqual(1, Integer(Length(Info.Links)));
  Assert.AreEqual('TBlatt', Info.Links[0].Target.Name);
end;

procedure TLspHoverTypesTests.InterfaceChainEndsAtIInterface;
var
  Info: THoverInfo;
begin
  Info := InfoAt('IFoo;');
  Assert.AreEqual('interface', Info.Kind);
  Assert.AreEqual(2, Integer(Length(Info.Ancestors)));
  Assert.AreEqual('IInterface', Info.Ancestors[1].Name);
end;

procedure TLspHoverTypesTests.LocalVariableLinksItsType;
var
  Info: THoverInfo;
begin
  // Haupt steht nicht im Index: Fundort und Links trotzdem aus dem Baum der eigenen Datei.
  Info := InfoAt('B :=');
  Assert.AreEqual('B: TBlatt;', Info.Declaration);
  Assert.AreEqual(HauptFile, Info.FileName);
  Assert.AreEqual(1, Integer(Length(Info.Links)));
  Assert.AreEqual(3, Info.Links[0].Start);
  Assert.AreEqual('TBlatt', Info.Links[0].Target.Name);
  Assert.AreEqual(0, Integer(Length(Info.Ancestors)), 'Variablen haben keine Kette');
end;

procedure TLspHoverTypesTests.OriginOfLibraryUnits;
begin
  Assert.AreEqual('VCL', TLspHoverTypes.Origin('Vcl.Forms'));
  Assert.AreEqual('FMX', TLspHoverTypes.Origin('FMX.Forms'));
  Assert.AreEqual('RTL', TLspHoverTypes.Origin('System.Classes'));
  Assert.AreEqual('RTL', TLspHoverTypes.Origin('System'));
  Assert.AreEqual('', TLspHoverTypes.Origin('Basis'));
  Assert.AreEqual('TBlatt', TLspHoverTypes.ClassRefTarget('TBlattKlasse = class of TBlatt;'));
  Assert.AreEqual('', TLspHoverTypes.ClassRefTarget('TBlatt = class(TMitte)'));
end;

procedure TLspHoverTypesTests.AtlasJsonCarriesLinksAndChain;
var
  Json: TJSONObject;
  Links, Ancestors: TJSONArray;
begin
  Json := TLspHover.AtlasJson(InfoAt('TBlatt;'));
  try
    Assert.AreEqual('class', Json.GetValue<string>('kind'));
    Assert.AreEqual(BasisFile, Json.GetValue<string>('file'));
    Assert.AreEqual(7, Json.GetValue<Integer>('line'));
    Assert.AreEqual(2, Json.GetValue<Integer>('character'));
    Assert.IsNull(Json.GetValue('origin'), 'leer entfällt');
    Links := Json.GetValue<TJSONArray>('links');
    Assert.AreEqual(1, Integer(Links.Count));
    Assert.AreEqual('TMitte', Links.Items[0].GetValue<string>('name'));
    Assert.AreEqual(Pos('TMitte', 'TBlatt = class(TMitte)') - 1, Links.Items[0].GetValue<Integer>('start'));
    Assert.AreEqual(6, Links.Items[0].GetValue<Integer>('length'));
    Assert.AreEqual(5, Links.Items[0].GetValue<Integer>('line'));
    Assert.AreEqual('TBlatt', Json.GetValue<string>('chainOf'));
    Ancestors := Json.GetValue<TJSONArray>('ancestors');
    Assert.AreEqual(4, Integer(Ancestors.Count));
    Assert.AreEqual('TObject', Ancestors.Items[3].GetValue<string>('name'));
    Assert.AreEqual('System', Ancestors.Items[3].GetValue<string>('unit'));
  finally
    Json.Free;
  end;
end;

procedure TLspHoverTypesTests.HoverReadsFilesThatAreNotOpen;
var
  Hover: TLspHover;
  Store: IDocumentStore;
  Dispatcher: TJsonRpcDispatcher;
  Message, Response: TJSONObject;
  Request: string;
begin
  Store := TDocumentStore.Create;
  Hover := TLspHover.Create(Store, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadText(AFileName, AText);
    end);
  try
    Dispatcher := TJsonRpcDispatcher.Create;
    try
      Hover.Attach(Dispatcher);
      // TMitte in Basis.pas (Zeile 5, Spalte 2), ohne didOpen: so fragt das Plugin einen angeklickten Typ ab.
      Request := '{"jsonrpc": "2.0", "id": 1, "method": "textDocument/hover", "params": {"textDocument": ' +
        '{"uri": "' + TDocumentUris.FromPath(BasisFile) + '"}, "position": {"line": 5, "character": 2}}}';
      Message := TJSONObject.ParseJSONValue(Request) as TJSONObject;
      try
        Response := Dispatcher.DispatchMessage(Message);
        try
          Assert.IsNotNull(Response);
          Assert.AreEqual('TMitte = class(TBasis)', Response.GetValue<string>('result.atlas.declaration'));
          Assert.AreEqual('TMitte', Response.GetValue<string>('result.atlas.chainOf'));
          Assert.AreEqual(3, Response.GetValue<TJSONArray>('result.atlas.ancestors').Count);
        finally
          Response.Free;
        end;
      finally
        Message.Free;
      end;
    finally
      Dispatcher.Free;
    end;
  finally
    Hover.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspHoverTypesTests);

end.
