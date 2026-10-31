unit Atlas.Common.Lsp.SafeDelete.Tests;

// Tests für „Sicher löschen“ über das Protokoll (#716): Angebot der
// Code-Aktion, Löschen ohne Verwendungen, Verwendungen in einer anderen Unit
// (Abbruch bzw. trotzdem löschen), Überschreibungen in Nachfahren,
// Folgeschritte (private Mitglieder, Getter, uses), Formular (Ereignis und
// Komponente) und das Löschen einer ganzen Unit samt uses-Einträgen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspSafeDeleteTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure OffersAction;
    [Test]
    procedure DeletesUnusedMethod;
    [Test]
    procedure BlocksUsedMethod;
    [Test]
    procedure HandlesOverrides;
    [Test]
    procedure OffersCascade;
    [Test]
    procedure FindsFormReferences;
    [Test]
    procedure DeletesWholeUnit;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.SafeDelete;

const
  ShapesFile = 'C:\P\Shapes.pas';
  CircleFile = 'C:\P\Circle.pas';
  UseFile = 'C:\P\Use.pas';
  HelpersFile = 'C:\P\Helpers.pas';
  MainFile = 'C:\P\Main.pas';
  MainForm = 'C:\P\Main.dfm';

  UnitHelpers =
    'unit Helpers;'#10'interface'#10 +
    'function Twice(A: Integer): Integer;'#10 +
    'implementation'#10#10 +
    'function Twice(A: Integer): Integer;'#10'begin'#10'  Result := A * 2;'#10'end;'#10#10 +
    'end.'#10;
  UnitShapes =
    'unit Shapes;'#10 +                                                   // 0
    'interface'#10 +                                                      // 1
    'type'#10 +                                                           // 2
    '  TShape = class'#10 +                                               // 3
    '  private'#10 +                                                      // 4
    '    FCache: Integer;'#10 +                                           // 5
    '    FSize: Integer;'#10 +                                            // 6
    '  public'#10 +                                                       // 7
    '    procedure Draw; virtual;'#10 +                                   // 8
    '    procedure Unused;'#10 +                                          // 9
    '    procedure Used;'#10 +                                            // 10
    '    procedure Refresh;'#10 +                                         // 11
    '    function GetSize: Integer;'#10 +                                 // 12
    '    property Size: Integer read GetSize;'#10 +                       // 13
    '  end;'#10 +                                                         // 14
    'implementation'#10 +                                                 // 15
    #10 +
    'uses'#10 +                                                           // 17
    '  Helpers;'#10 +                                                     // 18
    #10 +
    'procedure TShape.Draw;'#10'begin'#10'end;'#10#10 +                   // 20
    'procedure TShape.Unused;'#10'begin'#10'end;'#10#10 +                 // 24
    'procedure TShape.Used;'#10'begin'#10'end;'#10#10 +                   // 28
    'procedure TShape.Refresh;'#10'begin'#10'  FCache := Twice(FCache);'#10'end;'#10#10 + // 32
    'function TShape.GetSize: Integer;'#10'begin'#10'  Result := FSize;'#10'end;'#10#10 +
    'end.'#10;
  UnitCircle =
    'unit Circle;'#10'interface'#10'uses'#10'  Shapes, Helpers;'#10'type'#10 +
    '  TCircle = class(TShape)'#10 +
    '  public'#10 +
    '    procedure Draw; override;'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'procedure TCircle.Draw;'#10'begin'#10'  inherited;'#10'end;'#10#10 +
    'end.'#10;
  UnitUse =
    'unit Use;'#10'interface'#10'uses'#10'  Shapes, Helpers;'#10'implementation'#10#10 +
    'procedure Go(AShape: TShape);'#10'begin'#10'  AShape.Used;'#10'  Twice(2);'#10'end;'#10#10 +
    'end.'#10;
  UnitMain =
    'unit Main;'#10 +                                                     // 0
    'interface'#10 +                                                      // 1
    'type'#10 +                                                           // 2
    '  TMainForm = class(TForm)'#10 +                                     // 3
    '    Button1: TButton;'#10 +                                          // 4
    '    procedure Button1Click(Sender: TObject);'#10 +                   // 5
    '  end;'#10 +                                                         // 6
    'implementation'#10#10 +
    '{$R *.dfm}'#10#10 +
    'procedure TMainForm.Button1Click(Sender: TObject);'#10'begin'#10'end;'#10#10 +
    'end.'#10;
  FormMain =
    'object MainForm: TMainForm'#10 +
    '  Caption = ''Main'''#10 +
    '  object Button1: TButton'#10 +
    '    OnClick = Button1Click'#10 +
    '  end'#10 +
    'end'#10;

