unit Atlas.Common.Editing.ClassCommands.Tests;

// Tests für die Schnellbefehle /impl, /ctor, /dtor, /override, /msg und /intf (#295).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TClassCommandsTests = class
  public
    /// <summary>Führt einen Befehl vorab aus; einmalig angelegte Daten zählen sonst als Leck des ersten
    /// Tests.</summary>
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
    [Test]
    procedure DtorKeepsPassedReferences;
    [Test]
    procedure DtorExtendsExisting;
    [Test]
    procedure DtorAndMsgWrongPlaceFail;
    [Test]
    procedure IntfAddsInterfaceAndMethods;
    [Test]
    procedure IntfWithoutAncestorList;
    [Test]
    procedure IntfWrongPlaceFails;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
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
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.ClassCommands;

const
  cClassUnit =
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
  const AIndex: ISymbolIndex): Boolean; overload;
begin
  Result := TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0), nil, nil, AEdits,
    AIndex);
end;

function Run(const AText: string; ALine: Integer; out AEdits: TArray<TRuleEdit>): Boolean; overload;
begin
  Result := Run(AText, ALine, AEdits, nil);
end;

function WithCommand(const ACommand: string): string;
begin
  Result := Format(cClassUnit, [ACommand]);
end;

/// <summary>Wendet AEdits (nicht überlappend) auf AText an.</summary>
function Apply(const AText: string; AEdits: TArray<TRuleEdit>): string;
var
  mLines: TArray<string>;
  mEdit: TRuleEdit;
  mOffsets: TArray<Integer>;
  mIndex, mStart, mStop: Integer;
