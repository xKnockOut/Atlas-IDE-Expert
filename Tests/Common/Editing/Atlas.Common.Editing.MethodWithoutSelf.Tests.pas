unit Atlas.Common.Editing.MethodWithoutSelf.Tests;

// Tests für „Methode ohne Self umwandeln“ (#686): Erkennung samt
// Gegenbeispielen (impliziter Zugriff auf ein Feld, Self, virtuelle Methode,
// Ereignis in der Formulardatei, Interface, Methodenzeiger), class-Methode
// mit und ohne static, Aufrufe über die Klasse, freie Routine (Aufrufe in
// zwei Units, uses, Klassenmitglieder qualifiziert, vor den ersten Aufrufer
// verschoben), Record-Helper samt Warnung bei sichtbarem Helper.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMethodWithoutSelfTests = class
  public
    [Test]
    procedure TitlesFromTextUnit;
    [Test]
    procedure DetectsMethodWithoutSelf;
    [Test]
    procedure ImplicitFieldIsNoCandidate;
    [Test]
    procedure VirtualFormAndInterfaceAreNoCandidates;
    /// <summary>Methoden mit Attribut ([Test]) und published-Methoden ruft RTTI an der Instanz auf.</summary>
    [Test]
    procedure AttributeAndPublishedAreNoCandidates;
    [Test]
    procedure MethodPointerIsNoCandidate;
    [Test]
    procedure ClassMethodWithStatic;
    [Test]
    procedure ClassMethodCallsOverClass;
    [Test]
    procedure RoutineAcrossUnits;
    [Test]
    procedure RoutineMovesBeforeFirstCaller;
    [Test]
    procedure RoutineQualifiesClassMembers;
    [Test]
    procedure HelperAcrossUnits;
    [Test]
    procedure HelperWarnsAboutVisibleHelper;
    [Test]
    procedure RecordAndExistingHelper;
    [Test]
    procedure CandidatesAndNames;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.MethodWithoutSelf,
  Atlas.Common.Editing.MethodWithoutSelf.Contract,
  Atlas.Common.Editing.MethodWithoutSelf.Lookup,
  Atlas.Common.Editing.MethodWithoutSelf.Texts;