function TextOf(const AFileName: string): string;
begin
  if SameText(AFileName, ShapesFile) then
    Result := UnitShapes
  else if SameText(AFileName, CircleFile) then
    Result := UnitCircle
  else if SameText(AFileName, UseFile) then
    Result := UnitUse
  else if SameText(AFileName, HelpersFile) then
    Result := UnitHelpers
  else if SameText(AFileName, MainFile) then
    Result := UnitMain
  else if SameText(AFileName, MainForm) then
    Result := FormMain
  else
    Result := '';
end;

function Context(const AIndex: ISymbolIndex): TSafeDeleteContext;
begin
  Result := Default(TSafeDeleteContext);
  Result.Index := AIndex;
  Result.Files := [ShapesFile, CircleFile, UseFile, HelpersFile, MainFile];
  Result.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := TextOf(AFileName);
      Result := AText <> '';
    end;
  Result.UsesFor :=
    function(const AFileName: string): TUsesContext
    begin
      Result := Default(TUsesContext);
      Result.Info :=
        function(const AUnitName: string): TUsesUnitInfo
        var
          UnitIndex: TUnitIndex;
          Symbol: TIndexSymbol;
        begin
          Result := Default(TUsesUnitInfo);
          if not AIndex.FindUnit(AUnitName, UnitIndex) then
            Exit;
          Result.Known := True;
          Result.HasInitialization := UnitIndex.HasInitialization;
          for Symbol in UnitIndex.Symbols do
            if Symbol.InInterface then
              Result.Names := Result.Names + [Symbol.Name];
        end;
    end;
end;

function Choices(AOverrides, ACascade, AForce: Boolean): TSafeDeleteChoices;
begin
  Result.Overrides := AOverrides;
  Result.Cascade := ACascade;
  Result.Force := AForce;
end;

/// <summary>Text von AFileName nach dem WorkspaceEdit in AAnswer; '&lt;gelöscht&gt;' bei einer Löschung.</summary>
function After(AAnswer: TJSONObject; const AFileName: string): string;
var
  Item, Edit: TJSONValue;
  Document, Range: TJSONObject;
  Edits: TArray<TTextEdit>;
  Uri: string;
begin
  Result := TextOf(AFileName);
  for Item in (AAnswer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray do
  begin
    Document := TJSONObject(Item);
    if Document.GetValue('kind') <> nil then
    begin
      if SameText(TDocumentUris.ToPath(Document.GetValue('uri').Value), AFileName) then
        Result := '<geloescht>';
      Continue;
    end;
    Uri := (Document.GetValue('textDocument') as TJSONObject).GetValue('uri').Value;
    if not SameText(TDocumentUris.ToPath(Uri), AFileName) then
      Continue;
    Edits := nil;
    for Edit in Document.GetValue('edits') as TJSONArray do
    begin
      Range := TJSONObject(Edit).GetValue('range') as TJSONObject;
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(TLspPositions.ReadPosition(Range.GetValue('start')),
        TLspPositions.ReadPosition(Range.GetValue('end'))), TJSONObject(Edit).GetValue('newText').Value)];
    end;
    Result := TTextChanges.Apply(Result, Edits);
  end;
end;

function Prepare(const AIndex: ISymbolIndex; const AFileName: string; ALine, ACharacter: Integer): TJSONObject;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  Tree := TPascalParser.Parse(TextOf(AFileName));
  Resolver := TNameResolver.Create(AIndex, nil);
  try
    Result := TLspSafeDelete.Prepare(Resolver, Tree, AFileName, TextOf(AFileName),
      TTextPosition.Create(ALine, ACharacter), Context(AIndex));
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

