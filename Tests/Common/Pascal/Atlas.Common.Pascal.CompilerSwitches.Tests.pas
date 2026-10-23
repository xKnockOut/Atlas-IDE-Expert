unit Atlas.Common.Pascal.CompilerSwitches.Tests;

// Wirksame Compiler-Schalter an einer Stelle (#558): lokale Direktive mit
// Zeile, Include-Datei, Projektstand ohne Direktiven, {$WARN … OFF/ON},
// {$PUSHOPT}/{$POPOPT}, lange Namen und Ausrichtung, inaktive Zweige,
// bedingte Symbole, Kurzfassung für die Statusleiste.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.CompilerSwitches;

type
  [TestFixture]
  TCompilerSwitchesTests = class
  private
    /// <summary>Stand in Zeile ALine (0-basiert) von AText mit Projekt-Defines und -Eigenschaften.</summary>
    function StateAt(const AText: string; ALine: Integer; const ADefines: TArray<string>;
      const AProperties: TArray<TPair<string, string>>): TCompilerSwitchState;
    function Find(const AState: TCompilerSwitchState; const AName: string): TSwitchEntry;
  public
    [Test]
    procedure LocalDirectiveWithLine;
    [Test]
    procedure IncludeFileNamed;
    [Test]
    procedure ProjectValuesWithoutDirectives;
    [Test]
    procedure WarnOffAndOn;
    [Test]
    procedure PushAndPopRestore;
    [Test]
    procedure LongNamesAndAlignment;
    [Test]
    procedure InactiveBranchesDoNotCount;
    [Test]
    procedure DefinesWithOrigin;
    [Test]
    procedure SummaryNamesOnlyDeviations;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Preprocessor;

const
  ProjectDefines: array[0..5] of string = ('DEBUG', '$R+', '$Q+', '$O-', '$C+', '$I+*');

function Lines(const ALines: array of string): string;
var
  Line: string;
begin
  Result := '';
  for Line in ALines do
    Result := Result + Line + #10;
end;

function Defines: TArray<string>;
var
  Define: string;
begin
  Result := nil;
  for Define in ProjectDefines do
    Result := Result + [Define];
end;

function NoProperties: TArray<TPair<string, string>>;
begin
  Result := nil;
end;

{ TCompilerSwitchesTests }

function TCompilerSwitchesTests.StateAt(const AText: string; ALine: Integer; const ADefines: TArray<string>;
  const AProperties: TArray<TPair<string, string>>): TCompilerSwitchState;
var
  Options: TPreprocessorOptions;
  Input: TCompilerSwitchInput;
begin
  Options := TPreprocessorOptions.Default;
  Options.Defines := ADefines;
  Options.FileName := 'C:\P\Main.pas';
  Options.ResolveInclude :=
    function(const AName, AFromFile: string; out AFileName, AText: string): Boolean
    begin
      Result := SameText(AName, 'Schalter.inc');
      AFileName := 'C:\P\Schalter.inc';
      AText := '// Schalter'#10'{$Q-}'#10'{$WARN SYMBOL_PLATFORM OFF}'#10;
    end;
  Input := Default(TCompilerSwitchInput);
  Input.Defines := ADefines;
  Input.Properties := AProperties;
  Input.DefineOrigins := [TSwitchDefineOrigin.Create('DEBUG',
    TSwitchOrigin.Make(TSwitchOriginKind.Project, 'Konfiguration Debug (.dproj)'))];
  Result := TCompilerSwitches.At(TPascalPreprocessor.Process(AText, Options), TTextPosition.Create(ALine, 0), Input);
end;

function TCompilerSwitchesTests.Find(const AState: TCompilerSwitchState; const AName: string): TSwitchEntry;
var
  Entry: TSwitchEntry;
begin
  for Entry in AState.Switches + AState.Warns + AState.Defines do
    if SameText(Entry.Name, AName) then
      Exit(Entry);
  Result := Default(TSwitchEntry);
end;

procedure TCompilerSwitchesTests.LocalDirectiveWithLine;
var
  Text: string;
  State: TCompilerSwitchState;
  Range: TSwitchEntry;
  Index: Integer;
begin
  Text := '';
  for Index := 0 to 24 do
    if Index = 9 then
      Text := Text + '{$R-}'#10
    else
      Text := Text + '// Zeile'#10;
  State := StateAt(Text, 19, Defines, NoProperties);
  Range := Find(State, 'R');
  Assert.AreEqual('-', Range.Value);
  Assert.AreEqual('+', Range.ProjectValue);
  Assert.IsTrue(Range.Deviates);
  Assert.AreEqual(Ord(TSwitchOriginKind.Directive), Ord(Range.Origin.Kind));
  Assert.AreEqual(9, Range.Origin.Line, 'gesetzt in Zeile 10');
  Assert.AreEqual('C:\P\Main.pas', Range.Origin.FileName);
  Assert.AreEqual('{$R-}', Range.Origin.Text);
  State := StateAt(Text, 5, Defines, NoProperties);
  Assert.AreEqual('+', Find(State, 'R').Value, 'vor der Direktive');
