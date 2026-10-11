unit Atlas.Common.Editing.ClassCommands.Tests;

// Tests für die Schnellbefehle /impl, /ctor, /dtor, /override und /msg (#295).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TClassCommandsTests = class
  public
    /// <summary>Führt einen Befehl vorab aus; einmalig angelegte Daten zählen sonst als Leck des ersten Tests.</summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure ImplAddsMissingBodies;
    [Test]
    procedure ImplWithoutMissingFails;
    [Test]
    procedure CtorTakesFields;
    [Test]
    procedure CtorOwner;
    [Test]
    procedure DtorFreesCreatedFields;
    [Test]
    procedure MsgUsesRecordType;
    [Test]
    procedure MessageNames;
    [Test]
    procedure OverrideInSameFile;
    [Test]
    procedure OverrideFromIndex;
    [Test]
    procedure OverrideUnknownFails;
    [Test]
    procedure OutsideClassFails;
    [Test]
    procedure SignatureHelpers;
    [Test]
    procedure ResultsParseWithoutErrors;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.ClassCommands;

const
  ClassUnit =
    'unit U;'#10 +                                  // 0
    'interface'#10 +                                // 1
    'type'#10 +                                     // 2
    '  TBasis = class'#10 +                         // 3
    '  protected'#10 +                              // 4
    '    function Wert(const A: Integer; B: string): Integer; virtual;'#10 + // 5
    '    procedure Lauf; virtual;'#10 +             // 6
    '  end;'#10 +                                   // 7
    '  TFoo = class(TBasis)'#10 +                   // 8
    '  private'#10 +                                // 9
    '    FListe: TStringList;'#10 +                 // 10
    '    FName: string;'#10 +                       // 11
    '  public'#10 +                                 // 12
    '    procedure Run;'#10 +                       // 13
    '    procedure Stop;'#10 +                      // 14
    '    %s'#10 +                                   // 15 Befehl
    '  end;'#10 +                                   // 16
    'implementation'#10 +                           // 17
    #10 +                                           // 18
    'procedure TFoo.Run;'#10 +                      // 19
    'begin'#10 +                                    // 20
    'end;'#10 +                                     // 21
    #10 +                                           // 22
    'end.';

function Run(const AText: string; ALine: Integer; out AEdits: TArray<TRuleEdit>;
  const AIndex: ISymbolIndex = nil): Boolean;
begin
  Result := TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0), nil, nil, AEdits,
    AIndex);
end;

function WithCommand(const ACommand: string): string;
begin
  Result := Format(ClassUnit, [ACommand]);
end;

/// <summary>Wendet AEdits (nicht überlappend) auf AText an.</summary>
function Apply(const AText: string; AEdits: TArray<TRuleEdit>): string;
var
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Offsets: TArray<Integer>;
  Index, Start, Stop: Integer;