function Execute(const AIndex: ISymbolIndex; const AFileName: string; ALine, ACharacter: Integer;
  const AChoices: TSafeDeleteChoices): TJSONObject;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  Tree := TPascalParser.Parse(TextOf(AFileName));
  Resolver := TNameResolver.Create(AIndex, nil);
  try
    Result := TLspSafeDelete.Execute(Resolver, Tree, AFileName, TextOf(AFileName),
      TTextPosition.Create(ALine, ACharacter), AChoices, Context(AIndex));
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

function Items(AAnswer: TJSONObject; const AName: string): string;
var
  Item: TJSONValue;
begin
  Result := '';
  for Item in AAnswer.GetValue(AName) as TJSONArray do
    if Item is TJSONObject then
      Result := Result + ExtractFileName(TJSONObject(Item).GetValue('file').Value) + ':' +
        TJSONObject(Item).GetValue('line').Value + ':' + TJSONObject(Item).GetValue('kind').Value + '|'
    else
      Result := Result + Item.Value + '|';
end;

procedure TLspSafeDeleteTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitHelpers, HelpersFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitShapes, ShapesFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitCircle, CircleFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitUse, UseFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitMain, MainFile, nil));
end;

procedure TLspSafeDeleteTests.TearDown;
begin
  FIndex := nil;
end;

procedure TLspSafeDeleteTests.OffersAction;
var
  Tree: TSyntaxTree;
  Actions: TArray<TJSONObject>;
  Action: TJSONObject;
begin
  Tree := TPascalParser.Parse(UnitShapes);
  try
    Actions := TLspSafeDelete.Actions(True, Tree, UnitShapes, 'file:///C:/P/Shapes.pas', TTextPosition.Create(9, 15));
    Assert.AreEqual(1, Integer(Length(Actions)));
    Assert.IsTrue(ContainsText(Actions[0].GetValue('title').Value, 'Unused'));
    Assert.AreEqual(TLspSafeDelete.ClientCommand, (Actions[0].GetValue('command') as TJSONObject).GetValue('command').Value);
    for Action in Actions do
      Action.Free;
    Assert.AreEqual(0, Integer(Length(TLspSafeDelete.Actions(False, Tree, UnitShapes, 'file:///C:/P/Shapes.pas',
      TTextPosition.Create(9, 15)))), 'abgeschaltet');
    Assert.AreEqual(0, Integer(Length(TLspSafeDelete.Actions(True, Tree, UnitShapes, 'file:///C:/P/Shapes.pas',
      TTextPosition.Create(15, 2)))), 'implementation');
  finally
    Tree.Free;
  end;
end;

procedure TLspSafeDeleteTests.DeletesUnusedMethod;
var
  Answer: TJSONObject;
  Text: string;
begin
  Answer := Prepare(FIndex, ShapesFile, 9, 15);
  try
    Assert.AreEqual('', Items(Answer, 'usages'));
    Assert.AreEqual('', Items(Answer, 'overrides'));
    Assert.AreEqual('Unused', Answer.GetValue('name').Value);
  finally
    Answer.Free;
  end;
  Answer := Execute(FIndex, ShapesFile, 9, 15, Choices(False, False, False));
  try
    Text := After(Answer, ShapesFile);
    Assert.IsFalse(ContainsText(Text, 'Unused'), Text);
    Assert.IsTrue(ContainsText(Text, 'procedure TShape.Used;'), Text);
    Assert.AreEqual(1, (Answer.GetValue('files') as TJSONNumber).AsInt);
  finally
    Answer.Free;
  end;
end;

procedure TLspSafeDeleteTests.BlocksUsedMethod;
var
  Answer: TJSONObject;
begin
  Answer := Prepare(FIndex, ShapesFile, 10, 15);
  try
    Assert.AreEqual('Use.pas:8:code|', Items(Answer, 'usages'));
  finally
    Answer.Free;
  end;
  Assert.WillRaise(
    procedure
    begin
      Execute(FIndex, ShapesFile, 10, 15, Choices(False, False, False)).Free;
    end, EJsonRpcError);
  Answer := Execute(FIndex, ShapesFile, 10, 15, Choices(False, False, True));
  try
    Assert.IsFalse(ContainsText(After(Answer, ShapesFile), 'TShape.Used'));
    Assert.IsTrue(ContainsText(Items(Answer, 'warnings'), 'Trotz 1'));
  finally
    Answer.Free;
  end;
