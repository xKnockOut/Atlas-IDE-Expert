unit Atlas.Common.Pascal.CompilerSwitches.Tests;

// Wirksame Compiler-Schalter an einer Stelle (#558): lokale Direktive mit
// Zeile, Include-Datei, Projektstand ohne Direktiven, {$WARN … OFF/ON},
// {$PUSHOPT}/{$POPOPT}, lange Namen und Ausrichtung, inaktive Zweige,
// bedingte Symbole, Kurzfassung für die Statusleiste.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
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
    [Test]
    procedure DebugInfoAndLocalSymbols;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  System.SysUtils,
  Atlas.Common.Pascal.Preprocessor;

const
  cProjectDefines: array[0..5] of string = ('DEBUG', '$R+', '$Q+', '$O-', '$C+', '$I+*');

function Lines(const ALines: array of string): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in ALines do
  begin
    Result := Result + mLine + #10;
  end;
end;

function Defines: TArray<string>;
var
  mDefine: string;
begin
  Result := nil;
  for mDefine in cProjectDefines do
  begin
    Result := Result + [mDefine];
  end;
end;

function NoProperties: TArray<TPair<string, string>>;
begin
  Result := nil;
end;

{ TCompilerSwitchesTests }

function TCompilerSwitchesTests.StateAt(const AText: string; ALine: Integer; const ADefines: TArray<string>;
  const AProperties: TArray<TPair<string, string>>): TCompilerSwitchState;
var
  mOptions: TPreprocessorOptions;
  mInput: TCompilerSwitchInput;
begin
  mOptions := TPreprocessorOptions.Default;
  mOptions.Defines := ADefines;
  mOptions.FileName := 'C:\P\Main.pas';
  mOptions.ResolveInclude :=
    function(const AName, AFromFile: string; out AFileName, AText: string): Boolean
    begin
      Result := SameText(AName, 'Schalter.inc');
      AFileName := 'C:\P\Schalter.inc';
      AText := '// Schalter'#10'{$Q-}'#10'{$WARN SYMBOL_PLATFORM OFF}'#10;
    end;
  mInput := Default(TCompilerSwitchInput);
  mInput.Defines := ADefines;
  mInput.Properties := AProperties;
  mInput.DefineOrigins := [TSwitchDefineOrigin.Create('DEBUG',
    TSwitchOrigin.Make(TSwitchOriginKind.Project, 'Konfiguration Debug (.dproj)'))];
  Result := TCompilerSwitches.At(TPascalPreprocessor.Process(AText, mOptions), TTextPosition.Create(ALine, 0), mInput);
end;

function TCompilerSwitchesTests.Find(const AState: TCompilerSwitchState; const AName: string): TSwitchEntry;
var
  mEntry: TSwitchEntry;
begin
  for mEntry in AState.Switches + AState.Warns + AState.Defines do
  begin
    if SameText(mEntry.Name, AName) then
    begin
      Exit(mEntry);
    end;
  end;
  Result := Default(TSwitchEntry);
end;

procedure TCompilerSwitchesTests.LocalDirectiveWithLine;
var
  mText: string;
  mState: TCompilerSwitchState;
  mRange: TSwitchEntry;
  mIndex: Integer;
begin
  mText := '';
  for mIndex := 0 to 24 do
  begin
    if mIndex = 9 then
    begin
      mText := mText + '{$R-}'#10;
    end
    else
    begin
      mText := mText + '// Zeile'#10;
    end;
  end;
  mState := StateAt(mText, 19, Defines, NoProperties);
  mRange := Find(mState, 'R');
  Assert.AreEqual('-', mRange.Value);
  Assert.AreEqual('+', mRange.ProjectValue);
  Assert.IsTrue(mRange.Deviates);
  Assert.AreEqual(Ord(TSwitchOriginKind.Directive), Ord(mRange.Origin.Kind));
  Assert.AreEqual(9, mRange.Origin.Line, 'gesetzt in Zeile 10');
  Assert.AreEqual('C:\P\Main.pas', mRange.Origin.FileName);
  Assert.AreEqual('{$R-}', mRange.Origin.Text);
  mState := StateAt(mText, 5, Defines, NoProperties);
  Assert.AreEqual('+', Find(mState, 'R').Value, 'vor der Direktive');
