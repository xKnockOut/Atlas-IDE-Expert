unit Atlas.Common.Lsp.MoveClass.Tests;

// Tests für „Klasse in eigene Unit verschieben“ über das Protokoll (#103 Teil
// B): Namensauflösung über den Index, WorkspaceEdit mit neuer Datei,
// Ursprungs-Unit, verwendender Unit, .dpr und .dproj; Angebot der Code-Aktion.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspMoveClassTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MovesOverTheProject;
    [Test]
    procedure OffersOnlyMovableClasses;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.MoveClass;

const
  cBasisFile = 'C:\P\Basis.pas';
  cHelferFile = 'C:\P\Helfer.pas';
  cLagerFile = 'C:\P\Lager.pas';
  cKasseFile = 'C:\P\Kasse.pas';
  cProgramFile = 'C:\P\Projekt.dpr';
  cProjectFile = 'C:\P\Projekt.dproj';

  cUnitBasis =
    'unit Basis;'#10'interface'#10'type'#10'  TItems = class'#10'  end;'#10 +
    'function Fmt(A: Integer): string;'#10'implementation'#10 +
    'function Fmt(A: Integer): string;'#10'begin'#10'  Result := '''';'#10'end;'#10'end.'#10;
  cUnitHelfer =
    'unit Helfer;'#10'interface'#10'procedure Log;'#10'implementation'#10'procedure Log;'#10'begin'#10'end;'#10 +
    'end.'#10;
  cUnitLager =
    'unit Lager;'#10 +                     // 0
    ''#10 +                                // 1
    'interface'#10 +                       // 2
    ''#10 +                                // 3
    'uses'#10 +                            // 4
    '  Basis;'#10 +                        // 5
    ''#10 +                                // 6
    'type'#10 +                            // 7
    '  TStock = class'#10 +                // 8
    '    FItems: TItems;'#10 +             // 9
    '    function Text: string;'#10 +      // 10
    '  end;'#10 +                          // 11
    ''#10 +                                // 12
    'implementation'#10 +                  // 13
    ''#10 +                                // 14
    'uses'#10 +                            // 15
    '  Helfer;'#10 +                       // 16
    ''#10 +                                // 17
    'function TStock.Text: string;'#10 +   // 18
    'begin'#10 +                           // 19
    '  Log;'#10 +                          // 20
    '  Result := Fmt(1);'#10 +             // 21
    'end;'#10 +                            // 22
    ''#10 +                                // 23
    'end.'#10;
  cUnitKasse =
    'unit Kasse;'#10'interface'#10'uses Lager;'#10'implementation'#10'procedure Run;'#10'var'#10 +
    '  S: TStock;'#10'begin'#10'  S := Lager.TStock.Create;'#10'end;'#10'end.'#10;
  cTextProgram =
    'program Projekt;'#10'uses'#10'  Lager in ''Lager.pas'','#10'  Kasse in ''Kasse.pas'';'#10'begin'#10'end.'#10;
  cTextProject =
    '<Project>'#10'  <ItemGroup>'#10'    <DelphiCompile Include="Projekt.dpr"/>'#10 +
    '    <DCCReference Include="Lager.pas"/>'#10'    <DCCReference Include="Kasse.pas"/>'#10'  </ItemGroup>'#10 +
    '</Project>'#10;

function TextOf(const AFileName: string): string;
begin
  if SameText(AFileName, cBasisFile) then
  begin
    Result := cUnitBasis;
  end
  else if SameText(AFileName, cHelferFile) then
  begin
    Result := cUnitHelfer;
  end
  else if SameText(AFileName, cLagerFile) then
  begin
    Result := cUnitLager;
  end
  else if SameText(AFileName, cKasseFile) then
  begin
    Result := cUnitKasse;
  end
  else if SameText(AFileName, cProgramFile) then
  begin
    Result := cTextProgram;
  end
  else if SameText(AFileName, cProjectFile) then
  begin
    Result := cTextProject;
  end
  else
  begin
    Result := '';
  end;
end;

function Context: TMoveClassContext;
begin
  Result := Default(TMoveClassContext);
  Result.HasProject := True;
  Result.Project.FileName := cProjectFile;
  Result.Project.MainSource := cProgramFile;
  Result.Files := [cBasisFile, cHelferFile, cLagerFile, cKasseFile, cProgramFile];
  Result.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := TextOf(AFileName);
      Result := AText <> '';
    end;
  Result.Exists :=
    function(const AFileName: string): Boolean
    begin
      Result := TextOf(AFileName) <> '';
    end;
end;

/// <summary>Wendet die Edits aus einem documentChanges-Eintrag auf AText an.</summary>
function Apply(const AText: string; ADocument: TJSONObject): string;
var
  mItem: TJSONValue;
  mEdits: TArray<TTextEdit>;
  mRange: TJSONObject;
begin
  mEdits := nil;
  for mItem in ADocument.GetValue('edits') as TJSONArray do
  begin
    mRange := TJSONObject(mItem).GetValue('range') as TJSONObject;
    mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(TLspPositions.ReadPosition(mRange.GetValue('start')),
      TLspPositions.ReadPosition(mRange.GetValue('end'))), TJSONObject(mItem).GetValue('newText').Value)];
  end;
  Result := TChangeSignature.ApplyEdits(AText, mEdits);
end;

procedure TLspMoveClassTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBasis, cBasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitHelfer, cHelferFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitLager, cLagerFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitKasse, cKasseFile, nil));
end;

procedure TLspMoveClassTests.TearDown;
begin
  FIndex := nil;
end;

