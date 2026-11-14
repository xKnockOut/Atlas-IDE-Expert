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
  cSystemFile = 'C:\P\System.pas';
  cBasisFile = 'C:\P\Basis.pas';
  cHauptFile = 'C:\P\Haupt.pas';

  cUnitSystem =
    'unit System;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TObject = class'#10 +
    '  end;'#10 +
    '  IInterface = interface'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  cUnitBasis =
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

  cUnitHaupt =
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
  mIndex, mRun, mLine, mLineStart: Integer;
begin
  mIndex := Pos(AMarker, AText);
  if mIndex = 0 then
  begin
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  end;
  mLine := 0;
  mLineStart := 1;
  for mRun := 1 to mIndex - 1 do
  begin
    if AText[mRun] = #10 then
    begin
      Inc(mLine);
      mLineStart := mRun + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, cBasisFile) then
  begin
    AText := cUnitBasis;
  end
  else if SameText(AFileName, cSystemFile) then
  begin
    AText := cUnitSystem;
  end
  else if SameText(AFileName, cHauptFile) then
  begin
    AText := cUnitHaupt;
  end
  else
  begin
    Result := False;
  end;
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
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitSystem, cSystemFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBasis, cBasisFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspHoverTypesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspHoverTypesTests.InfoAt(const AMarker: string): THoverInfo;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(cUnitHaupt);
  try
    Result := TLspHover.InfoAt(THoverSource.Create(FResolver, FIndex, ReadText), mTree, cUnitHaupt, cHauptFile,
      PositionOf(cUnitHaupt, AMarker));
  finally
    mTree.Free;
  end;
end;

procedure TLspHoverTypesTests.ClassShowsKindLocationAndChain;
var
  mInfo: THoverInfo;
begin
  mInfo := InfoAt('TBlatt;');
  Assert.AreEqual('TBlatt = class(TMitte)', mInfo.Declaration);
  Assert.AreEqual('class', mInfo.Kind);
  Assert.AreEqual('', mInfo.Origin, 'eigene Unit');
  Assert.AreEqual(cBasisFile, mInfo.FileName);
  Assert.AreEqual(7, mInfo.Line);
  Assert.AreEqual(2, mInfo.Character);
  Assert.AreEqual('TBlatt', mInfo.ChainOf);
  Assert.AreEqual(4, Integer(Length(mInfo.Ancestors)));
  Assert.AreEqual('TBlatt', mInfo.Ancestors[0].Name);
  Assert.AreEqual('TMitte', mInfo.Ancestors[1].Name);
  Assert.AreEqual(5, mInfo.Ancestors[1].Line);
  Assert.AreEqual('TBasis', mInfo.Ancestors[2].Name);
  Assert.AreEqual('TObject', mInfo.Ancestors[3].Name);
  Assert.AreEqual(cSystemFile, mInfo.Ancestors[3].FileName);
end;

procedure TLspHoverTypesTests.DeclarationLinksTypes;
var
  mInfo: THoverInfo;
begin
  mInfo := InfoAt('TBlatt;');
  // Der eigene Name ist kein Link, der Vorfahr schon.
  Assert.AreEqual(1, Integer(Length(mInfo.Links)));
  Assert.AreEqual(Pos('TMitte', mInfo.Declaration) - 1, mInfo.Links[0].Start);
  Assert.AreEqual(6, mInfo.Links[0].Length);
  Assert.AreEqual('TMitte', mInfo.Links[0].Target.Name);
  Assert.AreEqual(cBasisFile, mInfo.Links[0].Target.FileName);
  Assert.AreEqual(5, mInfo.Links[0].Target.Line);
  Assert.AreEqual(2, mInfo.Links[0].Target.Character);
end;

procedure TLspHoverTypesTests.ClassReferenceShowsTargetChain;
var
  mInfo: THoverInfo;
begin
  mInfo := InfoAt('TBlattKlasse;');
  Assert.AreEqual('TBlattKlasse = class of TBlatt;', mInfo.Declaration);
  Assert.AreEqual(TLspHoverTypes.cKindClassRef, mInfo.Kind);
  Assert.AreEqual('TBlatt', mInfo.ChainOf);
  Assert.AreEqual('TBlatt', mInfo.Ancestors[0].Name);
  Assert.AreEqual('TObject', mInfo.Ancestors[High(mInfo.Ancestors)].Name);
  Assert.AreEqual(1, Integer(Length(mInfo.Links)));
  Assert.AreEqual('TBlatt', mInfo.Links[0].Target.Name);
end;

