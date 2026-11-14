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
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
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
  System.Generics.Collections,
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Completion;

const
  cFileName = 'C:\P\Foo.pas';
  cText =
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

procedure TLspSlashMenuTests.WarmUpFirstUse;
begin
  Setup;
  try
    MenuLeavesOutDisabledCommands;
  finally
    TearDown;
  end;
  Setup;
  try
    ImplementsMissingInterfaceMethods;
  finally
    TearDown;
  end;
end;

procedure TLspSlashMenuTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FStore.Open(TDocumentUris.FromPath(cFileName), 'pascal', 1, cText);
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
  // Vom Test gesetzt; der Leckmonitor zählte das Feld sonst dem Test an.
  FDisabled := nil;
end;

function TLspSlashMenuTests.Arguments(ALine, AEndLine: Integer): TJSONArray;
var
  mPosition: TJSONObject;
begin
  mPosition := TJSONObject.Create;
  mPosition.AddPair('line', TJSONNumber.Create(ALine));
  mPosition.AddPair('character', TJSONNumber.Create(0));
  Result := TJSONArray.Create;
  Result.Add(TDocumentUris.FromPath(cFileName));
  Result.AddElement(mPosition);
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
  mItem: TJSONValue;
begin
  Result := '';
  for mItem in TJSONObject(AResult).GetValue<TJSONArray>('commands') do
  begin
    Result := Result + ',' + mItem.GetValue<string>('name');
  end;
  Result := Result + ',';
end;

procedure TLspSlashMenuTests.MenuInClassOffersGenerateCommands;
var
  mArgs: TJSONArray;
  mAnswer: TJSONValue;
  mFirst: TJSONObject;
  mGroup, mArgument: string;
  mChoices: Boolean;
begin
  mArgs := Arguments(5, -1);
  mAnswer := FMenu.ExecuteMenu(mArgs);
  try
    Assert.IsTrue(Flag(mAnswer, 'enabled'));
    Assert.AreEqual('class', List(mAnswer, 'places').Items[0].Value);
    Assert.IsTrue(Pos(',ctor,', Names(mAnswer)) > 0, Names(mAnswer));
    Assert.IsTrue(Pos(',todo,', Names(mAnswer)) > 0, 'überall');
    Assert.AreEqual(0, Pos(',try,', Names(mAnswer)), 'Umschließen nur mit Markierung');
    Assert.AreEqual(0, Pos(',raise,', Names(mAnswer)), 'nur in Routinen');
    mFirst := TJSONObject(TJSONObject(mAnswer).GetValue<TJSONArray>('commands').Items[0]);
    Assert.AreEqual('ctor', Field(mFirst, 'name'));
    mGroup := mFirst.GetValue<string>('group');
    mArgument := mFirst.GetValue<string>('argument');
    mChoices := mFirst.GetValue<Boolean>('choices');
    Assert.AreEqual('generate', mGroup);
    Assert.AreEqual('optional', mArgument);
    Assert.IsTrue(mChoices);
    Assert.AreNotEqual('', Field(mFirst, 'summary'));
  finally
    mAnswer.Free;
    mArgs.Free;
  end;
end;

procedure TLspSlashMenuTests.MenuWithSelectionOffersSurround;
var
  mArgs: TJSONArray;
  mAnswer: TJSONValue;
begin
  mArgs := Arguments(10, 11);
  mAnswer := FMenu.ExecuteMenu(mArgs);
  try
    Assert.IsTrue(Pos(',try,', Names(mAnswer)) > 0, Names(mAnswer));
    Assert.IsTrue(Pos(',raise,', Names(mAnswer)) > 0, Names(mAnswer));
    Assert.AreEqual(0, Pos(',ctor,', Names(mAnswer)), 'keine Klasse');
  finally
    mAnswer.Free;
    mArgs.Free;
  end;
end;

procedure TLspSlashMenuTests.MenuLeavesOutDisabledCommands;
var
  mArgs: TJSONArray;
  mAnswer: TJSONValue;
begin
  FDisabled := ['ctor'];
  mArgs := Arguments(5, -1);
  mAnswer := FMenu.ExecuteMenu(mArgs);
  try
    Assert.AreEqual(0, Pos(',ctor,', Names(mAnswer)), Names(mAnswer));
    Assert.IsTrue(Pos(',dtor,', Names(mAnswer)) > 0, Names(mAnswer));
  finally
    mAnswer.Free;
    mArgs.Free;
  end;
end;

procedure TLspSlashMenuTests.MenuWhenSlashCommandsOff;
var
  mArgs: TJSONArray;
  mAnswer: TJSONValue;
  mRun: TJSONValue;
begin
  FEnabled := False;
  mArgs := Arguments(5, -1);
  mAnswer := FMenu.ExecuteMenu(mArgs);
  try
    Assert.IsFalse(Flag(mAnswer, 'enabled'));
    Assert.AreEqual(',', Names(mAnswer));
  finally
    mAnswer.Free;
    mArgs.Free;
  end;
  mArgs := Arguments(5, -1, 'ctor');
  mRun := FMenu.ExecuteRun(mArgs);
  try
    Assert.IsTrue(Pos('abgeschaltet', Field(mRun, 'reason')) > 0);
  finally
    mRun.Free;
    mArgs.Free;
  end;
end;

procedure TLspSlashMenuTests.ChoicesListFields;
var
  mArgs: TJSONArray;
  mAnswer: TJSONValue;
begin
  mArgs := Arguments(5, -1, 'ctor');
  mAnswer := FMenu.ExecuteChoices(mArgs);
  try
    Assert.AreEqual(1, Integer(TJSONArray(mAnswer).Count));
    Assert.AreEqual('FName', TJSONArray(mAnswer).Items[0].Value);
  finally
    mAnswer.Free;
    mArgs.Free;
  end;
