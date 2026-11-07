unit Atlas.Common.Editing.TestUnits;

// DUnitX-Testgerüst (#274) und Zuordnung zwischen Unit und Testunit (#189).
// Die Namen folgen dem Muster "testUnits.pattern" ({unit} = Name der
// getesteten Unit, Vorgabe "{unit}.Tests"). Das Gerüst enthält [TestFixture],
// [Setup] und [TearDown] mit dem Objekt unter Test und einen [Test] je
// öffentlicher Methode der Klasse (überladene durchnummeriert); ohne Klasse
// einen Test je Routine im interface. Jeder Test schlägt fehl, bis er
// geschrieben ist, damit kein leerer Test grün durchläuft.
// Reine Textfunktionen; Dateien, Index und Testprojekt liefert der Aufrufer.

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract;

type
  /// <summary>Ein Test des Gerüsts: Name der Testmethode und was er prüft.</summary>
  TTestUnitMethod = record
    /// <summary>Name der Testmethode, z. B. TestBerechne oder TestBerechne2.</summary>
    Name: string;
    /// <summary>Geprüfte Methode bzw. Routine, z. B. TKunde.Berechne.</summary>
    Target: string;
  end;

  /// <summary>Text einer Datei; '' wenn sie fehlt.</summary>
  TTestUnitReadText = reference to function(const AFileName: string): string;

  TTestUnits = class
  public const
    cDefaultPattern = '{unit}.Tests';
    cPlaceholder = '{unit}';
  public
    /// <summary>Name der Testunit zu AUnitName nach APattern; leeres Muster gilt als Vorgabe.</summary>
    class function TestUnitName(const AUnitName, APattern: string): string; static;
    /// <summary>Getestete Unit zu einer Testunit; False, wenn der Name nicht zum Muster passt.</summary>
    class function TestedUnitName(const ATestUnitName, APattern: string; out AUnitName: string): Boolean; static;
    /// <summary>Name der Fixture: TKunde wird TKundeTests; ohne Klasse der letzte Namensteil der
    /// Unit (Kunden.Logik wird TLogikTests).</summary>
    class function FixtureName(const AClassName, AUnitName: string): string; static;
    /// <summary>Klasse an der Zeile (0-basiert): ihre Deklaration oder eine ihrer Methoden im
    /// implementation-Teil; '' sonst.</summary>
    class function ClassAt(const AUnit: TUnitIndex; ALine: Integer): string; static;
    /// <summary>Erste Klasse im interface; '' ohne.</summary>
    class function FirstClass(const AUnit: TUnitIndex): string; static;
    /// <summary>Tests zu den public- und published-Methoden von AClassName (ohne Konstruktoren und
    /// Destroy); bei leerem AClassName zu den Routinen im interface.</summary>
    class function TestMethods(const AUnit: TUnitIndex; const AClassName: string): TArray<TTestUnitMethod>; static;
    /// <summary>Ausdruck, der ein Objekt der Klasse erzeugt (TKunde.Create, TForm1.Create(nil));
    /// '' wenn der Konstruktor Argumente braucht oder die Klasse generisch ist.</summary>
    class function CreateExpression(const AUnit: TUnitIndex; const AClassName: string): string; static;
    /// <summary>Text der Testunit. AClassName leer: Tests für die Routinen der Unit.</summary>
    class function UnitText(const ATestUnitName: string; const AUnit: TUnitIndex; const AClassName: string;
      const ALineBreak: string): string; static;
    /// <summary>Bindet die Programmdatei DUnitX oder DUnit ein?</summary>
    class function IsTestProgram(const AText: string): Boolean; static;
    /// <summary>Erstes Testprogramm (.dpr) unter ACandidates; '' ohne.</summary>
    class function FindTestProgram(const ACandidates: TArray<string>;
      const AReadText: TTestUnitReadText): string; static;
    /// <summary>Pfad von AFileName relativ zum Ordner ABaseDir, mit \ wie in .dpr und .dproj;
    /// AFileName unverändert, wenn es auf einem anderen Laufwerk liegt.</summary>
    class function RelativePath(const ABaseDir, AFileName: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditingTestUnitsText = (IsGenericCreateTheObject, TestForStillMissing, NeedsArgumentsInTheConstructor);

const
  cTexts: array[TEditingTestUnitsText] of TAtlasText = (
    (De: '  // %s ist generisch: Objekt mit konkreten Typargumenten im Test anlegen.';
     En: '  // %s is generic: create the object with concrete type arguments in the test.'),
    (De: 'Test für %s fehlt noch'; En: 'Test for %s still missing'),
    (De: '  // %s braucht Argumente im Konstruktor: FSubject hier anlegen.';
     En: '  // %s needs arguments in the constructor: create FSubject here.'));

{$SCOPEDENUMS OFF}

function PatternOrDefault(const APattern: string): string;
begin
  Result := APattern;
  if Pos(TTestUnits.cPlaceholder, Result) = 0 then
  begin
    Result := TTestUnits.cDefaultPattern;
  end;
end;

class function TTestUnits.TestUnitName(const AUnitName, APattern: string): string;
begin
  Result := StringReplace(PatternOrDefault(APattern), cPlaceholder, AUnitName, [rfIgnoreCase]);
end;

class function TTestUnits.TestedUnitName(const ATestUnitName, APattern: string; out AUnitName: string): Boolean;
var
  mPattern, mPrefix, mSuffix: string;
  mAt: Integer;
begin
  AUnitName := '';
  mPattern := PatternOrDefault(APattern);
  mAt := Pos(cPlaceholder, mPattern);
  mPrefix := Copy(mPattern, 1, mAt - 1);
  mSuffix := Copy(mPattern, mAt + Length(cPlaceholder), MaxInt);
  Result := (Length(ATestUnitName) > Length(mPrefix) + Length(mSuffix)) and StartsText(mPrefix, ATestUnitName) and
    EndsText(mSuffix, ATestUnitName);
  if Result then
  begin
    AUnitName := Copy(ATestUnitName, Length(mPrefix) + 1, Length(ATestUnitName) - Length(mPrefix) - Length(mSuffix));
  end;
end;

class function TTestUnits.FixtureName(const AClassName, AUnitName: string): string;
var
  mName: string;
  mDot: Integer;
begin
  if AClassName <> '' then
  begin
    mName := AClassName;
    if (Length(mName) > 1) and CharInSet(mName[1], ['T', 't']) and CharInSet(mName[2], ['A'..'Z']) then
    begin
      mName := Copy(mName, 2, MaxInt);
    end;
  end
  else
  begin
    mName := AUnitName;
    mDot := mName.LastIndexOf('.');
    if mDot >= 0 then
    begin
      mName := mName.Substring(mDot + 1);
    end;
  end;
  Result := 'T' + mName + 'Tests';
end;

function IsClass(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.Kind = TIndexSymbolKind.ClassType) and (ASymbol.Container = '');
end;

/// <summary>Letzte Methode bzw. Routine im implementation-Teil, die vor ALine (oder dort) beginnt.</summary>
function LastRoutineBefore(const AUnit: TUnitIndex; ALine: Integer; out ALast: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  Result := False;
  ALast := Default(TIndexSymbol);
  for mSymbol in AUnit.Symbols do
  begin
    if not mSymbol.InInterface and (mSymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_,
      TIndexSymbolKind.Routine]) and (mSymbol.Range.StartPos.Line <= ALine) and
      (not Result or (mSymbol.Range.StartPos.Line > ALast.Range.StartPos.Line)) then
    begin
      ALast := mSymbol;
      Result := True;
    end;
  end;
end;

/// <summary>Name der Klasse AName in der Schreibweise der Deklaration; '' ohne.</summary>
function ClassNamed(const AUnit: TUnitIndex; const AName: string): string;
var
  mSymbol: TIndexSymbol;
begin
  Result := '';
  for mSymbol in AUnit.Symbols do
  begin
    if IsClass(mSymbol) and SameText(mSymbol.Name, AName) then
    begin
      Exit(mSymbol.Name);
    end;
  end;
end;

class function TTestUnits.ClassAt(const AUnit: TUnitIndex; ALine: Integer): string;
var
  mSymbol, mLast: TIndexSymbol;
begin
  Result := '';
  for mSymbol in AUnit.Symbols do
  begin
    if IsClass(mSymbol) and (mSymbol.Range.StartPos.Line <= ALine) and (mSymbol.Range.EndPos.Line >= ALine) then
    begin
      Exit(mSymbol.Name);
    end;
  end;
  // Im implementation-Teil: die letzte Routine, die vor der Zeile beginnt.
  if LastRoutineBefore(AUnit, ALine, mLast) and (mLast.Kind <> TIndexSymbolKind.Routine) then
  begin
    Result := ClassNamed(AUnit, mLast.Container);
  end;
end;

class function TTestUnits.FirstClass(const AUnit: TUnitIndex): string;
var
  mSymbol: TIndexSymbol;
begin
  Result := '';
  for mSymbol in AUnit.Symbols do
  begin
    if IsClass(mSymbol) and mSymbol.InInterface then
    begin
      Exit(mSymbol.Name);
    end;
  end;
end;

class function TTestUnits.TestMethods(const AUnit: TUnitIndex; const AClassName: string): TArray<TTestUnitMethod>;
var
  mSymbol: TIndexSymbol;
  mMethod: TTestUnitMethod;
  mCount, mIndex: Integer;
  mWanted: Boolean;
begin
  Result := nil;
  for mSymbol in AUnit.Symbols do
  begin
    if not mSymbol.InInterface then
    begin
      Continue;
    end;
    if AClassName <> '' then
    begin
      mWanted := (mSymbol.Kind = TIndexSymbolKind.Method) and SameText(mSymbol.Container, AClassName) and
        (mSymbol.Visibility in [TIndexVisibility.Public, TIndexVisibility.Published]) and
        not SameText(mSymbol.Name, 'Destroy');
    end
    else
    begin
      mWanted := (mSymbol.Kind = TIndexSymbolKind.Routine) and (mSymbol.Container = '');
    end;
    if not mWanted then
    begin
      Continue;
    end;
    // Überladene Methoden: TestBerechne, TestBerechne2, …
    mCount := 1;
    for mIndex := 0 to High(Result) do
    begin
      if SameText(Result[mIndex].Target, mSymbol.QualifiedName) then
      begin
        Inc(mCount);
      end;
    end;
    mMethod.Target := mSymbol.QualifiedName;
    mMethod.Name := 'Test' + mSymbol.Name;
    if mCount > 1 then
    begin
      mMethod.Name := mMethod.Name + IntToStr(mCount);
    end;
    Result := Result + [mMethod];
  end;
end;

const
  cComponentAncestors: array[0..8] of string = ('TComponent', 'TControl', 'TWinControl', 'TCustomControl',
    'TGraphicControl', 'TForm', 'TFrame', 'TDataModule', 'TCustomForm');

/// <summary>Ist ASymbol ein Konstruktor von AClassName im interface?</summary>
function IsOwnConstructor(const ASymbol: TIndexSymbol; const AClassName: string): Boolean;
begin
  Result := (ASymbol.Kind = TIndexSymbolKind.Constructor_) and SameText(ASymbol.Container, AClassName) and
    ASymbol.InInterface;
end;

/// <summary>Aufruf des öffentlichen Konstruktors ASymbol ohne Argumente bzw. mit nil als Owner; '' sonst.
/// </summary>
function ConstructorCall(const ASymbol: TIndexSymbol; const AClassName: string): string;
begin
  Result := '';
  if not (ASymbol.Visibility in [TIndexVisibility.Public, TIndexVisibility.Published]) then
  begin
    Exit;
  end;
  if ASymbol.MinArgs = 0 then
  begin
    Result := AClassName + '.' + ASymbol.Name;
  end
  else if (ASymbol.MinArgs = 1) and (Length(ASymbol.ParamTypes) > 0) and
    MatchText(ASymbol.ParamTypes[0], ['TComponent', 'TObject']) then
  begin
    Result := AClassName + '.' + ASymbol.Name + '(nil)';
  end;
end;

/// <summary>Ist die Klasse AClassName generisch? AComponent: Sie stammt direkt von einer Komponente ab.</summary>
function ClassTraits(const AUnit: TUnitIndex; const AClassName: string; out AComponent: Boolean): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  Result := False;
  AComponent := False;
  for mSymbol in AUnit.Symbols do
  begin
    if IsClass(mSymbol) and SameText(mSymbol.Name, AClassName) then
    begin
      Result := Result or (mSymbol.TypeParams <> '');
      AComponent := AComponent or ((Length(mSymbol.Ancestors) > 0) and
        MatchText(mSymbol.Ancestors[0], cComponentAncestors));
    end;
  end;
end;

class function TTestUnits.CreateExpression(const AUnit: TUnitIndex; const AClassName: string): string;
var
  mSymbol: TIndexSymbol;
  mHasConstructor, mComponent: Boolean;
begin
  Result := '';
  if ClassTraits(AUnit, AClassName, mComponent) then
  begin
    Exit;
  end;
  mHasConstructor := False;
  for mSymbol in AUnit.Symbols do
  begin
    if IsOwnConstructor(mSymbol, AClassName) then
    begin
      mHasConstructor := True;
      Result := ConstructorCall(mSymbol, AClassName);
      if Result <> '' then
      begin
        Exit;
      end;
    end;
  end;
  // Ohne eigenen Konstruktor: der des Vorfahren; bei Komponenten mit Owner.
  if mHasConstructor then
  begin
    Result := '';
  end
  else if mComponent then
  begin
    Result := AClassName + '.Create(nil)';
  end
  else
  begin
    Result := AClassName + '.Create';
  end;
end;

type
  /// <summary>Schreibt den Text der Testunit.</summary>
  TTestUnitWriter = record
    Builder: TStringBuilder;
    LineBreak: string;
    Fixture: string;
    ClassName: string;
    CreateText: string;
    Generic: Boolean;
    Methods: TArray<TTestUnitMethod>;
    procedure Line(const AText: string);
    /// <summary>Hat der Test ein Objekt unter Test (FSubject)?</summary>
    function HasSubject: Boolean;
    procedure WriteInterface(const ATestUnitName, AUnitName: string);
    procedure WriteSetup;
    procedure WriteTearDown;
    procedure WriteTests;
  end;

procedure TTestUnitWriter.Line(const AText: string);
begin
  Builder.Append(AText).Append(LineBreak);
end;

function TTestUnitWriter.HasSubject: Boolean;
begin
  Result := (ClassName <> '') and not Generic;
end;

procedure TTestUnitWriter.WriteInterface(const ATestUnitName, AUnitName: string);
var
  mMethod: TTestUnitMethod;
begin
  Line('unit ' + ATestUnitName + ';');
  Line('');
  Line('interface');
  Line('');
  Line('uses');
  Line('  DUnitX.TestFramework,');
  Line('  ' + AUnitName + ';');
  Line('');
  Line('type');
  Line('  [TestFixture]');
  Line('  ' + Fixture + ' = class');
  if HasSubject then
  begin
    Line('  private');
    Line('    FSubject: ' + ClassName + ';');
  end;
  Line('  public');
  Line('    [Setup]');
  Line('    procedure Setup;');
  Line('    [TearDown]');
  Line('    procedure TearDown;');
  for mMethod in Methods do
  begin
    Line('    [Test]');
    Line('    procedure ' + mMethod.Name + ';');
  end;
  Line('  end;');
  Line('');
end;

procedure TTestUnitWriter.WriteSetup;
begin
  Line('procedure ' + Fixture + '.Setup;');
  Line('begin');
  if HasSubject and (CreateText <> '') then
  begin
    Line('  FSubject := ' + CreateText + ';');
  end
  else if HasSubject then
  begin
    Line(cTexts[TEditingTestUnitsText.NeedsArgumentsInTheConstructor].Fmt([ClassName]));
  end
  else if Generic then
  begin
    Line(cTexts[TEditingTestUnitsText.IsGenericCreateTheObject].Fmt([ClassName]));
  end;
  Line('end;');
  Line('');
end;

procedure TTestUnitWriter.WriteTearDown;
begin
  Line('procedure ' + Fixture + '.TearDown;');
  Line('begin');
  if HasSubject then
  begin
    Line('  FSubject.Free;');
    Line('  FSubject := nil;');
  end;
  Line('end;');
end;

procedure TTestUnitWriter.WriteTests;
var
  mMethod: TTestUnitMethod;
begin
  for mMethod in Methods do
  begin
    Line('');
    Line('procedure ' + Fixture + '.' + mMethod.Name + ';');
    Line('begin');
    Line('  Assert.Fail(' + QuotedStr(cTexts[TEditingTestUnitsText.TestForStillMissing].Fmt([mMethod.Target])) + ');');
    Line('end;');
  end;
end;

class function TTestUnits.UnitText(const ATestUnitName: string; const AUnit: TUnitIndex;
  const AClassName: string; const ALineBreak: string): string;
var
  mWriter: TTestUnitWriter;
  mComponent: Boolean;
begin
  mWriter := Default(TTestUnitWriter);
  mWriter.LineBreak := ALineBreak;
  mWriter.Fixture := FixtureName(AClassName, AUnit.UnitName);
  mWriter.ClassName := AClassName;
  mWriter.Methods := TestMethods(AUnit, AClassName);
  mWriter.Generic := ClassTraits(AUnit, AClassName, mComponent);
  if AClassName <> '' then
  begin
    mWriter.CreateText := CreateExpression(AUnit, AClassName);
  end;
  mWriter.Builder := TStringBuilder.Create;
  try
    mWriter.WriteInterface(ATestUnitName, AUnit.UnitName);
    mWriter.Line('implementation');
    mWriter.Line('');
    mWriter.WriteSetup;
    mWriter.WriteTearDown;
    mWriter.WriteTests;
    mWriter.Line('');
    mWriter.Line('initialization');
    mWriter.Line('  TDUnitX.RegisterTestFixture(' + mWriter.Fixture + ');');
    mWriter.Line('');
    mWriter.Line('end.');
    Result := mWriter.Builder.ToString;
  finally
    mWriter.Builder.Free;
  end;
end;

class function TTestUnits.IsTestProgram(const AText: string): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
begin
  mTokens := TPascalLexer.Tokenize(AText);
  Result := False;
  for mIndex := 0 to High(mTokens) do
  begin
    if mTokens[mIndex].IsKeyword('program') then
    begin
      Exit(TUsesClauses.IsTestUnit(mTokens));
    end
    else if mTokens[mIndex].IsKeyword('unit') or mTokens[mIndex].IsKeyword('library') or
      mTokens[mIndex].IsKeyword('package') then
    begin
      Exit(False);
    end;
  end;
end;

class function TTestUnits.FindTestProgram(const ACandidates: TArray<string>;
  const AReadText: TTestUnitReadText): string;
var
  mCandidate: string;
begin
  Result := '';
  for mCandidate in ACandidates do
  begin
    if SameText(ExtractFileExt(mCandidate), '.dpr') and IsTestProgram(AReadText(mCandidate)) then
    begin
      Exit(mCandidate);
    end;
  end;
end;

function SplitPath(const APath: string): TArray<string>;
var
  mPart: string;
begin
  Result := nil;
  for mPart in StringReplace(APath, '/', '\', [rfReplaceAll]).Split(['\']) do
  begin
    if (mPart <> '') and (mPart <> '.') then
    begin
      Result := Result + [mPart];
    end;
  end;
end;

class function TTestUnits.RelativePath(const ABaseDir, AFileName: string): string;
var
  mBase, mTarget: TArray<string>;
  mCommon, mIndex: Integer;
begin
  mBase := SplitPath(ABaseDir);
  mTarget := SplitPath(AFileName);
  mCommon := 0;
  while (mCommon < Length(mBase)) and (mCommon < Length(mTarget) - 1) and SameText(mBase[mCommon], mTarget[mCommon]) do
  begin
    Inc(mCommon);
  end;
  // Anderes Laufwerk (oder kein gemeinsamer Anfang bei absoluten Pfaden): vollständiger Pfad.
  if (mCommon = 0) and (Length(mBase) > 0) and (Length(mTarget) > 0) and (Pos(':', mTarget[0]) > 0) then
  begin
    Exit(StringReplace(AFileName, '/', '\', [rfReplaceAll]));
  end;
  Result := '';
  for mIndex := mCommon to High(mBase) do
  begin
    Result := Result + '..\';
  end;
  for mIndex := mCommon to High(mTarget) do
  begin
    Result := Result + mTarget[mIndex];
    if mIndex < High(mTarget) then
    begin
      Result := Result + '\';
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.TestUnits', cTexts);

end.
