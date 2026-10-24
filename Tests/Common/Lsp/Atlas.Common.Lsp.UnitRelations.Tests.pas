unit Atlas.Common.Lsp.UnitRelations.Tests;

// Tests der Unit-Beziehungen im LSP-Server (#593): atlas/unitRelations mit
// Tiefe, Generation und ungenutzten Einträgen, der Befehl atlas.unitRelations,
// Verschieben zwischen interface- und implementation-uses über
// atlas.server.moveUses und Entfernen nur ungenutzter Einträge über
// atlas.server.removeUses.

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
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.UsesActions,
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
  Value: string;
begin
  Result := TJSONArray.Create;
  for Value in AValues do
    Result.Add(Value);
end;

/// <summary>Text nach den Edits des WorkspaceEdit aus der Antwort {"edit": …}.</summary>
function Applied(const AText: string; AAnswer: TJSONValue): string;
var
  Changes: TJSONObject;
  Item: TJSONValue;
  Edits: TArray<TTextEdit>;
  Edit: TTextEdit;
begin
  Changes := (AAnswer as TJSONObject).GetValue<TJSONObject>('edit.changes');
  Assert.AreEqual(1, Changes.Count, 'eine Datei');
  Edits := nil;
  for Item in Changes.Pairs[0].JsonValue as TJSONArray do
  begin
    Edit := Default(TTextEdit);
    Edit.Range.StartPos.Line := Item.GetValue<Integer>('range.start.line');
    Edit.Range.StartPos.Character := Item.GetValue<Integer>('range.start.character');
    Edit.Range.EndPos.Line := Item.GetValue<Integer>('range.end.line');
    Edit.Range.EndPos.Character := Item.GetValue<Integer>('range.end.character');
    Edit.NewText := Item.GetValue<string>('newText');
    Edits := Edits + [Edit];
  end;
  Result := TChangeSignature.ApplyEdits(AText, Edits);
end;

{ TLspUnitRelationsTests }

procedure TLspUnitRelationsTests.Setup;
var
  Texts: TDictionary<string, string>;
  Self_: TLspUnitRelationsTests;

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
  Texts := FTexts;
  Self_ := Self;
  FOptionsAsked := 0;
  FRelations := TLspUnitRelations.Create(FGraph,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Texts.TryGetValue(AFileName, AText);
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
            Result.Names := ['TB'];
        end;
      Result := True;
    end,
    function(const AFileName: string): TUsesGraphOptions
    begin
      Inc(Self_.FOptionsAsked);
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
  Params: TJSONObject;
  Answer: TJSONValue;
  Uses_: TJSONArray;
begin
  Params := TJSONObject.Create;
  try
    // Pfad statt URI: unter FPC/Linux führt die URI nicht auf denselben Windows-Pfad zurück.
    Params.AddPair('uri', FileOf('A'));
    Answer := FRelations.Request(Params);
    try
      Assert.IsTrue(Answer.GetValue<Boolean>('found'));
      Assert.AreEqual(1, Answer.GetValue<Integer>('depth'), 'Vorgabe: direkt');
      Assert.AreEqual(FIndex.Generation, Answer.GetValue<Int64>('generation'));
      Assert.IsTrue(FOptionsAsked > 0, 'Optionen je Datei');
      Assert.IsTrue(FGraph.Options.IncludeLibrary, 'Bibliotheks-Units immer im Graphen');
      Uses_ := Answer.GetValue<TJSONArray>('uses');
      Assert.AreEqual(2, Uses_.Count);
      Assert.IsTrue(Uses_.Items[0].GetValue<Boolean>('cycle'), 'A ↔ B');
      Assert.IsTrue(Uses_.Items[1].GetValue<Boolean>('unused'), 'C liefert nichts');
      Assert.AreEqual(2, Answer.GetValue<TJSONArray>('usedBy').Count);
      Assert.AreEqual(2, Answer.GetValue<Integer>('recompileCount'), 'B und D');
    finally
      Answer.Free;
    end;
  finally
    Params.Free;
  end;
end;

procedure TLspUnitRelationsTests.CommandTakesDepthOption;
var
  Args: TJSONArray;
  Options: TJSONObject;
  Answer: TJSONValue;
begin
  Args := Arguments([FileOf('A')]);
  try
    Options := TJSONObject.Create;
    Options.AddPair('depth', TJSONNumber.Create(0));
    Args.AddElement(Options);
    Answer := FRelations.Execute(Args);
    try
      Assert.AreEqual(0, Answer.GetValue<Integer>('depth'));
      // B → A ist die Wurzel: wiederholt, nicht aufgeklappt.
      Assert.IsTrue(((Answer.GetValue<TJSONArray>('uses').Items[0] as TJSONObject).GetValue<TJSONArray>('children')
        .Items[0] as TJSONObject).GetValue<Boolean>('repeated'));
    finally
      Answer.Free;
    end;
  finally
    Args.Free;
  end;
end;

procedure TLspUnitRelationsTests.RequestNeedsUri;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        FRelations.Request(Params).Free;
      end, EJsonRpcError);
    Params.AddPair('uri', FileOf('A'));
    Params.AddPair('depth', TJSONNumber.Create(-1));
    Assert.WillRaise(
      procedure
      begin
        FRelations.Request(Params).Free;
      end, EJsonRpcError);
  finally
    Params.Free;
  end;
