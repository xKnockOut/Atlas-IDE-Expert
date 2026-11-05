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
    DefaultPattern = '{unit}.Tests';
    Placeholder = '{unit}';
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
    class function FindTestProgram(const ACandidates: TArray<string>; const AReadText: TTestUnitReadText): string; static;
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
  if Pos(TTestUnits.Placeholder, Result) = 0 then
  begin
    Result := TTestUnits.DefaultPattern;
  end;
end;

class function TTestUnits.TestUnitName(const AUnitName, APattern: string): string;
begin
  Result := StringReplace(PatternOrDefault(APattern), Placeholder, AUnitName, [rfIgnoreCase]);
end;

class function TTestUnits.TestedUnitName(const ATestUnitName, APattern: string; out AUnitName: string): Boolean;
var
  Pattern, Prefix, Suffix: string;
  At: Integer;
begin
  AUnitName := '';
  Pattern := PatternOrDefault(APattern);
  At := Pos(Placeholder, Pattern);
  Prefix := Copy(Pattern, 1, At - 1);
  Suffix := Copy(Pattern, At + Length(Placeholder), MaxInt);
  Result := (Length(ATestUnitName) > Length(Prefix) + Length(Suffix)) and StartsText(Prefix, ATestUnitName) and
    EndsText(Suffix, ATestUnitName);
  if Result then
  begin
    AUnitName := Copy(ATestUnitName, Length(Prefix) + 1, Length(ATestUnitName) - Length(Prefix) - Length(Suffix));
  end;
end;

class function TTestUnits.FixtureName(const AClassName, AUnitName: string): string;
var
  Name: string;
  Dot: Integer;
begin
  if AClassName <> '' then
  begin
    Name := AClassName;
    if (Length(Name) > 1) and CharInSet(Name[1], ['T', 't']) and CharInSet(Name[2], ['A'..'Z']) then
    begin
      Name := Copy(Name, 2, MaxInt);
    end;
  end
  else
  begin
    Name := AUnitName;
    Dot := Name.LastIndexOf('.');
    if Dot >= 0 then
    begin
      Name := Name.Substring(Dot + 1);
    end;
  end;
  Result := 'T' + Name + 'Tests';
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
  Symbol: TIndexSymbol;
begin
  Result := '';
  for Symbol in AUnit.Symbols do
  begin
    if IsClass(Symbol) and Symbol.InInterface then
    begin
      Exit(Symbol.Name);
    end;
  end;
end;

class function TTestUnits.TestMethods(const AUnit: TUnitIndex; const AClassName: string): TArray<TTestUnitMethod>;
var
  Symbol: TIndexSymbol;
  Method: TTestUnitMethod;
  Count, Index: Integer;
  Wanted: Boolean;
begin
  Result := nil;
  for Symbol in AUnit.Symbols do
  begin
    if not Symbol.InInterface then
    begin
      Continue;
    end;
    if AClassName <> '' then
    begin
      Wanted := (Symbol.Kind = TIndexSymbolKind.Method) and SameText(Symbol.Container, AClassName) and
        (Symbol.Visibility in [TIndexVisibility.Public, TIndexVisibility.Published]) and
        not SameText(Symbol.Name, 'Destroy');
    end
    else
    begin
      Wanted := (Symbol.Kind = TIndexSymbolKind.Routine) and (Symbol.Container = '');
    end;
    if not Wanted then
    begin
      Continue;
    end;
    // Überladene Methoden: TestBerechne, TestBerechne2, …
    Count := 1;
    for Index := 0 to High(Result) do
    begin
      if SameText(Result[Index].Target, Symbol.QualifiedName) then
      begin
        Inc(Count);
      end;
    end;
    Method.Target := Symbol.QualifiedName;
    Method.Name := 'Test' + Symbol.Name;
    if Count > 1 then
    begin
      Method.Name := Method.Name + IntToStr(Count);
    end;
    Result := Result + [Method];
  end;
end;

const
  ComponentAncestors: array[0..8] of string = ('TComponent', 'TControl', 'TWinControl', 'TCustomControl',
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
        MatchText(mSymbol.Ancestors[0], ComponentAncestors));
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
  Tokens: TArray<TPascalToken>;
  Index: Integer;
begin
  Tokens := TPascalLexer.Tokenize(AText);
  Result := False;
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].IsKeyword('program') then
    begin
      Exit(TUsesClauses.IsTestUnit(Tokens));
    end
    else if Tokens[Index].IsKeyword('unit') or Tokens[Index].IsKeyword('library') or
      Tokens[Index].IsKeyword('package') then
    begin
      Exit(False);
    end;
  end;
end;

class function TTestUnits.FindTestProgram(const ACandidates: TArray<string>;
  const AReadText: TTestUnitReadText): string;
var
  Candidate: string;
begin
  Result := '';
  for Candidate in ACandidates do
  begin
    if SameText(ExtractFileExt(Candidate), '.dpr') and IsTestProgram(AReadText(Candidate)) then
    begin
      Exit(Candidate);
    end;
  end;
end;

function SplitPath(const APath: string): TArray<string>;
var
  Part: string;
begin
  Result := nil;
  for Part in StringReplace(APath, '/', '\', [rfReplaceAll]).Split(['\']) do
  begin
    if (Part <> '') and (Part <> '.') then
    begin
      Result := Result + [Part];
    end;
  end;
end;

class function TTestUnits.RelativePath(const ABaseDir, AFileName: string): string;
var
  Base, Target: TArray<string>;
  Common, Index: Integer;
begin
  Base := SplitPath(ABaseDir);
  Target := SplitPath(AFileName);
  Common := 0;
  while (Common < Length(Base)) and (Common < Length(Target) - 1) and SameText(Base[Common], Target[Common]) do
  begin
    Inc(Common);
  end;
  // Anderes Laufwerk (oder kein gemeinsamer Anfang bei absoluten Pfaden): vollständiger Pfad.
  if (Common = 0) and (Length(Base) > 0) and (Length(Target) > 0) and (Pos(':', Target[0]) > 0) then
  begin
    Exit(StringReplace(AFileName, '/', '\', [rfReplaceAll]));
  end;
  Result := '';
  for Index := Common to High(Base) do
  begin
    Result := Result + '..\';
  end;
  for Index := Common to High(Target) do
  begin
    Result := Result + Target[Index];
    if Index < High(Target) then
    begin
      Result := Result + '\';
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.TestUnits', cTexts);

end.