/// <summary>Inhalt jeder geänderten Datei nach dem Verschieben von TStock.</summary>
procedure AssertMovedDocument(const AUri: string; const ADocument: TJSONObject);
begin
  if AUri = TDocumentUris.FromPath('C:\P\Stock.pas') then
  begin
    Assert.AreEqual('unit Stock;'#10#10'interface'#10#10'uses'#10'  Basis;'#10#10'type'#10'  TStock = class'#10 +
      '    FItems: TItems;'#10'    function Text: string;'#10'  end;'#10#10'implementation'#10#10'uses'#10 +
      '  Helfer;'#10#10'function TStock.Text: string;'#10'begin'#10'  Log;'#10'  Result := Fmt(1);'#10'end;'#10#10 +
      'end.'#10, Apply('', ADocument));
  end
  else if AUri = TDocumentUris.FromPath(cLagerFile) then
  begin
    Assert.AreEqual('unit Lager;'#10#10'interface'#10#10'uses'#10'  Basis;'#10#10'implementation'#10#10'uses'#10 +
      '  Helfer;'#10#10'end.'#10, Apply(cUnitLager, ADocument));
  end
  else if AUri = TDocumentUris.FromPath(cKasseFile) then
  begin
    Assert.AreEqual(StringReplace(StringReplace(cUnitKasse, 'uses Lager;', 'uses Lager, Stock;', []),
      'Lager.TStock', 'Stock.TStock', []), Apply(cUnitKasse, ADocument));
  end
  else if AUri = TDocumentUris.FromPath(cProgramFile) then
  begin
    Assert.Contains(Apply(cTextProgram, ADocument), 'Stock in ''Stock.pas''');
  end
  else if AUri = TDocumentUris.FromPath(cProjectFile) then
  begin
    Assert.Contains(Apply(cTextProject, ADocument), '<DCCReference Include="Stock.pas"/>');
  end;
end;

procedure TLspMoveClassTests.MovesOverTheProject;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mAnswer: TJSONObject;
  mChanges: TJSONArray;
  mItem: TJSONValue;
  mDocument: TJSONObject;
  mUri, mResults: string;
  mMoved: TMoveClassContext;
begin
  mTree := TPascalParser.Parse(cUnitLager);
  mResolver := TNameResolver.Create(FIndex, nil);
  mAnswer := nil;
  try
    mMoved := Context;
    mMoved.Index := FIndex;
    mMoved.UnitName := 'Stock';
    mAnswer := TLspMoveClass.Execute(mResolver, mTree, cLagerFile, cUnitLager, TTextPosition.Create(8, 4), mMoved);
    Assert.AreEqual(0, Integer((mAnswer.GetValue('warnings') as TJSONArray).Count), mAnswer.ToJSON);
    Assert.AreEqual(TDocumentUris.FromPath('C:\P\Stock.pas'), mAnswer.GetValue('file').Value);
    mChanges := (mAnswer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray;
    Assert.AreEqual('create', (mChanges.Items[0] as TJSONObject).GetValue('kind').Value);
    mResults := '';
    for mItem in mChanges do
    begin
      mDocument := TJSONObject(mItem);
      if mDocument.GetValue('textDocument') = nil then
      begin
        Continue;
      end;
      mUri := (mDocument.GetValue('textDocument') as TJSONObject).GetValue('uri').Value;
      mResults := mResults + ExtractFileName(TDocumentUris.ToPath(mUri)) + '|';
      AssertMovedDocument(mUri, mDocument);
    end;
    Assert.AreEqual('Stock.pas|Lager.pas|Kasse.pas|Projekt.dpr|Projekt.dproj|', mResults);
    // Gibt es die Datei schon, bricht der Befehl ab.
    mMoved.UnitName := 'Kasse';
    Assert.WillRaise(
      procedure
      begin
        TLspMoveClass.Execute(mResolver, mTree, cLagerFile, cUnitLager, TTextPosition.Create(8, 4), mMoved).Free;
      end);
  finally
    mAnswer.Free;
    mResolver.Free;
    mTree.Free;
  end;
end;

procedure TLspMoveClassTests.OffersOnlyMovableClasses;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mActions: TArray<TJSONObject>;
  mAction: TJSONObject;
  mText: string;
begin
  mResolver := TNameResolver.Create(FIndex, nil);
  mTree := TPascalParser.Parse(cUnitLager);
  try
    Assert.AreEqual(0, Integer(Length(TLspMoveClass.Actions(mResolver, mTree, cLagerFile, cUnitLager, 'u',
      TTextPosition.Create(9, 4)))));
    mActions := TLspMoveClass.Actions(mResolver, mTree, cLagerFile, cUnitLager, 'u', TTextPosition.Create(8, 4));
    try
      Assert.AreEqual(1, Integer(Length(mActions)));
      Assert.AreEqual('Klasse TStock in eigene Unit verschieben …', mActions[0].GetValue('title').Value);
      Assert.AreEqual('["u",{"line":8,"character":4},"Stock"]',
        ((mActions[0].GetValue('command') as TJSONObject).GetValue('arguments') as TJSONArray).ToJSON);
    finally
      for mAction in mActions do
      begin
        mAction.Free;
      end;
    end;
  finally
    mTree.Free;
  end;
  // Zugriff auf eine Variable aus dem implementation-Teil: kein Angebot.
  mText := StringReplace(StringReplace(cUnitLager, '  Log;', '  Inc(Zaehler);', []), 'uses'#10'  Helfer;',
    'var'#10'  Zaehler: Integer;', []);
  mTree := TPascalParser.Parse(mText);
  try
    Assert.AreEqual(0, Integer(Length(TLspMoveClass.Actions(mResolver, mTree, cLagerFile, mText, 'u',
      TTextPosition.Create(8, 4)))));
  finally
    mTree.Free;
    mResolver.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspMoveClassTests);

end.
