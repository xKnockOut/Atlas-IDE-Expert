unit Atlas.Common.Lsp.UnitRelations.Tests;

// Tests der Unit-Beziehungen im LSP-Server (#593): atlas/unitRelations mit
// Tiefe, Generation und ungenutzten Einträgen, der Befehl atlas.unitRelations,
// Verschieben zwischen interface- und implementation-uses über
// atlas.server.moveUses und Entfernen nur ungenutzter Einträge über
// atlas.server.removeUses; Kosten einer interface-Änderung über
// atlas.interfaceCost und nur im implementation gebrauchte interface-Einträge
// (#554).

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Lsp.UnitRelations;

type
  [TestFixture]
  TLspUnitRelationsTests = class
  private
    FTexts: TDictionary<string, string>;
    FIndex: ISymbolIndex;
    FGraph: TUsesGraphService;
    FRelations: TLspUnitRelations;
    FOptionsAsked: Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RequestAnswersWithGenerationAndDepth;
    [Test]
    procedure CommandTakesDepthOption;
    [Test]
    procedure RequestNeedsUri;
    [Test]
    procedure MovesBetweenSections;
    [Test]
    procedure MoveRejectsWrongTargets;
    [Test]
    procedure RemovesOnlyUnusedEntries;
    [Test]
    procedure MarksEntriesNeededOnlyInImplementation;
    [Test]
    procedure CostCommandAnswersRecompileCount;
    [Test]
    procedure UseUnitInfoListsInUsesAndCycles;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesGraph.Tests,
  Atlas.Common.Architecture.UnitRelations.Tests;

function FileOf(const AName: string): string;
begin
  Result := UsesUnit(AName, nil, nil).FileName;
end;

function Arguments(const AValues: array of string): TJSONArray;
var
  mValue: string;
begin
  Result := TJSONArray.Create;
  for mValue in AValues do
  begin
    Result.Add(mValue);
  end;
end;

/// <summary>Text nach den Edits des WorkspaceEdit aus der Antwort {"edit": …}.</summary>
function Applied(const AText: string; AAnswer: TJSONValue): string;
var
  mChanges: TJSONObject;
  mItem: TJSONValue;
  mEdits: TArray<TTextEdit>;
  mEdit: TTextEdit;
begin
  mChanges := (AAnswer as TJSONObject).GetValue<TJSONObject>('edit.changes');
  Assert.AreEqual(1, mChanges.Count, 'eine Datei');
  mEdits := nil;
  for mItem in mChanges.Pairs[0].JsonValue as TJSONArray do
  begin
    mEdit := Default(TTextEdit);
    mEdit.Range.StartPos.Line := mItem.GetValue<Integer>('range.start.line');
    mEdit.Range.StartPos.Character := mItem.GetValue<Integer>('range.start.character');
    mEdit.Range.EndPos.Line := mItem.GetValue<Integer>('range.end.line');
    mEdit.Range.EndPos.Character := mItem.GetValue<Integer>('range.end.character');
    mEdit.NewText := mItem.GetValue<string>('newText');
    mEdits := mEdits + [mEdit];
  end;
  Result := TChangeSignature.ApplyEdits(AText, mEdits);
end;

{ TLspUnitRelationsTests }

procedure TLspUnitRelationsTests.Setup;
var
  mTexts: TDictionary<string, string>;
  mSelf_: TLspUnitRelationsTests;

  procedure Add(const AName: string; const AInterface, AImplementation: TArray<string>);
  begin
    FIndex.AddUnit(UsesUnit(AName, AInterface, AImplementation));
    FTexts.AddOrSetValue(FileOf(AName), UnitSource(AName, AInterface, AImplementation));
  end;

begin
  FTexts := TDictionary<string, string>.Create;
  FIndex := TSymbolIndex.Create;
  // A ↔ B im interface, A → C im implementation; D verwendet A im implementation.
  Add('A', ['B'], ['C']);
  Add('B', ['A'], nil);
  Add('C', nil, nil);
  Add('D', nil, ['A']);
  FGraph := TUsesGraphService.Create(FIndex, TUsesGraphOptions.Default);
  mTexts := FTexts;
  mSelf_ := Self;
  FOptionsAsked := 0;
  FRelations := TLspUnitRelations.Create(FGraph,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := mTexts.TryGetValue(AFileName, AText);
    end,
    function(const AFileName: string): TArray<string>
    begin
      Result := nil;
    end,
    function(const AUri: string; out AContext: TUsesContext): Boolean
    begin
      AContext := Default(TUsesContext);
      // B liefert TB (nur im Test des Entfernens verwendet), C nichts.
      AContext.Info :=
        function(const AUnitName: string): TUsesUnitInfo
        begin
          Result := Default(TUsesUnitInfo);
          Result.Known := True;
          if SameText(AUnitName, 'B') then
          begin
            Result.Names := ['TB'];
          end;
        end;
      Result := True;
    end,
    function(const AFileName: string): TUsesGraphOptions
    begin
      Inc(mSelf_.FOptionsAsked);
      Result := TUsesGraphOptions.Default;
    end);
