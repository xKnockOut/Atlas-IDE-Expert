unit Atlas.Common.Lsp.SlashMenu.Tests;

// Tests für die Befehle des Erzeugen-Menüs (#719): passende Schnellbefehle
// an der Stelle, Auswahl möglicher Argumente, Ausführen mit Änderungen bzw.
// Grund, abgeschaltete Befehle und ganz abgeschaltete Schnellbefehle sowie
// „Interface implementieren“ (#466) als Menübefehl ohne Schnellbefehl.

interface

uses
  DUnitX.TestFramework,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.SlashMenu;

type
  [TestFixture]
  TLspSlashMenuTests = class
  private
    FStore: IDocumentStore;
    FMenu: TLspSlashMenu;
    FEnabled: Boolean;
    FDisabled: TArray<string>;
    function Arguments(ALine, AEndLine: Integer): TJSONArray; overload;
    function Arguments(ALine, AEndLine: Integer; const AName: string): TJSONArray; overload;
    function Arguments(ALine, AEndLine: Integer; const AName, AArgument: string): TJSONArray; overload;
    function Names(AResult: TJSONValue): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MenuInClassOffersGenerateCommands;
    [Test]
    procedure MenuWithSelectionOffersSurround;
    [Test]
    procedure MenuLeavesOutDisabledCommands;
    [Test]
    procedure MenuWhenSlashCommandsOff;
    [Test]
    procedure ChoicesListFields;
    [Test]
    procedure RunReturnsEditsOrReason;
    [Test]
    procedure UnknownDocumentFails;
    [Test]
    procedure ImplementsMissingInterfaceMethods;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Completion;

const
  FileName = 'C:\P\Foo.pas';
  Text =
    'unit Foo;'#10 +                     // 0
    'interface'#10 +                     // 1
    'type'#10 +                          // 2
    '  TFoo = class'#10 +                // 3
    '  private'#10 +                     // 4
    '    FName: string;'#10 +            // 5
    '  end;'#10 +                        // 6
    'implementation'#10 +                // 7
    'procedure Frei;'#10 +               // 8
    'begin'#10 +                         // 9
    '  Schritt1;'#10 +                   // 10
    '  Schritt2;'#10 +                   // 11
    'end;'#10 +                          // 12
    'end.';

function Field(AValue: TJSONValue; const AName: string): string;
begin
  Result := AValue.GetValue<string>(AName);
end;

function Flag(AValue: TJSONValue; const AName: string): Boolean;
begin
  Result := AValue.GetValue<Boolean>(AName);
end;

function List(AValue: TJSONValue; const AName: string): TJSONArray;
begin
  Result := AValue.GetValue<TJSONArray>(AName);
end;

procedure TLspSlashMenuTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FStore.Open(TDocumentUris.FromPath(FileName), 'pascal', 1, Text);
  FEnabled := True;
  FDisabled := nil;
  FMenu := TLspSlashMenu.Create(FStore);
  FMenu.SlashCommandsFor :=
    function(const AUri: string; out ADisabled: TArray<string>): Boolean
    begin
      ADisabled := FDisabled;
      Result := FEnabled;
    end;
end;

procedure TLspSlashMenuTests.TearDown;
begin
  FMenu.Free;
  FStore := nil;
end;

function TLspSlashMenuTests.Arguments(ALine, AEndLine: Integer): TJSONArray;
var
  Position: TJSONObject;
begin
  Position := TJSONObject.Create;
  Position.AddPair('line', TJSONNumber.Create(ALine));
  Position.AddPair('character', TJSONNumber.Create(0));
  Result := TJSONArray.Create;
  Result.Add(TDocumentUris.FromPath(FileName));
  Result.AddElement(Position);
  Result.Add(AEndLine);
end;

function TLspSlashMenuTests.Arguments(ALine, AEndLine: Integer; const AName: string): TJSONArray;
begin
  Result := Arguments(ALine, AEndLine);
  Result.Add(AName);
end;

function TLspSlashMenuTests.Arguments(ALine, AEndLine: Integer; const AName, AArgument: string): TJSONArray;
begin
  Result := Arguments(ALine, AEndLine, AName);
  Result.Add(AArgument);
end;

function TLspSlashMenuTests.Names(AResult: TJSONValue): string;
var
  Item: TJSONValue;
begin
  Result := '';
  for Item in TJSONObject(AResult).GetValue<TJSONArray>('commands') do
    Result := Result + ',' + Item.GetValue<string>('name');
  Result := Result + ',';
end;