const
  cKunden =
    'unit Kunden;'#10 +                                                  // 0
    'interface'#10 +                                                     // 1
    'uses System.SysUtils;'#10 +                                         // 2
    'type'#10 +                                                          // 3
    '  TKunde = class'#10 +                                              // 4
    '  private'#10 +                                                     // 5
    '    FName: string;'#10 +                                            // 6
    '  public'#10 +                                                      // 7
    '    function IsValidIban(const S: string; N: Integer): Boolean;'#10 + // 8
    '    procedure Zeige;'#10 +                                          // 9
    '  end;'#10 +                                                        // 10
    'implementation'#10 +                                                // 11
    'procedure TKunde.Zeige;'#10 +                                       // 12
    'begin'#10 +                                                         // 13
    '  if IsValidIban(FName, 2) then'#10 +                               // 14
    '    FName := '''';'#10 +                                            // 15
    'end;'#10 +                                                          // 16
    'function TKunde.IsValidIban(const S: string; N: Integer): Boolean;'#10 + // 17
    'begin'#10 +                                                         // 18
    '  Result := Length(S) > N;'#10 +                                    // 19
    'end;'#10 +                                                          // 20
    'end.'#10;

  cAufrufer =
    'unit Aufrufer;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Kunden;'#10 +
    'procedure Pruefe(K: TKunde; const T: string);'#10 +
    'begin'#10 +
    '  if K.IsValidIban(T + ''x'', 3) then'#10 +
    '    Exit;'#10 +
    'end;'#10 +
    'end.'#10;

/// <summary>Anfänge der Bezeichner AName in AText wie aus der Referenzsuche: ohne gleichnamige Routinen der Unit
/// (Name direkt hinter function bzw. procedure).</summary>
function OffsetsOf(ATree: TSyntaxTree; const AName: string): TArray<Integer>;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
begin
  Result := nil;
  mTokens := ATree.Tokens;
  for mIndex := 0 to High(mTokens) do
  begin
    if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[mIndex].Text, AName) and
      not ((mIndex > 0) and (mTokens[mIndex - 1].IsKeyword('function') or mTokens[mIndex - 1].IsKeyword('procedure'))) then
    begin
      Result := Result + [mTokens[mIndex].Offset];
    end;
  end;
end;

function EditsOf(const AResult: TMethodResult; const AFileName: string): TArray<TTextEdit>;
var
  mItem: TMethodFileEdits;
begin
  Result := nil;
  for mItem in AResult.Files do
  begin
    if SameText(mItem.FileName, AFileName) then
    begin
      Exit(mItem.Edits);
    end;
  end;
end;

type
  /// <summary>Eine Umwandlung von IsValidIban in Declaring; Other (oder '') ruft auf.</summary>
  TConversionCase = record
    Declaring: string;
    Other: string;
    Conversion: TMethodConversion;
    Static: Boolean;
    HelperLookup: Boolean;
  end;

const
  /// <summary>Lage von IsValidIban in Kunden.</summary>
  cLine = 17;
  cCharacter = 20;

function Converting(const ADeclaring, AOther: string; AConversion: TMethodConversion;
  AStatic, AHelperLookup: Boolean): TConversionCase;
begin
  Result := Default(TConversionCase);
  Result.Declaring := ADeclaring;
  Result.Other := AOther;
  Result.Conversion := AConversion;
  Result.Static := AStatic;
  Result.HelperLookup := AHelperLookup;
end;

/// <summary>Wandelt die Methode an cLine/cCharacter um; ANewDeclaring und ANewOther sind die geänderten
/// Texte.</summary>
function Convert(const ACase: TConversionCase; out ANewDeclaring, ANewOther: string; out AResult: TMethodResult;
  out AReason: string): Boolean;
var
  mTree, mOtherTree: TSyntaxTree;
  mOthers: TArray<TMethodSource>;
  mLookup: TMethodLookup;
begin
  mTree := TPascalParser.Parse(ACase.Declaring);
  mOtherTree := nil;
  try
    mLookup := TMethodLookup.FromTree(mTree);
    if not ACase.HelperLookup then
    begin
      mLookup.VisibleHelper := nil;
    end;
    mOthers := nil;
    if ACase.Other <> '' then
    begin
      mOtherTree := TPascalParser.Parse(ACase.Other);
      mOthers := [TMethodSource.Create('C:\P\Aufrufer.pas', ACase.Other, mOtherTree, OffsetsOf(mOtherTree,
        'IsValidIban'))];
    end;
    Result := TMethodWithoutSelf.Execute(TMethodSource.Create('C:\P\Kunden.pas', ACase.Declaring, mTree,
      OffsetsOf(mTree, 'IsValidIban')), mOthers, TMethodRequest.Create(TTextPosition.Create(cLine, cCharacter),
      ACase.Conversion, ACase.Static, mLookup, TFormatStyle.Default), AResult, AReason);
    ANewDeclaring := ACase.Declaring;
    ANewOther := ACase.Other;
    if Result then
    begin
      ANewDeclaring := TChangeSignature.ApplyEdits(ACase.Declaring, EditsOf(AResult, 'C:\P\Kunden.pas'));
      ANewOther := TChangeSignature.ApplyEdits(ACase.Other, EditsOf(AResult, 'C:\P\Aufrufer.pas'));
    end;
  finally
    mOtherTree.Free;
    mTree.Free;
  end;
end;

procedure TMethodWithoutSelfTests.TitlesFromTextUnit;
begin
  // Die Texte stehen in einer eigenen Unit (metric-unit-length); die Titel kommen weiter aus ihr.
  Assert.AreEqual(cTexts[TEditingMethodWithoutSelfText.ConvertToClassMethod].Text, TMethodWithoutSelf.ClassMethodTitle);
  Assert.AreEqual(cTexts[TEditingMethodWithoutSelfText.ConvertToStandaloneRoutine].Text,
    TMethodWithoutSelf.RoutineTitle);
end;

procedure TMethodWithoutSelfTests.DetectsMethodWithoutSelf;
var
  mTarget: TMethodTarget;
  mReason: string;
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cKunden);
  try
    // Auf dem Kopf der Implementierung und der Deklaration.
    Assert.IsTrue(TMethodWithoutSelf.Target(cKunden, mTree, TTextPosition.Create(17, 20),
      TMethodLookup.FromTree(mTree), mTarget, mReason), mReason);
    Assert.AreEqual('TKunde', mTarget.ClassName);
    Assert.AreEqual('IsValidIban', mTarget.Name);
    Assert.AreEqual(4, Integer(Length(mTarget.Conversions)), mTarget.RoutineReason + '|' + mTarget.HelperReason);
    Assert.AreEqual('string', mTarget.HelperType);
    Assert.AreEqual(17, mTarget.NamePosition.Line);
    Assert.AreEqual(16, mTarget.NamePosition.Character);
    Assert.IsTrue(TMethodWithoutSelf.Target(cKunden, mTree, TTextPosition.Create(8, 15),
      TMethodLookup.FromTree(mTree), mTarget, mReason), mReason);
    Assert.AreEqual('In Record-Helper für string verschieben', mTarget.Title(TMethodConversion.Helper));
    // Zeige ruft die Instanzmethode IsValidIban auf (und benutzt FName).
    Assert.IsFalse(TMethodWithoutSelf.Target(cKunden, mTree, TTextPosition.Create(12, 20),
      TMethodLookup.FromTree(mTree), mTarget, mReason));
    Assert.IsTrue(Pos('IsValidIban', mReason) > 0, mReason);
  finally
    mTree.Free;
  end;
end;

procedure TMethodWithoutSelfTests.ImplicitFieldIsNoCandidate;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TA = class'#10 +
    '    FWert: Integer;'#10 +
    '    function Mal(N: Integer): Integer;'#10 +
    '    function Selbst: TA;'#10 +
    '    function Anderes(N: Integer): Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TA.Mal(N: Integer): Integer;'#10 +             // 10
    'begin'#10 +
    '  Result := N * FWert;'#10 +
    'end;'#10 +
    'function TA.Selbst: TA;'#10 +                           // 14
    'begin'#10 +
    '  Result := Self;'#10 +
    'end;'#10 +
    'function TA.Anderes(N: Integer): Integer;'#10 +         // 18
    'var'#10 +
    '  FWert: Integer;'#10 +
    'begin'#10 +
    '  FWert := N;'#10 +
    '  Result := FWert;'#10 +
    'end;'#10 +
    'end.'#10;
var
  mTarget: TMethodTarget;
  mReason: string;
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.IsFalse(TMethodWithoutSelf.Target(cSource, mTree, TTextPosition.Create(10, 13),
      TMethodLookup.FromTree(mTree), mTarget, mReason));
    Assert.IsTrue(Pos('FWert', mReason) > 0, mReason);
    Assert.IsFalse(TMethodWithoutSelf.Target(cSource, mTree, TTextPosition.Create(14, 13),
      TMethodLookup.FromTree(mTree), mTarget, mReason));
    Assert.IsTrue(Pos('Self', mReason) > 0, mReason);
    // Die lokale Variable verdeckt das Feld.
    Assert.IsTrue(TMethodWithoutSelf.Target(cSource, mTree, TTextPosition.Create(18, 13),
      TMethodLookup.FromTree(mTree), mTarget, mReason), mReason);
  finally
    mTree.Free;
  end;
end;

procedure TMethodWithoutSelfTests.VirtualFormAndInterfaceAreNoCandidates;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  IPruefer = interface'#10 +
    '    function Pruefe(N: Integer): Boolean;'#10 +
    '  end;'#10 +
    '  TA = class(TInterfacedObject, IPruefer)'#10 +
    '    function Pruefe(N: Integer): Boolean;'#10 +
    '    function Virtuell(N: Integer): Boolean; virtual;'#10 +
    '    procedure Knopf(Sender: TObject);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TA.Pruefe(N: Integer): Boolean;'#10 +          // 12
    'begin'#10 +
    '  Result := N > 0;'#10 +
    'end;'#10 +
    'function TA.Virtuell(N: Integer): Boolean;'#10 +        // 16
    'begin'#10 +
    '  Result := N > 0;'#10 +
    'end;'#10 +
    'procedure TA.Knopf(Sender: TObject);'#10 +              // 20
    'begin'#10 +
    'end;'#10 +
    'end.'#10;
var
  mTarget: TMethodTarget;
  mReason: string;
  mTree: TSyntaxTree;
  mLookup: TMethodLookup;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mLookup := TMethodLookup.FromTree(mTree);
    Assert.IsFalse(TMethodWithoutSelf.Target(cSource, mTree, TTextPosition.Create(12, 13), mLookup, mTarget, mReason));
    Assert.IsTrue(Pos('IPruefer', mReason) > 0, mReason);
    Assert.IsFalse(TMethodWithoutSelf.Target(cSource, mTree, TTextPosition.Create(16, 13), mLookup, mTarget, mReason));
    Assert.IsTrue(Pos('virtuell', mReason) > 0, mReason);
    mLookup.InForm :=
      function(const AName: string): Boolean
      begin
        Result := SameText(AName, 'Knopf');
      end;
    Assert.IsFalse(TMethodWithoutSelf.Target(cSource, mTree, TTextPosition.Create(20, 14), mLookup, mTarget, mReason));
    Assert.IsTrue(Pos('Formulardatei', mReason) > 0, mReason);
  finally
    mTree.Free;
  end;
end;

procedure TMethodWithoutSelfTests.AttributeAndPublishedAreNoCandidates;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TA = class'#10 +
    '  public'#10 +
    '    [Test]'#10 +
    '    procedure Pruefe;'#10 +
    '    procedure Frei;'#10 +
    '  published'#10 +
    '    procedure Alt;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TA.Pruefe;'#10 +                                // 12
    'begin'#10 +
    'end;'#10 +
    'procedure TA.Frei;'#10 +                                  // 15
    'begin'#10 +
    'end;'#10 +
    'procedure TA.Alt;'#10 +                                   // 18
    'begin'#10 +
    'end;'#10 +
    'end.'#10;
var
  mTarget: TMethodTarget;
  mReason: string;
  mTree: TSyntaxTree;
  mLookup: TMethodLookup;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mLookup := TMethodLookup.FromTree(mTree);
    Assert.IsFalse(TMethodWithoutSelf.Target(cSource, mTree, TTextPosition.Create(12, 13), mLookup, mTarget, mReason));
    Assert.IsTrue(Pos('RTTI', mReason) > 0, mReason);
    Assert.IsTrue(TMethodWithoutSelf.Target(cSource, mTree, TTextPosition.Create(15, 13), mLookup, mTarget, mReason),
      mReason);
    Assert.IsFalse(TMethodWithoutSelf.Target(cSource, mTree, TTextPosition.Create(18, 13), mLookup, mTarget, mReason));
    Assert.IsTrue(Pos('RTTI', mReason) > 0, mReason);
  finally
    mTree.Free;
  end;
end;

procedure TMethodWithoutSelfTests.MethodPointerIsNoCandidate;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TA = class'#10 +
    '    FOnTick: TNotifyEvent;'#10 +
    '    procedure Tick(Sender: TObject);'#10 +
    '    procedure Start;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TA.Tick(Sender: TObject);'#10 +               // 9
    'begin'#10 +
    'end;'#10 +
    'procedure TA.Start;'#10 +
    'begin'#10 +
    '  FOnTick := Tick;'#10 +
    'end;'#10 +
    'end.'#10;
var
  mTarget: TMethodTarget;
  mReason: string;
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.IsFalse(TMethodWithoutSelf.Target(cSource, mTree, TTextPosition.Create(9, 14),
      TMethodLookup.FromTree(mTree), mTarget, mReason));
    Assert.IsTrue(Pos('Methodenzeiger', mReason) > 0, mReason);
  finally
    mTree.Free;
  end;
end;

procedure TMethodWithoutSelfTests.ClassMethodWithStatic;
var
  mDeclaring, mOther, mReason: string;
  mConverted: TMethodResult;
begin
  Assert.IsTrue(Convert(Converting(cKunden, cAufrufer, TMethodConversion.ClassMethod, True, True), mDeclaring, mOther,
    mConverted, mReason), mReason);
  Assert.IsTrue(Pos('    class function IsValidIban(const S: string; N: Integer): Boolean; static;'#10, mDeclaring) > 0,
    mDeclaring);
  Assert.IsTrue(Pos('class function TKunde.IsValidIban(const S: string; N: Integer): Boolean;', mDeclaring) > 0,
    mDeclaring);
  // Aufrufe über Instanzen bleiben.
  Assert.AreEqual(cAufrufer, mOther);
  Assert.AreEqual(0, mConverted.Calls);
  Assert.IsTrue(Pos('wird class-Methode', mConverted.Preview) > 0, mConverted.Preview);
  // Ohne static.
  Assert.IsTrue(Convert(Converting(cKunden, '', TMethodConversion.ClassMethod, False, True), mDeclaring, mOther,
    mConverted,
    mReason), mReason);
  Assert.IsTrue(Pos('class function IsValidIban(const S: string; N: Integer): Boolean;'#10, mDeclaring) > 0,
    mDeclaring);
  Assert.IsFalse(Pos('static', mDeclaring) > 0, mDeclaring);
end;

procedure TMethodWithoutSelfTests.ClassMethodCallsOverClass;
const
  cFremd =
    'unit Aufrufer;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Fabrik;'#10 +
    'procedure Pruefe(const T: string);'#10 +
    'begin'#10 +
    '  if Neu.IsValidIban(T, 3) and Liste[1].IsValidIban(T, 1) then'#10 +
    '    Exit;'#10 +
    'end;'#10 +
    'end.'#10;
var
  mDeclaring, mOther, mReason: string;
  mConverted: TMethodResult;
begin
  Assert.IsTrue(Convert(Converting(cKunden, cFremd, TMethodConversion.ClassMethodCalls, True, True), mDeclaring, mOther,
    mConverted, mReason), mReason);
  // Neu und Liste[1] sind Variablenketten: beide über die Klasse, Kunden ins uses.
  Assert.IsTrue(Pos('TKunde.IsValidIban(T, 3) and TKunde.IsValidIban(T, 1)', mOther) > 0, mOther);
  Assert.IsTrue(Pos('uses Fabrik, Kunden;', mOther) > 0, mOther);
  Assert.AreEqual(2, mConverted.Calls);
  Assert.IsTrue(Pos('Aufrufer.pas, Zeile 7: if Neu.IsValidIban(T, 3)', mConverted.Preview) > 0, mConverted.Preview);
end;

procedure TMethodWithoutSelfTests.RoutineAcrossUnits;
const
  cFremd =
    'unit Aufrufer;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Kunden;'#10 +
    'function IsValidIban(const S: string): Boolean;'#10 +
    'begin'#10 +
    '  Result := False;'#10 +
    'end;'#10 +
    'procedure Pruefe(K: TKunde; const T: string);'#10 +
    'begin'#10 +
    '  if K.IsValidIban(T, 3) or GetKunde().IsValidIban(T, 4) then'#10 +
    '    Exit;'#10 +
    'end;'#10 +
    'end.'#10;
var
  mDeclaring, mOther, mReason: string;
  mConverted: TMethodResult;
begin
  Assert.IsTrue(Convert(Converting(cKunden, cFremd, TMethodConversion.Routine, True, True), mDeclaring, mOther,
    mConverted,
    mReason), mReason);
  // Aus der Klasse heraus, ins interface vor implementation, Kopf ohne Klasse.
  Assert.IsFalse(Pos('    function IsValidIban', mDeclaring) > 0, mDeclaring);
  Assert.IsTrue(Pos('  end;'#10'function IsValidIban(const S: string; N: Integer): Boolean;'#10#10'implementation',
    mDeclaring) > 0, mDeclaring);
  Assert.IsTrue(Pos(#10'function IsValidIban(const S: string; N: Integer): Boolean;'#10'begin', mDeclaring) > 0,
    mDeclaring);
  // Der Aufrufer der eigenen Unit bleibt, der fremde qualifiziert (eigene IsValidIban dort).
  Assert.IsTrue(Pos('if IsValidIban(FName, 2) then', mDeclaring) > 0, mDeclaring);
  Assert.IsTrue(Pos('if Kunden.IsValidIban(T, 3) or Kunden.IsValidIban(T, 4) then', mOther) > 0, mOther);
  Assert.AreEqual(1, Integer(Length(mConverted.Warnings)), string.Join('|', mConverted.Warnings));
  Assert.IsTrue(Pos('GetKunde() wird nicht mehr ausgewertet', mConverted.Warnings[0]) > 0, mConverted.Warnings[0]);
  Assert.AreEqual(2, mConverted.Calls);
end;

procedure TMethodWithoutSelfTests.RoutineMovesBeforeFirstCaller;
var
  mDeclaring, mOther, mReason: string;
  mConverted: TMethodResult;
begin
  // Ohne fremde Aufrufer: nur implementation, vor TKunde.Zeige.
  Assert.IsTrue(Convert(Converting(cKunden, '', TMethodConversion.Routine, True, True), mDeclaring, mOther, mConverted,
    mReason), mReason);
  Assert.AreEqual(
    'unit Kunden;'#10 +
    'interface'#10 +
    'uses System.SysUtils;'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '  public'#10 +
    '    procedure Zeige;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function IsValidIban(const S: string; N: Integer): Boolean;'#10 +
    'begin'#10 +
    '  Result := Length(S) > N;'#10 +
    'end;'#10 +
    #10 +
    'procedure TKunde.Zeige;'#10 +
    'begin'#10 +
    '  if IsValidIban(FName, 2) then'#10 +
    '    FName := '''';'#10 +
    'end;'#10 +
    'end.'#10, mDeclaring);