end;

procedure TLspUnitRelationsTests.TearDown;
begin
  FRelations.Free;
  FRelations := nil;
  FGraph.Free;
  FGraph := nil;
  FIndex := nil;
  FTexts.Free;
  FTexts := nil;
end;

procedure TLspUnitRelationsTests.RequestAnswersWithGenerationAndDepth;
var
  mParams: TJSONObject;
  mAnswer: TJSONValue;
  mUses_: TJSONArray;
begin
  mParams := TJSONObject.Create;
  try
    // Pfad statt URI: unter FPC/Linux führt die URI nicht auf denselben Windows-Pfad zurück.
    mParams.AddPair('uri', FileOf('A'));
    mAnswer := FRelations.Request(mParams);
    try
      Assert.IsTrue(mAnswer.GetValue<Boolean>('found'));
      Assert.AreEqual(1, mAnswer.GetValue<Integer>('depth'), 'Vorgabe: direkt');
      Assert.AreEqual(FIndex.Generation, mAnswer.GetValue<Int64>('generation'));
      Assert.IsTrue(FOptionsAsked > 0, 'Optionen je Datei');
      Assert.IsTrue(FGraph.Options.IncludeLibrary, 'Bibliotheks-Units immer im Graphen');
      mUses_ := mAnswer.GetValue<TJSONArray>('uses');
      Assert.AreEqual(2, mUses_.Count);
      Assert.IsTrue(mUses_.Items[0].GetValue<Boolean>('cycle'), 'A ↔ B');
      Assert.IsTrue(mUses_.Items[1].GetValue<Boolean>('unused'), 'C liefert nichts');
      Assert.AreEqual(2, mAnswer.GetValue<TJSONArray>('usedBy').Count);
      Assert.AreEqual(2, mAnswer.GetValue<Integer>('recompileCount'), 'B und D');
    finally
      mAnswer.Free;
    end;
  finally
    mParams.Free;
  end;
end;

procedure TLspUnitRelationsTests.CommandTakesDepthOption;
var
  mArgs: TJSONArray;
  mOptions: TJSONObject;
  mAnswer: TJSONValue;
begin
  mArgs := Arguments([FileOf('A')]);
  try
    mOptions := TJSONObject.Create;
    mOptions.AddPair('depth', TJSONNumber.Create(0));
    mArgs.AddElement(mOptions);
    mAnswer := FRelations.Execute(mArgs);
    try
      Assert.AreEqual(0, mAnswer.GetValue<Integer>('depth'));
      // B → A ist die Wurzel: wiederholt, nicht aufgeklappt.
      Assert.IsTrue(((mAnswer.GetValue<TJSONArray>('uses').Items[0] as TJSONObject).GetValue<TJSONArray>('children')
        .Items[0] as TJSONObject).GetValue<Boolean>('repeated'));
    finally
      mAnswer.Free;
    end;
  finally
    mArgs.Free;
  end;
end;

procedure TLspUnitRelationsTests.RequestNeedsUri;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        FRelations.Request(mParams).Free;
      end, EJsonRpcError);
    mParams.AddPair('uri', FileOf('A'));
    mParams.AddPair('depth', TJSONNumber.Create(-1));
    Assert.WillRaise(
      procedure
      begin
        FRelations.Request(mParams).Free;
      end, EJsonRpcError);
  finally
    mParams.Free;
  end;
end;

procedure TLspUnitRelationsTests.MovesBetweenSections;
var
  mArgs: TJSONArray;
  mAnswer: TJSONValue;
  mText: string;