end;

procedure TCompilerSwitchesTests.IncludeFileNamed;
var
  mState: TCompilerSwitchState;
  mOverflow: TSwitchEntry;
begin
  mState := StateAt(Lines(['unit Main;', '{$I Schalter.inc}', 'interface', 'implementation', 'end.']), 3, Defines,
    NoProperties);
  mOverflow := Find(mState, 'Q');
  Assert.AreEqual('-', mOverflow.Value);
  Assert.AreEqual(Ord(TSwitchOriginKind.Include), Ord(mOverflow.Origin.Kind));
  Assert.AreEqual('C:\P\Schalter.inc', mOverflow.Origin.FileName);
  Assert.AreEqual(1, mOverflow.Origin.Line, 'Zeile in der Include-Datei');
  Assert.AreEqual('OFF', Find(mState, 'SYMBOL_PLATFORM').Value);
  mState := StateAt(Lines(['unit Main;', '{$I Schalter.inc}', 'interface']), 1, Defines, NoProperties);
  Assert.AreEqual('+', Find(mState, 'Q').Value, 'vor der $I-Direktive');
end;

procedure TCompilerSwitchesTests.ProjectValuesWithoutDirectives;
var
  mState: TCompilerSwitchState;
  mEntry: TSwitchEntry;
begin
  mState := StateAt(Lines(['unit Main;', 'interface', 'implementation', 'end.']), 2, Defines,
    [TPair<string, string>.Create('DCC_Alignment', '4'), TPair<string, string>.Create('DCC_Hints', 'false'),
    TPair<string, string>.Create('DCC_SYMBOL_DEPRECATED', 'false')]);
  Assert.AreEqual('RQOCIA', Find(mState, 'R').Name + mState.Switches[1].Name + mState.Switches[2].Name +
    mState.Switches[3].Name + mState.Switches[4].Name + mState.Switches[5].Name, 'Reihenfolge');
  for mEntry in mState.Switches do
  begin
    Assert.IsFalse(mEntry.Deviates, mEntry.Name);
  end;
  Assert.AreEqual('+', Find(mState, 'R').Value);
  Assert.AreEqual(Ord(TSwitchOriginKind.Project), Ord(Find(mState, 'R').Origin.Kind));
  Assert.AreEqual('DCC_RangeChecking', Find(mState, 'R').Origin.Text);
  Assert.AreEqual('-', Find(mState, 'O').Value);
  Assert.AreEqual(Ord(TSwitchOriginKind.Default), Ord(Find(mState, 'I').Origin.Kind), '"*" = Vorgabe');
  Assert.AreEqual('4', Find(mState, 'A').Value);
  Assert.AreEqual('DCC_Alignment', Find(mState, 'A').Origin.Text);
  Assert.AreEqual('OFF', mState.Hints.Value);
  Assert.IsFalse(mState.Hints.Deviates);
  Assert.AreEqual('ON', mState.Warnings.Value);
  Assert.AreEqual(Ord(TSwitchOriginKind.Default), Ord(mState.Warnings.Origin.Kind));
  Assert.AreEqual('OFF', Find(mState, 'SYMBOL_DEPRECATED').Value, 'in der .dproj abgeschaltet');
  Assert.IsFalse(Find(mState, 'SYMBOL_DEPRECATED').Deviates);
  Assert.AreEqual('', mState.Summary);
  // Ohne Projekt: Vorgaben des Compilers.
  mState := StateAt(Lines(['unit Main;']), 1, nil, NoProperties);
  Assert.AreEqual('-', Find(mState, 'R').Value);
  Assert.AreEqual('+', Find(mState, 'O').Value);
  Assert.AreEqual('8', Find(mState, 'A').Value);