procedure TLspSlashMenuTests.MenuInClassOffersGenerateCommands;
var
  Args: TJSONArray;
  Answer: TJSONValue;
  First: TJSONObject;
  Group, Argument: string;
  Choices: Boolean;
begin
  Args := Arguments(5, -1);
  Answer := FMenu.ExecuteMenu(Args);
  try
    Assert.IsTrue(Flag(Answer, 'enabled'));
    Assert.AreEqual('class', List(Answer, 'places').Items[0].Value);
    Assert.IsTrue(Pos(',ctor,', Names(Answer)) > 0, Names(Answer));
    Assert.IsTrue(Pos(',todo,', Names(Answer)) > 0, 'überall');
    Assert.AreEqual(0, Pos(',try,', Names(Answer)), 'Umschließen nur mit Markierung');
    Assert.AreEqual(0, Pos(',raise,', Names(Answer)), 'nur in Routinen');
    First := TJSONObject(TJSONObject(Answer).GetValue<TJSONArray>('commands').Items[0]);
    Assert.AreEqual('ctor', Field(First, 'name'));
    Group := First.GetValue<string>('group');
    Argument := First.GetValue<string>('argument');
    Choices := First.GetValue<Boolean>('choices');
    Assert.AreEqual('generate', Group);
    Assert.AreEqual('optional', Argument);
    Assert.IsTrue(Choices);
    Assert.IsTrue(Field(First, 'summary') <> '');
  finally
    Answer.Free;
    Args.Free;
  end;
end;

procedure TLspSlashMenuTests.MenuWithSelectionOffersSurround;
var
  Args: TJSONArray;
  Answer: TJSONValue;
begin
  Args := Arguments(10, 11);
  Answer := FMenu.ExecuteMenu(Args);
  try
    Assert.IsTrue(Pos(',try,', Names(Answer)) > 0, Names(Answer));
    Assert.IsTrue(Pos(',raise,', Names(Answer)) > 0, Names(Answer));
    Assert.AreEqual(0, Pos(',ctor,', Names(Answer)), 'keine Klasse');
  finally
    Answer.Free;
    Args.Free;
  end;
end;

procedure TLspSlashMenuTests.MenuLeavesOutDisabledCommands;
var
  Args: TJSONArray;
  Answer: TJSONValue;
begin
  FDisabled := ['ctor'];
  Args := Arguments(5, -1);
  Answer := FMenu.ExecuteMenu(Args);
  try
    Assert.AreEqual(0, Pos(',ctor,', Names(Answer)), Names(Answer));
    Assert.IsTrue(Pos(',dtor,', Names(Answer)) > 0, Names(Answer));
  finally
    Answer.Free;
    Args.Free;
  end;
end;

procedure TLspSlashMenuTests.MenuWhenSlashCommandsOff;
var
  Args: TJSONArray;
  Answer: TJSONValue;
  Run: TJSONValue;
begin
  FEnabled := False;
  Args := Arguments(5, -1);
  Answer := FMenu.ExecuteMenu(Args);
  try
    Assert.IsFalse(Flag(Answer, 'enabled'));
    Assert.AreEqual(',', Names(Answer));
  finally
    Answer.Free;
    Args.Free;
  end;
  Args := Arguments(5, -1, 'ctor');
  Run := FMenu.ExecuteRun(Args);
  try
    Assert.IsTrue(Pos('abgeschaltet', Field(Run, 'reason')) > 0);
  finally
    Run.Free;
    Args.Free;
  end;
end;

procedure TLspSlashMenuTests.ChoicesListFields;
var
  Args: TJSONArray;
  Answer: TJSONValue;
begin
  Args := Arguments(5, -1, 'ctor');
  Answer := FMenu.ExecuteChoices(Args);
  try
    Assert.AreEqual(1, TJSONArray(Answer).Count);
    Assert.AreEqual('FName', TJSONArray(Answer).Items[0].Value);
  finally
    Answer.Free;
    Args.Free;
  end;
end;

procedure TLspSlashMenuTests.RunReturnsEditsOrReason;
var
  Args: TJSONArray;
  Answer: TJSONValue;
  Edits: TJSONArray;
  Item: TJSONValue;
  NewText: string;