begin
  Lines := AText.Split([#10]);
  SetLength(Offsets, Length(Lines) + 1);
  Offsets[0] := 0;
  for Index := 0 to High(Lines) do
    Offsets[Index + 1] := Offsets[Index] + Length(Lines[Index]) + 1;
  TArray.Sort<TRuleEdit>(AEdits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for Edit in AEdits do
  begin
    Start := Offsets[Edit.Range.StartPos.Line] + Edit.Range.StartPos.Character;
    Stop := Offsets[Edit.Range.EndPos.Line] + Edit.Range.EndPos.Character;
    Result := Copy(Result, 1, Start) + Edit.NewText + Copy(Result, Stop + 1, MaxInt);
  end;
end;

function Expand(const ACommand: string; const AIndex: ISymbolIndex = nil): string;
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run(WithCommand(ACommand), 15, Edits, AIndex), ACommand);
  Result := Apply(WithCommand(ACommand), Edits);
end;

function Parses(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

procedure TClassCommandsTests.WarmUp;
begin
  Expand('/impl');
  Parses(WithCommand(''));
end;

procedure TClassCommandsTests.ImplAddsMissingBodies;
var
  Text: string;
begin
  Text := Expand('/impl');
  Assert.IsTrue(Pos('procedure TFoo.Stop;', Text) > 0, Text);
  Assert.AreEqual(0, Pos('/impl', Text), Text);
end;

procedure TClassCommandsTests.ImplWithoutMissingFails;
var
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  Text := StringReplace(WithCommand('/impl'), '    procedure Stop;'#10, '', []);
  Assert.IsFalse(Run(Text, 14, Edits));
end;

procedure TClassCommandsTests.CtorTakesFields;
var
  Text: string;
begin
  Text := Expand('/ctor');
  Assert.IsTrue(Pos('  public'#10'    constructor Create(const AListe: TStringList; const AName: string);'#10'  end;',
    Text) > 0, Text);
  Assert.IsTrue(Pos('constructor TFoo.Create(const AListe: TStringList; const AName: string);'#10'begin'#10 +
    '  inherited Create;'#10'  FListe := AListe;'#10'  FName := AName;'#10'end;', Text) > 0, Text);
end;

procedure TClassCommandsTests.CtorOwner;
var
  Text: string;
begin
  Text := Expand('/ctor owner');
  Assert.IsTrue(Pos('    constructor Create(AOwner: TComponent); override;', Text) > 0, Text);
  Assert.IsTrue(Pos('  inherited Create(AOwner);', Text) > 0, Text);
end;

procedure TClassCommandsTests.DtorFreesCreatedFields;
var
  Text, Source: string;
  Edits: TArray<TRuleEdit>;
begin
  Source := StringReplace(WithCommand('/dtor'), '    procedure Stop;'#10, '    constructor Create;'#10, []);
  Source := StringReplace(Source, 'procedure TFoo.Run;', 'constructor TFoo.Create;'#10'begin'#10 +
    '  FListe := TStringList.Create;'#10'  FName := ''x'';'#10'end;'#10#10'procedure TFoo.Run;', []);
  Assert.IsTrue(Run(Source, 15, Edits));
  Text := Apply(Source, Edits);
  Assert.IsTrue(Pos('    destructor Destroy; override;', Text) > 0, Text);
  Assert.IsTrue(Pos('destructor TFoo.Destroy;'#10'begin'#10'  FreeAndNil(FListe);'#10'  inherited;'#10'end;', Text) > 0,
    Text);
end;

procedure TClassCommandsTests.MsgUsesRecordType;
var
  Text: string;
begin
  Text := Expand('/msg WM_SIZE');
  Assert.IsTrue(Pos('  protected'#10'    procedure WMSize(var Message: TWMSize); message WM_SIZE;', Text) > 0, Text);
  Assert.IsTrue(Pos('procedure TFoo.WMSize(var Message: TWMSize);'#10'begin'#10'  inherited;'#10'end;', Text) > 0,
    Text);
end;

procedure TClassCommandsTests.MessageNames;
begin
  Assert.AreEqual('CMMouseEnter', MessageMethodName('CM_MOUSEENTER'));
  Assert.AreEqual('WMGetMinMaxInfo', MessageMethodName('WM_GETMINMAXINFO'));
  Assert.AreEqual('TMessage', MessageRecord('CM_MOUSEENTER'));
end;

procedure TClassCommandsTests.OverrideInSameFile;
var
  Text: string;
begin
  Text := Expand('/override Wert');
  Assert.IsTrue(Pos('  protected'#10'    function Wert(const A: Integer; B: string): Integer; override;', Text) > 0,
    Text);
  Assert.IsTrue(Pos('function TFoo.Wert(const A: Integer; B: string): Integer;'#10'begin'#10 +
    '  Result := inherited Wert(A, B);'#10'end;', Text) > 0, Text);
  Text := Expand('/override Lauf');
  Assert.IsTrue(Pos('procedure TFoo.Lauf;'#10'begin'#10'  inherited;'#10'end;', Text) > 0, Text);
end;

procedure TClassCommandsTests.OverrideFromIndex;
const
  Controls =
    'unit Vcl.Controls;'#10'interface'#10'type'#10 +
    '  TControl = class(TComponent)'#10'  end;'#10 +
    '  TCustomControl = class(TControl)'#10'  protected'#10'    procedure Paint; virtual;'#10'  end;'#10 +
    'implementation'#10'end.';
  Source =
    'unit U;'#10'interface'#10'type'#10'  TBild = class(TCustomControl)'#10'  public'#10'    /override Paint'#10 +
    '  end;'#10'implementation'#10'end.';
var
  Index: ISymbolIndex;
  Tree: TSyntaxTree;
  FileName, Text: string;
  Edits: TArray<TRuleEdit>;
begin
  FileName := TPath.Combine(TPath.GetTempPath, 'Atlas.ClassCommands.Controls.pas');
  TFile.WriteAllText(FileName, Controls);
  try
    Index := TSymbolIndex.Create;
    Tree := TPascalParser.Parse(Controls);
    try
      Index.AddUnit(TIndexExtractor.Extract(Tree, FileName));
    finally
      Tree.Free;
    end;
    Assert.IsTrue(Run(Source, 5, Edits, Index));
    Text := Apply(Source, Edits);
    Assert.IsTrue(Pos('  protected'#10'    procedure Paint; override;'#10'  end;', Text) > 0, Text);
    Assert.IsTrue(Pos('procedure TBild.Paint;'#10'begin'#10'  inherited;'#10'end;', Text) > 0, Text);
    // Ohne Index kennt der Befehl TCustomControl nicht.
    Assert.IsFalse(Run(Source, 5, Edits));
  finally
    TFile.Delete(FileName);
  end;
end;

procedure TClassCommandsTests.OverrideUnknownFails;
var
  Problems: TArray<TSlashProblem>;
begin
  Problems := TSlashCommandRegistry.Shared.Problems(WithCommand('/override Gibts'), nil);
  Assert.AreEqual(1, Integer(Length(Problems)));
  Assert.AreEqual('Keine virtuelle Methode Gibts in den Vorfahren von TFoo', Problems[0].Message);
end;

procedure TClassCommandsTests.OutsideClassFails;
const
  Text = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  /ctor'#10'end;'#10'end.';
var
  Edits: TArray<TRuleEdit>;
  Problems: TArray<TSlashProblem>;
begin
  Assert.IsFalse(Run(Text, 5, Edits));
  Problems := TSlashCommandRegistry.Shared.Problems(Text, nil);
  Assert.AreEqual(1, Integer(Length(Problems)));
  Assert.AreEqual('/ctor gilt nur in einer Klasse oder einer ihrer Methoden', Problems[0].Message);
end;

procedure TClassCommandsTests.SignatureHelpers;
begin
  Assert.AreEqual('function F(const A, B: Integer; var C: string): Boolean',
    RoutineSignature('function F(const A, B: Integer;'#10'  var C: string): Boolean; virtual; abstract;'));
  Assert.AreEqual('A, B, C', ParameterNames('function F(const A, B: Integer; var C: string): Boolean'));
  Assert.AreEqual('', ParameterNames('procedure P'));
end;

procedure TClassCommandsTests.ResultsParseWithoutErrors;
const
  Commands: array[0..5] of string = ('/impl', '/ctor', '/ctor owner', '/dtor', '/msg WM_PAINT', '/override Wert');
var
  Command, Text: string;
begin
  for Command in Commands do
  begin
    Text := Expand(Command);
    Assert.IsTrue(Parses(Text), Command + ': ' + Text);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TClassCommandsTests);

end.