end;

procedure TLspUnitRelationsTests.MovesBetweenSections;
var
  Args: TJSONArray;
  Answer: TJSONValue;
  Text: string;
begin
  Text := FTexts[FileOf('A')];
  Args := Arguments([FileOf('A'), 'B', 'implementation']);
  try
    Answer := FRelations.Move(Args);
    try
      Assert.AreEqual('unit A;'#10'interface'#10#10'implementation'#10'uses'#10'  C,'#10'  B;'#10'end.',
        Applied(Text, Answer));
    finally
      Answer.Free;
    end;
  finally
    Args.Free;
  end;
  Args := Arguments([FileOf('A'), 'c', 'interface']);
  try
    Answer := FRelations.Move(Args);
    try
      Assert.AreEqual('unit A;'#10'interface'#10'uses'#10'  B,'#10'  C;'#10'implementation'#10#10'end.',
        Applied(Text, Answer), 'Schreibweise aus dem Quelltext');
    finally
      Answer.Free;
    end;
  finally
    Args.Free;
  end;
end;

procedure TLspUnitRelationsTests.MoveRejectsWrongTargets;
var
  Edits: TArray<TTextEdit>;
  Error: string;

  procedure Fails(const AValues: array of string);
  var
    Args: TJSONArray;
  begin
    Args := Arguments(AValues);
    try
      Assert.WillRaise(
        procedure
        begin
          FRelations.Move(Args).Free;
        end, EJsonRpcError);
    finally
      Args.Free;
    end;
  end;

begin
  Assert.IsFalse(TLspUnitRelations.MoveEdits(FTexts[FileOf('A')], 'B', TUsesSection.Interface_, Edits, Error));
  Assert.IsTrue(Error.Contains('interface'), Error);
  Assert.IsFalse(TLspUnitRelations.MoveEdits(FTexts[FileOf('A')], 'X', TUsesSection.Interface_, Edits, Error));
  Assert.IsNull(Edits);
  Fails([FileOf('A'), 'B', 'interface']);
  Fails([FileOf('A'), 'B', 'woanders']);
  Fails([FileOf('A'), 'B']);
  FTexts.AddOrSetValue('C:\Projekt\P.dpr', 'program P;'#10'uses'#10'  A;'#10'begin'#10'end.');
  Fails(['C:\Projekt\P.dpr', 'A', 'implementation']);
end;

procedure TLspUnitRelationsTests.RemovesOnlyUnusedEntries;
var
  Args: TJSONArray;
  Answer: TJSONValue;
  Text: string;
begin
  Text := 'unit A;'#10'interface'#10'uses'#10'  B;'#10'type'#10'  T = TB;'#10'implementation'#10'uses'#10'  C;'#10'end.';
  FTexts.AddOrSetValue(FileOf('A'), Text);
  Args := Arguments([FileOf('A'), 'C']);
  try
    Answer := FRelations.Remove(Args);
    try
      Assert.IsFalse(Applied(Text, Answer).Contains('C;'), 'C entfernt');
      Assert.IsTrue(Applied(Text, Answer).Contains('  B;'), 'B bleibt');
    finally
      Answer.Free;
    end;
  finally
    Args.Free;
  end;
  Args := Arguments([FileOf('A'), 'B']);
  try
    Assert.WillRaise(
      procedure
      begin
        FRelations.Remove(Args).Free;
      end, EJsonRpcError, 'B wird verwendet');
  finally
    Args.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspUnitRelationsTests);

end.