begin
  mLines := AText.Split([#10]);
  SetLength(mOffsets, Length(mLines) + 1);
  mOffsets[0] := 0;
  for mIndex := 0 to High(mLines) do
  begin
    mOffsets[mIndex + 1] := mOffsets[mIndex] + Length(mLines[mIndex]) + 1;
  end;
  TArray.Sort<TRuleEdit>(AEdits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for mEdit in AEdits do
  begin
    mStart := mOffsets[mEdit.Range.StartPos.Line] + mEdit.Range.StartPos.Character;
    mStop := mOffsets[mEdit.Range.EndPos.Line] + mEdit.Range.EndPos.Character;
    Result := Copy(Result, 1, mStart) + mEdit.NewText + Copy(Result, mStop + 1, MaxInt);
  end;
end;

function Expand(const ACommand: string; const AIndex: ISymbolIndex): string; overload;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run(WithCommand(ACommand), 15, mEdits, AIndex), ACommand);
  Result := Apply(WithCommand(ACommand), mEdits);
end;

function Expand(const ACommand: string): string; overload;
begin
  Result := Expand(ACommand, nil);
end;

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

procedure TClassCommandsTests.WarmUp;
begin
  Expand('/impl');
  Parses(WithCommand(''));
  OverrideFromIndex;
end;

procedure TClassCommandsTests.ImplAddsMissingBodies;
var
  mText: string;
begin
  mText := Expand('/impl');
  Assert.IsTrue(Pos('procedure TFoo.Stop;', mText) > 0, mText);
  Assert.AreEqual(0, Pos('/impl', mText), mText);
end;

procedure TClassCommandsTests.ImplWithoutMissingFails;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  mText := StringReplace(WithCommand('/impl'), '    procedure Stop;'#10, '', []);
  Assert.IsFalse(Run(mText, 14, mEdits));
end;

procedure TClassCommandsTests.CtorTakesFields;
var
  mText: string;
begin
  mText := Expand('/ctor');
  Assert.IsTrue(Pos('  public'#10'    constructor Create(const AListe: TStringList; const AName: string);'#10'  end;',
    mText) > 0, mText);
  Assert.IsTrue(Pos('constructor TFoo.Create(const AListe: TStringList; const AName: string);'#10'begin'#10 +
    '  inherited Create;'#10'  FListe := AListe;'#10'  FName := AName;'#10'end;', mText) > 0, mText);
end;

procedure TClassCommandsTests.CtorOwner;
var
  mText: string;
begin
  mText := Expand('/ctor owner');
  Assert.IsTrue(Pos('    constructor Create(AOwner: TComponent); override;', mText) > 0, mText);
  Assert.IsTrue(Pos('  inherited Create(AOwner);', mText) > 0, mText);
end;

procedure TClassCommandsTests.DtorFreesCreatedFields;
var
  mText, mSource: string;
  mEdits: TArray<TRuleEdit>;
begin
  mSource := StringReplace(WithCommand('/dtor'), '    procedure Stop;'#10, '    constructor Create;'#10, []);
  mSource := StringReplace(mSource, 'procedure TFoo.Run;', 'constructor TFoo.Create;'#10'begin'#10 +
    '  FListe := TStringList.Create;'#10'  FName := ''x'';'#10'end;'#10#10'procedure TFoo.Run;', []);
  Assert.IsTrue(Run(mSource, 15, mEdits));
  mText := Apply(mSource, mEdits);
  Assert.IsTrue(Pos('    destructor Destroy; override;', mText) > 0, mText);
  Assert.IsTrue(Pos('destructor TFoo.Destroy;'#10'begin'#10'  FreeAndNil(FListe);'#10'  inherited;'#10'end;', mText) > 0,
    mText);
end;

procedure TClassCommandsTests.MsgUsesRecordType;
var
  mText: string;
begin
  mText := Expand('/msg WM_SIZE');
  Assert.IsTrue(Pos('  protected'#10'    procedure WMSize(var Message: TWMSize); message WM_SIZE;', mText) > 0, mText);
  Assert.IsTrue(Pos('procedure TFoo.WMSize(var Message: TWMSize);'#10'begin'#10'  inherited;'#10'end;', mText) > 0,
    mText);
end;

procedure TClassCommandsTests.MessageNames;
begin
  Assert.AreEqual('CMMouseEnter', MessageMethodName('CM_MOUSEENTER'));
  Assert.AreEqual('WMGetMinMaxInfo', MessageMethodName('WM_GETMINMAXINFO'));
  Assert.AreEqual('TMessage', MessageRecord('CM_MOUSEENTER'));
end;

procedure TClassCommandsTests.OverrideInSameFile;
var
  mText: string;
begin
  mText := Expand('/override Wert');
  Assert.IsTrue(Pos('  protected'#10'    function Wert(const A: Integer; B: string): Integer; override;', mText) > 0,
    mText);
  Assert.IsTrue(Pos('function TFoo.Wert(const A: Integer; B: string): Integer;'#10'begin'#10 +
    '  Result := inherited Wert(A, B);'#10'end;', mText) > 0, mText);
  mText := Expand('/override Lauf');
  Assert.IsTrue(Pos('procedure TFoo.Lauf;'#10'begin'#10'  inherited;'#10'end;', mText) > 0, mText);
end;

procedure TClassCommandsTests.OverrideFromIndex;
const
  cControls =
    'unit Vcl.Controls;'#10'interface'#10'type'#10 +
    '  TControl = class(TComponent)'#10'  end;'#10 +
    '  TCustomControl = class(TControl)'#10'  protected'#10'    procedure Paint; virtual;'#10'  end;'#10 +
    'implementation'#10'end.';
  cSource =
    'unit U;'#10'interface'#10'type'#10'  TBild = class(TCustomControl)'#10'  public'#10'    /override Paint'#10 +
    '  end;'#10'implementation'#10'end.';
var
  mIndex: ISymbolIndex;
  mTree: TSyntaxTree;
  mFileName, mText: string;
  mEdits: TArray<TRuleEdit>;
begin
  mFileName := TPath.Combine(TPath.GetTempPath, 'Atlas.ClassCommands.Controls.pas');
  TFile.WriteAllText(mFileName, cControls);
  try
    mIndex := TSymbolIndex.Create;
    mTree := TPascalParser.Parse(cControls);
    try
      mIndex.AddUnit(TIndexExtractor.Extract(mTree, mFileName));
    finally
      mTree.Free;
    end;
    Assert.IsTrue(Run(cSource, 5, mEdits, mIndex));
    mText := Apply(cSource, mEdits);
    Assert.IsTrue(Pos('  protected'#10'    procedure Paint; override;'#10'  end;', mText) > 0, mText);
    Assert.IsTrue(Pos('procedure TBild.Paint;'#10'begin'#10'  inherited;'#10'end;', mText) > 0, mText);
    // Ohne Index kennt der Befehl TCustomControl nicht.
    Assert.IsFalse(Run(cSource, 5, mEdits));
  finally
    TFile.Delete(mFileName);
  end;
end;

procedure TClassCommandsTests.OverrideUnknownFails;
var
  mProblems: TArray<TSlashProblem>;
begin
  mProblems := TSlashCommandRegistry.Shared.Problems(WithCommand('/override Gibts'), nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual('Keine virtuelle Methode Gibts in den Vorfahren von TFoo', mProblems[0].Message);
end;

procedure TClassCommandsTests.OutsideClassFails;
const
  cText = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  /ctor'#10'end;'#10'end.';
var
  mEdits: TArray<TRuleEdit>;
  mProblems: TArray<TSlashProblem>;
begin
  Assert.IsFalse(Run(cText, 5, mEdits));
  mProblems := TSlashCommandRegistry.Shared.Problems(cText, nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual('/ctor gilt nur in einer Klasse oder einer ihrer Methoden', mProblems[0].Message);
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
  cCommands: array[0..5] of string = ('/impl', '/ctor', '/ctor owner', '/dtor', '/msg WM_PAINT', '/override Wert');
var
  mCommand, mText: string;
begin
  for mCommand in cCommands do
  begin
    mText := Expand(mCommand);
    Assert.IsTrue(Parses(mText), mCommand + ': ' + mText);
  end;
end;

/// <summary>Anzahl der Vorkommen von ASub in AText.</summary>
function Occurrences(const AText, ASub: string): Integer;
var
  mStart: Integer;
begin
  Result := 0;
  mStart := Pos(ASub, AText);
  while mStart > 0 do
  begin
    Inc(Result);
    mStart := PosEx(ASub, AText, mStart + Length(ASub));
  end;
end;

procedure TClassCommandsTests.DtorKeepsPassedReferences;
var
  mText, mSource: string;
  mEdits: TArray<TRuleEdit>;
begin
  // Übergebene Referenz (FListe := AListe) gehört dem Aufrufer und wird nicht freigegeben.
  mSource := StringReplace(WithCommand('/dtor'), '    procedure Stop;'#10, '    constructor Create(AListe: TStringList);'#10,
    []);
  mSource := StringReplace(mSource, 'procedure TFoo.Run;', 'constructor TFoo.Create(AListe: TStringList);'#10'begin'#10 +
    '  FListe := AListe;'#10'end;'#10#10'procedure TFoo.Run;', []);
  Assert.IsTrue(Run(mSource, 15, mEdits));
  mText := Apply(mSource, mEdits);
  Assert.IsTrue(Pos('destructor TFoo.Destroy;'#10'begin'#10'  inherited;'#10'end;', mText) > 0, mText);
  Assert.AreEqual(0, Pos('FreeAndNil(FListe)', mText), mText);
end;

procedure TClassCommandsTests.DtorExtendsExisting;
var
  mText, mSource: string;
  mEdits: TArray<TRuleEdit>;
begin
  // Vorhandener Destruktor gibt FListe schon frei; FName2 kommt vor inherited dazu.
  mSource := StringReplace(WithCommand('/dtor'), '    procedure Stop;'#10,
    '    constructor Create;'#10'    destructor Destroy; override;'#10, []);
  mSource := StringReplace(mSource, '    FName: string;'#10, '    FName: string;'#10'    FWeitere: TStringList;'#10, []);
  mSource := StringReplace(mSource, 'procedure TFoo.Run;', 'constructor TFoo.Create;'#10'begin'#10 +
    '  FListe := TStringList.Create;'#10'  FWeitere := TStringList.Create;'#10'end;'#10#10 +
    'destructor TFoo.Destroy;'#10'begin'#10'  FListe.Free;'#10'  inherited;'#10'end;'#10#10'procedure TFoo.Run;', []);
  Assert.IsTrue(Run(mSource, 17, mEdits));
  mText := Apply(mSource, mEdits);
  Assert.IsTrue(Pos('destructor TFoo.Destroy;'#10'begin'#10'  FListe.Free;'#10'  FreeAndNil(FWeitere);'#10 +
    '  inherited;'#10'end;', mText) > 0, mText);
  // Keine zweite Deklaration und kein zweiter Rumpf.
  Assert.AreEqual(1, Occurrences(mText, 'destructor Destroy; override;'), mText);
  Assert.AreEqual(1, Occurrences(mText, 'destructor TFoo.Destroy;'), mText);
  Assert.IsTrue(Parses(mText), mText);
  // Alles schon freigegeben: Hinweis.
  mSource := StringReplace(mSource, '  inherited;'#10'end;'#10#10'procedure TFoo.Run;',
    '  FWeitere.Free;'#10'  inherited;'#10'end;'#10#10'procedure TFoo.Run;', []);
  Assert.IsFalse(Run(mSource, 17, mEdits));
end;

procedure TClassCommandsTests.DtorAndMsgWrongPlaceFail;
const
  cText = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  %s'#10'end;'#10'end.';
var
  mEdits: TArray<TRuleEdit>;
  mProblems: TArray<TSlashProblem>;
begin
  Assert.IsFalse(Run(Format(cText, ['/dtor']), 5, mEdits));
  mProblems := TSlashCommandRegistry.Shared.Problems(Format(cText, ['/dtor']), nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual('/dtor gilt nur in einer Klasse oder einer ihrer Methoden', mProblems[0].Message);
  Assert.IsFalse(Run(Format(cText, ['/msg WM_SIZE']), 5, mEdits));
  mProblems := TSlashCommandRegistry.Shared.Problems(Format(cText, ['/msg WM_SIZE']), nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual('/msg gilt nur in einer Klasse oder einer ihrer Methoden', mProblems[0].Message);
  // Ohne Botschaft.
  Assert.IsFalse(Run(WithCommand('/msg'), 15, mEdits));
end;

const
  cIntfUnit =
    'unit U;'#10 +                                  // 0
    'interface'#10 +                                // 1
    'type'#10 +                                     // 2
    '  IExporter = interface'#10 +                  // 3
    '    procedure Export(const AFileName: string);'#10 + // 4
    '    function Count: Integer;'#10 +             // 5
    '  end;'#10 +                                   // 6
    '  TFoo = %s'#10 +                              // 7
    '  public'#10 +                                 // 8
    '    procedure Run;'#10 +                       // 9
    '    %s'#10 +                                   // 10 Befehl
    '  end;'#10 +                                   // 11
    'implementation'#10 +                           // 12
    #10 +                                           // 13
    'procedure TFoo.Run;'#10 +                      // 14
    'begin'#10 +                                    // 15
    'end;'#10 +                                     // 16
    #10 +                                           // 17
    'end.';

procedure TClassCommandsTests.IntfAddsInterfaceAndMethods;
var
  mText, mSource: string;
  mEdits: TArray<TRuleEdit>;
begin
  mSource := Format(cIntfUnit, ['class(TInterfacedObject)', '/intf IExporter']);
  Assert.IsTrue(Run(mSource, 10, mEdits));
  mText := Apply(mSource, mEdits);
  Assert.IsTrue(Pos('  TFoo = class(TInterfacedObject, IExporter)', mText) > 0, mText);
  Assert.IsTrue(Pos('procedure Export(const AFileName: string);', mText) > 0, mText);
  Assert.IsTrue(Pos('function Count: Integer;', mText) > 0, mText);
  Assert.IsTrue(Pos('procedure TFoo.Export(const AFileName: string);', mText) > 0, mText);
  Assert.IsTrue(Pos('function TFoo.Count: Integer;', mText) > 0, mText);
  Assert.AreEqual(0, Pos('/intf', mText), mText);
  Assert.IsTrue(Parses(mText), mText);
  // Schon angehängt, aber eine Methode fehlt: nur die fehlende, Kopf bleibt.
  mSource := Format(cIntfUnit, ['class(TInterfacedObject, IExporter)', '/intf IExporter']);
  mSource := StringReplace(mSource, '    procedure Run;'#10, '    procedure Run;'#10'    function Count: Integer;'#10, []);
  mSource := StringReplace(mSource, 'procedure TFoo.Run;', 'function TFoo.Count: Integer;'#10'begin'#10 +
    '  Result := 0;'#10'end;'#10#10'procedure TFoo.Run;', []);
  Assert.IsTrue(Run(mSource, 11, mEdits));
  mText := Apply(mSource, mEdits);
  Assert.IsTrue(Pos('  TFoo = class(TInterfacedObject, IExporter)'#10, mText) > 0, mText);
  Assert.IsTrue(Pos('procedure TFoo.Export(const AFileName: string);', mText) > 0, mText);
  Assert.AreEqual(1, Occurrences(mText, 'function TFoo.Count'), mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TClassCommandsTests.IntfWithoutAncestorList;
var
  mText, mSource: string;
  mEdits: TArray<TRuleEdit>;
begin
  mSource := Format(cIntfUnit, ['class', '/intf IExporter']);
  Assert.IsTrue(Run(mSource, 10, mEdits));
  mText := Apply(mSource, mEdits);
  Assert.IsTrue(Pos('  TFoo = class(TInterfacedObject, IExporter)'#10, mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TClassCommandsTests.IntfWrongPlaceFails;
var
  mEdits: TArray<TRuleEdit>;
  mSource: string;
begin
  // Unbekanntes Interface, kein Interface, ohne Namen.
  Assert.IsFalse(Run(Format(cIntfUnit, ['class', '/intf IUnbekannt']), 10, mEdits));
  Assert.IsFalse(Run(Format(cIntfUnit, ['class', '/intf TFoo']), 10, mEdits));
  Assert.IsFalse(Run(Format(cIntfUnit, ['class', '/intf']), 10, mEdits));
  // Schon vollständig.
  mSource := Format(cIntfUnit, ['class(TInterfacedObject, IExporter)', '/intf IExporter']);
  mSource := StringReplace(mSource, '    procedure Run;'#10, '    procedure Run;'#10 +
    '    procedure Export(const AFileName: string);'#10'    function Count: Integer;'#10, []);
  Assert.IsFalse(Run(mSource, 12, mEdits));
  // In einer Methode statt in der Deklaration.
  mSource := StringReplace(Format(cIntfUnit, ['class', '']), 'procedure TFoo.Run;'#10'begin'#10,
    'procedure TFoo.Run;'#10'begin'#10'  /intf IExporter'#10, []);
  Assert.IsFalse(Run(mSource, 16, mEdits));
end;

initialization
  TDUnitX.RegisterTestFixture(TClassCommandsTests);

end.