end;

procedure TCompilerSwitchesTests.WarnOffAndOn;
var
  mText: string;
  mState: TCompilerSwitchState;
begin
  mText := Lines(['unit Main;', '{$WARN SYMBOL_DEPRECATED OFF}', 'interface', '{$WARN SYMBOL_DEPRECATED ON}',
    'implementation', '{$WARN UNIT_PLATFORM ERROR}', 'end.']);
  mState := StateAt(mText, 2, Defines, NoProperties);
  Assert.AreEqual('OFF', Find(mState, 'SYMBOL_DEPRECATED').Value);
  Assert.IsTrue(Find(mState, 'SYMBOL_DEPRECATED').Deviates);
  Assert.AreEqual(1, Find(mState, 'SYMBOL_DEPRECATED').Origin.Line);
  mState := StateAt(mText, 4, Defines, NoProperties);
  Assert.AreEqual('', Find(mState, 'SYMBOL_DEPRECATED').Name, 'nach ON nicht mehr abgeschaltet');
  mState := StateAt(mText, 6, Defines, NoProperties);
  Assert.AreEqual('ERROR', Find(mState, 'UNIT_PLATFORM').Value);
  // DEFAULT: zurück zum Projekt.
  mState := StateAt(Lines(['{$WARN SYMBOL_DEPRECATED ON}', '{$WARN SYMBOL_DEPRECATED DEFAULT}', 'x']), 2, Defines,
    [TPair<string, string>.Create('DCC_SYMBOL_DEPRECATED', 'false')]);
  Assert.AreEqual('OFF', Find(mState, 'SYMBOL_DEPRECATED').Value);
  Assert.AreEqual(Ord(TSwitchOriginKind.Project), Ord(Find(mState, 'SYMBOL_DEPRECATED').Origin.Kind));
end;

procedure TCompilerSwitchesTests.PushAndPopRestore;
var
  mText: string;
  mState: TCompilerSwitchState;
begin
  mText := Lines(['{$PUSHOPT}', '{$R-}{$WARN SYMBOL_DEPRECATED OFF}{$HINTS OFF}', 'x', '{$POPOPT}', 'y']);
  mState := StateAt(mText, 2, Defines, NoProperties);
  Assert.AreEqual('-', Find(mState, 'R').Value);
  Assert.AreEqual('OFF', mState.Hints.Value);
  mState := StateAt(mText, 4, Defines, NoProperties);
  Assert.AreEqual('+', Find(mState, 'R').Value, 'nach POPOPT');
  Assert.AreEqual(Ord(TSwitchOriginKind.Project), Ord(Find(mState, 'R').Origin.Kind));
  Assert.AreEqual('ON', mState.Hints.Value);
  Assert.AreEqual('', Find(mState, 'SYMBOL_DEPRECATED').Name);
end;

procedure TCompilerSwitchesTests.LongNamesAndAlignment;
var
  mState: TCompilerSwitchState;
begin
  mState := StateAt(Lines(['{$RANGECHECKS OFF}', '{$Q-,C-}', '{$ALIGN 4}', '{$OPTIMIZATION ON}', '{$R Datei.res}',
    '{$I-}', 'x']), 6, Defines, NoProperties);
  Assert.AreEqual('-', Find(mState, 'R').Value, '{$R Datei.res} ist kein Schalter');
  Assert.AreEqual('-', Find(mState, 'Q').Value);
  Assert.AreEqual('-', Find(mState, 'C').Value);
  Assert.AreEqual('4', Find(mState, 'A').Value);
  Assert.AreEqual('+', Find(mState, 'O').Value);
  Assert.AreEqual('-', Find(mState, 'I').Value);
  mState := StateAt(Lines(['{$A-}', 'x', '{$A16}', 'y']), 1, Defines, NoProperties);
  Assert.AreEqual('1', Find(mState, 'A').Value);
  mState := StateAt(Lines(['{$A-}', 'x', '{$A16}', 'y']), 3, Defines, NoProperties);
  Assert.AreEqual('16', Find(mState, 'A').Value);