begin
  mText := FTexts[FileOf('A')];
  mArgs := Arguments([FileOf('A'), 'B', 'implementation']);
  try
    mAnswer := FRelations.Move(mArgs);
    try
      Assert.AreEqual('unit A;'#10'interface'#10#10'implementation'#10'uses'#10'  C,'#10'  B;'#10'end.',
        Applied(mText, mAnswer));
    finally
      mAnswer.Free;
    end;
  finally
    mArgs.Free;
  end;
  mArgs := Arguments([FileOf('A'), 'c', 'interface']);
  try
    mAnswer := FRelations.Move(mArgs);
    try
      Assert.AreEqual('unit A;'#10'interface'#10'uses'#10'  B,'#10'  C;'#10'implementation'#10#10'end.',
        Applied(mText, mAnswer), 'Schreibweise aus dem Quelltext');
    finally
      mAnswer.Free;
    end;
  finally
    mArgs.Free;
  end;
end;

procedure TLspUnitRelationsTests.MoveRejectsWrongTargets;
var
  mEdits: TArray<TTextEdit>;
  mError: string;

  procedure Fails(const AValues: array of string);
  var
    mArgs: TJSONArray;
  begin
    mArgs := Arguments(AValues);
    try
      Assert.WillRaise(
        procedure
        begin
          FRelations.Move(mArgs).Free;
        end, EJsonRpcError);
    finally
      mArgs.Free;
    end;
  end;