begin
  Args := Arguments(5, -1, 'ctor', 'FName');
  Answer := FMenu.ExecuteRun(Args);
  try
    Assert.AreEqual('', Field(Answer, 'reason'));
    Edits := TJSONObject(Answer).GetValue<TJSONArray>('edits');
    Assert.IsTrue(Edits.Count > 0);
    NewText := '';
    for Item in Edits do
      NewText := NewText + Item.GetValue<string>('newText');
    Assert.IsTrue(Pos('constructor Create(const AName: string);', NewText) > 0, NewText);
  finally
    Answer.Free;
    Args.Free;
  end;
  Args := Arguments(10, -1, 'ctor', '');
  Answer := FMenu.ExecuteRun(Args);
  try
    Assert.AreEqual(0, List(Answer, 'edits').Count);
    Assert.IsTrue(Field(Answer, 'reason') <> '');
  finally
    Answer.Free;
    Args.Free;
  end;
end;

procedure TLspSlashMenuTests.UnknownDocumentFails;
var
  Args: TJSONArray;
begin
  Args := TJSONArray.Create;
  try
    Args.Add('file:///C:/gibts/nicht.pas');
    Args.AddElement(TJSONObject.Create);
    Args.Add(-1);
    Assert.WillRaise(
      procedure
      begin
        FMenu.ExecuteMenu(Args).Free;
      end, EJsonRpcError);
  finally
    Args.Free;
  end;
end;

procedure TLspSlashMenuTests.ImplementsMissingInterfaceMethods;
const
  UnitBasis =
    'unit Basis;'#10'interface'#10'type'#10 +
    '  IFlush = interface'#10 +
    '    procedure Flush;'#10 +
    '  end;'#10 +
    'implementation'#10'end.';
  HauptFile = 'C:\P\Haupt.pas';
  Haupt =
    'unit Haupt;'#10 +                                   // 0
    'interface'#10 +                                     // 1
    'uses Basis;'#10 +                                   // 2
    'type'#10 +                                          // 3
    '  TExporter = class(TInterfacedObject, IFlush)'#10 + // 4
    '  private'#10 +                                     // 5
    '    FText: string;'#10 +                            // 6
    '  end;'#10 +                                        // 7
    'implementation'#10 +                                // 8
    'end.';
var
  Index: ISymbolIndex;
  Completion: TLspCompletion;
  Args, Position: TJSONArray;
  Answer: TJSONValue;
  Item: TJSONValue;
  NewText, Names_: string;
  Edits: TJSONArray;
  Spot: TJSONObject;
  FirstLine: Integer;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(UnitBasis, 'C:\P\Basis.pas', nil));
  FStore.Open(TDocumentUris.FromPath(HauptFile), 'pascal', 1, Haupt);
  Completion := TLspCompletion.Create(FStore, Index, nil);
  try
    Completion.ReadText :=
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := UnitBasis;
        Result := SameText(AFileName, 'C:\P\Basis.pas');
      end;
    FMenu.Index := Index;
    FMenu.Completion := Completion;
    Spot := TJSONObject.Create;
    Spot.AddPair('line', TJSONNumber.Create(6));
    Spot.AddPair('character', TJSONNumber.Create(4));
    Position := TJSONArray.Create;
    Position.Add(TDocumentUris.FromPath(HauptFile));
    Position.AddElement(Spot);
    Position.Add(-1);
    try
      // Nach /override, wie im Mockup.
      Answer := FMenu.ExecuteMenu(Position);
      try
        Names_ := Names(Answer);
        Assert.IsTrue(Pos(',override,implement,', Names_) > 0, Names_);
      finally
        Answer.Free;
      end;
      Args := TJSONArray(Position.Clone);
      try
        Args.Add(TLspSlashMenu.ImplementName);
        Answer := FMenu.ExecuteChoices(Args);
        try
          Assert.AreEqual(1, TJSONArray(Answer).Count);
          Assert.AreEqual('IFlush.Flush', TJSONArray(Answer).Items[0].Value);
        finally
          Answer.Free;
        end;
        Args.Add('');
        Answer := FMenu.ExecuteRun(Args);
        try
          Assert.AreEqual('', Field(Answer, 'reason'));
          Edits := List(Answer, 'edits');
          NewText := '';
          for Item in Edits do
            NewText := NewText + Item.GetValue<string>('newText');
          Assert.IsTrue(Pos('procedure Flush;', NewText) > 0, NewText);
          Assert.IsTrue(Pos('procedure TExporter.Flush;', NewText) > 0, NewText);
          // Die Deklaration kommt vor das end der Klasse (Zeile 7 ohne die gedachte Zeile).
          FirstLine := Edits.Items[0].GetValue<Integer>('range.start.line');
          Assert.AreEqual(7, FirstLine);
        finally
          Answer.Free;
        end;
      finally
        Args.Free;
      end;
    finally
      Position.Free;
    end;
  finally
    FMenu.Completion := nil;
    Completion.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSlashMenuTests);

end.