end;

procedure TLspSafeDeleteTests.HandlesOverrides;
var
  Answer: TJSONObject;
begin
  Answer := Prepare(FIndex, ShapesFile, 8, 15);
  try
    Assert.AreEqual('Circle.pas:7:override|', Items(Answer, 'overrides'));
  finally
    Answer.Free;
  end;
  Assert.WillRaise(
    procedure
    begin
      Execute(FIndex, ShapesFile, 8, 15, Choices(False, False, False)).Free;
    end, EJsonRpcError);
  Answer := Execute(FIndex, ShapesFile, 8, 15, Choices(True, False, False));
  try
    Assert.IsFalse(ContainsText(After(Answer, ShapesFile), 'Draw'));
    Assert.IsFalse(ContainsText(After(Answer, CircleFile), 'Draw'), After(Answer, CircleFile));
    Assert.AreEqual(2, (Answer.GetValue('files') as TJSONNumber).AsInt);
  finally
    Answer.Free;
  end;
end;

procedure TLspSafeDeleteTests.OffersCascade;
var
  Answer: TJSONObject;
  Text: string;
begin
  // Refresh benutzt FCache und als einzige Routine Helpers.
  Answer := Prepare(FIndex, ShapesFile, 11, 15);
  try
    Assert.AreEqual('FCache|uses Helpers|', Items(Answer, 'cascade'));
  finally
    Answer.Free;
  end;
  Answer := Execute(FIndex, ShapesFile, 11, 15, Choices(False, True, False));
  try
    Text := After(Answer, ShapesFile);
    Assert.IsFalse(ContainsText(Text, 'FCache'), Text);
    Assert.IsFalse(ContainsText(Text, 'Helpers'), Text);
    Assert.IsTrue(ContainsText(Text, 'FSize'), Text);
  finally
    Answer.Free;
  end;
  Answer := Execute(FIndex, ShapesFile, 11, 15, Choices(False, False, False));
  try
    Assert.IsTrue(ContainsText(After(Answer, ShapesFile), 'FCache'), 'ohne Folgeschritt');
  finally
    Answer.Free;
  end;
  // Property Size: der öffentliche Getter wird frei, FSize über ihn.
  Answer := Prepare(FIndex, ShapesFile, 13, 15);
  try
    Assert.AreEqual('GetSize|', Items(Answer, 'cascade'));
  finally
    Answer.Free;
  end;
end;

procedure TLspSafeDeleteTests.FindsFormReferences;
var
  Answer: TJSONObject;
begin
  Answer := Prepare(FIndex, MainFile, 5, 15);
  try
    Assert.AreEqual('Main.dfm:3:form|', Items(Answer, 'usages'));
  finally
    Answer.Free;
  end;
  Answer := Prepare(FIndex, MainFile, 4, 6);
  try
    Assert.AreEqual('Main.dfm:2:form|', Items(Answer, 'usages'));
  finally
    Answer.Free;
  end;
end;

procedure TLspSafeDeleteTests.DeletesWholeUnit;
var
  Answer: TJSONObject;
  Text: string;
begin
  Answer := Prepare(FIndex, HelpersFile, 0, 6);
  try
    Assert.AreEqual('Unit', Answer.GetValue('kind').Value);
    // Use.pas ruft Twice; Circle.pas bindet sie nur ein; Shapes.pas ruft Twice.
    Assert.AreEqual('Shapes.pas:0:uses|Use.pas:0:uses|', Items(Answer, 'usages'));
    Assert.AreEqual(1, (Answer.GetValue('usesFiles') as TJSONNumber).AsInt);
  finally
    Answer.Free;
  end;
  Answer := Execute(FIndex, HelpersFile, 0, 6, Choices(False, False, True));
  try
    Assert.AreEqual('<geloescht>', After(Answer, HelpersFile));
    Text := After(Answer, CircleFile);
    Assert.IsTrue(ContainsText(Text, 'uses'#10'  Shapes;'), Text);
  finally
    Answer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSafeDeleteTests);

end.
