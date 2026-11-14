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
  Atlas.Common.Editing.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.SafeDelete;

const
  cShapesFile = 'C:\P\Shapes.pas';
  cCircleFile = 'C:\P\Circle.pas';
  cUseFile = 'C:\P\Use.pas';
  cHelpersFile = 'C:\P\Helpers.pas';
  cMainFile = 'C:\P\Main.pas';
  cMainForm = 'C:\P\Main.dfm';

  cUnitHelpers =
    'unit Helpers;'#10'interface'#10 +
    'function Twice(A: Integer): Integer;'#10 +
    'implementation'#10#10 +
    'function Twice(A: Integer): Integer;'#10'begin'#10'  Result := A * 2;'#10'end;'#10#10 +
    'end.'#10;
  cUnitShapes =
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
  cUnitCircle =
    'unit Circle;'#10'interface'#10'uses'#10'  Shapes, Helpers;'#10'type'#10 +
    '  TCircle = class(TShape)'#10 +
    '  public'#10 +
    '    procedure Draw; override;'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'procedure TCircle.Draw;'#10'begin'#10'  inherited;'#10'end;'#10#10 +
    'end.'#10;
  cUnitUse =
    'unit Use;'#10'interface'#10'uses'#10'  Shapes, Helpers;'#10'implementation'#10#10 +
    'procedure Go(AShape: TShape);'#10'begin'#10'  AShape.Used;'#10'  Twice(2);'#10'end;'#10#10 +
    'end.'#10;
  cUnitMain =
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
  cFormMain =
    'object MainForm: TMainForm'#10 +
    '  Caption = ''Main'''#10 +
    '  object Button1: TButton'#10 +
    '    OnClick = Button1Click'#10 +
    '  end'#10 +
    'end'#10;

function TextOf(const AFileName: string): string;
begin
  if SameText(AFileName, cShapesFile) then
  begin
    Result := cUnitShapes;
  end
  else if SameText(AFileName, cCircleFile) then
  begin
    Result := cUnitCircle;
  end
  else if SameText(AFileName, cUseFile) then
  begin
    Result := cUnitUse;
  end
  else if SameText(AFileName, cHelpersFile) then
  begin
    Result := cUnitHelpers;
  end
  else if SameText(AFileName, cMainFile) then
  begin
    Result := cUnitMain;
  end
  else if SameText(AFileName, cMainForm) then
  begin
    Result := cFormMain;
  end
  else
  begin
    Result := '';
  end;
end;

function Context(const AIndex: ISymbolIndex): TSafeDeleteContext;
begin
  Result := Default(TSafeDeleteContext);
  Result.Index := AIndex;
  Result.Files := [cShapesFile, cCircleFile, cUseFile, cHelpersFile, cMainFile];
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
          begin
            Exit;
          end;
          Result.Known := True;
          Result.HasInitialization := UnitIndex.HasInitialization;
          for Symbol in UnitIndex.Symbols do
          begin
            if Symbol.InInterface then
            begin
              Result.Names := Result.Names + [Symbol.Name];
            end;
          end;
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
  mItem, mEdit: TJSONValue;
  mDocument, mRange: TJSONObject;
  mEdits: TArray<TTextEdit>;
  mUri: string;
begin
  Result := TextOf(AFileName);
  for mItem in (AAnswer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray do
  begin
    mDocument := TJSONObject(mItem);
    if mDocument.GetValue('kind') <> nil then
    begin
      if SameText(TDocumentUris.ToPath(mDocument.GetValue('uri').Value), AFileName) then
      begin
        Result := '<geloescht>';
      end;
      Continue;
    end;
    mUri := (mDocument.GetValue('textDocument') as TJSONObject).GetValue('uri').Value;
    if not SameText(TDocumentUris.ToPath(mUri), AFileName) then
    begin
      Continue;
    end;
    mEdits := nil;
    for mEdit in mDocument.GetValue('edits') as TJSONArray do
    begin
      mRange := TJSONObject(mEdit).GetValue('range') as TJSONObject;
      mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(TLspPositions.ReadPosition(mRange.GetValue('start')),
        TLspPositions.ReadPosition(mRange.GetValue('end'))), TJSONObject(mEdit).GetValue('newText').Value)];
    end;
    Result := TTextChanges.Apply(Result, mEdits);
  end;
end;