end;

procedure TLspSlashMenuTests.RunReturnsEditsOrReason;
var
  mArgs: TJSONArray;
  mAnswer: TJSONValue;
  mEdits: TJSONArray;
  mItem: TJSONValue;
  mNewText: string;
begin
  mArgs := Arguments(5, -1, 'ctor', 'FName');
  mAnswer := FMenu.ExecuteRun(mArgs);
  try
    Assert.AreEqual('', Field(mAnswer, 'reason'));
    mEdits := TJSONObject(mAnswer).GetValue<TJSONArray>('edits');
    Assert.IsTrue(mEdits.Count > 0);
    mNewText := '';
    for mItem in mEdits do
    begin
      mNewText := mNewText + mItem.GetValue<string>('newText');
    end;
    Assert.IsTrue(Pos('constructor Create(const AName: string);', mNewText) > 0, mNewText);
  finally
    mAnswer.Free;
    mArgs.Free;
  end;
  mArgs := Arguments(10, -1, 'ctor', '');
  mAnswer := FMenu.ExecuteRun(mArgs);
  try
    Assert.AreEqual(0, List(mAnswer, 'edits').Count);
    Assert.AreNotEqual('', Field(mAnswer, 'reason'));
  finally
    mAnswer.Free;
    mArgs.Free;
  end;
end;

procedure TLspSlashMenuTests.UnknownDocumentFails;
var
  mArgs: TJSONArray;
begin
  mArgs := TJSONArray.Create;
  try
    mArgs.Add('file:///C:/gibts/nicht.pas');
    mArgs.AddElement(TJSONObject.Create);
    mArgs.Add(-1);
    Assert.WillRaise(
      procedure
      begin
        FMenu.ExecuteMenu(mArgs).Free;
      end, EJsonRpcError);
  finally
    mArgs.Free;
  end;
end;

/// <summary>Führt „implementieren“ mit AArgs aus und prüft, dass IFlush.Flush in TExporter landet.</summary>
procedure AssertImplementsFlush(AMenu: TLspSlashMenu; AArgs: TJSONArray);
var
  mAnswer, mItem: TJSONValue;
  mEdits: TJSONArray;
  mNewText: string;
  mFirstLine: Integer;
begin
  mAnswer := AMenu.ExecuteRun(AArgs);
  try
    Assert.AreEqual('', Field(mAnswer, 'reason'));
    mEdits := List(mAnswer, 'edits');
    mNewText := '';
    for mItem in mEdits do
    begin
      mNewText := mNewText + mItem.GetValue<string>('newText');
    end;
    Assert.IsTrue(Pos('procedure Flush;', mNewText) > 0, mNewText);
    Assert.IsTrue(Pos('procedure TExporter.Flush;', mNewText) > 0, mNewText);
    // Die Deklaration kommt vor das end der Klasse (Zeile 7 ohne die gedachte Zeile).
    mFirstLine := mEdits.Items[0].GetValue<Integer>('range.start.line');
    Assert.AreEqual(7, mFirstLine);
  finally
    mAnswer.Free;
  end;
end;

const
  cImplementsMissingUnitBasis =
    'unit Basis;'#10'interface'#10'type'#10 +
    '  IFlush = interface'#10 +
    '    procedure Flush;'#10 +
    '  end;'#10 +
    'implementation'#10'end.';
  cImplementsMissingHauptFile = 'C:\P\Haupt.pas';
  cImplementsMissingHaupt =
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

procedure TLspSlashMenuTests.ImplementsMissingInterfaceMethods;
var
  mIndex: ISymbolIndex;
  mCompletion: TLspCompletion;
  mArgs, mPosition: TJSONArray;
  mAnswer: TJSONValue;
  mNames_: string;
  mSpot: TJSONObject;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cImplementsMissingUnitBasis, 'C:\P\Basis.pas', nil));
  FStore.Open(TDocumentUris.FromPath(cImplementsMissingHauptFile), 'pascal', 1, cImplementsMissingHaupt);
  mCompletion := TLspCompletion.Create(FStore, mIndex, nil);
  try
    mCompletion.Hooks.ReadText :=
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := cImplementsMissingUnitBasis;
        Result := SameText(AFileName, 'C:\P\Basis.pas');
      end;
    FMenu.Index := mIndex;
    FMenu.Completion := mCompletion;
    mSpot := TJSONObject.Create;
    mSpot.AddPair('line', TJSONNumber.Create(6));
    mSpot.AddPair('character', TJSONNumber.Create(4));
    mPosition := TJSONArray.Create;
    mPosition.Add(TDocumentUris.FromPath(cImplementsMissingHauptFile));
    mPosition.AddElement(mSpot);
    mPosition.Add(-1);
    try
      // Nach /override, wie im Mockup.
      mAnswer := FMenu.ExecuteMenu(mPosition);
      try
        mNames_ := Names(mAnswer);
        Assert.IsTrue(Pos(',override,implement,', mNames_) > 0, mNames_);
      finally
        mAnswer.Free;
      end;
      mArgs := TJSONArray(mPosition.Clone);
      try
        mArgs.Add(TLspSlashMenu.cImplementName);
        mAnswer := FMenu.ExecuteChoices(mArgs);
        try
          Assert.AreEqual(1, Integer(TJSONArray(mAnswer).Count));
          Assert.AreEqual('IFlush.Flush', TJSONArray(mAnswer).Items[0].Value);
        finally
          mAnswer.Free;
        end;
        mArgs.Add('');
        AssertImplementsFlush(FMenu, mArgs);
      finally
        mArgs.Free;
      end;
    finally
      mPosition.Free;
    end;
  finally
    FMenu.Completion := nil;
    mCompletion.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSlashMenuTests);

end.