end;

procedure TCompilerSwitchesTests.InactiveBranchesDoNotCount;
var
  mState: TCompilerSwitchState;
begin
  mState := StateAt(Lines(['{$IFDEF RELEASE}', '{$R-}', '{$ELSE}', '{$Q-}', '{$ENDIF}', 'x']), 5, Defines,
    NoProperties);
  Assert.AreEqual('+', Find(mState, 'R').Value, 'RELEASE nicht definiert');
  Assert.AreEqual('-', Find(mState, 'Q').Value);
end;

procedure TCompilerSwitchesTests.DefinesWithOrigin;
var
  mState: TCompilerSwitchState;
  mNames: string;
  mEntry: TSwitchEntry;
begin
  mState := StateAt(Lines(['{$DEFINE EIGEN}', '{$UNDEF DEBUG}', 'x', '{$DEFINE SPAETER}']), 2, Defines, NoProperties);
  mNames := '';
  for mEntry in mState.Defines do
  begin
    mNames := mNames + mEntry.Name + ' ';
  end;
  Assert.AreEqual('EIGEN ', mNames, 'DEBUG aufgehoben, SPAETER erst danach, keine Schaltereinträge');
  Assert.AreEqual(0, Find(mState, 'EIGEN').Origin.Line);
  mState := StateAt(Lines(['x']), 1, Defines, NoProperties);
  Assert.AreEqual('Konfiguration Debug (.dproj)', Find(mState, 'DEBUG').Origin.Text);
end;

procedure TCompilerSwitchesTests.SummaryNamesOnlyDeviations;
var
  mState: TCompilerSwitchState;
begin
  mState := StateAt(Lines(['{$R-,Q-}', '{$HINTS OFF}', '{$R-}', 'x']), 3, Defines, NoProperties);
  Assert.AreEqual('R'#$2212' Q'#$2212' HINTS OFF', mState.Summary);
  mState := StateAt(Lines(['{$A4}{$WARN SYMBOL_DEPRECATED OFF}{$WARN UNIT_PLATFORM OFF}', 'x']), 1, Defines,
    NoProperties);
  Assert.AreEqual('A4 WARN 2×', mState.Summary);
  mState := StateAt(Lines(['{$WARN SYMBOL_DEPRECATED OFF}', 'x']), 1, Defines, NoProperties);
  Assert.AreEqual('WARN SYMBOL_DEPRECATED OFF', mState.Summary);
end;

procedure TCompilerSwitchesTests.DebugInfoAndLocalSymbols;
var
  mState: TCompilerSwitchState;
begin
  // D und L für die Erklärung „kein Zugriff“ (#840): Projekt "$D+", "$L+", Direktiven in der Unit.
  mState := StateAt(Lines(['unit Main;', '{$D-}', '{$LOCALSYMBOLS OFF}', 'implementation', 'end.']), 3,
    TArray<string>.Create('$D+', '$L+'), NoProperties);
  Assert.AreEqual('-', Find(mState, 'D').Value);
  Assert.AreEqual('+', Find(mState, 'D').ProjectValue);
  Assert.AreEqual('DEBUGINFO', Find(mState, 'D').LongName);
  Assert.AreEqual(1, Find(mState, 'D').Origin.Line);
  Assert.AreEqual('-', Find(mState, 'L').Value);
  Assert.AreEqual(2, Find(mState, 'L').Origin.Line);
  mState := StateAt(Lines(['unit Main;', 'implementation', 'end.']), 1, TArray<string>.Create('$D-'), NoProperties);
  Assert.AreEqual('-', Find(mState, 'D').Value, 'aus dem Projekt');
  Assert.AreEqual<TSwitchOriginKind>(TSwitchOriginKind.Project, Find(mState, 'D').Origin.Kind);
end;

end.