end;

procedure TMethodWithoutSelfTests.RoutineQualifiesClassMembers;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TA = class'#10 +
    '  private const'#10 +
    '    Max = 3;'#10 +
    '  strict private'#10 +
    '    class var FZaehler: Integer;'#10 +
    '  public'#10 +
    '    function Grenze(N: Integer): Integer;'#10 +
    '    function Zaehle(N: Integer): Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TA.Grenze(N: Integer): Integer;'#10 +          // 13
    'begin'#10 +
    '  Result := N + Max;'#10 +
    'end;'#10 +
    'function TA.Zaehle(N: Integer): Integer;'#10 +          // 17
    'begin'#10 +
    '  Result := N + FZaehler;'#10 +
    'end;'#10 +
    'end.'#10;
var
  mTree: TSyntaxTree;
  mLookup: TMethodLookup;
  mTarget: TMethodTarget;
  mConverted: TMethodResult;
  mReason, mText: string;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mLookup := TMethodLookup.FromTree(mTree);
    Assert.IsTrue(TMethodWithoutSelf.Execute(TMethodSource.Create('C:\P\U.pas', cSource, mTree, nil), nil,
      TMethodRequest.Create(TTextPosition.Create(13, 13), TMethodConversion.Routine, True, mLookup,
      TFormatStyle.Default), mConverted, mReason), mReason);
    mText := TChangeSignature.ApplyEdits(cSource, mConverted.Files[0].Edits);
    Assert.IsTrue(Pos('  Result := N + TA.Max;', mText) > 0, mText);
    Assert.IsTrue(Pos(#10'function Grenze(N: Integer): Integer;'#10, mText) > 0, mText);
    // strict private: nur class-Methode und Helper.
    Assert.IsTrue(TMethodWithoutSelf.Target(cSource, mTree, TTextPosition.Create(17, 13), mLookup, mTarget, mReason),
      mReason);
    Assert.IsTrue(Pos('FZaehler', mTarget.RoutineReason) > 0, mTarget.RoutineReason);
    Assert.AreEqual(2, Integer(Length(mTarget.Conversions)));
    Assert.IsTrue(TMethodWithoutSelf.Execute(TMethodSource.Create('C:\P\U.pas', cSource, mTree, nil), nil,
      TMethodRequest.Create(TTextPosition.Create(17, 13), TMethodConversion.ClassMethod, True, mLookup,
      TFormatStyle.Default), mConverted, mReason), mReason);
    mText := TChangeSignature.ApplyEdits(cSource, mConverted.Files[0].Edits);
    Assert.IsTrue(Pos('    class function Zaehle(N: Integer): Integer; static;', mText) > 0, mText);
  finally
    mTree.Free;
  end;
end;

procedure TMethodWithoutSelfTests.HelperAcrossUnits;
var
  mDeclaring, mOther, mReason: string;
  mConverted: TMethodResult;
begin
  Assert.IsTrue(Convert(Converting(cKunden, cAufrufer, TMethodConversion.Helper, True, False), mDeclaring, mOther,
    mConverted, mReason), mReason);
  Assert.IsTrue(Pos(
    '  end;'#10#10 +
    '  TStringHelper = record helper for string'#10 +
    '    function IsValidIban(N: Integer): Boolean;'#10 +
    '  end;'#10, mDeclaring) > 0, mDeclaring);
  Assert.IsTrue(Pos('function TStringHelper.IsValidIban(N: Integer): Boolean;'#10'begin'#10 +
    '  Result := Length(Self) > N;', mDeclaring) > 0, mDeclaring);
  Assert.IsTrue(Pos('if FName.IsValidIban(2) then', mDeclaring) > 0, mDeclaring);
  Assert.IsTrue(Pos('if (T + ''x'').IsValidIban(3) then', mOther) > 0, mOther);
  Assert.AreEqual(0, Integer(Length(mConverted.Warnings)), string.Join('|', mConverted.Warnings));
end;

procedure TMethodWithoutSelfTests.HelperWarnsAboutVisibleHelper;
const
  cSource =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TA = class'#10 +
    '    procedure Run;'#10 +
    '    function Doppelt(const S: string): string;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'uses System.SysUtils;'#10 +
    'procedure TA.Run;'#10 +
    'begin'#10 +
    '  Doppelt(''a'');'#10 +
    'end;'#10 +
    'function TA.Doppelt(const S: string): string;'#10 +     // 13
    'begin'#10 +
    '  Result := S + S;'#10 +
    'end;'#10 +
    'end.'#10;
var
  mTree: TSyntaxTree;
  mConverted: TMethodResult;
  mReason, mText: string;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.IsTrue(TMethodWithoutSelf.Execute(TMethodSource.Create('C:\P\Haupt.pas', cSource, mTree, OffsetsOf(mTree,
      'Doppelt')), nil, TMethodRequest.Create(TTextPosition.Create(13, 13), TMethodConversion.Helper, True,
      TMethodLookup.FromTree(mTree), TFormatStyle.Default), mConverted, mReason), mReason);
    mText := TChangeSignature.ApplyEdits(cSource, mConverted.Files[0].Edits);
  finally
    mTree.Free;
  end;
  // Neuer Helper im implementation-Teil hinter dessen uses, mit dem Namen der Unit.
  Assert.IsTrue(Pos('uses System.SysUtils;'#10#10'type'#10'  THauptStringHelper = record helper for string'#10 +
    '    function Doppelt: string;'#10'  end;'#10, mText) > 0, mText);
  Assert.IsTrue(Pos('  (''a'').Doppelt;', mText) > 0, mText);
  Assert.IsTrue(Pos('Result := Self + Self;', mText) > 0, mText);
  Assert.AreEqual(1, Integer(Length(mConverted.Warnings)));
  Assert.IsTrue(Pos('TStringHelper', mConverted.Warnings[0]) > 0, mConverted.Warnings[0]);
end;

procedure TMethodWithoutSelfTests.RecordAndExistingHelper;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TPunkt = record'#10 +
    '    X: Integer;'#10 +
    '    function Doppelt(const A: Integer): Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'type'#10 +
    '  TZahlHelper = record helper for Integer'#10 +
    '    function Halb: Integer;'#10 +
    '  end;'#10 +
    'function TZahlHelper.Halb: Integer;'#10 +
    'begin'#10 +
    '  Result := Self div 2;'#10 +
    'end;'#10 +
    'function TPunkt.Doppelt(const A: Integer): Integer;'#10 +  // 16
    'begin'#10 +
    '  Result := A * 2;'#10 +
    'end;'#10 +
    'end.'#10;
var
  mTree: TSyntaxTree;
  mConverted: TMethodResult;
  mReason, mText: string;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    // Records: class-Methoden sind immer static.
    Assert.IsTrue(TMethodWithoutSelf.Execute(TMethodSource.Create('C:\P\U.pas', cSource, mTree, nil), nil,
      TMethodRequest.Create(TTextPosition.Create(16, 16), TMethodConversion.ClassMethod, False,
      TMethodLookup.FromTree(mTree), TFormatStyle.Default), mConverted, mReason), mReason);
    mText := TChangeSignature.ApplyEdits(cSource, mConverted.Files[0].Edits);
    Assert.IsTrue(Pos('    class function Doppelt(const A: Integer): Integer; static;', mText) > 0, mText);
    // Vorhandener Helper für Integer bekommt die Methode.
    Assert.IsTrue(TMethodWithoutSelf.Execute(TMethodSource.Create('C:\P\U.pas', cSource, mTree, nil), nil,
      TMethodRequest.Create(TTextPosition.Create(16, 16), TMethodConversion.Helper, False,
      TMethodLookup.FromTree(mTree), TFormatStyle.Default), mConverted, mReason), mReason);
    mText := TChangeSignature.ApplyEdits(cSource, mConverted.Files[0].Edits);
  finally
    mTree.Free;
  end;
  Assert.IsTrue(Pos('    function Halb: Integer;'#10'    function Doppelt: Integer;'#10'  end;', mText) > 0, mText);
  Assert.IsTrue(Pos('function TZahlHelper.Doppelt: Integer;'#10'begin'#10'  Result := Self * 2;', mText) > 0, mText);
  Assert.IsFalse(Pos('TPunkt.Doppelt', mText) > 0, mText);
end;

procedure TMethodWithoutSelfTests.CandidatesAndNames;
var
  mTree: TSyntaxTree;
  mFound: TArray<TMethodTarget>;
  mConversion, mParsed: TMethodConversion;
begin
  mTree := TPascalParser.Parse(cKunden);
  try
    mFound := TMethodWithoutSelf.Candidates(cKunden, mTree, TMethodLookup.FromTree(mTree));
    Assert.AreEqual(1, Integer(Length(mFound)));
    Assert.AreEqual('IsValidIban', mFound[0].Name);
    Assert.AreEqual(17, mFound[0].HeaderEnd.Line);
  finally
    mTree.Free;
  end;
  for mConversion := Low(TMethodConversion) to High(TMethodConversion) do
  begin
    Assert.IsTrue(TMethodWithoutSelf.ConversionOf(TMethodWithoutSelf.ConversionName(mConversion), mParsed));
    Assert.AreEqual(Ord(mConversion), Ord(mParsed));
  end;
  Assert.IsFalse(TMethodWithoutSelf.ConversionOf('x', mParsed));
  Assert.AreEqual('TDateTimeHelper', TMethodWithoutSelf.HelperNameFor('TDateTime'));
  Assert.AreEqual('TIntegerHelper', TMethodWithoutSelf.HelperNameFor('Integer'));
  Assert.IsTrue(TMethodWithoutSelf.IsSimpleType('Integer'));
  Assert.IsFalse(TMethodWithoutSelf.IsSimpleType('TKunde'));
end;

initialization
  TDUnitX.RegisterTestFixture(TMethodWithoutSelfTests);

end.