function Prepare(const AIndex: ISymbolIndex; const AFileName: string; ALine, ACharacter: Integer): TJSONObject;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
begin
  mTree := TPascalParser.Parse(TextOf(AFileName));
  mResolver := TNameResolver.Create(AIndex, nil);
  try
    Result := TLspSafeDelete.Prepare(mResolver, mTree, AFileName, TextOf(AFileName),
      TTextPosition.Create(ALine, ACharacter), Context(AIndex));
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

function Execute(const AIndex: ISymbolIndex; const AFileName: string; ALine, ACharacter: Integer;
  const AChoices: TSafeDeleteChoices): TJSONObject;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mWithChoices: TSafeDeleteContext;
begin
  mWithChoices := Context(AIndex);
  mWithChoices.Choices := AChoices;
  mTree := TPascalParser.Parse(TextOf(AFileName));
  mResolver := TNameResolver.Create(AIndex, nil);
  try
    Result := TLspSafeDelete.Execute(mResolver, mTree, AFileName, TextOf(AFileName),
      TTextPosition.Create(ALine, ACharacter), mWithChoices);
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

function Items(AAnswer: TJSONObject; const AName: string): string;
var
  mItem: TJSONValue;
begin
  Result := '';
  for mItem in AAnswer.GetValue(AName) as TJSONArray do
  begin
    if mItem is TJSONObject then
    begin
      Result := Result + ExtractFileName(TJSONObject(mItem).GetValue('file').Value) + ':' +
        TJSONObject(mItem).GetValue('line').Value + ':' + TJSONObject(mItem).GetValue('kind').Value + '|';
    end
    else
    begin
      Result := Result + mItem.Value + '|';
    end;
  end;
end;

procedure TLspSafeDeleteTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitHelpers, cHelpersFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitShapes, cShapesFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitCircle, cCircleFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitUse, cUseFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitMain, cMainFile, nil));
end;

procedure TLspSafeDeleteTests.TearDown;
begin
  FIndex := nil;
end;

procedure TLspSafeDeleteTests.OffersAction;
var
  mTree: TSyntaxTree;
  mActions: TArray<TJSONObject>;
  mAction: TJSONObject;
begin
  mTree := TPascalParser.Parse(cUnitShapes);
  try
    mActions := TLspSafeDelete.Actions(True, mTree, cUnitShapes, 'file:///C:/P/Shapes.pas', TTextPosition.Create(9, 15));
    Assert.AreEqual(1, Integer(Length(mActions)));
    Assert.IsTrue(ContainsText(mActions[0].GetValue('title').Value, 'Unused'));
    Assert.AreEqual(TLspSafeDelete.cClientCommand, (mActions[0].GetValue('command') as TJSONObject).GetValue('command').Value);
    for mAction in mActions do
    begin
      mAction.Free;
    end;
    Assert.AreEqual(0, Integer(Length(TLspSafeDelete.Actions(False, mTree, cUnitShapes, 'file:///C:/P/Shapes.pas',
      TTextPosition.Create(9, 15)))), 'abgeschaltet');
    Assert.AreEqual(0, Integer(Length(TLspSafeDelete.Actions(True, mTree, cUnitShapes, 'file:///C:/P/Shapes.pas',
      TTextPosition.Create(15, 2)))), 'implementation');
  finally
    mTree.Free;
  end;
end;

procedure TLspSafeDeleteTests.DeletesUnusedMethod;
var
  mAnswer: TJSONObject;
  mText: string;
begin
  mAnswer := Prepare(FIndex, cShapesFile, 9, 15);
  try
    Assert.AreEqual('', Items(mAnswer, 'usages'));
    Assert.AreEqual('', Items(mAnswer, 'overrides'));
    Assert.AreEqual('Unused', mAnswer.GetValue('name').Value);
  finally
    mAnswer.Free;
  end;
  mAnswer := Execute(FIndex, cShapesFile, 9, 15, Choices(False, False, False));
  try
    mText := After(mAnswer, cShapesFile);
    Assert.IsFalse(ContainsText(mText, 'Unused'), mText);
    Assert.IsTrue(ContainsText(mText, 'procedure TShape.Used;'), mText);
    Assert.AreEqual(1, (mAnswer.GetValue('files') as TJSONNumber).AsInt);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspSafeDeleteTests.BlocksUsedMethod;
var
  mAnswer: TJSONObject;
