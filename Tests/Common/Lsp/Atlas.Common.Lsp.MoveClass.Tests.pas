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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.MoveClass;

const
  BasisFile = 'C:\P\Basis.pas';
  HelferFile = 'C:\P\Helfer.pas';
  LagerFile = 'C:\P\Lager.pas';
  KasseFile = 'C:\P\Kasse.pas';
  ProgramFile = 'C:\P\Projekt.dpr';
  ProjectFile = 'C:\P\Projekt.dproj';

  UnitBasis =
    'unit Basis;'#10'interface'#10'type'#10'  TItems = class'#10'  end;'#10 +
    'function Fmt(A: Integer): string;'#10'implementation'#10 +
    'function Fmt(A: Integer): string;'#10'begin'#10'  Result := '''';'#10'end;'#10'end.'#10;
  UnitHelfer =
    'unit Helfer;'#10'interface'#10'procedure Log;'#10'implementation'#10'procedure Log;'#10'begin'#10'end;'#10 +
    'end.'#10;
  UnitLager =
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
  UnitKasse =
    'unit Kasse;'#10'interface'#10'uses Lager;'#10'implementation'#10'procedure Run;'#10'var'#10 +
    '  S: TStock;'#10'begin'#10'  S := Lager.TStock.Create;'#10'end;'#10'end.'#10;
  TextProgram =
    'program Projekt;'#10'uses'#10'  Lager in ''Lager.pas'','#10'  Kasse in ''Kasse.pas'';'#10'begin'#10'end.'#10;
  TextProject =
    '<Project>'#10'  <ItemGroup>'#10'    <DelphiCompile Include="Projekt.dpr"/>'#10 +
    '    <DCCReference Include="Lager.pas"/>'#10'    <DCCReference Include="Kasse.pas"/>'#10'  </ItemGroup>'#10 +
    '</Project>'#10;

function TextOf(const AFileName: string): string;
begin
  if SameText(AFileName, BasisFile) then
    Result := UnitBasis
  else if SameText(AFileName, HelferFile) then
    Result := UnitHelfer
  else if SameText(AFileName, LagerFile) then
    Result := UnitLager
  else if SameText(AFileName, KasseFile) then
    Result := UnitKasse
  else if SameText(AFileName, ProgramFile) then
    Result := TextProgram
  else if SameText(AFileName, ProjectFile) then
    Result := TextProject
  else
    Result := '';
end;

function Context: TMoveClassContext;
begin
  Result := Default(TMoveClassContext);
  Result.HasProject := True;
  Result.Project.FileName := ProjectFile;
  Result.Project.MainSource := ProgramFile;
  Result.Files := [BasisFile, HelferFile, LagerFile, KasseFile, ProgramFile];
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
  Item: TJSONValue;
  Edits: TArray<TTextEdit>;
  Range: TJSONObject;
begin
  Edits := nil;
  for Item in ADocument.GetValue('edits') as TJSONArray do
  begin
    Range := TJSONObject(Item).GetValue('range') as TJSONObject;
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(TLspPositions.ReadPosition(Range.GetValue('start')),
      TLspPositions.ReadPosition(Range.GetValue('end'))), TJSONObject(Item).GetValue('newText').Value)];
  end;
  Result := TChangeSignature.ApplyEdits(AText, Edits);
end;

procedure TLspMoveClassTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, BasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitHelfer, HelferFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitLager, LagerFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitKasse, KasseFile, nil));
end;

procedure TLspMoveClassTests.TearDown;
begin
  FIndex := nil;
end;

procedure TLspMoveClassTests.MovesOverTheProject;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Answer: TJSONObject;
  Changes: TJSONArray;
  Item: TJSONValue;
  Document: TJSONObject;
  Uri, Results: string;
  Moved: TMoveClassContext;