begin
  Assert.IsFalse(TLspUnitRelations.MoveEdits(FTexts[FileOf('A')], 'B', TUsesSection.Interface_, mEdits, mError));
  Assert.IsTrue(mError.Contains('interface'), mError);
  Assert.IsFalse(TLspUnitRelations.MoveEdits(FTexts[FileOf('A')], 'X', TUsesSection.Interface_, mEdits, mError));
  Assert.IsNull(mEdits);
  Fails([FileOf('A'), 'B', 'interface']);
  Fails([FileOf('A'), 'B', 'woanders']);
  Fails([FileOf('A'), 'B']);
  FTexts.AddOrSetValue('C:\Projekt\P.dpr', 'program P;'#10'uses'#10'  A;'#10'begin'#10'end.');
  Fails(['C:\Projekt\P.dpr', 'A', 'implementation']);
end;

procedure TLspUnitRelationsTests.RemovesOnlyUnusedEntries;
var
  mArgs: TJSONArray;
  mAnswer: TJSONValue;
  mText: string;
begin
  mText := 'unit A;'#10'interface'#10'uses'#10'  B;'#10'type'#10'  T = TB;'#10'implementation'#10'uses'#10'  C;'#10'end.';
  FTexts.AddOrSetValue(FileOf('A'), mText);
  mArgs := Arguments([FileOf('A'), 'C']);
  try
    mAnswer := FRelations.Remove(mArgs);
    try
      Assert.IsFalse(Applied(mText, mAnswer).Contains('C;'), 'C entfernt');
      Assert.IsTrue(Applied(mText, mAnswer).Contains('  B;'), 'B bleibt');
    finally
      mAnswer.Free;
    end;
  finally
    mArgs.Free;
  end;
  mArgs := Arguments([FileOf('A'), 'B']);
  try
    Assert.WillRaise(
      procedure
      begin
        FRelations.Remove(mArgs).Free;
      end, EJsonRpcError, 'B wird verwendet');
  finally
    mArgs.Free;
  end;
end;

procedure TLspUnitRelationsTests.MarksEntriesNeededOnlyInImplementation;
var
  mParams: TJSONObject;
  mAnswer: TJSONValue;
  mUses_: TJSONArray;
begin
  // TB aus B wird nur in der implementation gebraucht: B lässt sich verschieben.
  FTexts.AddOrSetValue(FileOf('A'), 'unit A;'#10'interface'#10'uses'#10'  B;'#10'implementation'#10'uses'#10'  C;'#10 +
    'var'#10'  V: TB;'#10'end.');
  mParams := TJSONObject.Create;
  try
    mParams.AddPair('uri', FileOf('A'));
    mAnswer := FRelations.Request(mParams);
    try
      mUses_ := mAnswer.GetValue<TJSONArray>('uses');
      Assert.AreEqual('B', mUses_.Items[0].GetValue<string>('name'));
      Assert.IsTrue(mUses_.Items[0].GetValue<Boolean>('onlyImplementation'));
      Assert.IsNull((mUses_.Items[0] as TJSONObject).GetValue('unused'));
      Assert.IsNull((mUses_.Items[1] as TJSONObject).GetValue('onlyImplementation'), 'C steht schon dort');
      Assert.IsTrue(mUses_.Items[1].GetValue<Boolean>('unused'));
    finally
      mAnswer.Free;
    end;
  finally
    mParams.Free;
  end;
end;

procedure TLspUnitRelationsTests.CostCommandAnswersRecompileCount;
var
  mArgs: TJSONArray;
  mAnswer: TJSONValue;
begin
  mArgs := Arguments([FileOf('A')]);
  try
    mAnswer := FRelations.Cost(mArgs);
    try
      Assert.IsTrue(mAnswer.GetValue<Boolean>('found'));
      Assert.AreEqual('A', mAnswer.GetValue<string>('unit'));
      Assert.AreEqual(2, mAnswer.GetValue<Integer>('recompileCount'), 'B und D');
      Assert.AreEqual('B', mAnswer.GetValue<TJSONArray>('units').Items[0].Value);
      Assert.AreEqual('D', mAnswer.GetValue<TJSONArray>('units').Items[1].Value);
      Assert.AreEqual(FIndex.Generation, mAnswer.GetValue<Int64>('generation'));
      Assert.IsTrue(FGraph.Options.IncludeLibrary, 'derselbe Graph wie atlas/unitRelations');
    finally
      mAnswer.Free;
    end;
  finally
    mArgs.Free;
  end;
  mArgs := Arguments([FileOf('C')]);
  try
    mAnswer := FRelations.Cost(mArgs);
    try
      // A verwendet C nur im implementation: A wird neu übersetzt, B und D nicht.
      Assert.AreEqual(1, mAnswer.GetValue<Integer>('recompileCount'));
    finally
      mAnswer.Free;
    end;
  finally
    mArgs.Free;
  end;
  mArgs := TJSONArray.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        FRelations.Cost(mArgs).Free;
      end, EJsonRpcError);
  finally
    mArgs.Free;
  end;
end;

procedure TLspUnitRelationsTests.UseUnitInfoListsInUsesAndCycles;
var
  mArgs: TJSONArray;
  mAnswer: TJSONValue;
  mCycles: TJSONArray;
begin
  mArgs := Arguments([FileOf('A')]);
  try
    mAnswer := FRelations.UseUnitInfo(mArgs);
    try
      Assert.IsTrue(mAnswer.GetValue<Boolean>('found'));
      Assert.AreEqual('A', mAnswer.GetValue<string>('unit'));
      // „schon in uses“: beide Listen aus dem Text.
      Assert.AreEqual(2, mAnswer.GetValue<TJSONArray>('inUses').Count);
      Assert.AreEqual('B', mAnswer.GetValue<TJSONArray>('inUses').Items[0].Value);
      Assert.AreEqual('C', mAnswer.GetValue<TJSONArray>('inUses').Items[1].Value);
      // B verwendet A im interface (Kreis, den der Compiler ablehnt), D nur im implementation.
      mCycles := mAnswer.GetValue<TJSONArray>('cycles');
      Assert.AreEqual(2, mCycles.Count);
      Assert.AreEqual('B', (mCycles.Items[0] as TJSONObject).GetValue<string>('name'));
      Assert.AreEqual('A → B → A', (mCycles.Items[0] as TJSONObject).GetValue('interfacePath').Value);
      Assert.AreEqual('D', (mCycles.Items[1] as TJSONObject).GetValue<string>('name'));
      Assert.IsNull((mCycles.Items[1] as TJSONObject).GetValue('interfacePath'));
      Assert.AreEqual('A → D → A', (mCycles.Items[1] as TJSONObject).GetValue('path').Value);
      Assert.AreEqual(FIndex.Generation, mAnswer.GetValue<Int64>('generation'));
    finally
      mAnswer.Free;
    end;
  finally
    mArgs.Free;
  end;
  mArgs := Arguments([FileOf('C')]);
  try
    mAnswer := FRelations.UseUnitInfo(mArgs);
    try
      Assert.AreEqual(0, mAnswer.GetValue<TJSONArray>('inUses').Count);
      // A, B und D erreichen C nur über das implementation-uses von A: überall nur ein Hinweis.
      mCycles := mAnswer.GetValue<TJSONArray>('cycles');
      Assert.AreEqual(3, mCycles.Count);
      Assert.AreEqual('C → B → A → C', (mCycles.Items[1] as TJSONObject).GetValue('path').Value);
      Assert.IsNull((mCycles.Items[1] as TJSONObject).GetValue('interfacePath'));
    finally
      mAnswer.Free;
    end;
  finally
    mArgs.Free;
  end;
  mArgs := TJSONArray.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        FRelations.UseUnitInfo(mArgs).Free;
      end, EJsonRpcError);
  finally
    mArgs.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspUnitRelationsTests);

end.