procedure TLspHoverTypesTests.InterfaceChainEndsAtIInterface;
var
  mInfo: THoverInfo;
begin
  mInfo := InfoAt('IFoo;');
  Assert.AreEqual('interface', mInfo.Kind);
  Assert.AreEqual(2, Integer(Length(mInfo.Ancestors)));
  Assert.AreEqual('IInterface', mInfo.Ancestors[1].Name);
end;

procedure TLspHoverTypesTests.LocalVariableLinksItsType;
var
  mInfo: THoverInfo;
begin
  // Haupt steht nicht im Index: Fundort und Links trotzdem aus dem Baum der eigenen Datei.
  mInfo := InfoAt('B :=');
  Assert.AreEqual('B: TBlatt;', mInfo.Declaration);
  Assert.AreEqual(cHauptFile, mInfo.FileName);
  Assert.AreEqual(1, Integer(Length(mInfo.Links)));
  Assert.AreEqual(3, mInfo.Links[0].Start);
  Assert.AreEqual('TBlatt', mInfo.Links[0].Target.Name);
  Assert.AreEqual(0, Integer(Length(mInfo.Ancestors)), 'Variablen haben keine Kette');
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
  mJson: TJSONObject;
  mLinks, mAncestors: TJSONArray;
begin
  mJson := TLspHover.AtlasJson(InfoAt('TBlatt;'));
  try
    Assert.AreEqual('class', mJson.GetValue<string>('kind'));
    Assert.AreEqual(cBasisFile, mJson.GetValue<string>('file'));
    Assert.AreEqual(7, mJson.GetValue<Integer>('line'));
    Assert.AreEqual(2, mJson.GetValue<Integer>('character'));
    Assert.IsNull(mJson.GetValue('origin'), 'leer entfällt');
    mLinks := mJson.GetValue<TJSONArray>('links');
    Assert.AreEqual(1, Integer(mLinks.Count));
    Assert.AreEqual('TMitte', mLinks.Items[0].GetValue<string>('name'));
    Assert.AreEqual(Pos('TMitte', 'TBlatt = class(TMitte)') - 1, mLinks.Items[0].GetValue<Integer>('start'));
    Assert.AreEqual(6, mLinks.Items[0].GetValue<Integer>('length'));
    Assert.AreEqual(5, mLinks.Items[0].GetValue<Integer>('line'));
    Assert.AreEqual('TBlatt', mJson.GetValue<string>('chainOf'));
    mAncestors := mJson.GetValue<TJSONArray>('ancestors');
    Assert.AreEqual(4, Integer(mAncestors.Count));
    Assert.AreEqual('TObject', mAncestors.Items[3].GetValue<string>('name'));
    Assert.AreEqual('System', mAncestors.Items[3].GetValue<string>('unit'));
  finally
    mJson.Free;
  end;
end;

procedure TLspHoverTypesTests.HoverReadsFilesThatAreNotOpen;
var
  mHover: TLspHover;
  mStore: IDocumentStore;
  mDispatcher: TJsonRpcDispatcher;
  mMessage, mResponse: TJSONObject;
  mRequest: string;
begin
  mStore := TDocumentStore.Create;
  mHover := TLspHover.Create(mStore, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadText(AFileName, AText);
    end);
  try
    mDispatcher := TJsonRpcDispatcher.Create;
    try
      mHover.Attach(mDispatcher);
      // TMitte in Basis.pas (Zeile 5, Spalte 2), ohne didOpen: so fragt das Plugin einen angeklickten Typ ab.
      mRequest := '{"jsonrpc": "2.0", "id": 1, "method": "textDocument/hover", "params": {"textDocument": ' +
        '{"uri": "' + TDocumentUris.FromPath(cBasisFile) + '"}, "position": {"line": 5, "character": 2}}}';
      mMessage := TJSONObject.ParseJSONValue(mRequest) as TJSONObject;
      try
        mResponse := mDispatcher.DispatchMessage(mMessage);
        try
          Assert.IsNotNull(mResponse);
          Assert.AreEqual('TMitte = class(TBasis)', mResponse.GetValue<string>('result.atlas.declaration'));
          Assert.AreEqual('TMitte', mResponse.GetValue<string>('result.atlas.chainOf'));
          Assert.AreEqual(3, mResponse.GetValue<TJSONArray>('result.atlas.ancestors').Count);
        finally
          mResponse.Free;
        end;
      finally
        mMessage.Free;
      end;
    finally
      mDispatcher.Free;
    end;
  finally
    mHover.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspHoverTypesTests);

end.