end;

procedure TCompilerSwitchesTests.IncludeFileNamed;
var
  State: TCompilerSwitchState;
  Overflow: TSwitchEntry;
begin
  State := StateAt(Lines(['unit Main;', '{$I Schalter.inc}', 'interface', 'implementation', 'end.']), 3, Defines,
    NoProperties);
  Overflow := Find(State, 'Q');
  Assert.AreEqual('-', Overflow.Value);
  Assert.AreEqual(Ord(TSwitchOriginKind.Include), Ord(Overflow.Origin.Kind));
  Assert.AreEqual('C:\P\Schalter.inc', Overflow.Origin.FileName);
  Assert.AreEqual(1, Overflow.Origin.Line, 'Zeile in der Include-Datei');
  Assert.AreEqual('OFF', Find(State, 'SYMBOL_PLATFORM').Value);
  State := StateAt(Lines(['unit Main;', '{$I Schalter.inc}', 'interface']), 1, Defines, NoProperties);
  Assert.AreEqual('+', Find(State, 'Q').Value, 'vor der $I-Direktive');
end;

procedure TCompilerSwitchesTests.ProjectValuesWithoutDirectives;
var
  State: TCompilerSwitchState;
  Entry: TSwitchEntry;
begin
  State := StateAt(Lines(['unit Main;', 'interface', 'implementation', 'end.']), 2, Defines,
    [TPair<string, string>.Create('DCC_Alignment', '4'), TPair<string, string>.Create('DCC_Hints', 'false'),
    TPair<string, string>.Create('DCC_SYMBOL_DEPRECATED', 'false')]);
  Assert.AreEqual('RQOCIA', Find(State, 'R').Name + State.Switches[1].Name + State.Switches[2].Name +
    State.Switches[3].Name + State.Switches[4].Name + State.Switches[5].Name, 'Reihenfolge');
  for Entry in State.Switches do
    Assert.IsFalse(Entry.Deviates, Entry.Name);
  Assert.AreEqual('+', Find(State, 'R').Value);
  Assert.AreEqual(Ord(TSwitchOriginKind.Project), Ord(Find(State, 'R').Origin.Kind));
  Assert.AreEqual('DCC_RangeChecking', Find(State, 'R').Origin.Text);
  Assert.AreEqual('-', Find(State, 'O').Value);
  Assert.AreEqual(Ord(TSwitchOriginKind.Default), Ord(Find(State, 'I').Origin.Kind), '"*" = Vorgabe');
  Assert.AreEqual('4', Find(State, 'A').Value);
  Assert.AreEqual('DCC_Alignment', Find(State, 'A').Origin.Text);
  Assert.AreEqual('OFF', State.Hints.Value);
  Assert.IsFalse(State.Hints.Deviates);
  Assert.AreEqual('ON', State.Warnings.Value);
  Assert.AreEqual(Ord(TSwitchOriginKind.Default), Ord(State.Warnings.Origin.Kind));
  Assert.AreEqual('OFF', Find(State, 'SYMBOL_DEPRECATED').Value, 'in der .dproj abgeschaltet');
  Assert.IsFalse(Find(State, 'SYMBOL_DEPRECATED').Deviates);
  Assert.AreEqual('', State.Summary);
  // Ohne Projekt: Vorgaben des Compilers.
  State := StateAt(Lines(['unit Main;']), 1, nil, NoProperties);
  Assert.AreEqual('-', Find(State, 'R').Value);
  Assert.AreEqual('+', Find(State, 'O').Value);
  Assert.AreEqual('8', Find(State, 'A').Value);
end;

procedure TCompilerSwitchesTests.WarnOffAndOn;
var
  Text: string;
  State: TCompilerSwitchState;
begin
  Text := Lines(['unit Main;', '{$WARN SYMBOL_DEPRECATED OFF}', 'interface', '{$WARN SYMBOL_DEPRECATED ON}',
    'implementation', '{$WARN UNIT_PLATFORM ERROR}', 'end.']);
  State := StateAt(Text, 2, Defines, NoProperties);
  Assert.AreEqual('OFF', Find(State, 'SYMBOL_DEPRECATED').Value);
  Assert.IsTrue(Find(State, 'SYMBOL_DEPRECATED').Deviates);
  Assert.AreEqual(1, Find(State, 'SYMBOL_DEPRECATED').Origin.Line);
  State := StateAt(Text, 4, Defines, NoProperties);
  Assert.AreEqual('', Find(State, 'SYMBOL_DEPRECATED').Name, 'nach ON nicht mehr abgeschaltet');
  State := StateAt(Text, 6, Defines, NoProperties);
  Assert.AreEqual('ERROR', Find(State, 'UNIT_PLATFORM').Value);
  // DEFAULT: zurück zum Projekt.
  State := StateAt(Lines(['{$WARN SYMBOL_DEPRECATED ON}', '{$WARN SYMBOL_DEPRECATED DEFAULT}', 'x']), 2, Defines,
    [TPair<string, string>.Create('DCC_SYMBOL_DEPRECATED', 'false')]);
  Assert.AreEqual('OFF', Find(State, 'SYMBOL_DEPRECATED').Value);
  Assert.AreEqual(Ord(TSwitchOriginKind.Project), Ord(Find(State, 'SYMBOL_DEPRECATED').Origin.Kind));