begin
  mAnswer := Prepare(FIndex, cShapesFile, 10, 15);
  try
    Assert.AreEqual('Use.pas:8:code|', Items(mAnswer, 'usages'));
  finally
    mAnswer.Free;
  end;
  Assert.WillRaise(
    procedure
    begin
      Execute(FIndex, cShapesFile, 10, 15, Choices(False, False, False)).Free;
    end, EJsonRpcError);
  mAnswer := Execute(FIndex, cShapesFile, 10, 15, Choices(False, False, True));
  try
    Assert.IsFalse(ContainsText(After(mAnswer, cShapesFile), 'TShape.Used'));
    Assert.IsTrue(ContainsText(Items(mAnswer, 'warnings'), 'Trotz 1'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspSafeDeleteTests.HandlesOverrides;
var
  mAnswer: TJSONObject;
begin
  mAnswer := Prepare(FIndex, cShapesFile, 8, 15);
  try
    Assert.AreEqual('Circle.pas:7:override|', Items(mAnswer, 'overrides'));
  finally
    mAnswer.Free;
  end;
  Assert.WillRaise(
    procedure
    begin
      Execute(FIndex, cShapesFile, 8, 15, Choices(False, False, False)).Free;
    end, EJsonRpcError);
  mAnswer := Execute(FIndex, cShapesFile, 8, 15, Choices(True, False, False));
  try
    Assert.IsFalse(ContainsText(After(mAnswer, cShapesFile), 'Draw'));
    Assert.IsFalse(ContainsText(After(mAnswer, cCircleFile), 'Draw'), After(mAnswer, cCircleFile));
    Assert.AreEqual(2, (mAnswer.GetValue('files') as TJSONNumber).AsInt);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspSafeDeleteTests.OffersCascade;
var
  mAnswer: TJSONObject;
  mText: string;
begin
  // Refresh benutzt FCache und als einzige Routine Helpers.
  mAnswer := Prepare(FIndex, cShapesFile, 11, 15);
  try
    Assert.AreEqual('FCache|uses Helpers|', Items(mAnswer, 'cascade'));
  finally
    mAnswer.Free;
  end;
  mAnswer := Execute(FIndex, cShapesFile, 11, 15, Choices(False, True, False));
  try
    mText := After(mAnswer, cShapesFile);
    Assert.IsFalse(ContainsText(mText, 'FCache'), mText);
    Assert.IsFalse(ContainsText(mText, 'Helpers'), mText);
    Assert.IsTrue(ContainsText(mText, 'FSize'), mText);
  finally
    mAnswer.Free;
  end;
  mAnswer := Execute(FIndex, cShapesFile, 11, 15, Choices(False, False, False));
  try
    Assert.IsTrue(ContainsText(After(mAnswer, cShapesFile), 'FCache'), 'ohne Folgeschritt');
  finally
    mAnswer.Free;
  end;
  // Property Size: der öffentliche Getter wird frei, FSize über ihn.
  mAnswer := Prepare(FIndex, cShapesFile, 13, 15);
  try
    Assert.AreEqual('GetSize|', Items(mAnswer, 'cascade'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspSafeDeleteTests.FindsFormReferences;
var
  mAnswer: TJSONObject;
begin
  mAnswer := Prepare(FIndex, cMainFile, 5, 15);
  try
    Assert.AreEqual('Main.dfm:3:form|', Items(mAnswer, 'usages'));
  finally
    mAnswer.Free;
  end;
  mAnswer := Prepare(FIndex, cMainFile, 4, 6);
  try
    Assert.AreEqual('Main.dfm:2:form|', Items(mAnswer, 'usages'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspSafeDeleteTests.DeletesWholeUnit;
var
  mAnswer: TJSONObject;
  mText: string;
begin
  mAnswer := Prepare(FIndex, cHelpersFile, 0, 6);
  try
    Assert.AreEqual('Unit', mAnswer.GetValue('kind').Value);
    // Use.pas ruft Twice; Circle.pas bindet sie nur ein; Shapes.pas ruft Twice.
    Assert.AreEqual('Shapes.pas:0:uses|Use.pas:0:uses|', Items(mAnswer, 'usages'));
    Assert.AreEqual(1, (mAnswer.GetValue('usesFiles') as TJSONNumber).AsInt);
  finally
    mAnswer.Free;
  end;
  mAnswer := Execute(FIndex, cHelpersFile, 0, 6, Choices(False, False, True));
  try
    Assert.AreEqual('<geloescht>', After(mAnswer, cHelpersFile));
    mText := After(mAnswer, cCircleFile);
    Assert.IsTrue(ContainsText(mText, 'uses'#10'  Shapes;'), mText);
  finally
    mAnswer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSafeDeleteTests);

end.