begin
  Tree := TPascalParser.Parse(UnitLager);
  Resolver := TNameResolver.Create(FIndex, nil);
  Answer := nil;
  try
    Moved := Context;
    Moved.Index := FIndex;
    Answer := TLspMoveClass.Execute(Resolver, Tree, LagerFile, UnitLager, TTextPosition.Create(8, 4), 'Stock', Moved);
    Assert.AreEqual(0, Integer((Answer.GetValue('warnings') as TJSONArray).Count), Answer.ToJSON);
    Assert.AreEqual(TDocumentUris.FromPath('C:\P\Stock.pas'), Answer.GetValue('file').Value);
    Changes := (Answer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray;
    Assert.AreEqual('create', (Changes.Items[0] as TJSONObject).GetValue('kind').Value);
    Results := '';
    for Item in Changes do
    begin
      Document := TJSONObject(Item);
      if Document.GetValue('textDocument') = nil then
        Continue;
      Uri := (Document.GetValue('textDocument') as TJSONObject).GetValue('uri').Value;
      Results := Results + ExtractFileName(TDocumentUris.ToPath(Uri)) + '|';
      if Uri = TDocumentUris.FromPath('C:\P\Stock.pas') then
        Assert.AreEqual('unit Stock;'#10#10'interface'#10#10'uses'#10'  Basis;'#10#10'type'#10'  TStock = class'#10 +
          '    FItems: TItems;'#10'    function Text: string;'#10'  end;'#10#10'implementation'#10#10'uses'#10 +
          '  Helfer;'#10#10'function TStock.Text: string;'#10'begin'#10'  Log;'#10'  Result := Fmt(1);'#10'end;'#10#10 +
          'end.'#10, Apply('', Document))
      else if Uri = TDocumentUris.FromPath(LagerFile) then
        Assert.AreEqual('unit Lager;'#10#10'interface'#10#10'uses'#10'  Basis;'#10#10'implementation'#10#10'uses'#10 +
          '  Helfer;'#10#10'end.'#10, Apply(UnitLager, Document))
      else if Uri = TDocumentUris.FromPath(KasseFile) then
        Assert.AreEqual(StringReplace(StringReplace(UnitKasse, 'uses Lager;', 'uses Lager, Stock;', []),
          'Lager.TStock', 'Stock.TStock', []), Apply(UnitKasse, Document))
      else if Uri = TDocumentUris.FromPath(ProgramFile) then
        Assert.Contains(Apply(TextProgram, Document), 'Stock in ''Stock.pas''')
      else if Uri = TDocumentUris.FromPath(ProjectFile) then
        Assert.Contains(Apply(TextProject, Document), '<DCCReference Include="Stock.pas"/>');
    end;
    Assert.AreEqual('Stock.pas|Lager.pas|Kasse.pas|Projekt.dpr|Projekt.dproj|', Results);
    // Gibt es die Datei schon, bricht der Befehl ab.
    Assert.WillRaise(
      procedure
      begin
        TLspMoveClass.Execute(Resolver, Tree, LagerFile, UnitLager, TTextPosition.Create(8, 4), 'Kasse', Moved).Free;
      end);
  finally
    Answer.Free;
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspMoveClassTests.OffersOnlyMovableClasses;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Actions: TArray<TJSONObject>;
  Action: TJSONObject;
  Text: string;
begin
  Resolver := TNameResolver.Create(FIndex, nil);
  Tree := TPascalParser.Parse(UnitLager);
  try
    Assert.AreEqual(0, Integer(Length(TLspMoveClass.Actions(False, Resolver, Tree, LagerFile, UnitLager, 'u',
      TTextPosition.Create(8, 4)))));
    Assert.AreEqual(0, Integer(Length(TLspMoveClass.Actions(True, Resolver, Tree, LagerFile, UnitLager, 'u',
      TTextPosition.Create(9, 4)))));
    Actions := TLspMoveClass.Actions(True, Resolver, Tree, LagerFile, UnitLager, 'u', TTextPosition.Create(8, 4));
    try
      Assert.AreEqual(1, Integer(Length(Actions)));
      Assert.AreEqual('Klasse TStock in eigene Unit verschieben …', Actions[0].GetValue('title').Value);
      Assert.AreEqual('["u",{"line":8,"character":4},"Stock"]',
        ((Actions[0].GetValue('command') as TJSONObject).GetValue('arguments') as TJSONArray).ToJSON);
    finally
      for Action in Actions do
        Action.Free;
    end;
  finally
    Tree.Free;
  end;
  // Zugriff auf eine Variable aus dem implementation-Teil: kein Angebot.
  Text := StringReplace(StringReplace(UnitLager, '  Log;', '  Inc(Zaehler);', []), 'uses'#10'  Helfer;',
    'var'#10'  Zaehler: Integer;', []);
  Tree := TPascalParser.Parse(Text);
  try
    Assert.AreEqual(0, Integer(Length(TLspMoveClass.Actions(True, Resolver, Tree, LagerFile, Text, 'u',
      TTextPosition.Create(8, 4)))));
  finally
    Tree.Free;
    Resolver.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspMoveClassTests);

end.