end;

procedure TCompilerSwitchesTests.PushAndPopRestore;
var
  Text: string;
  State: TCompilerSwitchState;
begin
  Text := Lines(['{$PUSHOPT}', '{$R-}{$WARN SYMBOL_DEPRECATED OFF}{$HINTS OFF}', 'x', '{$POPOPT}', 'y']);
  State := StateAt(Text, 2, Defines, NoProperties);
  Assert.AreEqual('-', Find(State, 'R').Value);
  Assert.AreEqual('OFF', State.Hints.Value);
  State := StateAt(Text, 4, Defines, NoProperties);
  Assert.AreEqual('+', Find(State, 'R').Value, 'nach POPOPT');
  Assert.AreEqual(Ord(TSwitchOriginKind.Project), Ord(Find(State, 'R').Origin.Kind));
  Assert.AreEqual('ON', State.Hints.Value);
  Assert.AreEqual('', Find(State, 'SYMBOL_DEPRECATED').Name);
end;

procedure TCompilerSwitchesTests.LongNamesAndAlignment;
var
  State: TCompilerSwitchState;
begin
  State := StateAt(Lines(['{$RANGECHECKS OFF}', '{$Q-,C-}', '{$ALIGN 4}', '{$OPTIMIZATION ON}', '{$R Datei.res}',
    '{$I-}', 'x']), 6, Defines, NoProperties);
  Assert.AreEqual('-', Find(State, 'R').Value, '{$R Datei.res} ist kein Schalter');
  Assert.AreEqual('-', Find(State, 'Q').Value);
  Assert.AreEqual('-', Find(State, 'C').Value);
  Assert.AreEqual('4', Find(State, 'A').Value);
  Assert.AreEqual('+', Find(State, 'O').Value);
  Assert.AreEqual('-', Find(State, 'I').Value);
  State := StateAt(Lines(['{$A-}', 'x', '{$A16}', 'y']), 1, Defines, NoProperties);
  Assert.AreEqual('1', Find(State, 'A').Value);
  State := StateAt(Lines(['{$A-}', 'x', '{$A16}', 'y']), 3, Defines, NoProperties);
  Assert.AreEqual('16', Find(State, 'A').Value);
end;

procedure TCompilerSwitchesTests.InactiveBranchesDoNotCount;
var
  State: TCompilerSwitchState;
begin
  State := StateAt(Lines(['{$IFDEF RELEASE}', '{$R-}', '{$ELSE}', '{$Q-}', '{$ENDIF}', 'x']), 5, Defines,
    NoProperties);
  Assert.AreEqual('+', Find(State, 'R').Value, 'RELEASE nicht definiert');
  Assert.AreEqual('-', Find(State, 'Q').Value);
end;

procedure TCompilerSwitchesTests.DefinesWithOrigin;
var
  State: TCompilerSwitchState;
  Names: string;
  Entry: TSwitchEntry;
begin
  State := StateAt(Lines(['{$DEFINE EIGEN}', '{$UNDEF DEBUG}', 'x', '{$DEFINE SPAETER}']), 2, Defines, NoProperties);
  Names := '';
  for Entry in State.Defines do
    Names := Names + Entry.Name + ' ';
  Assert.AreEqual('EIGEN ', Names, 'DEBUG aufgehoben, SPAETER erst danach, keine Schaltereinträge');
  Assert.AreEqual(0, Find(State, 'EIGEN').Origin.Line);
  State := StateAt(Lines(['x']), 1, Defines, NoProperties);
  Assert.AreEqual('Konfiguration Debug (.dproj)', Find(State, 'DEBUG').Origin.Text);
end;

procedure TCompilerSwitchesTests.SummaryNamesOnlyDeviations;
var
  State: TCompilerSwitchState;
begin
  State := StateAt(Lines(['{$R-,Q-}', '{$HINTS OFF}', '{$R-}', 'x']), 3, Defines, NoProperties);
  Assert.AreEqual('R'#$2212' Q'#$2212' HINTS OFF', State.Summary);
  State := StateAt(Lines(['{$A4}{$WARN SYMBOL_DEPRECATED OFF}{$WARN UNIT_PLATFORM OFF}', 'x']), 1, Defines,
    NoProperties);
  Assert.AreEqual('A4 WARN 2×', State.Summary);
  State := StateAt(Lines(['{$WARN SYMBOL_DEPRECATED OFF}', 'x']), 1, Defines, NoProperties);
  Assert.AreEqual('WARN SYMBOL_DEPRECATED OFF', State.Summary);
end;

end.
